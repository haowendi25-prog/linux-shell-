# Shell-Based System Administration Toolkit (Bash CLI Project)

A Linux-based automation toolkit developed using Bash scripting for the Operating Systems Laboratory course.

---

## Overview

This project automates common system administration tasks such as user monitoring, disk cleanup, backup management, and system health analysis. It also includes additional modules like student management, CSV export, and attendance tracking.

---

## Features

* User Monitoring (who, w, last)
* Disk Cleanup Automation
* Backup System with timestamp
* System Health Check (CPU, RAM, Disk usage)
* Student Management System
* CSV Export for student data
* Attendance tracking using login logs
* Secure login with hidden password input
* Activity logging system
* ASCII-based system flow diagram
* Structured CLI interface

---

## Concepts Used

* Bash Shell Scripting
* Linux System Commands
* File Handling
* Process Monitoring
* Automation
* Logging System
* Data Export (CSV)

---

## Requirements

* Linux Operating System (Ubuntu recommended)
* Bash Shell
* Basic terminal knowledge

---

## How to Run

1. Clone the repository:
   git clone https://github.com/nafis-ak/Shell-System-Admin-Toolkit.git

2. Navigate to project folder:
   cd Shell-System-Admin-Toolkit

3. Give permission:
   chmod +x main.sh

4. Run the program:
   ./main.sh

---

## Default Login Credentials
(Add here 👇)

Username: admin  
Password: 12345

---

## Project Structure

```
project/
│
├── main.sh
├── data/
│   ├── students.txt
│   └── students.csv
├── logs/
│   └── activity.log
├── backup/
│   └── *.tar.gz
└── README.md
```

---

## Automation (Cron Scheduling Example)

```bash
crontab -e
```

```bash
0 2 * * * bash /home/username/main.sh
```

---

## Sample Outputs

* Backup files are stored in the backup directory with timestamp
* Logs are recorded in logs/activity.log
* CSV export is saved in data/students.csv

---

## Developed By

Md. Asif Khandoker
Operating Systems Laboratory Project

---

## Version

v3.0 – Final Version

---

## Quote

"Automate everything you can. Human time is valuable."
