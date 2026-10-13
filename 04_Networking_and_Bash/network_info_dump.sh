#!/bin/bash

# Ubuntu Networking Lab
# Purpose: Display network information and save it to a file.

#Create a filename containing my name, date, and purpose
DATE=$(date +%Y-%m-%d)
OUTPUT="$HOME/networking_lab/rodriguez_${DATE}_network_info.txt"

#Displays information and save it to the ouput file
{
	echo "=============================================="
	echo "              NETWORK INFORMATION             "
	echo "=============================================="

	echo
	echo "Date: $(date)"

	echo
	echo "===== SERVER INFORMATION ====="
	hostnamectl

	echo
	echo "===== NETWORK INTERFACES ====="
	ip addr

	echo
	echo "===== ROUTING INFORMATION ====="
	ip route

	echo
	echo "===== DNS CONFIGURATION ====="
	resolvectl status

	echo
	echo "===== NETWORK SERVICE STATUS ====="
	systemctl is-active systemd-networkd

	echo
	echo "===== NETWORK CONNECTIVITY ====="
	ping -c 4 google.com

	echo
	echo "===== NETWORK TRACE (ICMP) ====="
	traceroute -I -m 10 -w 1 google.com
}  2>&1 | tee "$OUTPUT"

echo
echo "Report saved to $OUTPUT"
