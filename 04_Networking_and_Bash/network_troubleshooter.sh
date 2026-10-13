#!/bin/bash

# Ubuntu Networking Troubleshooter
# Purpose: Purpose: Help troubleshoot ubuntu and CentOS networking.
# This script uses variables, conditionals and a loop.

echo "=========================================="
echo "       LINUX NETWORK TROUBLESHOOTER       "
echo "=========================================="

# Ask the user to select a Linux server.
echo "Which Linux Server are you using?"
echo "1. Ubuntu"
echo "2. CentOS"
read distro

# Check the user's selection.
if [ "$distro" = "1" ]
then
	echo "You selected Ubuntu."
elif [ "$distro" = "2" ]
then
	echo "You selected CentOS."
else
	echo "Invalid server selection."
	exit 1
fi

# Repeat the menu until the user chooses to exit.
choice=0

while [ "$choice" != "6" ]
do
	echo
	echo "===== NETWORK TROUBLESHOOTING MENU ====="
	echo "1. No Internet connection"
	echo "2. Configure a static IP address"
	echo "3. Check DNS settings"
	echo "4. Run traceroute"
	echo "5. Check network interfaces"
	echo "6. Exit"
	echo "Enter your choice:"
	read choice

	case "$choice" in

		1)
			echo "Check your IP address:"
			echo "ip addr"
			echo "Check your default gateway:"
			echo "ip route"
			echo "Test your Internet Connection:"
			echo "ping -c 4 8.8.8.8"

			if [ "$distro" = "1" ]
			then
				echo "Check Ubuntu network services:"
				echo "systemctl status systemd-networkd"
			else
				echo "Check CentOS network service:"
				echo "systemctl status NetworkManager:"
			fi
			;;

		2)
			echo "STATIC IP CONFIGURATION"

			if [ "$distro" = "1" ]
			then
				echo "Ubuntu uses Netplan."
				echo "Find your configuration file:"
				echo "ls /etc/netplan"
				echo "Edit the correct YAML file:"
				echo "sudo nano /etc/netplan/00-installer-config.yaml"
				echo "After editing, test the configuration:"
				echo "sudo netplan try"
				echo "Check your IP address:"
				echo "ip addr"
			else
				echo "CentOS uses NetworkManager."
				echo "View your connections:"
				echo "nmcli connection show"
				echo "Use nmcli to configure a static IP."
				echo "Check your IP address:"
				echo "ip addr"
			fi
			;;
		3)
			echo "DNS TROUBLESHOOTING"
			if [ "$distro" = "1" ]
			then
				echo "Check Ubuntu DNS settings:"
				echo "resolvectl status"
			else
				echo "Check CentOS DNS settings:"
				echo "nmcli device show"
			fi

			echo "View the DNS resolver file:"
			echo "cat /etc/resolv,conf"
			echo "Test domain name resolution:"
			echo "ping -c 4 google.com"
			;;
		4)
			echo "Enter a website to trace:"
			read website

			if [ -z "$website" ]
			then
				echo "No website was entered."
			else
				echo "Run this ICMP traceroute command:"
				echo "traceroute -I $website"
			fi
			;;
		5)
			echo "NETWORK INTERFACE INFORMATION"
			echo "View IP addresses:"
			echo "ip addr"
			echo "View routing information:"
			echo "ip route"
			;;
		6)
			echo "Exiting the troubleshooting script."
			;;
		*)
			echo "Invalid option. Try again."
			;;
	esac
done
