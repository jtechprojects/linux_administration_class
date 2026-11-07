#!/bin/bash

# Compatible with CentOS and Ubuntu
# Purpose: Collect health information for troubleshooting

REPORT_DIR="$HOME/Security_Lab/reports"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
REPORT_FILE="$REPORT_DIR/system_diagnostics_$TIMESTAMP.txt"

mkdir -p "$REPORT_DIR"

# Section 1: Basic System Informaton

{
	echo "======= SYSTEM INFORMATION ======="
	echo "Report generated: $(date)"
	echo "Hostname: $(hostname)"
	echo "Operating System: "
	cat /etc/os-release
	echo "Kernel version: $(uname -r)"
	echo "System uptime: "
	uptime
} >> "$REPORT_FILE" 2>&1

# Section 2: CPU and Memory Information

{
	echo " "
	echo "======= CPU AND MEMORY INFORMATION ======="
	echo "CPU details: "
	lscpu
	echo "Memory usage: "
	free -h
	echo "System load: "
	uptime
} >> "$REPORT_FILE" 2>&1

# Section 3: Disk Space Information

{
	echo " "
	echo "======= DISK SPACE INFORMATION ======="
	echo "Filesystem disk usage: "
	df -h
	echo "Disk and partition information: "
	lsblk
} >> "$REPORT_FILE" 2>&1

# Section 4: Network Diagnostics

{
	echo " "
	echo "======= NETWORK DIAGNOSTICS ======="
	ip addr
	echo "Routing table: "
	ip route
	echo "DNS configuration: "
	cat /etc/resolv.conf
	echo "External connectivity test: "
	ping -c 4 -W 2 1.1.1.1
	echo "DNS resolution test: "
	getent hosts google.com
} >> "$REPORT_FILE" 2>&1

# Section 5: Systemd Services

{
	echo " "
	echo "======= SYSTEMD SERVICES ======="
	echo "Overall system status: "
	systemctl is-system-running
	echo "Failed services: "
	systemctl --failed --no-pager
	echo "Running services: "
	systemctl list-units --type=service --state=running --no-pager
} >> "$REPORT_FILE" 2>&1

# Section 6: System Logs and Errors

{
	echo " "
	echo "======= SYSTEM LOGS AND ERRORS ======="
	echo "Recent system errors: "
	journalctl -p err -n 20 --no-pager
	echo "Recent boot warnings and errors: "
	journalctl -b -p warning -n 20 --no-pager
} >> "$REPORT_FILE" 2>&1

# Section 7: Final Report Summary
{
	echo " "
	echo "======= DIAGNOSTICS REPORT COMPLETE ======="
	echo "Report completed: $(date)"
	echo "Hostname: $(hostname)"
	echo "Review the sections above for potential issues."
} >> "$REPORT_FILE" 2>&1

echo "Diagnostics completed successfully."
echo "Report saved to: $REPORT_FILE"
