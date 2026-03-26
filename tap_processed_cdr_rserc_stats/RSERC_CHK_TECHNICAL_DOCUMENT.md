# RSERC CHK — Comprehensive Technical Document

**Script Name:** `rserc_chk.sh` (Linux Bash)
**Converted From:** `RSERC_CHK.COM` (VMS DCL)
**Description:** TAP outbound directory monitoring, hourly RSERC/CDR report generation, and automatic RSERC failure recovery

---

## 1. Overview

### What is this system?

The RSERC CHK script is a **continuous monitoring and reporting daemon** that runs within a telecom billing environment as part of the **Transferred Account Procedure (TAP)** system. TAP is a GSMA standard used by mobile network operators worldwide to exchange billing records for roaming calls.

### Background: What is VMS and DCL?

If you are unfamiliar with the original platform, here is a brief primer:

- **VMS (Virtual Memory System)**, also called **OpenVMS**, is an operating system developed by Digital Equipment Corporation (DEC) in the 1970s. It was widely used in telecom and banking for its stability and security. It is **not** Unix/Linux — it has its own file system, command language, batch queue system, and mail system.
- **DCL (Digital Command Language)** is the scripting/command language of VMS — analogous to Bash on Linux. DCL scripts have the `.COM` extension and every command line starts with a dollar sign (`$`).
- **Logical names** (VMS) are similar to Linux environment variables. For example, `DISK$CALL_DATA:[TAP.OB.COLLECT]` is a VMS file path where `DISK$CALL_DATA:` is a logical name (like a mount point), and `[TAP.OB.COLLECT]` is the directory path (using `.` instead of `/`).
- **VMS file versioning**: VMS keeps multiple versions of every file (`;1`, `;2`, etc.). `DEL file;*` deletes all versions, unlike Linux where each filename is unique.
- **VMS batch queues**: VMS has a built-in job scheduler (`SUBMIT`, `SHOW QUEUE`, `START/QUE`, `STOP/QUE`). On Linux, this is replaced by `cron`, `at`, or process managers like `systemd`.
- **`NL:`** in VMS is the null device (equivalent to `/dev/null` on Linux).
- **`SYS$OUTPUT`** is VMS standard output (equivalent to `stdout`).
- **`$STATUS`** holds the exit status after each command (like `$?` in Bash). `%X00000001` means success; other values mean failure.

The original `RSERC_CHK.COM` was a VMS DCL batch script that ran daily. It has been converted to `rserc_chk.sh` (Linux Bash) while preserving the same monitoring logic, alert messages, and recovery behavior.

### What problem does it solve?

When roaming call data records (CDRs) are processed through the TAP outbound pipeline, files pass through multiple stages:

1. **Collection** — Raw call data files (`CD*GBRCN*.dat`) are gathered
2. **Pricing** — Files are tariffed and rated (`CD*GBRCN*.DAT` in `TO_PRICE`)
3. **Splitting** — Priced files are split per service provider/destination (`CD*.SPLIT` in per-SPID directories)
4. **Assembly (RSERC)** — Split files are assembled into RSERC records for inter-operator settlement
5. **Distribution** — Assembled RSERCs are dispatched to partner networks

If any stage stalls (files pile up beyond safe limits), billing to partner operators is delayed and revenue is at risk. Additionally, the RSERC assembly process itself can fail, leaving behind orphaned `.tmp` and `.don` files that must be detected and recovered.

The RSERC CHK script exists to:

- **Detect directory backlogs** — Alert operators when file counts exceed configured thresholds at any pipeline stage
- **Generate hourly reports** — Query Oracle for RSERC file and CDR processing statistics and email them to L2 support
- **Detect zero-output conditions** — Alert if no RSERCs have been created in the last 4 hours
- **Auto-recover failed RSERCs** — Detect orphaned `.tmp` files from failed assembly runs, clean them up, and re-trigger the RSERC assembly for affected service providers
- **Detect `.don` leftover files** — Alert support when `.don` files are left behind (indicating an incomplete distribution)

### Where is it used?

This script runs on a **Linux/RHEL production server** (migrated from OpenVMS) as part of the TAP billing pipeline. It operates as a long-running background process, starting at 06:00 each day and running continuously until 23:00, then re-submitting itself for the next day.

---

## 2. High-Level Workflow

### End-to-End Flow (Step by Step)

```
   ┌───────────────────────────────────────────────────────┐
   │                   SCRIPT STARTS                        │
   └──────────────────────┬────────────────────────────────┘
                          │
                          ▼
   ┌───────────────────────────────────────────────────────┐
   │  SCHEDULE NEXT RUN                                    │
   │  Use at/cron to start again tomorrow at 06:00         │
   └──────────────────────┬────────────────────────────────┘
                          │
                          ▼
   ┌───────────────────────────────────────────────────────┐
   │  GENERATE SPID LIST                                   │
   │  Query Oracle for all service_providers.SP_ID values  │
   │  Write to spid_list.lis                               │
   └──────────────────────┬────────────────────────────────┘
                          │
                          ▼
   ┌──────────────── OUTER LOOP (hourly) ──────────────────┐
   │                                                        │
   │  1. CHECK TAP DIRECTORIES                              │
   │     a. Archive: any cd*.dat files in last 4 hours?     │
   │        NO → ALERT "No Call files processed"           │
   │     b. Collect: CD?????GBRCN*.dat count > 400?         │
   │        YES → ALERT backlog in collection              │
   │     c. To-Price: CD?????GBRCN*.DAT count > 400?        │
   │        YES → ALERT backlog in pricing                 │
   │     d. Priced: CD?????GBRCN*.PRC count > 400?          │
   │        YES → ALERT backlog in splitting               │
   │     e. Per-SPID Split: CD*.SPLIT count > 600?          │
   │        YES → ALERT backlog for that SPID              │
   │                                                        │
   │  2. GENERATE HOURLY REPORTS (Oracle)                   │
   │     a. Query RSERC file creation stats by hour         │
   │     b. Query roaming CDR processing stats by hour      │
   │     c. Email reports to L2 / Apollo                    │
   │     d. Check if zero RSERCs in last 4 hours            │
   │        YES (and not first run) → ALERT               │
   │                                                        │
   │  3. Record last_hour                                   │
   │                                                        │
   │  ┌──────── INNER LOOP (every 10 min) ────────────┐    │
   │  │                                                │    │
   │  │  4. CHECK RSERC FAILURES                       │    │
   │  │     a. Is assembly/dist process running?        │    │
   │  │        YES → skip failure checks               │    │
   │  │     b. Any *.don files in TAP_OUTGOING_SP?      │    │
   │  │        YES → ALERT + email listing             │    │
   │  │     c. Any *.tmp files in TAP_OUTGOING_SP?      │    │
   │  │        YES → ALERT + auto-recovery:            │    │
   │  │           - List mrlog*.tmp filenames           │    │
   │  │           - Delete all .tmp from OG_SP + PERIOD │    │
   │  │           - Extract SP_IDs from mrlog filenames │    │
   │  │           - Re-run RSERC assembly per SP_ID     │    │
   │  │                                                │    │
   │  │  5. CHECK HOUR                                  │    │
   │  │     cur_hour == "23" → EXIT (finish)           │    │
   │  │     cur_hour > last_hour → break to outer loop │    │
   │  │     Otherwise → sleep 10 minutes, repeat       │    │
   │  │                                                │    │
   │  └────────────────────────────────────────────────┘    │
   │                                                        │
   └────────────────────────────────────────────────────────┘
                          │
                          ▼ (on exit or hour == 23)
   ┌───────────────────────────────────────────────────────┐
   │  CLEANUP AND EXIT                                     │
   │  Delete logs older than 30 days                       │
   │  Remove temp files (rserc_failure*.txt, rserc_chk.lis,│
   │   spid_list.lis, work directory)                      │
   │  Log "RSERC_CHK completed"                            │
   └───────────────────────────────────────────────────────┘
```

### Startup Behavior

1. The script schedules itself to run again tomorrow at 06:00 via `at` (or relies on a cron entry).
2. A SPID (Service Provider ID) list is generated by querying Oracle.
3. The run counter is initialized to 0.
4. Signal handlers are registered (EXIT, SIGTERM, SIGINT trigger cleanup).

### Loop Behavior

The script uses a **two-level loop structure**:

- **Outer loop** (hourly): Runs the full directory check + Oracle hourly reports each time the clock hour advances.
- **Inner loop** (every 10 minutes): Checks for RSERC assembly failures between hourly report runs.

### Exit Conditions

- The script exits when the current hour reaches `23` (11 PM).
- On exit, temporary files and old logs are cleaned up.

---

## 3. Core Functional Areas

### 3.1 Directory Backlog Monitoring

Five distinct directories are monitored for file accumulation:

| Directory | File Pattern | Threshold | Alert Message |
|-----------|-------------|-----------|---------------|
| `TAP_ARCHIVE_DIR` | `cd*.dat` (< 4 hours old) | At least 1 file | "No Call files processed by TAP collection in last four hours" |
| `TAP_COLLECT_DIR` | `CD?????GBRCN*.dat` | > 400 (MAX) | "There are N files in tap collection" |
| `TAP_READY_FOR_PRICING` | `CD?????GBRCN*.DAT` | > 400 (MAX) | "There are N files in TAP pricing" |
| `TAP_OB_PRICED` | `CD?????GBRCN*.PRC` | > 400 (MAX) | "There are N files in TAP spliting" |
| `TAP_OB_SPLIT/<SPID>` | `CD*.SPLIT` | > 600 (SPLIT_MAX) | "There are N files in TAP Distribute for spid XXX" |

The per-SPID check iterates through all service providers returned by the Oracle query, zero-pads each to 3 digits, and checks the corresponding split subdirectory.

### 3.2 Oracle Hourly Reporting

Two SQL reports are generated every hour:

**Report 1 — RSERC File Report:**
- Queries `outgoing_outbound_call_files` table
- Groups RSERC file creation by hour for the current day
- Shows `DATE | HOUR | FILES_PROCESSED` with a daily total
- Emailed to L2 with subject: `"TAP - Processed RESRC File Report"`

**Report 2 — Roaming CDR Report:**
- Queries `PROCESS_STATISTICS` table (where `PS_PROCESS_NAME='PRICING'`)
- Groups CDR processing by hour for the current day
- Shows `DATE | HOUR | RECORDS_PROCESSED` with a daily total
- Emailed to L2 and Apollo with subject: `"TAP - Processed roaming CDRs Report"`

**Zero-RSERC Check:**
- A separate query counts files created in the last 4 hours (`TRUNC(SYSDATE-4/24)`)
- If the count is 0 and it is not the first iteration, an alert is sent: `"There are no RSERC created in last 4 hours"`

### 3.3 RSERC Failure Detection and Auto-Recovery

This is the most complex section. When the RSERC assembly process (`dist`) is not currently running, the script checks for leftover artifacts:

**`.don` files** — These indicate that the distribution phase completed partially. An alert is sent with a file listing emailed to TAP Support and L2. No automatic recovery is performed.

**`.tmp` files** — These indicate that the assembly phase failed mid-execution. The script performs automatic recovery:
1. Lists all `mrlog*.tmp` filenames (excluding `*.dat`)
2. Deletes all `.tmp` files from `TAP_OUTGOING_SP` and `TAP_PERIOD_DIR`
3. Extracts the SP_ID from each mrlog filename (at character position 35)
4. Deduplicates the SP_ID list
5. Calls `rerun_rserc.sql` via `sqlplus` for each unique SP_ID to re-trigger assembly

### 3.4 Self-Scheduling

The script re-submits itself for the next day at 06:00 using the `at` command. If `at` is unavailable, it logs a warning suggesting cron be configured instead.

---

## 4. Function-by-Function Explanation

---

### 4.1 `log_msg()`

**Purpose:** Writes a timestamped message to both stdout and the log file.

**Input:**
- `$1` — The message text

**Internal Logic:**
1. Generate timestamp in `DD-Mon-YYYY HH:MM:SS` format using `date`
2. Construct: `<timestamp> - <message>`
3. Write to stdout and append to `LOG_FILE` via `tee -a`

**Output:** Formatted log line on stdout; appended to the log file.

**Return Values:** Always 0.

**VMS Equivalent Explained:**
The original VMS script uses:
```dcl
$ dttm=f$time()
$ wso "''dttm' - RSERC CHK started"
```
- `f$time()` is a VMS built-in function that returns the current date/time.
- `wso` is a symbol (alias) defined earlier: `wso="write sys$output"`, which writes text to standard output (the terminal or log).
- `''dttm'` is VMS variable substitution (equivalent to `${dttm}` in Bash). The double single-quotes force symbol substitution.
- There is no built-in `tee` equivalent in VMS; the script writes to `SYS$OUTPUT` and VMS batch queue redirects the output to the log file specified at `SUBMIT` time.

On Linux, `tee -a "${LOG_FILE}"` writes to both stdout AND appends to the log file simultaneously.

**How to Test on the Test Server:**

| Pre-requisite | Details |
|--------------|---------|
| Bash 4+ | `bash --version` — must be 4.0 or higher |
| Writable log directory | `TAP_LOG_DIR` must exist and be writable by the test user |
| Script sourced | Script must be sourced (not executed) so you can call functions directly |

**Manual Test Steps:**
```bash
# 1. Set up environment
export TAP_LOG_DIR="/tmp/rserc_test_log"
export LOG_FILE="${TAP_LOG_DIR}/rserc_chk.log"
mkdir -p "${TAP_LOG_DIR}"

# 2. Source the script (the entry-point guard prevents execution)
source /path/to/rserc_chk.sh

# 3. Call the function
log_msg "Test message from manual test"

# 4. Verify output
cat "${LOG_FILE}"
# EXPECTED: A single line like:
#   26-Mar-2026 10:30:45 - Test message from manual test

# 5. Call it again and verify it appends (not overwrites)
log_msg "Second message"
wc -l < "${LOG_FILE}"
# EXPECTED: 2

# 6. Cleanup
rm -rf "${TAP_LOG_DIR}"
```

**Automated Test (Bats):**
The test suite covers this in 3 tests: timestamp format verification, content check, and append behavior. No special prerequisites beyond Bats itself.

---

### 4.2 `send_alert()`

**Purpose:** Sends an email alert with an empty body (subject-only notification) and logs the alert.

**Input:**
- `$1` — The email subject / alert message

**Internal Logic:**
1. Pipe an empty string to `mailx -s "<subject>" <EMAIL_L2>`
2. Call `log_msg` with the same subject text

**Output:** Email sent to L2; log entry written.

**Return Values:** Always 0. Mail failures silently ignored.

**VMS Equivalent Explained:**
```dcl
$ mail NL: "Telefonica_UK.L2@accenture.com"/sub="No Call files processed by TAP collection in last four hours"
```
- `MAIL` is the VMS built-in mail utility (like `mailx` on Linux).
- `NL:` is the VMS **null device** (equivalent to `/dev/null`). Passing it as the message body means the email has an empty body — only the subject line carries the information.
- `/sub="..."` provides the subject line.
- The quoted string after `/sub=` is the recipient's email address.

On Linux, `echo "" | mailx -s "subject" recipient` achieves the same effect — piping an empty string as the body.

**How to Test on the Test Server:**

| Pre-requisite | Details |
|--------------|---------|
| `mailx` installed | `which mailx` — install with `yum install mailx` if missing |
| Working MTA | Postfix or sendmail must be running: `systemctl status postfix` |
| Test email recipient | Use your own Accenture email for testing, NOT the production L2 address |
| Writable log directory | `TAP_LOG_DIR` must exist and be writable |

**Manual Test Steps:**
```bash
# 1. Set up environment
export TAP_LOG_DIR="/tmp/rserc_test_log"
export LOG_FILE="${TAP_LOG_DIR}/rserc_chk.log"
export EMAIL_L2="your-test-email@accenture.com"   # Use YOUR email, not L2
mkdir -p "${TAP_LOG_DIR}"

# 2. Source the script
source /path/to/rserc_chk.sh

# 3. Call the function
send_alert "Test Alert - RSERC CHK Manual Test"

# 4. Verify log entry
grep "Test Alert" "${LOG_FILE}"
# EXPECTED: Timestamped line with "Test Alert - RSERC CHK Manual Test"

# 5. Check your email inbox for the alert
# EXPECTED: Email with subject "Test Alert - RSERC CHK Manual Test" and empty body

# 6. If no email received, check mail logs:
sudo tail -20 /var/log/maillog

# 7. Cleanup
rm -rf "${TAP_LOG_DIR}"
```

**Automated Test (Bats):**
The Bats tests use a mock `mailx` that logs calls instead of actually sending email. This makes the tests safe to run without MTA configuration. The mock records each invocation to `${WORK_DIR}/mailx.log` which tests inspect for correctness.

---

### 4.3 `send_report()`

**Purpose:** Sends an email with a file as the body to one or more recipients.

**Input:**
- `$1` — Email subject
- `$2` — Path to the file to send as the body
- `$3...$N` — One or more recipient email addresses

**Internal Logic:**
1. Iterate through each recipient (shift past subject and file)
2. Call `mailx -s "<subject>" "<recipient>" < "<file>"`

**Output:** Email(s) sent.

**Return Values:** Always 0.

**VMS Equivalent Explained:**
```dcl
$ MAIL/SUBJ="TAP - Processed RESRC File Report" files_created.lis "Telefonica_UK.L2@accenture.com"
$ MAIL/SUBJ="TAP - Processed roaming CDRs Report" recs_created.lis "VMO2_ApolloL2@accenture.com"
```
- `MAIL` with a filename as the first positional argument sends that file as the email body.
- `/SUBJ="..."` is the subject qualifier.
- The quoted string is the recipient address.
- On VMS, each `MAIL` command sends to one recipient. To send to multiple recipients, you issue multiple `MAIL` commands (which is what the original VMS script does).

On Linux, the function loops through all recipients and calls `mailx` once per recipient using standard input redirection (`< file`).

**How to Test on the Test Server:**

| Pre-requisite | Details |
|--------------|---------|
| `mailx` installed + working MTA | Same as `send_alert` |
| A test file | Any text file to use as the email body |
| Test email recipient | Your own email, NOT production addresses |

**Manual Test Steps:**
```bash
# 1. Set up environment (same as send_alert)
export TAP_LOG_DIR="/tmp/rserc_test_log"
export LOG_FILE="${TAP_LOG_DIR}/rserc_chk.log"
mkdir -p "${TAP_LOG_DIR}"

# 2. Source the script
source /path/to/rserc_chk.sh

# 3. Create a test report file
echo "This is a test RSERC report body" > /tmp/test_report.txt
echo "Line 2 of the report" >> /tmp/test_report.txt

# 4. Call the function with two recipients
send_report "Test Report Subject" "/tmp/test_report.txt" "your-email@accenture.com" "another-email@accenture.com"

# 5. Check both email inboxes
# EXPECTED: Both recipients receive an email with subject "Test Report Subject"
#           and body containing "This is a test RSERC report body"

# 6. Cleanup
rm -f /tmp/test_report.txt
rm -rf "${TAP_LOG_DIR}"
```

**Automated Test (Bats):**
The mock `mailx` logs each call. Tests verify that the correct number of `MAILX_CALL:` entries appear (one per recipient). A separate test verifies graceful handling when the report file does not exist.

---

### 4.4 `schedule_next_run()`

**Purpose:** Schedules the script to execute again at 06:00 the next day.

**Input:** None (uses `$0` to get the current script path).

**Internal Logic:**
1. Resolve the script's full path via `readlink -f "$0"`
2. Pipe it to `at 06:00 tomorrow`
3. If `at` fails, log a warning suggesting cron configuration

**Output:** Job scheduled via `at`; or a warning is logged.

**VMS Equivalent Explained:**
```dcl
$ submit/after=tomorrow"+6"/keep/log=tap_log_dir:rserc_chk.log/noprint rserc_chk.com
```
This is one of the first lines in the VMS script, and it is critical to understand:
- `SUBMIT` is the VMS command to submit a job to the **batch queue** (VMS's built-in job scheduler). It is roughly equivalent to combining Linux `at` or `cron` with `nohup`.
- `/AFTER=tomorrow"+6"` means "run this job tomorrow at 06:00". The `+6` means 6 hours past midnight. This is how VMS implements daily scheduling — each run of the script immediately schedules its next run.
- `/KEEP` means keep the job entry in the queue log after it completes (don't auto-delete it).
- `/LOG=tap_log_dir:rserc_chk.log` directs the job's output to the specified log file. `tap_log_dir:` is a VMS logical name (like an environment variable pointing to a directory).
- `/NOPRINT` means don't print the log file after the job completes.
- `rserc_chk.com` is the script filename itself — the script is re-submitting itself.

On Linux, `at 06:00 tomorrow` schedules a one-time execution at 06:00 the next day. The `at` daemon (`atd`) must be running. Alternatively, a cron entry (`0 6 * * *`) can be used for more reliable recurring scheduling.

**How to Test on the Test Server:**

| Pre-requisite | Details |
|--------------|---------|
| `at` command available | `which at` — install with `yum install at` if missing |
| `atd` service running | `systemctl status atd` → if not running: `sudo systemctl start atd` |
| OR cron configured | As an alternative: `crontab -l` to verify |

**Manual Test Steps:**
```bash
# 1. Source the script
source /path/to/rserc_chk.sh

# 2. Call the function
schedule_next_run

# 3. Verify the job was scheduled
at -l
# EXPECTED: A job scheduled for tomorrow at 06:00

# 4. To test the fallback (at fails):
#    Temporarily stop atd and try again:
sudo systemctl stop atd
schedule_next_run
# EXPECTED: Log message "WARNING: Could not schedule next run via 'at'. Ensure cron is configured."
sudo systemctl start atd

# 5. Clean up scheduled test jobs
atrm <job_number>   # Replace with the actual job ID from at -l
```

**Automated Test (Bats):**
The Bats tests replace `at` with a mock that logs the call. A second test replaces `at` with a failing mock to verify the warning message. No actual scheduling occurs during testing.

---

### 4.5 `generate_spid_list()`

**Purpose:** Queries Oracle for all service provider IDs and writes them to a file.

**Input:** None (uses OS-authenticated Oracle connection).

**Internal Logic:**
1. Log "Creating SPID list"
2. Run `sqlplus -s /` with heredoc SQL that selects `SP_ID FROM service_providers`
3. Redirect output to `${WORK_DIR}/spid_list.lis`

**Output:** File `spid_list.lis` containing one SP_ID per line.

**VMS Equivalent Explained:**
```dcl
$ sqlplus -s /
set verify off
set feedback off
set termout off
set pagesize 0
SPOOL spid_list.lis
select SP_ID from service_providers;
SPOOL OFF
EXIT
$!
```
Key concepts for someone unfamiliar with VMS:
- `sqlplus -s /` works exactly the same on both VMS and Linux — it is an Oracle SQL client tool. The `-s` flag means "silent" mode (suppress banners). The `/` means use OS authentication (the Oracle user is mapped from the OS user — no username or password needed).
- `SPOOL spid_list.lis` tells Oracle to write all subsequent output to the file `spid_list.lis`. `SPOOL OFF` stops writing.
- `$!` is a VMS comment (like `#` in Bash).
- `SET VERIFY OFF` / `SET FEEDBACK OFF` / `SET TERMOUT OFF` / `SET PAGESIZE 0` suppress extra Oracle output so only the raw data is in the spool file.
- On VMS, `SPOOL` writes to the current directory. On Linux, the converted script redirects the entire `sqlplus` output to `${WORK_DIR}/spid_list.lis`, which achieves the same result more simply.

The resulting `spid_list.lis` file will look like:
```
  10
  20
  42
 105
```
Each line is an SP_ID (a numeric identifier for a service provider / roaming partner).

**How to Test on the Test Server:**

| Pre-requisite | Details |
|--------------|---------|
| Oracle client installed | `which sqlplus` must return a path |
| `ORACLE_HOME` set | `echo $ORACLE_HOME` — e.g., `/opt/oracle/product/19c` |
| `ORACLE_SID` set | `echo $ORACLE_SID` — e.g., `TAPDB` |
| OS-authenticated Oracle access | `sqlplus / <<< "SELECT 1 FROM DUAL; EXIT;"` must succeed |
| `service_providers` table exists | `sqlplus / <<< "SELECT COUNT(*) FROM service_providers; EXIT;"` |
| Writable temp directory | `/tmp` or configured `WORK_DIR` must be writable |

**Manual Test Steps:**
```bash
# 1. Set up environment
export WORK_DIR="/tmp/rserc_test_work"
export TAP_LOG_DIR="/tmp/rserc_test_log"
export LOG_FILE="${TAP_LOG_DIR}/rserc_chk.log"
mkdir -p "${WORK_DIR}" "${TAP_LOG_DIR}"

# 2. Source the script
source /path/to/rserc_chk.sh

# 3. Call the function
generate_spid_list

# 4. Verify the SPID list was created
cat "${SPID_LIST}"
# EXPECTED: One SP_ID per line (numeric values)

# 5. Verify the log entry
grep "Creating SPID list" "${LOG_FILE}"
# EXPECTED: Timestamped log line

# 6. Verify the count matches the database
sqlplus -s / <<< "SELECT COUNT(*) FROM service_providers; EXIT;"
wc -l < "${SPID_LIST}"
# EXPECTED: Both numbers should match (approximately — SPOOL may add blank lines)

# 7. Cleanup
rm -rf "${WORK_DIR}" /tmp/rserc_test_log
```

**Automated Test (Bats):**
The mock `sqlplus` in the test suite reads the heredoc SQL from stdin, honours `SPOOL` directives by creating the specified files, and writes configurable SP_ID values. No actual Oracle connection is needed.

---

### 4.6 `check_tap_directories()`

**Purpose:** Checks all TAP pipeline directories for file backlogs and sends alerts when thresholds are exceeded.

**Input:**
- Environment variables for directory paths (`TAP_ARCHIVE_DIR`, `TAP_COLLECT_DIR`, etc.)
- Thresholds `MAX` (default 400) and `SPLIT_MAX` (default 600)
- `SPID_LIST` file for per-provider split checks

**Internal Logic:**
1. Increment `run_count`
2. **Archive check:** Use `find` with `-mmin -240` to count `cd*.dat` files modified in the last 4 hours. If zero → alert.
3. **Collect check:** Count `CD?????GBRCN*.dat` files. If count > MAX → alert.
4. **To-Price check:** Count `CD?????GBRCN*.DAT` files. If count > MAX → alert.
5. **Priced check:** Count `CD?????GBRCN*.PRC` files. If count > MAX → alert.
6. **Per-SPID split check:** Read each SPID from `spid_list.lis`, zero-pad to 3 digits with `printf "%03d"`, count `CD*.SPLIT` files in the corresponding split directory. If count > SPLIT_MAX → alert.

**Return Values:** Implicit 0.

**VMS Equivalent Explained (Step by Step):**

**Step 1: Archive check**
```dcl
$ dir DISK$CALL_DATA2:[TAP.OB.ARCHIVE]cd*.dat/sin="-4"/tot/nohead
$ if $status .nes. "%X00000001"
$ then
$ mail NL: "Telefonica_UK.L2@accenture.com"/sub="No Call files processed by TAP collection in last four hours"
$ endif
```
- `DIR` is the VMS directory listing command (like `ls` on Linux).
- `DISK$CALL_DATA2:[TAP.OB.ARCHIVE]` is the VMS path: `DISK$CALL_DATA2:` is a logical name (disk/mount), `[TAP.OB.ARCHIVE]` is the directory path.
- `cd*.dat` is the file pattern — filenames starting with `cd` and ending with `.dat`.
- `/SIN="-4"` means **"since 4 hours ago"** — only list files created/modified within the last 4 hours. This is the VMS-specific time filter.
- `/TOT` means show the total count. `/NOHEAD` means don't show column headers.
- `$STATUS` holds the result: `%X00000001` = success (files found), anything else = failed (no files found).
- `.NES.` is VMS "not equal string" operator.
- If no files found → send alert email.

On Linux, `find "${TAP_ARCHIVE_DIR}" -maxdepth 1 -iname 'cd*.dat' -mmin -240 | wc -l` replaces this. `-mmin -240` means "modified within the last 240 minutes (= 4 hours)".

**Step 2: Collect / To-Price / Priced checks**
```dcl
$ dir DISK$CALL_DATA:[TAP.OB.COLLECT]CD%%%%%GBRCN*.dat/noout
$ if $status .eqs. "%X00000001"
$ then
$ pip dir DISK$CALL_DATA:[TAP.OB.COLLECT]CD%%%%%GBRCN*.dat/tot | sea sys$input "Total of " | (read sys$pipe line ; lines=f$element(2," ",f$extract(0,30,line)) ; define/job file_count &lines)
$ total_files= f$integer(F$TRNLNM("file_count"))
$       if total_files .gt. max
$       then
$       mail NL: "Telefonica_UK.L2@accenture.com"/sub="There are ''total_files' files in tap collection"
$       endif
$ endif
```
This is the most complex VMS construct, broken down:
- `CD%%%%%GBRCN*.dat` — `%` is the VMS single-character wildcard (like `?` on Linux). Five `%` means exactly five characters. So the pattern matches `CD` + exactly 5 characters + `GBRCN` + anything + `.dat`.
- `/NOOUT` — suppress output; the command is used just to check if files exist (exit status).
- `$STATUS .EQS. "%X00000001"` — `.EQS.` is "equal string"; if files exist, proceed to count them.
- `PIP` (short for `PIPE`) — VMS pipe operator, chains commands like `|` on Linux.
- `DIR .../TOT` — list files with a total line like `Total of 456 files`.
- `SEA SYS$INPUT "Total of "` — `SEARCH` filters for lines containing "Total of " (like `grep`).
- `READ SYS$PIPE LINE` — reads the piped line into variable `LINE`.
- `F$ELEMENT(2," ",F$EXTRACT(0,30,LINE))` — extracts the 3rd space-delimited word (the count number) from the first 30 characters of the line. `F$ELEMENT` is like `awk '{print $3}'`.
- `DEFINE/JOB FILE_COUNT &LINES` — creates a job-scope logical name (like an environment variable) with the count value.
- `F$TRNLNM("file_count")` — translates (reads) the logical name back into a variable.
- `F$INTEGER(...)` — converts string to integer.
- `.GT.` is "greater than".

On Linux, all of this is replaced by a single command: `find ... | wc -l` which directly counts matching files.

**Step 3: Per-SPID split check**
```dcl
$ open/read inpfile spid_list.lis
$ loop:
$ read/end=exit1 inpfile inpro
$ spid = f$fao("!3ZL",f$integer(f$edit(inpro,"trim")))
$ dir DISK$CALL_DATA:[TAP.OB.SPLIT.'spid']CD*.SPLIT/tot
...
$ goto loop
$ exit1:
$ close inpfile
```
- `OPEN/READ INPFILE` — opens the file for reading (like `while IFS= read -r line; do ... done < file` in Bash).
- `READ/END=EXIT1` — reads one line; if end-of-file reached, jump to label `EXIT1`.
- `F$EDIT(INPRO,"TRIM")` — trims whitespace (like `tr -d '[:space:]'`).
- `F$FAO("!3ZL",...)` — **Formatted ASCII Output**: `!3ZL` means "format as a 3-digit zero-padded integer". So SP_ID `5` becomes `005`. This is equivalent to `printf "%03d"` in Bash.
- `DISK$CALL_DATA:[TAP.OB.SPLIT.'spid']` — the `'spid'` is variable substitution within the path.
- `GOTO LOOP` — jumps back to the `LOOP:` label (VMS uses labels + GOTO instead of Bash loops).

On Linux, a `while read` loop with `printf "%03d"` and `find ... | wc -l` replaces this.

**How to Test on the Test Server:**

| Pre-requisite | Details |
|--------------|---------|
| TAP directories created | All `TAP_*` directories must exist. See Section 11.2 for setup. |
| SPID list present | Either run `generate_spid_list()` first (requires Oracle), OR create a manual SPID list |
| `mailx` + MTA (or use mock) | For sending alerts. For dry-run testing, override `EMAIL_L2` |
| Test data files | Create dummy files matching the expected patterns |

**Manual Test Steps:**

*Test 1: Archive alert (no recent files)*
```bash
# 1. Set up environment with empty directories
export TAP_ARCHIVE_DIR="/tmp/rserc_test/ARCHIVE"
export TAP_COLLECT_DIR="/tmp/rserc_test/COLLECT"
export TAP_READY_FOR_PRICING="/tmp/rserc_test/TO_PRICE"
export TAP_OB_PRICED="/tmp/rserc_test/PRICED"
export TAP_OB_SPLIT="/tmp/rserc_test/SPLIT"
export TAP_LOG_DIR="/tmp/rserc_test/LOG"
export LOG_FILE="${TAP_LOG_DIR}/rserc_chk.log"
export WORK_DIR="/tmp/rserc_test/work"
export EMAIL_L2="your-email@accenture.com"
export MAX=400
export SPLIT_MAX=600
mkdir -p $TAP_ARCHIVE_DIR $TAP_COLLECT_DIR $TAP_READY_FOR_PRICING \
         $TAP_OB_PRICED $TAP_OB_SPLIT $TAP_LOG_DIR $WORK_DIR

# 2. Create a manual SPID list (skip Oracle dependency)
SPID_LIST="${WORK_DIR}/spid_list.lis"
echo "10" > "${SPID_LIST}"
echo "20" >> "${SPID_LIST}"

# 3. Source script and call function
source /path/to/rserc_chk.sh
run_count=0
check_tap_directories

# 4. Verify archive alert was triggered
grep "No Call files processed" "${LOG_FILE}"
# EXPECTED: Alert message present (archive is empty → no recent files)
```

*Test 2: Archive no-alert (recent files exist)*
```bash
# Create a recent file in the archive
touch "${TAP_ARCHIVE_DIR}/cd00001.dat"

# Reset log
> "${LOG_FILE}"
run_count=0
check_tap_directories

# Verify NO archive alert
grep "No Call files processed" "${LOG_FILE}" && echo "FAIL: alert should not appear" || echo "PASS"
```

*Test 3: Collect backlog alert*
```bash
# Create 401 files (exceeds MAX=400)
for i in $(seq 1 401); do
    touch "${TAP_COLLECT_DIR}/CD00001GBRCN$(printf '%05d' $i).dat"
done

# Create a recent archive file to avoid archive alert noise
touch "${TAP_ARCHIVE_DIR}/cd00001.dat"

> "${LOG_FILE}"
check_tap_directories

grep "files in tap collection" "${LOG_FILE}"
# EXPECTED: "There are 401 files in tap collection"
```

*Test 4: Per-SPID split backlog*
```bash
# Create a SPID directory and populate it
mkdir -p "${TAP_OB_SPLIT}/010"
for i in $(seq 1 601); do
    touch "${TAP_OB_SPLIT}/010/CD$(printf '%05d' $i).SPLIT"
done

> "${LOG_FILE}"
check_tap_directories

grep "files in TAP Distribute for spid 010" "${LOG_FILE}"
# EXPECTED: "There are 601 files in TAP Distribute for spid 010"

# Cleanup
rm -rf /tmp/rserc_test
```

**Automated Test (Bats):**
12+ tests cover: empty archives, recent/old files, exact-boundary counts (400 vs 401), per-SPID checks, missing SPID list, invalid SPID entries, non-matching file patterns. All run with isolated temp directories — no production data needed.

---

### 4.7 `generate_hourly_reports()`

**Purpose:** Runs Oracle SQL queries to produce hourly RSERC and CDR processing reports, emails them, and checks for zero-RSERC conditions.

**Input:**
- Oracle database connection (OS-authenticated)
- `WORK_DIR` for temporary spool files
- `run_count` to skip the zero-RSERC alert on first iteration

**Internal Logic:**
1. Run a single `sqlplus` session with three SPOOL outputs:
   - `files_created.lis` — Hourly RSERC file creation stats (grouped by hour, with daily total)
   - `files_created1.lis` — Count of files created in the last 4 hours (single number)
   - `recs_created.lis` — Hourly roaming CDR processing stats (grouped by hour, with daily total)
2. Email `files_created.lis` to L2
3. Email `recs_created.lis` to L2 and Apollo
4. Parse `files_created1.lis` for the `FILE_COUNT=` value
5. If `FILE_COUNT` is 0 and `run_count` > 1 → send zero-RSERC alert
6. Clean up all three spool files

**Output:** Emails sent; alert if zero RSERCs.

**VMS Equivalent Explained:**

This is the largest Oracle interaction in the script. Here is the VMS version with explanations:

```dcl
$ Rserc_created_and_CDRs_processed:
$ dttm=f$time()
$ wso "''dttm' - Creating Tap hourly reports"
$ sqlplus -s /
```
The label `Rserc_created_and_CDRs_processed:` is a VMS section label (used with `GOTO` for flow control). On Linux this becomes the function name `generate_hourly_reports()`.

Inside `sqlplus`, the SQL is identical on both VMS and Linux because `sqlplus` is Oracle's tool and works the same on any OS. The key SQL constructs:

```sql
SET TRANSACTION READ ONLY;
```
This ensures the queries see a consistent snapshot of the data (no dirty reads).

```sql
SPOOL files_created.lis
SELECT SUBSTR(TO_CHAR(OOCF_CREATED_DTTM,'YYYY-MM-DD HH24'),1,10) DAT,
       SUBSTR(TO_CHAR(OOCF_CREATED_DTTM,'YYYY-MM-DD HH24'),12,2) HOUR_OF_THE_DAY,
       COUNT(*) FILES_PROCESSED
  FROM outgoing_outbound_call_files
 WHERE TRUNC(OOCF_CREATED_DTTM)=TRUNC(SYSDATE)
 GROUP BY TO_CHAR(OOCF_CREATED_DTTM,'YYYY-MM-DD HH24')
 ORDER BY TO_CHAR(OOCF_CREATED_DTTM,'YYYY-MM-DD HH24');
SPOOL OFF
```
This counts RSERC files created **today**, grouped by hour. `SPOOL files_created.lis` writes the output to a file. The result looks like:
```
 ** Tap hourly report **
DATE_TIME
26-MAR-2026 10:30:45
DATE            HOUR     FILES_PROCESSED
2026-03-26      06                    150
2026-03-26      07                    200
2026-03-26      08                    175
                        *DAY TOTAL*   525
```

The zero-RSERC check query:
```sql
SPOOL files_created1.lis
SELECT 'FILE_COUNT=',COUNT(*) FROM outgoing_outbound_call_files
 WHERE TRUNC(OOCF_CREATED_DTTM)=TRUNC(SYSDATE-4/24);
SPOOL OFF
```
This counts files created approximately 4 hours ago. `SYSDATE-4/24` means "current time minus 4/24 of a day (= 4 hours)". If the count is 0, it means nothing was produced 4 hours ago.

The VMS post-Oracle section:
```dcl
$ MAIL/SUBJ="TAP - Processed RESRC File Report" files_created.lis "Telefonica_UK.L2@accenture.com"
$ MAIL/SUBJ="TAP - Processed roaming CDRs Report" recs_created.lis "Telefonica_UK.L2@accenture.com"
$ MAIL/SUBJ="TAP - Processed roaming CDRs Report" recs_created.lis "VMO2_ApolloL2@accenture.com"
```
These mail the generated report files. On Linux, this is done via `send_report()`.

The zero-RSERC check:
```dcl
$ pipe search files_created1.lis "FILE_COUNT=" | (read sys$pipe line ; lines=f$integer(f$edit(f$extract(11,f$length(line)-11,line),"trim")) ; define/job file_count &lines)
$ total_files= f$integer(F$TRNLNM("file_count"))
$ if total_files .eq. 0 .and. run_count .ne. 1
$ then
$       mail NL: "Telefonica_UK.L2@accenture.com"/sub="There are no RSERC created in last 4 hours"
$ endif
```
- `PIPE SEARCH ... | READ SYS$PIPE` — searches the file for "FILE_COUNT=" and reads the matching line.
- `F$EXTRACT(11,...)` — extracts from position 11 (after "FILE_COUNT=") to get the numeric count.
- `.EQ.` is "equal"; `.AND.` is logical AND; `.NE.` is "not equal".
- The alert is **skipped on the first run** (`run_count .ne. 1`) because the time window might not have enough data yet at startup.

On Linux, `grep "FILE_COUNT=" file | sed 's/.*FILE_COUNT=[[:space:]]*//'` extracts the number.

**Key Difference:** The heredoc in the Linux script uses an **unquoted** delimiter (`<<EOSQL` not `<<'EOSQL'`) so that shell variables like `${FILES_CREATED}` expand inside the Oracle SPOOL directives, ensuring the spool files are created at the correct paths.

**How to Test on the Test Server:**

| Pre-requisite | Details |
|--------------|---------|
| Oracle connection working | `sqlplus / <<< "SELECT 1 FROM DUAL; EXIT;"` must succeed |
| `outgoing_outbound_call_files` table exists | `sqlplus / <<< "SELECT COUNT(*) FROM outgoing_outbound_call_files; EXIT;"` |
| `PROCESS_STATISTICS` table exists | `sqlplus / <<< "SELECT COUNT(*) FROM PROCESS_STATISTICS; EXIT;"` |
| `mailx` + MTA (or mock) | For report emails |
| Writable `WORK_DIR` and `TAP_LOG_DIR` | For spool files and log |

**Manual Test Steps:**
```bash
# 1. Set up environment
export WORK_DIR="/tmp/rserc_test_work"
export TAP_LOG_DIR="/tmp/rserc_test_log"
export LOG_FILE="${TAP_LOG_DIR}/rserc_chk.log"
export EMAIL_L2="your-email@accenture.com"
export EMAIL_APOLLO="your-email@accenture.com"
mkdir -p "${WORK_DIR}" "${TAP_LOG_DIR}"

# 2. Source the script
source /path/to/rserc_chk.sh

# 3. Test with run_count=2 (to enable zero-RSERC alert)
run_count=2
generate_hourly_reports

# 4. Check log for report generation
grep "Creating Tap hourly reports" "${LOG_FILE}"
# EXPECTED: Present

grep "Processed RESRC File Report sent to L2" "${LOG_FILE}"
# EXPECTED: Present

grep "Processed roaming CDRs Report sent to L2" "${LOG_FILE}"
# EXPECTED: Present

# 5. Check email inbox for the reports
# EXPECTED: Two emails — one RSERC report, one CDR report

# 6. If zero RSERCs in last 4 hours, check for alert
grep "no RSERC created in last 4 hours" "${LOG_FILE}"
# EXPECTED: Present if FILE_COUNT was 0 and run_count > 1

# 7. Test the first-run skip (run_count=1 should suppress zero alert)
> "${LOG_FILE}"
run_count=1
generate_hourly_reports
grep "no RSERC created" "${LOG_FILE}" && echo "FAIL: should be suppressed" || echo "PASS"

# 8. Cleanup
rm -rf "${WORK_DIR}" /tmp/rserc_test_log
```

**Automated Test (Bats):**
8+ tests cover: report logging, email dispatch, spool file cleanup, zero FILE_COUNT alert on non-first run, suppression on first run, positive FILE_COUNT (no alert), and SPOOL path expansion verification. The mock `sqlplus` creates deterministic spool files without needing a real database.

---

### 4.8 `check_rserc_failures()`

**Purpose:** Detects failed RSERC assembly runs and performs automatic recovery when `.tmp` files are found.

**Input:**
- Directory paths `TAP_OUTGOING_SP`, `TAP_PERIOD_DIR`
- `RERUN_RSERC_SQL` path to the Oracle SQL script for re-running assembly

**Internal Logic:**
1. Check if assembly/distribution processes are running (`ps -ef | grep "assemb\|dist"`). If found → skip all failure checks (process is active).
2. **`.don` file check:** Count `.don` files in `TAP_OUTGOING_SP`. If any exist:
   - List them with `find -ls` to a file
   - Email the listing to TAP Support and L2 with subject: `"RSERC Failure - Procedure 841 - *.DON files left out"`
3. **`.tmp` file check + auto-recovery:** Count `.tmp` files. If any exist:
   - List them and email alert: `"RSERC Failure - Procudure 841 - *.TMP files left out - Recovering"` (note: "Procudure" is the original VMS typo, preserved intentionally)
   - List `mrlog*.tmp` filenames (excluding `*.dat`) to `mrlog.lis`
   - Delete all `.tmp` files from `TAP_OUTGOING_SP` and `TAP_PERIOD_DIR`
   - Extract SP_ID from character position 35 of each mrlog filename using `awk`
   - Deduplicate with `sort -u`
   - For each unique SP_ID, call `sqlplus -s / @rerun_rserc.sql "<SP_ID>"`
4. Clean up temp files.

**Return Values:** Always 0.

**VMS Equivalent Explained (Step by Step):**

**Step 1: Check if assembly process is running**
```dcl
$ sh que *ass*/out=rserc_chk.lis
$ sea rserc_chk.lis dist
$ if $status .eqs. "%X00000001"
$ then
$       goto check_hour
```
- `SH QUE *ASS*` means `SHOW QUEUE *ASS*` — displays all VMS batch queues whose names contain "ASS" (for "ASSEMB" — the RSERC assembly queue). The `/OUT=rserc_chk.lis` writes the output to a file.
- `SEA rserc_chk.lis dist` means `SEARCH rserc_chk.lis dist` — searches the file for the string "dist" (distribution). This checks whether the distribution phase is active.
- If "dist" is found (`$STATUS = %X00000001` = success), the script skips failure checks (the process is still running, so leftover files are expected).
- `GOTO CHECK_HOUR` jumps to the loop control section.

On Linux, VMS batch queues don't exist. Instead, `ps -ef | grep "assemb\|dist"` checks for running processes. If any matching process is found, failure checks are skipped.

**Step 2: .don file check**
```dcl
$       dir tap_outgoing_sp:*.don;*
$       if $status .eqs. "%X00000001"
$       then
$               dir/out=rserc_failure_2.txt tap_outgoing_sp:*.don;*
$               mail rserc_failure_2.txt "sdcmg1::smtp%""TAPSupport@o2.com"""/sub="RSERC Failure - Procedure 841 - *.DON files left out"
$               mail rserc_failure_2.txt "sdcmg1::smtp%""Telefonica_UK.L2@accenture.com"""/sub="RSERC Failure - Procedure 841 - *.DON files left out"
$       endif
```
- `tap_outgoing_sp:` is a VMS logical name pointing to the outgoing service provider directory.
- `*.don;*` matches all `.don` files (all versions — the `;*` is VMS version wildcard).
- `DIR/OUT=file` writes the directory listing to a file (like `find ... -ls > file`).
- The mail address `sdcmg1::smtp%""TAPSupport@o2.com""` is a VMS DECnet/SMTP address. `sdcmg1::` is the DECnet node name, `smtp%""...""` routes through SMTP. On Linux, `mailx` sends directly.
- `.don` files indicate that the **distribution** step partially completed. These files need human investigation.

On Linux, `find ... -iname '*.don' | wc -l` counts the files, and `find ... -iname '*.don' -ls` lists them for the report.

**Step 3: .tmp file check + auto-recovery**
```dcl
$       dir tap_outgoing_sp:*.tmp;*
$       if $status .eqs. "%X00000001"
$       then
$               dir/out=rserc_failure_1.txt tap_outgoing_sp:*.tmp;*
$               mail rserc_failure_1.txt "sdcmg1::smtp%""TAPSupport@o2.com"""/sub="RSERC Failure - Procudure 841 - *.TMP files left out - Recovering"
$!
$               dir/nohead/notrail tap_outgoing_sp:mrlog*.tmp;*/excl=*.dat/out=mrlog.lis
$               del tap_outgoing_sp:*.tmp;*
$               del tap_ob_period:*.tmp;*
$               sort/nodup/key=(pos:35,siz=3) mrlog.lis;1 mrlog.lis;2
$               open/read infile mrlog.lis
$ next_spid:
$               read/end=no_more_spids infile rec
$               sp_id = f$extract(34,3,rec)
$               sqlplus -s / @rerun_rserc "''sp_id'"
$               goto next_spid
$ no_more_spids:
$               close infile
$               del mrlog.lis;*
$       endif
```
Breaking this down:
- `.tmp` files indicate that the **assembly** step failed mid-execution. Unlike `.don` files, these can be automatically recovered.
- `"Procudure"` is a **typo** in the original VMS script (should be "Procedure"). It has been preserved intentionally to match the original behavior.
- `DIR/NOHEAD/NOTRAIL ... mrlog*.tmp;*/EXCL=*.dat/OUT=mrlog.lis` — list filenames of `mrlog*.tmp` files, excluding any `*.dat` files. `/NOHEAD/NOTRAIL` means output filenames only (no headers, no trailing summary). On Linux: `find ... -iname 'mrlog*.tmp' ! -iname '*.dat' -exec basename {} \;`
- `DEL tap_outgoing_sp:*.tmp;*` — delete all `.tmp` files. `DEL tap_ob_period:*.tmp;*` — delete `.tmp` files from the period directory too. These are cleaned up before re-triggering assembly.
- `SORT/NODUP/KEY=(POS:35,SIZ=3) mrlog.lis;1 mrlog.lis;2` — sort the file list by the 3-character substring at position 35 (which is the SP_ID embedded in the filename), remove duplicates, and write the result as version 2 of the file. On Linux: `awk '{ print substr($0,35,3) }' | sort -u`
- The loop reads each unique SP_ID and calls `sqlplus -s / @rerun_rserc "042"` to re-trigger the RSERC assembly for that provider.
- `F$EXTRACT(34,3,REC)` — extract 3 characters starting at position 34 (0-based, so character 35 in 1-based counting). This extracts the SP_ID from the full-path filename output of VMS `DIR`.

**IMPORTANT NOTE:** On VMS, `DIR/NOHEAD/NOTRAIL` outputs full file paths including the directory prefix. The SP_ID at position 35 works because the VMS path prefix is a known fixed length. On Linux, `find -exec basename` outputs **filename only**, so position 35 may need adjustment depending on actual `mrlog*.tmp` filename formats. This should be verified during deployment.

**How to Test on the Test Server:**

| Pre-requisite | Details |
|--------------|---------|
| `TAP_OUTGOING_SP` directory writable | The script deletes `.tmp` files during recovery |
| `TAP_PERIOD_DIR` directory writable | `.tmp` files also deleted here |
| `rerun_rserc.sql` available | Required for RSERC re-run. Set `RERUN_RSERC_SQL` to its path |
| Oracle (for real recovery) | `sqlplus` must work for the re-run. For dry testing, you can mock it |
| No assembly process running | If `ps -ef | grep -i "assemb\|dist"` finds a process, checks will be skipped |

**Manual Test Steps:**

*Test 1: Clean run (no failures)*
```bash
# 1. Set up
export TAP_OUTGOING_SP="/tmp/rserc_test/OG_SP"
export TAP_PERIOD_DIR="/tmp/rserc_test/PERIOD"
export TAP_LOG_DIR="/tmp/rserc_test/LOG"
export LOG_FILE="${TAP_LOG_DIR}/rserc_chk.log"
export WORK_DIR="/tmp/rserc_test/work"
export EMAIL_L2="your-email@accenture.com"
export EMAIL_TAP_SUPPORT="your-email@accenture.com"
mkdir -p $TAP_OUTGOING_SP $TAP_PERIOD_DIR $TAP_LOG_DIR $WORK_DIR

# 2. Source and call
source /path/to/rserc_chk.sh
check_rserc_failures

# 3. Verify clean run (no alerts)
grep "Checking for RSERC failures" "${LOG_FILE}"  # EXPECTED: Present
grep "RSERC Failure" "${LOG_FILE}" && echo "FAIL" || echo "PASS: No failures"
```

*Test 2: .don file detection*
```bash
# Create some .don files
touch "${TAP_OUTGOING_SP}/file1.don"
touch "${TAP_OUTGOING_SP}/file2.don"

> "${LOG_FILE}"
check_rserc_failures

# Verify .don alert
grep "Procedure 841.*DON files" "${LOG_FILE}"
# EXPECTED: "RSERC Failure - Procedure 841 - *.DON files left out"

# Check email for the failure listing
```

*Test 3: .tmp file recovery*
```bash
# Create .tmp files (simulating a failed assembly)
touch "${TAP_OUTGOING_SP}/file1.tmp"
touch "${TAP_OUTGOING_SP}/mrlog_test.tmp"
touch "${TAP_PERIOD_DIR}/period.tmp"

> "${LOG_FILE}"
check_rserc_failures

# Verify .tmp alert
grep "Procudure 841.*TMP files" "${LOG_FILE}"
# EXPECTED: Alert including the original VMS typo "Procudure"

# Verify .tmp files were deleted
ls -la "${TAP_OUTGOING_SP}"/*.tmp 2>/dev/null && echo "FAIL: .tmp still present" || echo "PASS: .tmp deleted"
ls -la "${TAP_PERIOD_DIR}"/*.tmp 2>/dev/null && echo "FAIL: .tmp still present" || echo "PASS: .tmp deleted"

# Cleanup
rm -rf /tmp/rserc_test
```

*Test 4: Verify skipping when assembly process is active*
```bash
# Start a dummy process that matches "dist" in its name
sleep 300 &
DUMMY_PID=$!

# This won't match because "sleep" doesn't contain "assemb" or "dist".
# To properly test, start a process with "dist" in its name:
bash -c 'exec -a "tap_dist_process" sleep 300' &
DIST_PID=$!

touch "${TAP_OUTGOING_SP}/dangerous.don"
> "${LOG_FILE}"
check_rserc_failures

# Verify checks were skipped
grep "RSERC Failure" "${LOG_FILE}" && echo "FAIL: should be skipped" || echo "PASS: skipped"

kill $DIST_PID 2>/dev/null
```

**Automated Test (Bats):**
9+ tests cover: clean run, `.don` alert, `.tmp` alert and recovery, `.tmp` deletion verification, period dir cleanup, mrlog SP_ID re-run via sqlplus mock, dist process skipping, and cleanup verification. The mock `ps` can be replaced to simulate active/inactive assembly processes.

---

### 4.9 `cleanup_and_exit()`

**Purpose:** Performs end-of-day cleanup — removes old logs, temp files, and the work directory.

**Input:** None (uses global variables).

**Internal Logic:**
1. Guard against double execution via `_CLEANUP_DONE` flag
2. Log "RSERC_CHK completed"
3. Delete log files older than 30 days in `TAP_LOG_DIR`
4. Remove `rserc_failure*.txt`, `rserc_chk.lis`, `spid_list.lis`
5. Remove the entire `WORK_DIR`

**Output:** Log entry; temp files removed.

**VMS Equivalent Explained:**
```dcl
$ finish:
$ wso "''dttm' - RSERC_CHK completed"
$ del/bef="-30-" tap_log_dir:rserc_chk.log;*
$ del rserc_failure*.txt;*
$ del rserc_chk.lis;*
$ delete spid_list.lis;*
$ exit
```
- `finish:` is a VMS label (like a function name or goto target).
- `DEL/BEF="-30-"` means "delete files with a creation date **before** 30 days ago". This is VMS's way of cleaning up old log files based on age. On Linux, `find ... -mtime +30 -delete` does the same.
- `DEL ... ;*` deletes all versions of the file (VMS file versioning). On Linux, each file has only one version, so `rm -f` suffices.
- `tap_log_dir:rserc_chk.log;*` — `tap_log_dir:` is a VMS logical name for the log directory.
- The `EXIT` command ends the VMS script.

The Linux version adds a **double-call guard** (`_CLEANUP_DONE` flag) that the VMS version doesn't have. This prevents cleanup from running twice if it is triggered by both the normal exit and a signal handler (`trap`).

**How to Test on the Test Server:**

| Pre-requisite | Details |
|--------------|---------|
| `TAP_LOG_DIR` writable | For log file operations |
| `WORK_DIR` exists | To verify it gets cleaned up |
| Old log files present (for age test) | Create files with `touch -d '31 days ago' ...` |

**Manual Test Steps:**
```bash
# 1. Set up environment
export WORK_DIR="/tmp/rserc_cleanup_test/work"
export TAP_LOG_DIR="/tmp/rserc_cleanup_test/LOG"
export LOG_FILE="${TAP_LOG_DIR}/rserc_chk.log"
mkdir -p "${WORK_DIR}" "${TAP_LOG_DIR}"

# 2. Create some temp files (simulating runtime leftovers)
touch "${WORK_DIR}/rserc_failure_1.txt"
touch "${WORK_DIR}/rserc_failure_2.txt"
touch "${WORK_DIR}/rserc_chk.lis"
touch "${WORK_DIR}/spid_list.lis"

# 3. Create an old log file (31 days old)
touch -d '31 days ago' "${TAP_LOG_DIR}/rserc_chk.log.old"
# And a recent log
touch "${TAP_LOG_DIR}/rserc_chk.log.recent"

# 4. Source and call
source /path/to/rserc_chk.sh
_CLEANUP_DONE=0
cleanup_and_exit

# 5. Verify
grep "RSERC_CHK completed" "${LOG_FILE}"  # EXPECTED: Present
[ -d "${WORK_DIR}" ] && echo "FAIL: WORK_DIR still exists" || echo "PASS: WORK_DIR removed"
[ -f "${TAP_LOG_DIR}/rserc_chk.log.old" ] && echo "FAIL: old log still exists" || echo "PASS: old log deleted"
[ -f "${TAP_LOG_DIR}/rserc_chk.log.recent" ] && echo "PASS: recent log preserved" || echo "FAIL: recent log deleted"

# 6. Test double-call guard
cleanup_and_exit  # Second call should be a no-op
grep -c "RSERC_CHK completed" "${LOG_FILE}"
# EXPECTED: 1 (only one entry, not two)

# 7. Cleanup
rm -rf /tmp/rserc_cleanup_test
```

**Automated Test (Bats):**
5 tests cover: completion log message, work directory removal, failure file removal, old log deletion (30+ days), recent log preservation, and double-call guard verification.

---

### 4.10 `main()`

**Purpose:** Orchestrates the entire monitoring process with its two-level loop structure.

**Input:** Command-line arguments (not currently used).

**Internal Logic:**
1. Call `schedule_next_run()` to queue tomorrow's execution
2. Log "RSERC CHK started"
3. Call `generate_spid_list()` to populate SP_ID list from Oracle
4. Initialize `run_count=0`
5. **Outer loop** (`while true`):
   - Call `check_tap_directories()` — full directory backlog scan
   - Call `generate_hourly_reports()` — Oracle reports + zero-RSERC check
   - Record `last_hour`
   - **Inner loop** (`while true`):
     - Call `check_rserc_failures()` — failure detection + recovery
     - If current hour = "23" → `return 0` (triggers cleanup via trap)
     - If current hour > `last_hour` → `break` to outer loop (new hour started)
     - Otherwise → sleep 600 seconds (10 minutes)

**Output:** Log entries, alerts, emails, and possibly triggered RSERC re-runs.

**VMS Equivalent Explained:**

The VMS script does NOT use functions — it uses **labels** and **GOTO** statements for flow control. Here is the structural mapping:

```
VMS Label                    Linux Function
---------                    ---------------
(script start)               main()
  submit/after=tomorrow...     schedule_next_run()
  sqlplus (SPID query)         generate_spid_list()
start:                       check_tap_directories()  ← outer loop entry
  notify_check:
  to_price_check:
  priced_check:
  loop: / exit1:
Rserc_created_and_CDRs_processed:   generate_hourly_reports()
  rserc_check:                      (inside generate_hourly_reports)
start_1:                     check_rserc_failures()   ← inner loop entry
check_hour:                  (loop control in main)
  wait 00:10:00                sleep 600
  goto start_1                 continue inner loop
  goto start                   break to outer loop
  goto finish                  return 0
finish:                      cleanup_and_exit()
```

Key VMS flow control concepts:
- `$ GOTO START` — unconditional jump to the `START:` label. This implements the outer loop.
- `$ GOTO START_1` — jumps back to the inner failure-check loop.
- `$ GOTO FINISH` — exits the loop entirely.
- `$ WAIT 00:10:00` — pauses execution for 10 minutes (like `sleep 600`).
- VMS uses `F$EXTRACT(12,2,DTTM)` to extract the hour (positions 12-13) from the timestamp string returned by `F$TIME()`. Linux uses `date '+%H'`.
- The `last_hour` / `cur_hour` comparison logic is identical in both versions: if the hour hasn't changed, stay in the inner loop; if it has advanced, break to the outer loop; if it's 23, exit.

The VMS script's `SET NOON` command at the beginning means "do not abort on errors" — continue processing even if a command fails. This is the default behavior in Bash (without `set -e`), so no explicit equivalent is needed.

**How to Test on the Test Server:**

| Pre-requisite | Details |
|--------------|---------|
| ALL prerequisites from all other functions | `main()` calls every other function |
| Oracle working | For `generate_spid_list()` and `generate_hourly_reports()` |
| `mailx` + MTA | For alerts and reports |
| `at` or cron | For self-scheduling |
| All TAP directories exist | For directory checks |
| Long test window | `main()` runs from startup until 23:00 |

**Manual Test Steps (short-duration test):**

Testing `main()` end-to-end requires the script to run for hours. For a quick validation:

```bash
# 1. Set up full environment (all TAP directories, Oracle, mail)
export TAP_ARCHIVE_DIR="/data/tap/TEST/ARCHIVE"
export TAP_COLLECT_DIR="/data/tap/TEST/COLLECT"
# ... (all other TAP_* variables — see Section 6)
export EMAIL_L2="your-email@accenture.com"
export EMAIL_APOLLO="your-email@accenture.com"
export EMAIL_TAP_SUPPORT="your-email@accenture.com"
export MAX=5       # Low threshold for quick testing
export SPLIT_MAX=5

# 2. Create the directories
mkdir -p $TAP_ARCHIVE_DIR $TAP_COLLECT_DIR ...

# 3. Run the script (it will start the main loop)
# To test for just one cycle, you can modify the exit condition:
# Option A: Run near 23:00 so it exits after one cycle
# Option B: Run in background and kill after verifying initial output
nohup ./rserc_chk.sh > /tmp/rserc_test_output.log 2>&1 &
SCRIPT_PID=$!

# 4. Wait 30 seconds and check initial output
sleep 30
head -20 /tmp/rserc_test_output.log
# EXPECTED:
#   <timestamp> - RSERC CHK started
#   <timestamp> - Creating SPID list
#   <timestamp> - Checking TAP directories
#   <timestamp> - Creating Tap hourly reports
#   <timestamp> - Checking for RSERC failures
#   <timestamp> - Waiting for 10 mins

# 5. Stop the test
kill $SCRIPT_PID

# 6. Cleanup
rm -rf /data/tap/TEST /tmp/rserc_test_output.log
```

**Automated Test (Bats):**
The `main()` function is NOT directly unit-tested in Bats because it contains infinite loops and `sleep` calls. Instead, each function it calls is tested individually. Integration tests verify multi-function sequences (e.g., `check_tap_directories` + `generate_hourly_reports` in sequence).

---

## 5. External Dependencies

### 5.1 Oracle Database (`sqlplus`)

| Usage | Purpose |
|-------|---------|
| `SELECT SP_ID FROM service_providers` | Generate SPID list for per-provider directory checks |
| Hourly report queries on `outgoing_outbound_call_files` | RSERC file creation statistics by hour |
| Hourly report queries on `PROCESS_STATISTICS` | Roaming CDR processing statistics by hour |
| `@rerun_rserc.sql "<SP_ID>"` | Re-trigger RSERC assembly for a failed service provider |

- Requires **OS-authenticated** Oracle access (no username/password — uses the OS user's Oracle credentials via `sqlplus /`)
- Requires `ORACLE_HOME` and `ORACLE_SID` (or `TWO_TASK`) environment variables to be set
- Requires the `sqlplus` binary on `PATH`

### 5.2 Oracle Tables Referenced

| Table | Columns Used | Purpose |
|-------|-------------|---------|
| `service_providers` | `SP_ID` | List of all service provider IDs for per-SPID directory checks |
| `outgoing_outbound_call_files` | `OOCF_CREATED_DTTM` | Hourly RSERC file creation count |
| `PROCESS_STATISTICS` | `PS_RUN_DTTM`, `PS_RECORD_COUNT`, `PS_PROCESS_NAME` | Hourly CDR processing statistics |

### 5.3 SQL Scripts

| Script | Purpose |
|--------|---------|
| `rerun_rserc.sql` | Takes an SP_ID as argument and re-triggers the RSERC assembly process for that provider. Called during automatic failure recovery. |

### 5.4 File System Directories

| Variable | Default Path | Purpose |
|----------|-------------|---------|
| `TAP_ARCHIVE_DIR` | `/data/tap/R53_TAPLIVE/TAP/ARCHIVE` | Archived call data files — checked for recent activity |
| `TAP_COLLECT_DIR` | `/data/tap/R53_TAPLIVE/TAP/COLLECT` | Outbound call data collection — backlog monitoring |
| `TAP_READY_FOR_PRICING` | `/data/tap/R53_TAPLIVE/TAP/TO_PRICE` | Files awaiting pricing — backlog monitoring |
| `TAP_OB_PRICED` | `/data/tap/R53_TAPLIVE/TAP/PRICED` | Priced files awaiting splitting — backlog monitoring |
| `TAP_OB_SPLIT` | `/data/tap/R53_TAPLIVE/TAP/SPLIT` | Per-SPID split directories — backlog monitoring |
| `TAP_OUTGOING_SP` | `/data/tap/R53_TAPLIVE/TAP/OG_SP` | Outgoing SP directory — checked for `.don`/`.tmp` failure artifacts |
| `TAP_PERIOD_DIR` | `/data/tap/R53_TAPLIVE/TAP/PERIOD` | Period directory — `.tmp` files deleted during recovery |
| `TAP_LOG_DIR` | `/data/tap/R53_TAPLIVE/TAP/LOG` | Log file directory |

### 5.5 OS Utilities

| Utility | Purpose |
|---------|---------|
| `find` | Counts files matching patterns in monitored directories; deletes old logs and temp files |
| `mailx` | Sends email alerts and reports |
| `at` | Schedules next day's run (alternative: cron) |
| `date` | Generates timestamps for logging and hour-change detection |
| `sleep` | 10-minute wait between RSERC failure checks |
| `ps` | Checks if assembly/distribution processes are running |
| `grep` | Parses process list and spool files |
| `awk` | Extracts SP_ID from mrlog filenames |
| `sort` | Deduplicates SP_ID list |
| `tee` | Writes to log file and stdout simultaneously |
| `readlink` | Resolves the script's full path for self-scheduling |

---

## 6. Configuration (Environment Variables)

| Variable | Description | Required | Default | Example |
|----------|-------------|:--------:|---------|---------|
| `TAP_ARCHIVE_DIR` | Archive directory for processed call files | No | `/data/tap/R53_TAPLIVE/TAP/ARCHIVE` | *(same)* |
| `TAP_COLLECT_DIR` | Collection directory for outbound call data | No | `/data/tap/R53_TAPLIVE/TAP/COLLECT` | *(same)* |
| `TAP_READY_FOR_PRICING` | Directory for files awaiting pricing | No | `/data/tap/R53_TAPLIVE/TAP/TO_PRICE` | *(same)* |
| `TAP_OB_PRICED` | Directory for priced files awaiting splitting | No | `/data/tap/R53_TAPLIVE/TAP/PRICED` | *(same)* |
| `TAP_OB_SPLIT` | Parent directory for per-SPID split subdirectories | No | `/data/tap/R53_TAPLIVE/TAP/SPLIT` | *(same)* |
| `TAP_OUTGOING_SP` | Outgoing SP directory (checked for failures) | No | `/data/tap/R53_TAPLIVE/TAP/OG_SP` | *(same)* |
| `TAP_PERIOD_DIR` | Period directory (cleaned during recovery) | No | `/data/tap/R53_TAPLIVE/TAP/PERIOD` | *(same)* |
| `TAP_LOG_DIR` | Log output directory | No | `/data/tap/R53_TAPLIVE/TAP/LOG` | *(same)* |
| `MAX` | File count threshold for collect/pricing/priced alerts | No | `400` | `500` |
| `SPLIT_MAX` | File count threshold for per-SPID split alerts | No | `600` | `800` |
| `WORK_DIR` | Temporary working directory for spool/temp files | No | `/tmp/rserc_chk_$$` | *(auto-generated)* |
| `LOG_FILE` | Full path to the log file | No | `${TAP_LOG_DIR}/rserc_chk.log` | *(derived)* |
| `RERUN_RSERC_SQL` | Path to the SQL script for re-running RSERC assembly | No | `rerun_rserc.sql` | `/data/tap/sql/rerun_rserc.sql` |
| `ORACLE_HOME` | Oracle installation directory | Yes (external) | *(system-dependent)* | `/opt/oracle/product/19c` |
| `ORACLE_SID` | Oracle System Identifier | Yes (external) | *(system-dependent)* | `TAPDB` |

---

## 7. Email Recipients and Report Subjects

| Recipient Variable | Address | Used For |
|-------------------|---------|----------|
| `EMAIL_L2` | `Telefonica_UK.L2@accenture.com` | All alerts and reports |
| `EMAIL_APOLLO` | `VMO2_ApolloL2@accenture.com` | CDR report only |
| `EMAIL_TAP_SUPPORT` | `TAPSupport@o2.com` | RSERC failure alerts only |

| Email Subject | Trigger |
|--------------|---------|
| `"No Call files processed by TAP collection in last four hours"` | No recent `cd*.dat` in archive |
| `"There are N files in tap collection"` | Collect directory > MAX |
| `"There are N files in TAP pricing"` | To-Price directory > MAX |
| `"There are N files in TAP spliting"` | Priced directory > MAX |
| `"There are N files in TAP Distribute for spid XXX"` | Per-SPID split > SPLIT_MAX |
| `"TAP - Processed RESRC File Report"` | Hourly RSERC report |
| `"TAP - Processed roaming CDRs Report"` | Hourly CDR report |
| `"There are no RSERC created in last 4 hours"` | Zero RSERCs (non-first run) |
| `"RSERC Failure - Procedure 841 - *.DON files left out"` | `.don` files detected |
| `"RSERC Failure - Procudure 841 - *.TMP files left out - Recovering"` | `.tmp` files detected (auto-recovery) |

> **Note:** `"Procudure"` in the `.tmp` alert is an intentional preservation of the original VMS typo.

---

## 8. Differences Between VMS Script and Bash Script

| Aspect | VMS (`RSERC_CHK.COM`) | Linux (`rserc_chk.sh`) |
|--------|----------------------|------------------------|
| **Self-scheduling** | `SUBMIT/AFTER=tomorrow"+6"` — VMS batch queue scheduler | `at 06:00 tomorrow` or cron — Linux scheduling utilities |
| **File counting** | `DIR .../TOT` + `PIPE ... SEA "Total of "` — parses directory totals from formatted output | `find ... \| wc -l` — direct count, more efficient |
| **Archive time filter** | `DIR .../SIN="-4"` — VMS since qualifier (4 hours ago) | `find -mmin -240` — files modified within last 240 minutes |
| **SPID zero-padding** | `f$fao("!3ZL",f$integer(...))` — VMS formatted ASCII output | `printf "%03d"` — standard POSIX formatting |
| **Email (empty body)** | `MAIL NL: "addr"/sub="subject"` — NL: is the null device | `echo "" \| mailx -s "subject" addr` |
| **Email (with file)** | `MAIL/SUBJ="subject" file "addr"` | `mailx -s "subject" addr < file` |
| **Queue/process check** | `SH QUE *ASS*/OUT=file` then `SEA file dist` — checks VMS batch queues | `ps -ef \| grep "assemb\|dist"` — checks Linux processes |
| **Job logical names** | `DEFINE/JOB file_count N` — VMS job-scope logical names shared between commands | Shell variables — process-local, no inter-process sharing needed |
| **Temp file cleanup** | `DEL file;*` — deletes all versions of a VMS file | `rm -f file` — single file delete (no versioning on Linux) |
| **Log retention** | `DEL/BEF="-30-" tap_log_dir:rserc_chk.log;*` — VMS before-date qualifier | `find ... -mtime +30 -delete` — POSIX find with age filter |
| **Error handling** | `SET NOON` — VMS continues on errors without aborting | `set -o nounset` is not used; script uses `2>/dev/null` for graceful degradation |
| **String extraction** | `F$EXTRACT(pos,len,string)` / `F$ELEMENT(n,delim,string)` | `sed`, `awk`, shell parameter expansion |
| **SP_ID extraction from mrlog** | `f$extract(34,3,rec)` on full VMS directory output (includes path) | `awk '{ print substr($0,35,3) }'` on filename-only output — **position may need adjustment** |

### Risks and Behavioral Changes

1. **SP_ID extraction position:** The VMS version extracts SP_ID from position 35 of a full directory listing line (which includes the VMS path prefix). The Linux version extracts from position 35 of the bare filename. Depending on actual `mrlog*.tmp` filename formats, the `awk` offset may need to be adjusted during deployment.

2. **Process detection vs. queue checking:** VMS checks batch queue status (`SHOW QUEUE`), which shows queued and running jobs. Linux checks running processes (`ps -ef`), which only shows currently executing processes. A job that is queued but not yet started would be detected on VMS but not on Linux.

3. **Alert delivery:** VMS `MAIL` is synchronous and integrated with the VMS mail system. Linux `mailx` depends on an external MTA (sendmail, postfix, etc.) being configured and running.

4. **No singleton guard:** Unlike other scripts in this suite, the VMS `RSERC_CHK.COM` does not enforce single-instance (no `SET PROCESS/NAME`). The Linux version also lacks a lock/PID file mechanism. If the script is started twice, both instances will run concurrently. Consider adding `flock` if this is a concern.

5. **`at` command availability:** The `at` daemon (`atd`) must be running for self-scheduling. On RHEL 9, it is installed but may not be enabled by default. Cron is the recommended alternative.

---

## 9. Real-World Example Scenarios

### Scenario 1: File Collection Backlog

**Setup:**
- `MAX=400`
- 450 `CD00001GBRCN*.dat` files are in `TAP_COLLECT_DIR`

**What happens:**
1. `check_tap_directories()` counts 450 files in the collect directory
2. 450 > 400 → `send_alert "There are 450 files in tap collection"`
3. Email sent to L2; log entry written
4. L2 investigates why the collection pipeline is stalled (perhaps the pricing process is down)
5. On the next hourly cycle, if files are still above 400, another alert is sent

### Scenario 2: RSERC Assembly Failure with .tmp Files

**Setup:**
- The RSERC assembly process crashed, leaving `mrlog_XXX_042.tmp` and `data.tmp` in `TAP_OUTGOING_SP`
- Assembly/distribution process is not currently running

**What happens:**
1. `check_rserc_failures()` runs and does not find "dist" in `ps -ef` output
2. Finds `.tmp` files in `TAP_OUTGOING_SP`
3. Sends alert: `"RSERC Failure - Procudure 841 - *.TMP files left out - Recovering"`
4. Lists `mrlog*.tmp` filenames to `mrlog.lis`
5. Deletes all `.tmp` files from `TAP_OUTGOING_SP` and `TAP_PERIOD_DIR`
6. Extracts SP_ID (e.g., `042`) from mrlog filename at position 35
7. Calls `sqlplus -s / @rerun_rserc.sql "042"`
8. RSERC assembly is re-triggered for SP_ID 042
9. On the next 10-minute check, if no more `.tmp` files exist, no further action is taken

### Scenario 3: Zero RSERCs Created

**Setup:**
- It is 14:00, the script has been running since 06:00 (run_count > 1)
- No RSERC files were created in the last 4 hours (e.g., upstream pipeline stalled at midnight)

**What happens:**
1. `generate_hourly_reports()` queries Oracle
2. `files_created1.lis` contains `FILE_COUNT= 0`
3. Since `run_count != 1`: `send_alert "There are no RSERC created in last 4 hours"`
4. L2 receives the alert and investigates the upstream pipeline

### Scenario 4: Normal Day — No Issues

**What happens:**
1. 06:00 — Script starts, schedules tomorrow's run, generates SPID list
2. 06:00-06:10 — First `check_tap_directories()` runs. Archives have recent files, all counts below thresholds.
3. 06:10 — `generate_hourly_reports()` queries Oracle. File count > 0 but `run_count == 1`, so no zero-RSERC alert. Reports emailed.
4. 06:10-07:00 — Inner loop checks for RSERC failures every 10 minutes. No `.don` or `.tmp` files.
5. 07:00 — Hour changes, outer loop restarts. Full directory check + new hourly report.
6. Pattern repeats until 23:00.
7. 23:00 — `check_hour` detects hour = "23", `main()` returns, cleanup runs.

---

## 10. Test Approach for the Converted Shell Script

### 10.1 Testing Framework

The test suite uses **[Bats](https://github.com/bats-core/bats-core)** (Bash Automated Testing System), which provides structured unit testing for Bash scripts. The test file is `tests/rserc_chk.bats` with shared setup in `tests/test_helper.bash`.

### 10.2 Mocking Strategy

Since the script depends on Oracle (`sqlplus`), email (`mailx`), and system scheduling (`at`), **all external dependencies are mocked** via shim scripts placed early on `PATH`:

| Dependency | Mock Approach |
|-----------|---------------|
| `sqlplus` | A bash shim that reads stdin (the heredoc SQL), honours `SPOOL` directives by creating files at the specified paths, and writes predictable output. Does not require Oracle to be installed. |
| `mailx` | A bash shim that logs all invocations (subject, recipients) to `${WORK_DIR}/mailx.log` for assertion. |
| `at` | A bash shim that logs scheduling calls to `${WORK_DIR}/at.log`. Can be replaced with a failing version to test the warning path. |
| `ps` | Optionally replaced to simulate assembly/distribution processes being active. |

### 10.3 Directory Isolation

Each test runs in a **completely isolated temporary directory** created by `setup()`:
- All `TAP_*` directories are created under a per-test `TEST_TEMP_DIR`
- All file paths, log files, and work directories point to the temp tree
- `teardown()` removes the entire temp directory after each test

This ensures:
- No test affects another test
- No test touches the real filesystem
- Tests can run in parallel (each gets its own temp dir)

### 10.4 Test Categories

The test suite covers **11 categories** with both positive and negative scenarios:

| # | Category | Test Count | What Is Tested |
|---|----------|-----------|----------------|
| 1 | `log_msg` | 3 | Timestamped logging, format correctness, append behavior |
| 2 | `send_alert` | 2 | Email invocation, subject text, logging |
| 3 | `send_report` | 2 | Multi-recipient email, missing file handling |
| 4 | `schedule_next_run` | 2 | `at` invocation, fallback warning on failure |
| 5 | `generate_spid_list` | 2 | File creation, log message |
| 6 | `check_tap_directories` | 12+ | Archive (recent/old/none), collect/pricing/priced backlog, per-SPID split, boundary at MAX/SPLIT_MAX, missing SPID list, invalid SPIDs |
| 7 | `generate_hourly_reports` | 8+ | Report logging, email sending, spool cleanup, zero FILE_COUNT alerts (first run skipped vs. subsequent), SPOOL path expansion |
| 8 | `check_rserc_failures` | 9+ | No failures, `.don` alert, `.tmp` alert + recovery, `.tmp` deletion, period dir cleanup, mrlog rerun, dist process skipping, cleanup |
| 9 | `cleanup_and_exit` | 5 | Completion log, work dir removal, failure file removal, old log deletion, recent log preservation, double-call guard |
| 10 | Edge cases | 8+ | MAX=0, boundary values (401@400, 601@600), multiple SPIDs, zero-padding, empty SPID list, non-matching patterns, case-insensitive matching |
| 11 | Golden master | 9 | Exact output format validation — log line format, alert subjects, email subjects, VMS typo preservation |
| 12 | Integration | 3 | Full check+report cycle, failure+cleanup cycle, SPID generation+directory check |

### 10.5 Key Test Assertions

- **Alert triggers:** Verify that specific log messages appear (or do not appear) based on file counts and thresholds
- **Boundary conditions:** Exactly at threshold (e.g., 400 files with MAX=400) → no alert; one above (401) → alert
- **Email invocations:** Count `MAILX_CALL:` entries in the mock log to verify correct number of recipients
- **File cleanup:** Assert that temp files are removed after each operation
- **Error resilience:** Invalid SPID entries, missing files, and failing commands do not crash the script
- **Output format fidelity:** Golden master tests verify that alert messages, email subjects, and log formats exactly match the original VMS output

### 10.6 Running the Tests Locally

```bash
# Prerequisites: Install bats-core
# On RHEL/CentOS:
sudo yum install -y bats
# Or from source:
git clone https://github.com/bats-core/bats-core.git
cd bats-core && sudo ./install.sh /usr/local

# Run all rserc_chk tests:
cd converted/tests
bats rserc_chk.bats

# Run a single test by name:
bats -f "archive files" rserc_chk.bats

# Run with verbose output (TAP format):
bats --tap rserc_chk.bats
```

---

## 11. Test Server Deployment and Testing Guide

### 11.1 Prerequisites

| Component | Requirement | How to Verify |
|-----------|------------|---------------|
| **OS** | RHEL 8/9 or compatible Linux | `cat /etc/redhat-release` |
| **Bash** | Version 4.0+ | `bash --version` |
| **Oracle Client** | sqlplus on PATH with OS-authenticated access | `which sqlplus` and `sqlplus / <<< "EXIT 77;"` (exit code should be 77) |
| **Mail** | `mailx` installed and MTA configured (postfix/sendmail) | `echo "test" \| mailx -s "test" your@email.com` |
| **Bats** | bats-core 1.x+ installed | `bats --version` |
| **Oracle Tables** | `service_providers`, `outgoing_outbound_call_files`, `PROCESS_STATISTICS` present | `sqlplus / <<< "SELECT COUNT(*) FROM service_providers;"` |
| **SQL Script** | `rerun_rserc.sql` available at the configured path | `ls -l rerun_rserc.sql` |
| **Scheduler** | `atd` service running (or cron configured) | `systemctl status atd` |

### 11.2 Test Server Directory Setup

Create the required directory structure on the test server:

```bash
# Define base path (adjust for your test environment)
BASE="/data/tap/R53_TAPLIVE/TAP"

# Create all required directories
sudo mkdir -p \
    "${BASE}/ARCHIVE" \
    "${BASE}/COLLECT" \
    "${BASE}/TO_PRICE" \
    "${BASE}/PRICED" \
    "${BASE}/SPLIT" \
    "${BASE}/OG_SP" \
    "${BASE}/PERIOD" \
    "${BASE}/LOG"

# Set ownership to the TAP service account
sudo chown -R taplive:taplive "${BASE}"
```

### 11.3 Phase 1 — Unit Tests (No Oracle, No Email)

These tests use **mocked dependencies** and can run on any Linux box, even without Oracle:

```bash
# 1. Copy the converted scripts and tests to the test server
scp -r converted/ testserver:/home/taplive/rserc_chk_test/

# 2. SSH to the test server
ssh taplive@testserver

# 3. Run the Bats unit tests
cd /home/taplive/rserc_chk_test/tests
bats rserc_chk.bats

# Expected: All tests pass (mocks simulate Oracle and email)
```

**What this validates:**
- All function logic (directory checking, threshold comparisons, alert decisions)
- File pattern matching (case-insensitive, wildcard patterns)
- Email invocation correctness (via mock log analysis)
- Error handling (missing files, invalid inputs, edge cases)
- Output format fidelity (golden master tests)

### 11.4 Phase 2 — Oracle Integration Tests

Run the script with **real Oracle** but test-safe email addresses and test directories:

```bash
# Set environment to use test directories (not production!)
export TAP_ARCHIVE_DIR="/data/tap/TEST/ARCHIVE"
export TAP_COLLECT_DIR="/data/tap/TEST/COLLECT"
export TAP_READY_FOR_PRICING="/data/tap/TEST/TO_PRICE"
export TAP_OB_PRICED="/data/tap/TEST/PRICED"
export TAP_OB_SPLIT="/data/tap/TEST/SPLIT"
export TAP_OUTGOING_SP="/data/tap/TEST/OG_SP"
export TAP_PERIOD_DIR="/data/tap/TEST/PERIOD"
export TAP_LOG_DIR="/data/tap/TEST/LOG"
export WORK_DIR="/tmp/rserc_chk_test"
export LOG_FILE="/data/tap/TEST/LOG/rserc_chk_test.log"
export MAX=5          # Low threshold for testing
export SPLIT_MAX=5    # Low threshold for testing

# Create test directories
mkdir -p $TAP_ARCHIVE_DIR $TAP_COLLECT_DIR $TAP_READY_FOR_PRICING \
         $TAP_OB_PRICED $TAP_OB_SPLIT $TAP_OUTGOING_SP \
         $TAP_PERIOD_DIR $TAP_LOG_DIR $WORK_DIR

# Test 1: SPID list generation (verifies Oracle connectivity)
source rserc_chk.sh   # Source without executing (guard prevents main())
generate_spid_list
cat "${SPID_LIST}"
# EXPECTED: List of SP_IDs from the database

# Test 2: Hourly report generation (verifies Oracle queries)
run_count=2
generate_hourly_reports
# EXPECTED: files_created.lis and recs_created.lis generated and emailed
# Check log: grep "Processed" "${LOG_FILE}"

# Test 3: Directory backlog detection with low thresholds
# Create 6 test files to exceed MAX=5
for i in $(seq 1 6); do
    touch "${TAP_COLLECT_DIR}/CD00001GBRCN$(printf '%05d' $i).dat"
done
touch "${TAP_ARCHIVE_DIR}/cd00001.dat"  # Prevent archive alert
check_tap_directories
grep "files in tap collection" "${LOG_FILE}"
# EXPECTED: Alert logged showing 6 files

# Test 4: RSERC failure detection
touch "${TAP_OUTGOING_SP}/test.don"
check_rserc_failures
grep "DON files left out" "${LOG_FILE}"
# EXPECTED: Alert logged about .don files

# Clean up test data
rm -rf /data/tap/TEST /tmp/rserc_chk_test
```

### 11.5 Phase 3 — Full End-to-End Test

Run the script as it would run in production, but with controlled conditions:

```bash
# 1. Start the script with test-safe configuration
#    (Use test email, test directories, low thresholds)
export EMAIL_L2="your-test-email@accenture.com"
export EMAIL_APOLLO="your-test-email@accenture.com"
export EMAIL_TAP_SUPPORT="your-test-email@accenture.com"

# 2. Run the script (it will loop until 23:00)
nohup ./rserc_chk.sh >> /data/tap/TEST/LOG/rserc_chk.log 2>&1 &

# 3. Monitor the log
tail -f /data/tap/TEST/LOG/rserc_chk.log

# 4. Verify:
#    - SPID list generated on startup
#    - Directory checks run every hour
#    - Hourly reports emailed
#    - RSERC failure checks every 10 minutes
#    - Script exits cleanly at 23:00

# 5. Inject failures to test recovery:
#    a. Create .don files:
touch /data/tap/TEST/OG_SP/test.don
#    b. Create .tmp files for recovery:
touch /data/tap/TEST/OG_SP/mrlog_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx042.tmp

# 6. Watch the log for alerts and recovery actions

# 7. Stop the script early if needed:
kill $(pgrep -f rserc_chk.sh)
```

### 11.6 Test Validation Checklist

| Test | Method | Expected Result | Pass/Fail |
|------|--------|----------------|:---------:|
| Script starts without error | Run `./rserc_chk.sh` | "RSERC CHK started" in log | |
| SPID list generated | Check `spid_list.lis` | Contains SP_IDs from database | |
| Archive alert (no recent files) | Empty archive dir | "No Call files processed..." email | |
| Archive no-alert (recent files) | Touch `cd*.dat` in archive | No archive alert in log | |
| Collect backlog alert | Create > MAX files | "There are N files in tap collection" email | |
| Pricing backlog alert | Create > MAX files in TO_PRICE | "There are N files in TAP pricing" email | |
| Split backlog alert | Create > SPLIT_MAX in SPLIT/XXX | "There are N files in TAP Distribute for spid XXX" | |
| Hourly RSERC report | Wait for hourly cycle | "TAP - Processed RESRC File Report" email received | |
| Hourly CDR report | Wait for hourly cycle | "TAP - Processed roaming CDRs Report" email received | |
| Zero-RSERC alert | No files created in 4h (run_count > 1) | "There are no RSERC created in last 4 hours" email | |
| .don file alert | Create `.don` in TAP_OUTGOING_SP | "RSERC Failure - Procedure 841 - *.DON files left out" | |
| .tmp file recovery | Create `.tmp` in TAP_OUTGOING_SP | Alert sent + `.tmp` files deleted + `rerun_rserc.sql` executed | |
| Script exits at 23:00 | Let it run until 23:00 | "RSERC_CHK completed" in log, process exits | |
| Old log cleanup | Create log > 30 days old | File deleted during cleanup | |
| Temp file cleanup | Check WORK_DIR after exit | Directory removed | |
| Next-day scheduling | Check `at -l` or cron | Job scheduled for 06:00 tomorrow | |

---

## 12. Dependency Summary

### Runtime Dependencies

```
rserc_chk.sh
├── Oracle Database (sqlplus)
│   ├── service_providers table (SPID list)
│   ├── outgoing_outbound_call_files table (RSERC reports)
│   ├── PROCESS_STATISTICS table (CDR reports)
│   └── rerun_rserc.sql (failure recovery script)
├── Mail System (mailx)
│   └── MTA (postfix/sendmail) configured and running
├── Scheduler
│   ├── at daemon (atd) — for self-scheduling
│   └── OR cron — recommended alternative
├── File System
│   ├── TAP_ARCHIVE_DIR — must exist and be readable
│   ├── TAP_COLLECT_DIR — must exist and be readable
│   ├── TAP_READY_FOR_PRICING — must exist and be readable
│   ├── TAP_OB_PRICED — must exist and be readable
│   ├── TAP_OB_SPLIT/<SPID> — per-provider subdirectories
│   ├── TAP_OUTGOING_SP — must be readable AND writable (deletes .tmp)
│   ├── TAP_PERIOD_DIR — must be writable (deletes .tmp)
│   ├── TAP_LOG_DIR — must be writable (log output)
│   └── /tmp — for WORK_DIR (writable)
├── OS Utilities
│   ├── bash 4+
│   ├── find, grep, awk, sort, sed, tee, wc
│   ├── ps (for process detection)
│   ├── sleep, date, readlink
│   └── mkdir, rm, touch
└── Environment Variables
    ├── ORACLE_HOME — Oracle installation path
    ├── ORACLE_SID — database identifier
    └── PATH — must include sqlplus, mailx, standard utilities
```

### Test Dependencies

```
rserc_chk.bats (unit tests)
├── bats-core 1.x+ (Bash Automated Testing System)
├── bash 4+ (for sourcing and function testing)
├── test_helper.bash
│   ├── Mock sqlplus (reads heredocs, honours SPOOL)
│   ├── Mock mailx (logs invocations)
│   ├── Mock at (logs scheduling calls)
│   └── File helper functions (populate_dir, create_spid_list, etc.)
├── Temp directory (/tmp) — writable, auto-cleaned per test
└── NO Oracle, NO email, NO network required
```

### Inter-Script Dependencies

| Script | Relationship |
|--------|-------------|
| `rerun_rserc.sql` | Called by `check_rserc_failures()` to re-trigger RSERC assembly per SP_ID |
| `tap_job_startup.sh` | Not directly called by this script (unlike `tap_monitor.sh`) |

---

## 13. Summary

The **RSERC CHK** script is a dual-purpose monitoring and recovery daemon for the TAP outbound billing pipeline. It performs three main functions:

1. **Directory Backlog Monitoring** — Every hour, it counts files in the Archive, Collect, To-Price, Priced, and per-SPID Split directories. When counts exceed configured thresholds (400 for most stages, 600 for splits), it sends email alerts to L2 support.

2. **Oracle Hourly Reporting** — Every hour, it queries Oracle for RSERC file creation and CDR processing statistics, grouping by hour for the current day. Reports are emailed to L2 and Apollo. If zero RSERCs have been created in the last 4 hours (and it is not the first check), an alert is sent.

3. **RSERC Failure Detection and Auto-Recovery** — Every 10 minutes, it checks for orphaned `.don` and `.tmp` files left behind by failed RSERC assembly runs. `.don` files trigger an alert. `.tmp` files trigger both an alert and automatic recovery: the temp files are cleaned up and the RSERC assembly is re-triggered via Oracle SQL for each affected service provider.

The script runs from 06:00 to 23:00 daily, self-scheduling for the next day. It was originally written for VMS in DCL and has been converted to Linux Bash, preserving the same monitoring logic, alert messages (including the original "Procudure" typo), and recovery behavior. The primary differences are in file counting (VMS `DIR/TOT` vs. Linux `find|wc`), process detection (VMS batch queues vs. Linux `ps`), and email delivery (VMS `MAIL` vs. `mailx`).

---

## 14. VMS DCL Glossary (for non-VMS developers)

This section provides a comprehensive reference of every VMS/DCL construct used in the original `RSERC_CHK.COM` script, so non-VMS developers can understand the original code.

### 14.1 Command Reference

| VMS Command/Construct | Linux Equivalent | Explanation |
|----------------------|------------------|-------------|
| `$ set proc/priv=all` | `sudo` / run as root | Sets all VMS privileges for the current process. Similar to running with elevated permissions. |
| `$ set noverify` | (no equivalent) | Suppresses command echo in the log. By default, VMS logs every command; `SET NOVERIFY` turns that off. |
| `$ set noon` | (default Bash behaviour) | "Set No ON-error" — continue executing even if a command fails. Bash does this by default (unless `set -e` is used). |
| `$ submit /after=... /keep /log=... /noprint file.com` | `at`, `cron`, `nohup` | Submits a job to the VMS batch queue scheduler. `/AFTER=` sets the start time, `/KEEP` retains the job log, `/LOG=` specifies the log file. |
| `$ wso "text"` | `echo "text"` | `WSO` is a user-defined symbol: `wso="write sys$output"`. It writes to standard output. |
| `$ dir DISK$...[DIR]pattern/qualifiers` | `ls`, `find` | Lists files matching a pattern. Various qualifiers modify behaviour: `/TOT` (totals), `/SIN="-4"` (since 4 hours), `/NOOUT` (no output), `/NOHEAD/NOTRAIL` (no headers). |
| `$ mail NL: "addr"/sub="subj"` | `echo "" \| mailx -s "subj" addr` | Send email with empty body. `NL:` is the null device (/dev/null). |
| `$ MAIL/SUBJ="subj" file "addr"` | `mailx -s "subj" addr < file` | Send email with file as body. |
| `$ if $status .eqs. "%X00000001"` | `if [ $? -eq 0 ]` | Check previous command status. `%X00000001` = success. |
| `$ if cond .then. ... $ endif` | `if [ cond ]; then ... fi` | Conditional execution. |
| `$ goto label` | `continue`, `break`, function calls | Unconditional jump to a label. VMS uses GOTOs instead of loops/functions. |
| `$ label:` | function name() { } | A jump target for GOTO. |
| `$!` | `#` | Comment line. |
| `$ open/read filevar filename` | `while read line; do ... done < file` | Opens a file for reading. |
| `$ read/end=label filevar line` | `read -r line` | Reads one line. `/END=label` jumps to label at EOF. |
| `$ close filevar` | (automatic on loop end) | Closes the file. |
| `$ wait 00:10:00` | `sleep 600` | Pauses execution for 10 minutes. |
| `$ exit` | `exit 0` | Exits the script. |
| `$ delete file;*` or `$ del file;*` | `rm -f file` | Deletes all versions of a file. |
| `$ pip dir .../tot \| sea sys$input "Total of " \| (read ...)` | `find ... \| wc -l` | VMS pipe chain: lists files with total, searches for the total line, parses the count. |
| `$ sh que *ass*/out=file` | `ps -ef \| grep assemb` | `SHOW QUEUE *ASS*` lists batch queues matching the pattern. |
| `$ sea file pattern` | `grep pattern file` | `SEARCH` looks for a string in a file. |
| `$ sort/nodup/key=(pos:N,siz:M) in out` | `awk '{...}' \| sort -u` | Sorts a file, deduplicates by a positional key. |
| `$ define/job logical value` | `export VAR=value` | Creates a job-scope logical name (like a persistent environment variable). |
| `$ deassign/job logical` | `unset VAR` | Removes a logical name. |

### 14.2 VMS Built-in Functions

| VMS Function | Linux Equivalent | Explanation |
|-------------|------------------|-------------|
| `F$TIME()` | `date '+...'` | Returns current date/time as a string. Format: `DD-MON-YYYY HH:MM:SS.CC` |
| `F$EXTRACT(offset,length,string)` | `${var:offset:length}`, `cut`, `awk substr()` | Extracts a substring. Offset is 0-based. |
| `F$ELEMENT(n,delimiter,string)` | `awk -F'delim' '{print $N}'` | Returns the Nth delimited element from a string. 0-based. |
| `F$FAO("!3ZL",integer)` | `printf "%03d" integer` | Formatted ASCII Output: `!3ZL` = 3-digit zero-padded integer. |
| `F$INTEGER(string)` | `$((string + 0))` | Converts a string to an integer. |
| `F$EDIT(string,"TRIM")` | `echo "$var" \| tr -d '[:space:]'` | Trims whitespace from a string. |
| `F$LENGTH(string)` | `${#var}` | Returns the length of a string. |
| `F$TRNLNM("logical")` | `echo "$VAR"` | Translates (reads) a logical name — like reading an environment variable. |

### 14.3 VMS Path Notation

| VMS Notation | Linux Equivalent | Explanation |
|-------------|------------------|-------------|
| `DISK$CALL_DATA:` | `/data/tap/` (mount point) | A **logical name** pointing to a disk device. Defined system-wide by the administrator. |
| `[TAP.OB.COLLECT]` | `/TAP/OB/COLLECT/` | Directory path. Uses `.` instead of `/` for path separators, enclosed in square brackets. |
| `DISK$CALL_DATA:[TAP.OB.COLLECT]CD*.dat` | `/data/tap/TAP/OB/COLLECT/CD*.dat` | Full file specification: device + directory + filename pattern. |
| `file.ext;1` | `file.ext` | VMS file versioning: `;1` is version 1. Every edit creates a new version. |
| `file.ext;*` | `file.ext` | All versions of the file. Linux has no versioning. |
| `NL:` | `/dev/null` | The null device — discards all input. |
| `SYS$OUTPUT` | stdout | Standard output stream. |
| `SYS$INPUT` | stdin | Standard input stream. |
| `SYS$PIPE` | pipe (stdin from `\|`) | Data coming through a VMS PIPE chain. |
| `tap_log_dir:` | `${TAP_LOG_DIR}` | A user-defined logical name pointing to the log directory. |
| `tap_outgoing_sp:` | `${TAP_OUTGOING_SP}` | A user-defined logical name pointing to the outgoing SP directory. |

### 14.4 VMS Comparison Operators

| VMS Operator | Bash Equivalent | Meaning |
|-------------|-----------------|---------|
| `.EQS.` | `==` (string) | Equal (string comparison) |
| `.NES.` | `!=` (string) | Not equal (string) |
| `.EQ.` | `-eq` (integer) | Equal (integer) |
| `.NE.` | `-ne` (integer) | Not equal (integer) |
| `.GT.` | `-gt` (integer) | Greater than |
| `.GE.` | `-ge` (integer) | Greater or equal |
| `.LT.` | `-lt` (integer) | Less than |
| `.LE.` | `-le` (integer) | Less or equal |
| `.AND.` | `&&` | Logical AND |
| `.OR.` | `\|\|` | Logical OR |

### 14.5 VMS Variable Substitution

| VMS Syntax | Bash Equivalent | Explanation |
|-----------|-----------------|-------------|
| `'variable'` | `${variable}` | Single-level substitution. |
| `''variable'` | `${variable}` (forced) | Double-quote forces substitution inside strings. Used inside `WSO` strings as `''dttm'` to substitute the value of `dttm`. |
| `&variable` | `${variable}` | Ampersand substitution (used in `DEFINE/JOB`). |

---

## 15. Per-Function Testing Prerequisites Summary

The following table consolidates the prerequisites needed to test each function on the test server, making it easy to plan and prepare.

### 15.1 Quick Reference: What Each Function Needs

| Function | Oracle | `mailx` + MTA | `at` / cron | TAP Directories | Files to Create | Notes |
|----------|:------:|:-------------:|:-----------:|:---------------:|:---------------:|-------|
| `log_msg()` | No | No | No | `TAP_LOG_DIR` only | None | Simplest to test |
| `send_alert()` | No | **Yes** | No | `TAP_LOG_DIR` only | None | Override `EMAIL_L2` for testing |
| `send_report()` | No | **Yes** | No | `TAP_LOG_DIR` only | A text file to send | Override recipients for testing |
| `schedule_next_run()` | No | No | **Yes** | None | None | `atd` service must be running |
| `generate_spid_list()` | **Yes** | No | No | `WORK_DIR` | None | Needs OS-authenticated Oracle |
| `check_tap_directories()` | No | **Yes** (for alerts) | No | ALL `TAP_*` dirs | Dummy `cd*.dat`, `CD?????GBRCN*.dat`, etc. | Most dirs needed |
| `generate_hourly_reports()` | **Yes** | **Yes** | No | `WORK_DIR`, `TAP_LOG_DIR` | None (Oracle generates spool) | Needs Oracle tables populated |
| `check_rserc_failures()` | **Yes** (for recovery) | **Yes** (for alerts) | No | `TAP_OUTGOING_SP`, `TAP_PERIOD_DIR` | `.don` and/or `.tmp` files | `rerun_rserc.sql` needed for recovery |
| `cleanup_and_exit()` | No | No | No | `WORK_DIR`, `TAP_LOG_DIR` | Temp files, old log files | Safe — only deletes from work/log dirs |
| `main()` | **Yes** | **Yes** | **Yes** | ALL | All of the above | Full end-to-end |

### 15.2 Minimal Setup for Unit-Test Execution (No Oracle, No Email)

To run the fully automated Bats unit tests, you need only:

| Component | How to Install/Verify |
|-----------|----------------------|
| **Linux server** (RHEL 8/9 or compatible) | `cat /etc/redhat-release` |
| **Bash 4+** | `bash --version` |
| **Bats-core** | `bats --version` — install: `sudo yum install -y bats` or from GitHub |
| **Writable `/tmp`** | `touch /tmp/test_file && rm /tmp/test_file` |

No Oracle, no email, no TAP directories, no special permissions needed. **All dependencies are mocked.**

```bash
# Run all unit tests
cd /path/to/converted/tests
bats rserc_chk.bats
# Expected: 50+ tests, all passing
```

### 15.3 Setup for Oracle Integration Testing

In addition to the unit test prerequisites, you need:

| Component | How to Verify |
|-----------|---------------|
| **Oracle Client (sqlplus)** | `which sqlplus` |
| **ORACLE_HOME** set | `echo $ORACLE_HOME` |
| **ORACLE_SID** set | `echo $ORACLE_SID` |
| **OS-authenticated access** | `sqlplus / <<< "SELECT 1 FROM DUAL; EXIT;"` — should return `1` |
| **Tables exist with data** | `sqlplus / <<< "SELECT COUNT(*) FROM service_providers; EXIT;"` |
|  | `sqlplus / <<< "SELECT COUNT(*) FROM outgoing_outbound_call_files; EXIT;"` |
|  | `sqlplus / <<< "SELECT COUNT(*) FROM PROCESS_STATISTICS; EXIT;"` |
| **rerun_rserc.sql** | `ls -l /path/to/rerun_rserc.sql` |

### 15.4 Setup for Full End-to-End Testing

In addition to all the above:

| Component | How to Verify |
|-----------|---------------|
| **mailx** installed | `which mailx` — install: `yum install mailx` |
| **MTA running** | `systemctl status postfix` (or sendmail) |
| **Mail delivery** | `echo "test" \| mailx -s "E2E Test" your-email@accenture.com` — check inbox |
| **at daemon** | `systemctl status atd` — or configure cron: `crontab -l` |
| **TAP directories created** | See Section 11.2 for the full `mkdir` script |
| **Correct ownership** | `ls -la /data/tap/` — the test user must own the directories |
| **Test email addresses configured** | Override `EMAIL_L2`, `EMAIL_APOLLO`, `EMAIL_TAP_SUPPORT` with your own addresses |
| **Low thresholds for testing** | Set `MAX=5` and `SPLIT_MAX=5` to trigger alerts with fewer test files |

### 15.5 Common Troubleshooting During Testing

| Issue | Cause | Fix |
|-------|-------|-----|
| `sqlplus: command not found` | Oracle client not on PATH | `export PATH=$ORACLE_HOME/bin:$PATH` |
| `ORA-01017: invalid username/password` | OS authentication not configured | Ensure the OS user is mapped in Oracle's `orapwd` or external authentication |
| `mailx: command not found` | `mailx` not installed | `sudo yum install -y mailx` |
| Emails not received | MTA not running or misconfigured | `sudo systemctl start postfix` and check `/var/log/maillog` |
| `at: command not found` | `at` package not installed | `sudo yum install -y at` and `sudo systemctl start atd` |
| Permission denied on TAP directories | Incorrect ownership | `sudo chown -R $USER:$USER /data/tap/TEST/` |
| `bats: command not found` | Bats not installed | Install from package manager or GitHub (see Section 10.6) |
| Archive alert fires unexpectedly | No recent files, or `find -mmin -240` finds nothing | Ensure test files were created with `touch` (which sets current timestamp) |
| SPID list is empty | Oracle query returns no rows | Verify data in `service_providers` table |
| `check_rserc_failures` always skips | A "dist" or "assemb" process is running | Stop the matching process, or adjust the `ps -ef | grep` pattern |
