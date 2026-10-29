#!/usr/bin/env bash
#
# sec-monitor.sh - read-only security snapshot for CentOS Stream 10 and Ubuntu
#
# What it does
#   1. Counts/summarises failed SSH logins from the last 24 hours
#   2. Lists every UID 0 account and every account with an empty password
#   3. Lists listening TCP/UDP sockets with ss
#   4. Writes everything to a timestamped report (default: /var/log/security-monitor)
#
# Exit codes (useful for cron, monitoring agents, CI):
#   0 = no security problem found
#   1 = security problem found (see report)
#   2 = script could not run or could not check everything (not a verdict)
#
# Options / environment variables (all optional - defaults need no editing):
#   -v                      also print the full report to stdout
#   OUT_DIR=/some/dir       report directory (must NOT be under /tmp or /var/tmp)
#   SSH_FAIL_THRESHOLD=20   failed SSH logins in 24h that count as a problem
#
# It only READS system state. The one thing it creates is its own report
# directory/file. It installs nothing and changes no system settings.
#
# References
#   [1] Bash manual                 https://www.gnu.org/software/bash/manual/bash.html
#   [2] ss(8)                       https://man7.org/linux/man-pages/man8/ss.8.html
#   [3] journalctl(1)               https://www.freedesktop.org/software/systemd/man/latest/journalctl.html
#   [4] passwd(5)                   https://man7.org/linux/man-pages/man5/passwd.5.html
#   [5] shadow(5)                   https://man7.org/linux/man-pages/man5/shadow.5.html
#   [6] getent(1)                   https://man7.org/linux/man-pages/man1/getent.1.html
#   [7] date input formats (GNU)    https://www.gnu.org/software/coreutils/manual/html_node/Date-input-formats.html
#   [8] sshd(8) log messages        https://man.openbsd.org/sshd
#   [9] crontab(5)                  https://man7.org/linux/man-pages/man5/crontab.5.html

# --- Shell safety settings ---------------------------------------------------
# -u: treat use of an unset variable as an error. [1]
# pipefail: a pipeline fails if any command in it fails. [1]
# We deliberately do NOT use "set -e": grep/diff return 1 for "no match", which
# is a normal result here, not an error.
set -u
set -o pipefail

# New files get mode 600 and new directories 700: reports are root-only. [1]
umask 077

# Cron runs with a minimal PATH, so set one explicitly. ss lives in /usr/sbin
# on some systems and /usr/bin on others.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# Force the C locale so tool output (and our parsing of it) is identical on
# every host and under cron.
LC_ALL=C
export LC_ALL

# --- Configuration -----------------------------------------------------------
OUT_DIR="${OUT_DIR:-/var/log/security-monitor}"            # report directory
SSH_FAIL_THRESHOLD="${SSH_FAIL_THRESHOLD:-20}"             # failures/24h that trigger exit 1
VERBOSE=0
if [[ "${1:-}" == "-v" ]]; then VERBOSE=1; fi              # -v prints the report to stdout too

# --- Helper: print an error to stderr and exit with code 2 -------------------
die() { echo "sec-monitor: $*" >&2; exit 2; }

# --- Pre-flight checks (all before anything is written) ----------------------
# Reading /etc/shadow, other users' process names (ss -p) and the journal
# requires root. Under cron, install this in root's crontab.
(( EUID == 0 )) || die "must be run as root (needed to read /etc/shadow and system logs)"

# The threshold must be a plain non-negative integer, or the comparison breaks.
[[ "$SSH_FAIL_THRESHOLD" =~ ^[0-9]+$ ]] || die "SSH_FAIL_THRESHOLD must be a whole number"

# Require an absolute path and refuse the world-writable temp directories.
[[ "$OUT_DIR" == /* ]] || die "OUT_DIR must be an absolute path"
case "$OUT_DIR" in
  /tmp|/tmp/*|/var/tmp|/var/tmp/*) die "OUT_DIR must not be under /tmp or /var/tmp" ;;
esac

# Create the report directory if needed (umask above makes it 700).
mkdir -p -- "$OUT_DIR" || die "cannot create $OUT_DIR"
[[ -w "$OUT_DIR" ]]   || die "$OUT_DIR is not writable"

# --- Report file -------------------------------------------------------------
# "uname -n" is used instead of "hostname" because minimal CentOS installs may
# not ship the hostname binary. "cut" drops the domain part.
HOST="$(uname -n | cut -d. -f1)"
REPORT="$OUT_DIR/security-report-${HOST}-$(date +%Y%m%d-%H%M%S).txt"

# Keep the original stdout on file descriptor 3, then send all normal output
# to the report file. Cron therefore only mails us what we print to FD 3. [1]
exec 3>&1 >"$REPORT" || die "cannot open $REPORT"

PROBLEMS=()     # one human-readable line per security problem found
INCOMPLETE=0    # set to 1 if a check could not be performed
add_problem() { PROBLEMS+=("$1"); }

# --- Report header -----------------------------------------------------------
echo "=== Security report for ${HOST} ==="
echo "Generated : $(date '+%Y-%m-%d %H:%M:%S %Z')"
# Run in a subshell so sourcing os-release does not leak variables here.
echo "OS        : $( . /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}" )"
echo "Kernel    : $(uname -r)"
echo

# =============================================================================
# 1. FAILED SSH LOGINS, LAST 24 HOURS
# =============================================================================
# Where sshd logs differs by distro:
#   - Both: systemd journal (works regardless of syslog daemon)    [3]
#   - Ubuntu with rsyslog:   /var/log/auth.log
#   - RHEL family w/ rsyslog: /var/log/secure
# OpenSSH 9.8+ (CentOS Stream 10, newer Ubuntu) logs from a helper process
# called "sshd-session" instead of "sshd", so we match both names.   [8]
#
# collect_ssh_failures sets two globals (not a subshell, so they survive):
#   SSH_LINES  - matching log lines, newline separated
#   SSH_SOURCE - description of where the data came from ("none" if unavailable)
collect_ssh_failures() {
  SSH_LINES=""
  SSH_SOURCE="none"
  # Matches: "sshd[123]: Failed password for ..." / "sshd-session[123]: Failed publickey ..."
  local fail_re='sshd(-session)?(\[[0-9]+\])?: Failed (password|publickey|keyboard-interactive)'
  local jout f files=() now cutoff line ts epoch

  # --- Preferred source: the journal ---
  if command -v journalctl >/dev/null 2>&1; then
    # Two _COMM= matches on the same field are OR-ed by journalctl.
    # -q hides the "-- No entries --" banner; -o short-iso gives ISO timestamps.
    if jout="$(journalctl --no-pager -q -o short-iso --since '24 hours ago' \
                 _COMM=sshd _COMM=sshd-session 2>/dev/null)" && [[ -n "$jout" ]]; then
      SSH_SOURCE="systemd journal"
      SSH_LINES="$(grep -E "$fail_re" <<<"$jout" || true)"
      return 0
    fi
  fi

  # --- Fallback source: plain-text log files ---
  # Include the most recent rotated Ubuntu file in case rotation happened today.
  for f in /var/log/auth.log /var/log/auth.log.1 /var/log/secure; do
    [[ -r "$f" ]] && files+=("$f")
  done
  if (( ${#files[@]} > 0 )); then
    SSH_SOURCE="log files: ${files[*]}"
    now="$(date +%s)"
    cutoff=$(( now - 86400 ))                    # 24 hours ago, in epoch seconds
    # Pre-filter with grep (cheap) so we only call "date" on relevant lines.
    while IFS= read -r line; do
      # rsyslog writes either ISO timestamps (2026-10-27T10:00:00+00:00)
      # or classic syslog ones ("Oct 27 10:00:00", no year).
      if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
        ts="${line%% *}"                         # first word = ISO timestamp
      else
        ts="${line:0:15}"                        # first 15 chars = "Mon DD HH:MM:SS"
      fi
      epoch="$(date -d "$ts" +%s 2>/dev/null)" || continue   # GNU date parses both [7]
      # A classic timestamp with no year can be misread as "future" right after
      # New Year; if so, retry with last year.
      if (( epoch > now + 86400 )); then
        epoch="$(date -d "$ts $(( $(date +%Y) - 1 ))" +%s 2>/dev/null)" || continue
      fi
      if (( epoch >= cutoff )); then SSH_LINES+="${line}"$'\n'; fi
    done < <(grep -hE "$fail_re" "${files[@]}" 2>/dev/null)
    return 0
  fi

  # --- Journal worked but was empty, and no log files: treat as "zero events" ---
  if command -v journalctl >/dev/null 2>&1 && journalctl -q -n 1 >/dev/null 2>&1; then
    SSH_SOURCE="systemd journal (no sshd entries in window)"
  fi
  return 0
}

echo "=== 1. Failed SSH logins (last 24 hours) ==="
collect_ssh_failures

if [[ "$SSH_SOURCE" == "none" ]]; then
  echo "WARNING: no readable SSH log source found; this check was skipped."
  INCOMPLETE=1
else
  # grep -c . counts non-empty lines (a here-string always ends with a newline).
  FAIL_COUNT="$(grep -c . <<<"$SSH_LINES")"
  echo "Source    : $SSH_SOURCE"
  echo "Failures  : $FAIL_COUNT (threshold: $SSH_FAIL_THRESHOLD)"
  if (( FAIL_COUNT > 0 )); then
    echo
    echo "Top source addresses (count address):"
    # Pull the text between " from " and " port N", then count and rank.
    sed -nE 's/.* from ([0-9A-Fa-f:.]+) port [0-9]+.*/\1/p' <<<"$SSH_LINES" \
      | sort | uniq -c | sort -rn | head -10
    echo
    echo "Top targeted usernames (count user):"
    # "Failed password for [invalid user] NAME from ..." -> NAME
    sed -nE 's/.*Failed [a-z-]+ for (invalid user )?(.+) from [0-9A-Fa-f:.]+ port.*/\2/p' <<<"$SSH_LINES" \
      | sort | uniq -c | sort -rn | head -10
    echo
    echo "Most recent events (log text may contain attacker-supplied usernames):"
    grep . <<<"$SSH_LINES" | tail -n 10      # grep . drops blank lines
  fi
  if (( FAIL_COUNT >= SSH_FAIL_THRESHOLD )); then
    add_problem "SSH: $FAIL_COUNT failed logins in 24h (threshold $SSH_FAIL_THRESHOLD)"
  fi
fi
echo

# =============================================================================
# 2. UID 0 ACCOUNTS AND EMPTY PASSWORDS
# =============================================================================
echo "=== 2. Privileged and passwordless accounts ==="

# getent queries every configured account source (local files, LDAP, SSSD...). [6]
# passwd(5) fields: name:pw:UID:GID:comment:home:shell -> UID is field 3.      [4]
# The regex check avoids treating a malformed non-numeric field as 0.
mapfile -t UID0_ACCOUNTS < <(getent passwd | awk -F: '$3 ~ /^[0-9]+$/ && $3 + 0 == 0 { print $1 }')

echo "Accounts with UID 0:"
if (( ${#UID0_ACCOUNTS[@]} == 0 )); then
  echo "  (none found - unexpected; 'root' should exist)"
else
  printf '  %s\n' "${UID0_ACCOUNTS[@]}"
fi
# Exactly one UID 0 account, named root, is the expected state.
for acct in "${UID0_ACCOUNTS[@]}"; do
  if [[ "$acct" != "root" ]]; then
    add_problem "UID 0: non-root account '$acct' has UID 0"
  fi
done
echo

# shadow(5) fields: name:hash:lastchg:... An EMPTY hash field means the account
# needs no password. "!" or "*" means locked/no password login, which is fine. [5]
echo "Accounts with an empty password:"
if [[ -r /etc/shadow ]]; then
  mapfile -t EMPTY_PW < <(awk -F: '$2 == "" { print $1 }' /etc/shadow)
  if (( ${#EMPTY_PW[@]} == 0 )); then
    echo "  (none)"
  else
    printf '  %s\n' "${EMPTY_PW[@]}"
    for acct in "${EMPTY_PW[@]}"; do
      add_problem "Empty password: account '$acct' has no password set"
    done
  fi
else
  echo "WARNING: /etc/shadow not readable; check skipped."
  INCOMPLETE=1
fi
echo

# =============================================================================
# 3. LISTENING PORTS
# =============================================================================
# -t TCP  -u UDP  -l listening only  -n numeric (no DNS/service lookups)
# -p show owning process (needs root)                                      [2]
echo "=== 3. Listening sockets (ss -tulnp) ==="
if command -v ss >/dev/null 2>&1; then
  ss -tulnp || { echo "WARNING: ss returned an error."; INCOMPLETE=1; }
else
  echo "WARNING: 'ss' not found (package iproute2 / iproute); check skipped."
  INCOMPLETE=1
fi
echo

# =============================================================================
# SUMMARY AND EXIT CODE
# =============================================================================
echo "=== Summary ==="
if (( ${#PROBLEMS[@]} > 0 )); then
  echo "RESULT: PROBLEMS FOUND (${#PROBLEMS[@]})"
  printf ' - %s\n' "${PROBLEMS[@]}"
  EXIT_CODE=1
elif (( INCOMPLETE )); then
  echo "RESULT: INCOMPLETE - no problems found, but some checks were skipped (see warnings)"
  EXIT_CODE=2
else
  echo "RESULT: OK - no problems found"
  EXIT_CODE=0
fi
echo "Report file: $REPORT"

# Under cron, anything on stdout is emailed. So stay silent when all is well,
# and send the full report only when there is a problem (or when -v is given).
if (( EXIT_CODE != 0 || VERBOSE )); then
  cat -- "$REPORT" >&3
fi

exit "$EXIT_CODE"