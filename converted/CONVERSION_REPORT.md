# TAP Scripts — VMS to Linux Conversion: Full Deliverable

## Table of Contents

1. [Converted Shell Scripts](#1-converted-shell-scripts)
2. [Dependency Report](#2-dependency-report)
3. [Functional Analysis](#3-functional-analysis)
4. [Module Handling](#4-module-handling)
5. [Potential Risks & Differences](#5-potential-risks--differences)
6. [Suggested Improvements](#6-suggested-improvements)

---

## 1. Converted Shell Scripts

All converted scripts are in the `converted/` folder:

| VMS Original         | Linux Script               | Purpose                                      |
|----------------------|----------------------------|----------------------------------------------|
| `RSERC_CHK.COM`      | `rserc_chk.sh`             | Main TAP resource checker & RSERC monitor    |
| `DISK_CHECK.COM`     | `disk_check.sh`            | Disk space usage report                      |
| `TAP_SERVER_STAT.COM`| `tap_server_stat.sh`       | Server statistics collector & mailer         |
| `TAP_MONITOR.COM`    | `tap_monitor.sh`           | TAP file & process monitor daemon            |
| `TAP_RSERCFILES_TRANSFER.COM` | `tap_rsercfiles_transfer.sh` | RSERC/MRLOG file SFTP transfer to ABS |

---

## 2. Dependency Report

### 2.1 RSERC_CHK Dependencies

| Dependency                     | Type       | VMS Path / Logical                                    | Linux Equivalent                                         | Read/Write | Description                                                |
|-------------------------------|------------|------------------------------------------------------|----------------------------------------------------------|------------|-------------------------------------------------------------|
| Oracle Database                | DB/Service | OS Authentication (`sqlplus -s /`)                    | Same — Oracle OS auth via `sqlplus -s /`                  | Read       | Queries `service_providers`, `outgoing_outbound_call_files`, `PROCESS_STATISTICS` |
| Service Providers table        | DB Table   | Oracle schema                                         | Oracle schema                                             | Read       | `SELECT SP_ID FROM service_providers` — builds SPID list    |
| `outgoing_outbound_call_files` | DB Table   | Oracle schema                                         | Oracle schema                                             | Read       | RSERC hourly file count report                              |
| `PROCESS_STATISTICS`           | DB Table   | Oracle schema                                         | Oracle schema                                             | Read       | Roaming CDR hourly record count report                      |
| `rerun_rserc.sql`              | SQL Script | Current directory (VMS default)                       | `$SCRIPT_DIR/rerun_rserc.sql`                             | Read       | Re-runs failed RSERC for a given SP_ID                      |
| Archive directory              | Folder     | `DISK$CALL_DATA2:[TAP.OB.ARCHIVE]`                    | `/data/call_data2/tap/ob/archive`                         | Read       | Checks for `cd*.dat` files modified in last 4 hours         |
| Collect directory              | Folder     | `DISK$CALL_DATA:[TAP.OB.COLLECT]`                     | `/data/call_data/tap/ob/collect`                          | Read       | Counts `CD?????GBRCN*.dat` files                            |
| To_Price directory             | Folder     | `DISK$CALL_DATA:[TAP.OB.TO_PRICE]`                    | `/data/call_data/tap/ob/to_price`                         | Read       | Counts `CD?????GBRCN*.DAT` files                            |
| Priced directory               | Folder     | `DISK$CALL_DATA:[TAP.OB.PRICED]`                      | `/data/call_data/tap/ob/priced`                           | Read       | Counts `CD?????GBRCN*.PRC` files                            |
| Split directories (per SPID)   | Folder     | `DISK$CALL_DATA:[TAP.OB.SPLIT.<spid>]`                | `/data/call_data/tap/ob/split/<spid>`                     | Read       | Counts `CD*.SPLIT` files per SPID                           |
| Outgoing SP directory          | Folder     | VMS logical `tap_outgoing_sp:`                        | `/data/call_data/tap/ob/outgoing_sp`                      | Read/Write | Checks for `*.don` and `*.tmp` failure indicators; deletes `.tmp` |
| OB Period directory            | Folder     | VMS logical `tap_ob_period:`                          | `/data/call_data/tap/ob/period`                           | Write      | Deletes `*.tmp` during recovery                            |
| Log directory                  | Folder     | VMS logical `tap_log_dir:`                            | `/data/call_data/tap/log`                                 | Write      | `rserc_chk.log` written here; old logs cleaned after 30 days|
| `spid_list.lis`                | Temp File  | Current working directory                             | `/tmp/rserc_chk_$$/spid_list.lis`                         | Read/Write | Oracle spool output of SP_IDs                               |
| `files_created.lis`            | Temp File  | Current working directory                             | `/tmp/rserc_chk_$$/files_created.lis`                     | Read/Write | Oracle spool: hourly RSERC file counts                      |
| `files_created1.lis`           | Temp File  | Current working directory                             | `/tmp/rserc_chk_$$/files_created1.lis`                    | Read/Write | Oracle spool: file count for last 4 hours                   |
| `recs_created.lis`             | Temp File  | Current working directory                             | `/tmp/rserc_chk_$$/recs_created.lis`                      | Read/Write | Oracle spool: hourly CDR record counts                      |
| `rserc_chk.lis`                | Temp File  | Current working directory                             | `/tmp/rserc_chk_$$/rserc_chk.lis`                         | Read/Write | Queue status listing (assembly queue check)                 |
| `rserc_failure_1.txt`          | Temp File  | Current working directory                             | `/tmp/rserc_chk_$$/rserc_failure_1.txt`                   | Write      | Directory listing of leftover `.tmp` files                  |
| `rserc_failure_2.txt`          | Temp File  | Current working directory                             | `/tmp/rserc_chk_$$/rserc_failure_2.txt`                   | Write      | Directory listing of leftover `.don` files                  |
| `mrlog.lis`                    | Temp File  | Current working directory                             | `/tmp/rserc_chk_$$/mrlog.lis`                             | Read/Write | List of `mrlog*.tmp` files for recovery                     |
| VMS MAIL                       | Service    | VMS MAIL command                                      | `mailx` command                                           | Write      | Sends alerts and reports                                    |
| Email: L2 Support              | Service    | `Telefonica_UK.L2@accenture.com`                      | Same                                                      | Write      | Primary alert recipient                                     |
| Email: Apollo L2               | Service    | `VMO2_ApolloL2@accenture.com`                         | Same                                                      | Write      | CDR report recipient                                        |
| Email: TAP Support             | Service    | `TAPSupport@o2.com`                                   | Same                                                      | Write      | RSERC failure notifications                                 |

### 2.2 DISK_CHECK Dependencies

| Dependency       | Type       | VMS Method                          | Linux Equivalent     | Read/Write | Description                      |
|-----------------|------------|-------------------------------------|----------------------|------------|----------------------------------|
| Mounted disks    | System     | `F$DEVICE(,"DISK")` / `F$GETDVI()` | `df -T -P`           | Read       | Enumerates all mounted filesystems|
| Terminal (ANSI)  | System     | VT100 escape codes                  | ANSI escape codes    | Write      | Formatted display output          |

### 2.3 TAP_SERVER_STAT Dependencies

| Dependency                      | Type       | VMS Path / Logical                                 | Linux Equivalent                            | Read/Write | Description                                    |
|--------------------------------|------------|---------------------------------------------------|---------------------------------------------|------------|------------------------------------------------|
| `DISK_CHECK.COM_1`              | Module     | `DISK$USERDISK:[USER.varrej1]DISK_CHECK.COM_1`    | `disk_check.sh`                             | Execute    | Generates disk usage output                    |
| `asma.txt`                      | Temp File  | Current working directory                          | `/tmp/tap_server_stat_$$/asma.txt`           | Read/Write | Full disk check output                         |
| `SERVER_STAT.txt`               | Temp File  | Current working directory                          | `/tmp/tap_server_stat_$$/SERVER_STAT.txt`    | Read/Write | Filtered disk stats for target devices         |
| `TAPLIV_SERVER_STAT.TXT`        | Temp File  | Current working directory                          | `/tmp/tap_server_stat_$$/TAPLIV_SERVER_STAT.TXT` | Write  | Formatted TAPLIV stats for email               |
| `EDLIVE_SERVER_STAT.TXT`        | File       | `DISK$USERDISK:[USER.varrej1]`                     | `$HOME/EDLIVE_SERVER_STAT.TXT`               | Read       | External EDLIVE server stats (from another host)|
| `EMAIL.DIS`                     | Config     | Current directory                                  | `$SCRIPT_DIR/email.dis`                      | Read       | Email distribution list                        |
| VMS MAIL + uuencode             | Service    | `tcpip$uuencode.exe` + VMS MAIL                   | `mailx`                                      | Write      | Sends stats via email                          |
| `at` / cron                     | Service    | VMS `SUBMIT/AFTER`                                 | `at` or crontab                              | Write      | Self-scheduling for 2nd of next month          |

### 2.4 TAP_MONITOR Dependencies

| Dependency                       | Type       | VMS Path / Logical                          | Linux Equivalent                              | Read/Write | Description                                        |
|---------------------------------|------------|---------------------------------------------|-----------------------------------------------|------------|----------------------------------------------------|
| Oracle Database                  | DB/Service | `sqlplus /` with `EXIT 77`                  | Same                                          | Read       | Connectivity check + row count queries              |
| `incoming_outbound_call_files`   | DB Table   | Oracle schema                               | Oracle schema                                 | Read       | Counts for OBVP (`AP` status) and OBSP (`AS` status)|
| `tap_system_configuration`       | DB Table   | Oracle schema                               | Oracle schema                                 | Read       | GAPS/GSDM queue and process name config             |
| `tap_ib_receive_from_sdm:`       | Folder     | VMS logical                                 | `/data/call_data/tap/ib/receive_from_sdm`     | Read       | `ibr*.dat` files for IBCC check                     |
| `tap_ob_receive_from_dch:`       | Folder     | VMS logical                                 | `/data/call_data/tap/ob/receive_from_dch`     | Read       | `cd*.dat` + `td*.dat` files for OBCC check          |
| `tap_wrk_dir:`                   | Folder     | VMS logical                                 | `/data/call_data/tap/wrk`                     | Write      | Temp spool file `tap_monitor.lis`                   |
| `tap_com_dir:`                   | Folder     | VMS logical                                 | `/data/call_data/tap/com`                     | Read       | `tap_job_startup.sh` script                         |
| `tap_log_dir:`                   | Folder     | VMS logical                                 | `/data/call_data/tap/log`                     | Write      | Log files: `tap_gaps_01.log`, `tap_gsdm_01.log`     |
| `tap_job_startup` (COM/sh)       | Module     | `tap_com_dir:tap_job_startup`               | `tap_com_dir/tap_job_startup.sh`              | Execute    | Starts GAPS and GSDM background jobs                |
| `taplog_mess` (COM/sh)           | Module     | `tap_com_dir:taplog_mess`                   | Logger / inline logging                       | Execute    | Logging utility (replaced with inline `log_msg`)    |
| VMS Environment Variables        | Config     | VMS logicals: `TAP_FILE_CHECK_PERIOD`, etc. | Linux env vars: same names                    | Read       | Threshold configuration                            |
| VMS `REQUEST/REPLY`              | Service    | VMS operator console                        | `logger` + `mailx`                            | Write      | Operator alerts                                     |

### 2.5 TAP_RSERCFILES_TRANSFER Dependencies

| Dependency | Type | VMS Path / Logical | Linux Equivalent | Read/Write | Description |
|------------|------|-------------------|-----------------|------------|-------------|
| `RSERC_SFTP.CFG` | Config | `TAP_CFG_DIR:RSERC_SFTP.CFG` | `${TAP_CFG_DIR}/RSERC_SFTP.CFG` | Read | SFTP username (line 1) and hostname (line 2) |
| `FCS_RSERC_DIR` | Folder | VMS logical | `/data/tap/R53_TAPLIVE/TAP/FCS_RSERC` | Read | Source directory for `RSERC??????.DAT` files |
| `XI_DAT` | Folder | VMS logical | `/data/tap/R53_TAPLIVE/TAP/XI_DAT` | Read | Source directory for `MRLOG??????.DAT` files |
| `SFTP_TMP_DIR` | Folder | VMS logical | `/data/tap/R53_TAPLIVE/TAP/SFTP_TMP` | Read/Write | Staging area for files being transferred |
| `TAP_DAT_DIR` | Folder | VMS logical | `/data/tap/R53_TAPLIVE/TAP/DAT` | Read/Write | Control files: SFTP batch, rename script, delete script, flag file |
| `TAP_LOG_DIR` | Folder | VMS logical | `/data/tap/R53_TAPLIVE/TAP/LOG` | Write | Log file output; housekeeping deletes logs > 7 days |
| ABS Server | Remote | SFTP destination | `${DEST_USERNAME}@${DEST_HOSTNAME}` | Write | Remote system receiving RSERC/MRLOG files |
| `SFTP` | Command | VMS SFTP with `-b` batch | `sftp -b` (OpenSSH) | Execute | Batch file transfer |
| SSH Keys | Auth | N/A | `~/.ssh/id_rsa` or similar | Read | Key-based authentication for SFTP |
| `RSERC_TRANS_SHUTDOWN` | Env Var | VMS logical | Env var or flag file | Read | Graceful shutdown flag |
| `TAP_CLOSEDOWN_ALL` | Env Var | VMS logical | Env var (e.g., `23:00`) | Read | Time-based closedown threshold |
| `taplog_mess` | Module | `TAP_COM_DIR:TAPLOG_MESS` | Replaced with `log_msg()` | Execute | Logging utility |

---

## 3. Functional Analysis

### 3.1 RSERC_CHK.COM — Step-by-Step VMS Logic

| Step | VMS Section | What It Does |
|------|------------|--------------|
| 1 | `set proc/priv=all` + `submit/after=tomorrow"+6"` | Grants all privileges. Self-reschedules to run tomorrow at 06:00. |
| 2 | `sqlplus` → `spid_list.lis` | Queries `service_providers` table, spools all SP_IDs to `spid_list.lis`. |
| 3 | `start:` — Archive check | Checks `DISK$CALL_DATA2:[TAP.OB.ARCHIVE]` for `cd*.dat` files from last 4 hours (`/sin="-4"`). If none found, sends email alert. |
| 4 | `notify_check:` — Collect dir | Counts `CD?????GBRCN*.dat` files in `[TAP.OB.COLLECT]`. If count > 400, sends alert. |
| 5 | `to_price_check:` — Pricing dir | Counts `CD?????GBRCN*.DAT` files in `[TAP.OB.TO_PRICE]`. If count > 400, sends alert. |
| 6 | `priced_check:` — Priced dir | Counts `CD?????GBRCN*.PRC` files in `[TAP.OB.PRICED]`. If count > 400, sends alert. |
| 7 | `loop:` — Per-SPID split check | For each SPID from `spid_list.lis`, counts `CD*.SPLIT` files in `[TAP.OB.SPLIT.<spid>]`. If count > 600, sends alert. |
| 8 | `Rserc_created_and_CDRs_processed:` | Runs 3 Oracle queries via `sqlplus`: (a) Hourly RSERC file creation report, (b) File count from last 4 hours, (c) Hourly incoming roaming CDR report. |
| 9 | Email reports | Emails `files_created.lis` and `recs_created.lis` to L2 and Apollo. |
| 10 | `rserc_check:` | Parses `files_created1.lis` for `FILE_COUNT=`. If 0 files and not first run, sends "no RSERC created" alert. |
| 11 | `start_1:` — Assembly queue check | Lists assembly queues (`sh que *ass*`), searches for "dist". If distribution process NOT in queue, checks for failure indicators. |
| 12 | `.don` file check | If `*.don` files exist in `tap_outgoing_sp:`, emails failure alert. |
| 13 | `.tmp` file recovery | If `*.tmp` files exist in `tap_outgoing_sp:`, emails alert, then: extracts SP_IDs from `mrlog*.tmp` filenames, deletes `.tmp` files, runs `rerun_rserc.sql` for each unique SP_ID. |
| 14 | `check_hour:` | Compares current hour to last recorded hour. If hour changed → go to `start:` (full cycle). If 23:00 → exit. Otherwise wait 10 min and re-check failures. |
| 15 | `finish:` | Cleans up temp files; deletes logs older than 30 days. |

### 3.2 RSERC_CHK.sh — Converted Shell Script Logic

| Step | Function / Section | What It Does |
|------|-------------------|--------------|
| 1 | `schedule_next_run()` | Uses `at` to schedule tomorrow's 06:00 run (or advises cron). |
| 2 | Oracle `sqlplus` → `spid_list.lis` | Identical SQL query, output to temp file. |
| 3 | `check_tap_directories()` — Archive | Uses `find -mmin -240` to find files modified in last 4 hours. |
| 4 | `check_tap_directories()` — Collect | Uses `find -iname` with wildcard pattern, counts results. |
| 5 | `check_tap_directories()` — To_Price | Same approach with appropriate pattern. |
| 6 | `check_tap_directories()` — Priced | Same approach with appropriate pattern. |
| 7 | `check_tap_directories()` — Split loop | Reads `spid_list.lis`, zero-pads SPID to 3 digits with `printf "%03d"`, counts files. |
| 8 | `generate_hourly_reports()` | Runs the same 3 Oracle queries via heredoc to `sqlplus`. |
| 9 | `send_report()` | Uses `mailx` to email report files. |
| 10 | RSERC zero-check | Greps `files_created1.lis` for `FILE_COUNT=`, extracts number. |
| 11 | `check_rserc_failures()` — Queue check | Uses `ps -ef | grep` as substitute for VMS `SHOW QUEUE`. |
| 12 | `.don` file check | Uses `find -iname '*.don'` with `-ls` for directory listing. |
| 13 | `.tmp` recovery | Uses `find` to list/delete `.tmp` files, `awk` to extract SP_IDs, loops through `sqlplus` calls. |
| 14 | `main()` — Loop control | Outer `while true` for hourly cycle, inner `while true` for 10-minute failure checks. Exits at hour 23. |
| 15 | `cleanup_and_exit()` | Removes temp files, deletes logs > 30 days via `find -mtime +30`. |

### 3.3 TAP_RSERCFILES_TRANSFER.COM — Step-by-Step VMS Logic

| Step | VMS Section | What It Does |
|------|------------|--------------|
| 1 | `SAVE_ENVIRONMENT` | Saves DCL state (default dir, messages, control codes). Sets up symbols, escape codes, process name. |
| 2 | `CHECK_INSTANCES` | Renames process to `RSERC_TRANS`. If rename fails (already running), exits to prevent multiple instances. |
| 3 | Logical checks | Validates `TAP_CFG_DIR`, `XI_DAT`, `FCS_RSERC_DIR`, `RSERC_TRANS_SHUTDOWN`, `SFTP_TMP_DIR`, and SFTP config file. |
| 4 | `HOUSE_KEEP` | Deletes log files older than 7 days from `TAP_LOG_DIR`. |
| 5 | `EXTRACT_SFTP` | Reads SFTP username and hostname from `RSERC_SFTP.CFG`. |
| 6 | `SELF_RECOVERY` | Cleans temp dir. If `SFTP_ABS_IN_PROGRESS.FLAG` exists, recovers: (1) removes partial `.SFTP_TMP_RS` files from remote, (2) rename recovery (commented out in original), (3) runs pending local deletes. |
| 7 | `MAIN_LOOP` | Creates 3 control files: SFTP batch, remote rename batch, local delete script. |
| 8 | `RSERC_FILE_COUNT` | Loops up to 50 `RSERC??????.DAT` files from `FCS_RSERC_DIR`. Copies to temp dir with `.SFTP_TMP_RS` extension, adds to all 3 control files. |
| 9 | `MRLOG_FILE_COUNT` | Same for `MRLOG??????.DAT` from `XI_DAT`, up to 50 files. If no files at all, waits 10 minutes. |
| 10 | `SFTP_PROCESS` | Creates flag. SFTPs files. Renames remote files (`.SFTP_TMP_RS` → `.DAT`). Deletes local source files. Removes flag. |
| 11 | `FINAL_CHECK` | Checks time > `TAP_CLOSEDOWN_ALL` or `RSERC_TRANS_SHUTDOWN=Y`. If so, exits; otherwise loops back. |
| 12 | `ERROR` | Logs error, sends operator request, exits with status 4. |

### 3.4 TAP_RSERCFILES_TRANSFER.sh — Converted Shell Script Logic

| Step | Function / Section | What It Does |
|------|-------------------|--------------|
| 1 | `acquire_lock()` | Uses `flock` for single-instance enforcement (replaces VMS `SET PROCESS /NAME=`). |
| 2 | `validate_environment()` | Checks all required env vars and directories exist. |
| 3 | `housekeeping()` | Deletes old logs via `find -mtime +7 -delete`. |
| 4 | `read_sftp_config()` | Reads username/hostname from config file. |
| 5 | `self_recovery()` | Three-stage recovery matching VMS logic. |
| 6 | `main_loop()` — collect | Creates batch/rename/delete files, calls `collect_rserc_files()` and `collect_mrlog_files()`. |
| 7 | `collect_rserc_files()` | Uses `find -name 'RSERC??????.DAT'`, copies with `.sftp_tmp_rs` extension, caps at 50. |
| 8 | `collect_mrlog_files()` | Uses `find -name 'MRLOG??????.DAT'`, same approach, caps at 50. |
| 9 | `sftp_transfer()` | Three-step: upload, rename on remote, delete local sources. Flag file for crash recovery. |
| 10 | `should_shutdown()` | Checks env var, flag file, and time-based closedown. |
| 11 | `main()` | Orchestrates: lock → validate → housekeep → config → recover → loop. |

### 3.5 Key Differences Between VMS and Shell Versions

| Aspect | VMS (DCL) | Linux (Bash) | Impact |
|--------|-----------|--------------|--------|
| **File versioning** | VMS files have versions (`;*`). `delete file;*` removes all versions. | Linux has no file versioning. `rm file` removes the file. | No behavioral difference — cleanup works the same. |
| **Scheduling** | `SUBMIT/AFTER=TOMORROW"+6"` — built-in batch scheduler. | `at` command or cron. Cron is recommended for reliability. | Must configure cron manually. |
| **Queue system** | `SHOW QUEUE *ASS*` — VMS batch queues. | `ps -ef \| grep` — process listing. | Less accurate; consider a proper job scheduler (systemd timer, etc.). |
| **File counting** | `DIR ... /TOT` piped through parsing. Complex pipe/search construct. | `find ... \| wc -l` — simpler and more reliable. | Simplified; same result. |
| **SPID formatting** | `f$fao("!3ZL",...)` — zero-padded 3-digit. | `printf "%03d"` — identical behavior. | No difference. |
| **Date filtering** | `DIR .../sin="-4"` — files modified since 4 hours ago. | `find -mmin -240` — files modified in last 240 minutes. | Equivalent. |
| **Email** | VMS MAIL command with `/SUB=` qualifier. | `mailx -s` — standard Linux mailer. | Must ensure `mailx` is configured with SMTP relay. |
| **Error continuation** | `SET NOON` — continue on error. | `set +e` implicit (bash default). Scripts don't use `set -e`. | Same behavior — scripts continue on errors. |
| **Privilege escalation** | `SET PROC/PRIV=ALL` — VMS per-process privileges. | Run as appropriate user (root or service account). | Ensure script runs with correct filesystem/DB permissions. |
| **Oracle SPOOL** | Spools to local file from sqlplus. | Same, but path must be writable by the Oracle OS user. | May need to adjust `SPOOL` path or use shell redirection. |
| **Case sensitivity** | VMS is case-insensitive for filenames. | Linux is case-sensitive. `find -iname` used for compatibility. | Using `-iname` preserves VMS behavior. |

---

## 4. Module Handling

### 4.1 Called Modules

| Module | Called By | VMS Invocation | Linux Equivalent | Status |
|--------|-----------|---------------|------------------|--------|
| `rerun_rserc.sql` | `RSERC_CHK` | `sqlplus -s / @rerun_rserc "''sp_id'"` | `sqlplus -s / @rerun_rserc.sql "${sp_id}"` | **Not converted** — SQL script referenced as-is. Must be present alongside `rserc_chk.sh`. |
| `DISK_CHECK.COM_1` | `TAP_SERVER_STAT` | `@DISK_CHECK.COM_1;/out=asma.txt` | `disk_check.sh U T > asma.txt` | **Converted** as `disk_check.sh`. |
| `EMAIL.DIS` | `TAP_SERVER_STAT` | `@EMAIL.DIS;` — VMS mail distribution list | `email.dis` — text file with recipients, one per line | **Not converted** — config file, must be created manually. |
| `tap_job_startup` | `TAP_MONITOR` | `tap_com_dir:tap_job_startup` | `tap_com_dir/tap_job_startup.sh` | **Converted** as `tap_job_startup.sh`. Generic job wrapper: validates 3 params, singleton via flock, runs executable, cleans up closedown flag. |
| `taplog_mess` | `TAP_MONITOR`, `TAP_RSERCFILES_TRANSFER` | `@tap_com_dir:taplog_mess` | Replaced with inline `log_msg()` function | **Replaced** with inline logging. |

### 4.2 Placeholder: rerun_rserc.sql

This SQL script is called by RSERC_CHK when `.tmp` files are found (RSERC failure recovery). It accepts one parameter — the SP_ID — and presumably re-triggers the RSERC assembly process for that service provider. The script must be placed in the same directory as `rserc_chk.sh` or its path updated in the configuration.

### 4.3 Converted: tap_job_startup.sh

This is the TAP batch job startup script called by TAP_MONITOR to submit GAPS and GSDM jobs. Now fully converted as `tap_job_startup.sh`. It receives 3 parameters:
1. Process type (`GAPS` or `GSDM`)
2. Instance number (`01`)
3. Program name (executable or `.sh` script in `TAP_EXE_DIR`)

Features: parameter validation, singleton enforcement via `flock`, closedown flag cleanup, structured logging, operator alerts. Full documentation in `TAP_JOB_STARTUP_MIGRATION_DOCUMENT.md`.

### 4.4 Placeholder: email.dis

VMS email distribution list file. On Linux, create a plain text file with one email address per line:
```
user1@example.com
user2@example.com
```

---

## 5. Potential Risks & Differences

### 5.1 High Risk

| Risk | Description | Mitigation |
|------|-------------|------------|
| **Oracle SPOOL paths** | `sqlplus` SPOOL writes to the DB server if remote. On VMS, the DB was local. | Verify Oracle runs locally, or replace SPOOL with shell redirection: `sqlplus ... <<SQL > output.lis`. |
| **VMS queue system** | VMS `SHOW QUEUE *ASS*` is a proper queue manager. `ps -ef \| grep` is a rough equivalent. | Consider integrating with a Linux job scheduler (systemd, cron, or Oracle DBMS_SCHEDULER). |
| **rerun_rserc.sql** unavailable | This SQL script was not provided. If it doesn't exist, RSERC recovery will fail. | Obtain and test the SQL script. Ensure it's idempotent. |
| **File pattern case sensitivity** | VMS is case-insensitive; Linux is case-sensitive. | All `find` commands use `-iname` (case-insensitive). Verify actual filenames on Linux. |
| **SFTP batch rename** | VMS SFTP supports wildcard rename; standard OpenSSH SFTP does not. | TAP_RSERCFILES_TRANSFER generates per-file rename commands (already handled). |
| **SFTP key authentication** | VMS may use password auth. Linux script assumes key-based auth. | Set up SSH key pair between TAP and ABS servers before deployment. |

### 5.2 Medium Risk

| Risk | Description | Mitigation |
|------|-------------|------------|
| **Mail configuration** | VMS MAIL is built-in. Linux `mailx` needs SMTP config. | Configure `/etc/mail.rc` or use `sendmail`/`postfix`. Test with: `echo test \| mailx -s test user@example.com` |
| **Self-scheduling** | VMS `SUBMIT/AFTER` is atomic. `at` command may not be available on all Linux systems. | Prefer cron for scheduling. Add entries: `0 6 * * * /path/to/rserc_chk.sh` |
| **Directory structure** | VMS paths like `DISK$CALL_DATA:[TAP.OB.COLLECT]` must map correctly to Linux. | All paths are configurable at the top of each script. Verify and update before first run. |
| **RSERC failure detection** | VMS checks assembly queues. Linux substitute (`ps -ef`) may miss processes. | Consider using a dedicated process monitoring tool or PID files for critical processes. |

### 5.3 Low Risk

| Risk | Description | Mitigation |
|------|-------------|------------|
| **Temp file cleanup** | VMS file versions prevent accidental overwrites. Linux doesn't have this. | PID-based temp directories (`/tmp/rserc_chk_$$`) are used to avoid collisions. |
| **Log rotation** | VMS versions auto-managed. Linux needs explicit cleanup. | `find -mtime +30 -delete` handles this. Consider `logrotate` for production. |

---

## 6. Suggested Improvements

### 6.1 For Production Readiness

1. **Use cron instead of `at`** for all self-scheduling:
   ```crontab
   # RSERC_CHK: Run daily at 06:00
   0 6 * * * /opt/tap/scripts/rserc_chk.sh >> /data/call_data/tap/log/rserc_chk.log 2>&1

   # TAP_SERVER_STAT: Run on 2nd of each month at 08:00
   0 8 2 * * /opt/tap/scripts/tap_server_stat.sh >> /data/call_data/tap/log/tap_server_stat.log 2>&1

   # TAP_MONITOR: Run at system startup (or via systemd service)
   @reboot /opt/tap/scripts/tap_monitor.sh >> /data/call_data/tap/log/tap_monitor.log 2>&1

   # TAP_RSERCFILES_TRANSFER: Run at system startup (continuous daemon)
   @reboot /opt/tap/scripts/tap_rsercfiles_transfer.sh >> /data/call_data/tap/log/tap_rsercfiles_transfer.log 2>&1
   ```

2. **Replace `sqlplus` SPOOL with shell redirection** for more portable Oracle interaction:
   ```bash
   sqlplus -s / <<'SQL' > output.lis 2>&1
   SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
   SELECT ... FROM ...;
   EXIT
   SQL
   ```

3. **Create a shared configuration file** (e.g., `tap_config.sh`) sourced by all scripts:
   ```bash
   # tap_config.sh
   export DISK_CALL_DATA="/data/call_data"
   export TAP_LOG_DIR="${DISK_CALL_DATA}/tap/log"
   export EMAIL_L2="Telefonica_UK.L2@accenture.com"
   # ... etc
   ```

4. **Add `set -o pipefail`** to catch errors in piped commands.

5. **Use `logrotate`** instead of manual log cleanup.

6. **Create a systemd service** for `tap_monitor.sh` instead of running it as a background cron job:
   ```ini
   [Unit]
   Description=TAP Monitor Service
   After=network.target oracle.service

   [Service]
   Type=simple
   ExecStart=/opt/tap/scripts/tap_monitor.sh
   Restart=on-failure
   User=taplive

   [Install]
   WantedBy=multi-user.target
   ```

### 6.2 Deployment Checklist

- [ ] Update all directory paths in each script's configuration section
- [ ] Verify Oracle connectivity: `sqlplus -s / <<< "SELECT 1 FROM DUAL; EXIT;"`
- [ ] Verify `mailx` is configured and can send external email
- [ ] Place `rerun_rserc.sql` in the script directory
- [ ] Create `email.dis` distribution list file
- [ ] Set file permissions: `chmod 750 *.sh`
- [ ] Set up cron entries (see above)
- [ ] Create required temp/log directories
- [ ] Test each script individually in a non-production environment
- [ ] Verify case-sensitivity of filenames on the target Linux filesystem
