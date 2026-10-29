# ACME-1842 — Security Monitoring Lab

## Project Overview

This project was completed as part of my CIS-245 Linux Administration coursework. The goal was to develop, test, and compare two Bash security monitoring scripts generated using different AI assistants: ChatGPT and Claude.

Both scripts were tested on CentOS Stream 10 and Ubuntu to evaluate their functionality, compatibility, and effectiveness for basic Linux security monitoring.

## Repository Files

- **gpt_security_monitor.sh** — Security monitoring script generated using ChatGPT.
- **claude_sec_monitor.sh** — Security monitoring script generated using Claude.

## Security Monitoring Features

The scripts were developed to perform basic Linux security checks, including:

- Detecting failed SSH login attempts.
- Checking for user accounts with UID 0.
- Identifying accounts with empty passwords.
- Listing listening network ports and services.
- Generating timestamped security reports.
- Returning exit codes to indicate monitoring results.

## Testing Environment

| System | Operating System |
|---|---|
| Server 1 | CentOS Stream 10 |
| Server 2 | Ubuntu Linux |

The scripts were initially created on Windows and transferred to the Linux virtual machines using WinSCP.

Testing included checking script execution, correcting formatting issues, reviewing generated reports, testing security detection conditions, and configuring scheduled execution using cron.

## Troubleshooting and Observations

During testing, I encountered Windows-to-Linux line-ending compatibility issues and corrected them before continuing.

I also tested the monitoring thresholds and reviewed differences between the two AI-generated implementations.

Both scripts were evaluated for their ability to run on CentOS and Ubuntu.

## Skills Demonstrated

- Bash scripting
- Linux system administration
- Security monitoring
- SSH log analysis
- Network service inspection
- Cron job scheduling
- Troubleshooting and debugging
- GitHub version control
- AI-generated code evaluation

## Project Purpose

This lab provided practical experience in reviewing, testing, and troubleshooting AI-generated Bash scripts while developing foundational Linux security monitoring skills.
