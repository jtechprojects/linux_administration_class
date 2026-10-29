
#!/usr/bin/env bash
# Monitor SSH failures, privileged accounts, passwords, and ports.
# Compatible with CentOS Stream 10 and Ubuntu.

# Use a predictable command search path for cron.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# Restrict permissions on newly created report files.
umask 077

# Set the directory where reports will be saved.
REPORT_DIR="/var/log/security-monitor"

# Create a unique timestamp for each report.
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S_%N')

# Set the complete report filename.
REPORT="$REPORT_DIR/security_$TIMESTAMP.log"

# Initialize the security finding counter.
FINDINGS=0

# Exit with an error if the script is not run as root.
if (( EUID != 0 )); then
    echo "ERROR: Run this script as root." >&2
    exit 2
fi

# Confirm that all required commands are available.
for cmd in date mkdir awk getent journalctl ss; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command missing: $cmd" >&2
        exit 2
    fi
done

# Create the report directory if it does not exist.
if ! mkdir -p -m 700 "$REPORT_DIR"; then
    echo "ERROR: Cannot create report directory." >&2
    exit 2
fi

# Restrict access to the report directory.
if ! chmod 700 "$REPORT_DIR"; then
    echo "ERROR: Cannot secure report directory." >&2
    exit 2
fi

# Create the report and verify that it is writable.
if ! ( umask 077; : > "$REPORT" ); then
    echo "ERROR: Cannot create report file." >&2
    exit 2
fi

# Write a heading to both the terminal and the report.
echo "Security Monitoring Report" | tee -a "$REPORT"

# Record the time the report was generated.
date -Is | tee -a "$REPORT"

# Identify the machine being checked.
printf 'Hostname: %s\n' "$(hostname)" | tee -a "$REPORT"

# Print the SSH authentication section heading.
echo "=== Failed SSH Logins: Last 24 Hours ===" | tee -a "$REPORT"

# Read journal entries from the previous 24 hours.
# Match messages associated with SSH authentication failures.
# Include both ssh.service and sshd.service unit names.
# Use the SSH process identifier to avoid unrelated messages.
if SSH_LOGS=$(journalctl --since "24 hours ago" \
    --until "now" --no-pager -o cat \
    _COMM=sshd _COMM=sshd-session 2>/dev/null); then

    # Extract messages describing failed SSH authentication.
    SSH_FAILURES=$(printf '%s\n' "$SSH_LOGS" |
        grep -Ei 'Failed password|Failed publickey|authentication failure|maximum authentication attempts|PAM: Authentication failure' || true)

    # Report the failures if any were found.
    if [[ -n "$SSH_FAILURES" ]]; then
        printf '%s\n' "$SSH_FAILURES" | tee -a "$REPORT"
        FINDINGS=$((FINDINGS + 1))
    else
        echo "No failed SSH logins found." | tee -a "$REPORT"
    fi
else
    echo "ERROR: Unable to read the system journal." | tee -a "$REPORT"
    exit 2
fi

# Print the UID 0 account section heading.
echo "=== Accounts With UID 0 ===" | tee -a "$REPORT"

# Query the system's configured account database.
if ! ACCOUNTS=$(getent passwd); then
    echo "ERROR: Unable to enumerate accounts." | tee -a "$REPORT"
    exit 2
fi

# Print every account whose third passwd field is zero.
printf '%s\n' "$ACCOUNTS" |
    awk -F: '$3 == 0 {print $1 " (UID 0)"}' |
    tee -a "$REPORT"

# Identify UID 0 accounts other than the normal root account.
EXTRA_ROOT=$(printf '%s\n' "$ACCOUNTS" |
    awk -F: '$3 == 0 && $1 != "root" {print $1}')

# Flag additional UID 0 accounts as security findings.
if [[ -n "$EXTRA_ROOT" ]]; then
    echo "WARNING: Additional UID 0 accounts detected." | tee -a "$REPORT"
    FINDINGS=$((FINDINGS + 1))
fi

# Print the empty-password section heading.
echo "=== Accounts With Empty Password Fields ===" | tee -a "$REPORT"

# Verify that the local shadow database is readable.
if [[ ! -r /etc/shadow ]]; then
    echo "ERROR: Cannot read /etc/shadow." | tee -a "$REPORT"
    exit 2
fi

# Find accounts with an empty second field in /etc/shadow.
EMPTY_PASSWORDS=$(awk -F: '$2 == "" {print $1}' /etc/shadow)

# Report empty password fields without exposing password hashes.
if [[ -n "$EMPTY_PASSWORDS" ]]; then
    printf '%s\n' "$EMPTY_PASSWORDS" | tee -a "$REPORT"
    FINDINGS=$((FINDINGS + 1))
else
    echo "No empty local password fields found." | tee -a "$REPORT"
fi

# Print the listening-port section heading.
echo "=== Listening TCP and UDP Ports ===" | tee -a "$REPORT"

# List listening TCP and UDP sockets with process information.
if ! ss -tulnp >> "$REPORT" 2>&1; then
    echo "ERROR: Unable to inspect listening ports." | tee -a "$REPORT"
    exit 2
fi

# Print the same socket information to the terminal.
ss -tulnp

# Print the summary heading.
echo "=== Security Summary ===" | tee -a "$REPORT"

# Report the number of finding categories detected.
echo "Finding categories: $FINDINGS" | tee -a "$REPORT"

# Record where the report was saved.
echo "Report saved to: $REPORT" | tee -a "$REPORT"

# Return a non-zero status when security findings exist.
if (( FINDINGS > 0 )); then
    echo "STATUS: SECURITY FINDINGS DETECTED" | tee -a "$REPORT"
    exit 1
fi

# Report successful completion with no detected findings.
echo "STATUS: No security findings detected." | tee -a "$REPORT"

# Return a successful exit code.
exit 0
