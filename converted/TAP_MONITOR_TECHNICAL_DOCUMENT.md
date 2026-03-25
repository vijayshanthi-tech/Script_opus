# TAP Monitor — Comprehensive Technical Document

**Script Name:** `tap_monitor.sh` (Linux Bash)
**Converted From:** `TAP_MONITOR.COM` (VMS DCL)
**Case ID:** TAPOP0280 | **Spec ID:** TAPSO280.DOC

---

## 1. Overview

### What is this system?

The TAP Monitor is a **continuous background watchdog process** that runs inside a telecom billing environment. It operates as part of the **Transferred Account Procedure (TAP)** system — a GSMA standard used by mobile network operators worldwide to exchange billing records for roaming calls.

### What problem does it solve?

When a mobile subscriber roams onto another operator's network (for example, a UK subscriber making a call while visiting France), the visited network generates a call record. These records must flow through a multi-stage pipeline:

1. **Inbound collection** — receiving roaming records from partner networks
2. **Outbound collection** — gathering records to send to partner networks
3. **Validation and pricing** — verifying and applying tariffs
4. **Splitting** — dividing records per partner/destination
5. **Database processing** — storing and querying records via Oracle

If any stage stalls (files pile up, database goes down, background jobs crash), billing is delayed and revenue is lost. The TAP Monitor exists to:

- **Detect backlogs** — Alert operators when file counts exceed safe limits
- **Check database health** — Verify Oracle is reachable and query pipeline counts
- **Ensure jobs are running** — Restart critical background processes (GAPS, GSDM) if they have stopped
- **Notify operators** — Send immediate alerts when something is wrong

### Where is it used?

This script runs in a **telecom billing production environment** on a Linux/RHEL server (previously OpenVMS). It is intended to run 24/7 (or until a configured closedown time) as a long-lived daemon process.

---

## 2. High-Level Workflow

### End-to-End Flow (Step by Step)

```
   ┌───────────────────────────────────────────┐
   │             SCRIPT STARTS                  │
   └───────────────┬───────────────────────────┘
                   │
                   ▼
   ┌───────────────────────────────────────────┐
   │  SINGLETON CHECK                          │
   │  Is another instance already running?     │
   │  YES → Exit immediately                  │
   │  NO  → Write PID file, continue          │
   └───────────────┬───────────────────────────┘
                   │
                   ▼
   ┌───────────────────────────────────────────┐
   │  INITIALIZE                               │
   │  Set up row-count variables to zero       │
   │  Set up signal handlers (cleanup on exit) │
   └───────────────┬───────────────────────────┘
                   │
                   ▼
   ┌─────────────────────── MAIN LOOP ─────────────────────┐
   │                                                        │
   │  1. CHECK SHUTDOWN SIGNALS                             │
   │     - TAP_CLOSEDOWN_MONITOR set? → EXIT                │
   │     - Current time > TAP_CLOSEDOWN_ALL? → EXIT         │
   │                                                        │
   │  2. VALIDATE CHECK INTERVAL                            │
   │     - Is TAP_FILE_CHECK_PERIOD defined and valid?      │
   │     - If not → ALERT, use default (900 seconds)        │
   │                                                        │
   │  3. CHECK ORACLE CONNECTIVITY                          │
   │     - Run sqlplus with EXIT 77                         │
   │     - If exit code ≠ 77 → ALERT "Oracle not running"  │
   │                                                        │
   │  4. CHECK INBOUND FILES (IBCC)                         │
   │     - Count ibr*.dat files in receive directory        │
   │     - If count > limit → ALERT                         │
   │                                                        │
   │  5. CHECK OUTBOUND FILES (OBCC)                        │
   │     - Count cd*.dat + td*.dat files                    │
   │     - If count > limit → ALERT                         │
   │                                                        │
   │  6. QUERY ORACLE ROW COUNTS                            │
   │     - Get OBVP, OBSP counts from database              │
   │     - Get GAPS/GSDM queue and process names            │
   │                                                        │
   │  7. CHECK OUTBOUND VALIDATION/PRICING (OBVP)           │
   │     - If database count > limit → ALERT                │
   │                                                        │
   │  8. CHECK OUTBOUND SPLITTING (OBSP)                    │
   │     - If database count > limit → ALERT                │
   │                                                        │
   │  9. CHECK GAPS JOB                                     │
   │     - Is TAP_GAPS_01 process running?                  │
   │     - NO → Submit/restart it                           │
   │                                                        │
   │ 10. CHECK GSDM JOB                                     │
   │     - Is TAP_GSDM_01 process running?                  │
   │     - NO → Submit/restart it                           │
   │                                                        │
   │ 11. SLEEP for TAP_FILE_CHECK_PERIOD seconds            │
   │                                                        │
   │ 12. → GO TO STEP 1                                     │
   │                                                        │
   └────────────────────────────────────────────────────────┘
                   │
                   ▼ (on exit)
   ┌───────────────────────────────────────────┐
   │  CLEANUP                                  │
   │  Remove PID file                          │
   │  Log "exiting" message                    │
   └───────────────────────────────────────────┘
```

### Startup Behavior

1. The script performs a **singleton check** to prevent duplicate instances.
2. Variables for Oracle row counts and job queue names are initialized.
3. A log message is written: `"TAP_MONITOR started"`.

### Loop Behavior

The script runs in an infinite `while true` loop. Each iteration performs all checks in sequence, then sleeps for the configured interval (default: 15 minutes). Every check returns a numeric status code that determines whether an alert is sent.

### Exit Conditions

The loop exits when any of these conditions is true:
- `TAP_CLOSEDOWN_MONITOR` environment variable is set (to any non-empty value)
- Current timestamp exceeds the `TAP_CLOSEDOWN_ALL` datetime string

On exit, the `cleanup` trap removes the PID file and logs a final message.

---

## 3. Core Functional Areas

### 3.1 Configuration Handling

The script relies on **environment variables** to define:
- Directory paths (where to look for files)
- Warning thresholds (how many files are "too many")
- Check intervals (how often to run the loop)
- Shutdown controls (when to stop)

If a required variable is missing or invalid, the script sends an alert and falls back to a safe default.

### 3.2 File Monitoring

Two types of file backlogs are monitored by counting files in specific directories:
- **Inbound (IBCC):** `ibr*.dat` files in the SDM receive directory — records arriving from partner networks
- **Outbound (OBCC):** `cd*.dat` and `td*.dat` files in the DCH receive directory — records being prepared for dispatch

If the count exceeds a configured threshold, an operator alert is sent.

### 3.3 Database Monitoring

Oracle is checked in two ways:
- **Connectivity test:** A trivial `sqlplus / EXIT 77` is run. If the exit code is not 77, Oracle is down.
- **Row count queries:** SQL queries count records in the `incoming_outbound_call_files` table that are in "Awaiting Processing" (`AP`) or "Awaiting Splitting" (`AS`) status. High counts indicate pipeline congestion.

### 3.4 Batch Job Control

Two critical background jobs are monitored:
- **GAPS** (Gap Analysis Processing System) — processes gaps in call data
- **GSDM** (Generic SDM) — handles SDM data distribution

For each, the script:
1. Queries Oracle for the job's queue name and process name
2. Checks whether the process is currently running
3. If not running, submits/starts it automatically

### 3.5 Alerting System

When any check fails or exceeds a threshold, the script sends an alert through two channels:
- **Syslog** (`logger`) — for centralized logging and monitoring tools
- **Email** (`mailx`) — direct notification to the operator

In the original VMS system, alerts were sent via `REQUEST/REPLY/TO=operator`, which displayed messages on the operator's terminal.

---

## 4. Function-by-Function Explanation

---

### 4.1 `log_msg()`

**Purpose:** Writes a timestamped message to both the terminal (stdout) and the log file.

**Input:**
- `$1` — The message text to log

**Internal Logic:**
1. Generate a timestamp in `DD-Mon-YYYY HH:MM:SS` format using `date`
2. Construct the log line: `<timestamp> - <message>`
3. Write to stdout and append to `LOG_FILE` via `tee -a`

**Output:** The formatted log line on stdout; appended to the log file.

**Return Values:** Always returns 0 (success).

**Failure Scenarios:**
- If the log directory does not exist, `tee -a` will fail silently (stderr suppressed by `2>/dev/null`)

**VMS Equivalent:** `WRITE SYS$OUTPUT` + `@TAP_COM_DIR:TAPLOG_MESS`

---

### 4.2 `send_request()`

**Purpose:** Sends an operator alert via syslog and email when a problem is detected.

**Input:**
- `$1` — The alert message text

**Internal Logic:**
1. Call `log_msg` to write the alert to the log file with an `ALERT:` prefix
2. Send to syslog via `logger -t TAP_MONITOR`
3. Send an email via `mailx` to the configured `OPERATOR_EMAIL`

**Output:** Log entry, syslog entry, and email notification.

**Return Values:** Always returns 0 (success). Mail/logger failures are silently ignored.

**Failure Scenarios:**
- If `mailx` is not installed or the mail system is down, the email will not be sent (but syslog still works)
- If `logger` fails, the syslog entry is lost (but the log file still has the message)

**VMS Equivalent:** `REQUEST/REPLY/TO=OPER8` (VMS OPCOM operator message system)

**VMS Behavioral Note:** The VMS version used subprocesses (`PIPE/TRUST ... &`) to send operator requests asynchronously. If the subprocess limit was reached, it would wait 30 seconds and retry. The Linux version does not have this retry-on-subprocess-limit behavior, as Linux does not impose the same subprocess limits.

---

### 4.3 `check_singleton()`

**Purpose:** Ensures only one instance of TAP Monitor runs at a time.

**Input:**
- Uses global `PID_FILE` path

**Internal Logic:**
1. Check if the PID file exists
2. If it exists, read the PID from it
3. Try to send signal 0 to that PID (`kill -0`) — this succeeds if the process is alive
4. If the process is running → print a message and `exit 1`
5. If not running (stale PID file) → overwrite with current PID
6. Write current PID (`$$`) to the PID file

**Output:** PID file created/updated if no other instance is running.

**Return Values:** Returns normally on success; calls `exit 1` if another instance is running.

**Failure Scenarios:**
- A race condition exists if two instances start at the exact same millisecond (unlikely in practice)
- If the PID file is on a shared filesystem, there is a small risk of two nodes both writing

**VMS Equivalent:** `SET PROCESS/NAME="TAP$MONITOR"` — VMS process naming is system-enforced and atomic (no two processes can have the same name). The Linux PID-file approach is a conventional approximation.

---

### 4.4 `cleanup()`

**Purpose:** Runs on script exit to clean up resources.

**Input:** None (triggered by `trap` on EXIT, SIGTERM, SIGINT).

**Internal Logic:**
1. Remove the PID file
2. Log an "exiting" message

**Output:** PID file deleted; log message written.

**Return Values:** N/A (runs as a signal handler).

**Failure Scenarios:**
- If the PID file was already deleted, `rm -f` silently succeeds

**VMS Equivalent:** The `EXIT:` label section that restores DCL environment, terminal settings, and default directory.

---

### 4.5 `check_file_check_period()`

**Purpose:** Validates that the check interval (`TAP_FILE_CHECK_PERIOD`) is defined and is a valid number.

**Input:**
- Environment variable `TAP_FILE_CHECK_PERIOD`

**Internal Logic:**
1. Read `TAP_FILE_CHECK_PERIOD` from the environment
2. If empty → set to default (900 seconds), return status 3
3. If not a valid integer → set to default, return status 5
4. If valid → return status 1

**Output:** `TAP_FILE_CHECK_PERIOD` is exported (possibly set to the default).

**Return Values / Status Codes:**

| Code | Meaning |
|------|---------|
| 1 | Success — period is defined and valid |
| 3 | Not defined — was empty, default applied |
| 5 | Defined incorrectly — not a valid number, default applied |

**Failure Scenarios:**
- The function itself never fails fatally; it always falls back to the default

**VMS Equivalent:** `FILE_CHECK_LOGICAL` subroutine — reads the VMS logical name `TAP_FILE_CHECK_PERIOD`, validates it using `F$CVTIME()`, and falls back to `"00:15:00"`. Note: VMS uses a time string format (`"00:15:00"` = 15 minutes), while Linux uses an integer number of seconds (`900`).

---

### 4.6 `check_oracle()`

**Purpose:** Tests whether the Oracle database is reachable.

**Input:** None (uses OS-authenticated Oracle connection `sqlplus /`).

**Internal Logic:**
1. Run `sqlplus -s /` with a single command: `EXIT 77`
2. Capture the exit code
3. If exit code = 77 → Oracle is up (sqlplus successfully connected and exited with our code)
4. If exit code ≠ 77 → Oracle is down or unreachable

**Output:** None (status only).

**Return Values / Status Codes:**

| Code | Meaning |
|------|---------|
| 1 | Oracle is reachable |
| 3 | Oracle is NOT reachable |

**Failure Scenarios:**
- `sqlplus` binary not found → exit code will not be 77 → status 3
- Oracle listener down → same result
- Network issues to Oracle → same result

**VMS Equivalent:** `ORACLE` subroutine — identical logic using `sqlplus / EXIT 77` and checking `$STATUS`.

---

### 4.7 `check_ibcc()`

**Purpose:** Counts inbound call collection files and checks against the warning limit.

**Input:**
- Environment variable `TAP_IBCC_FILE_WARNING_LIMIT`
- Files matching `ibr*.dat` in `TAP_IB_RECEIVE_FROM_SDM` directory

**Internal Logic:**
1. Read the warning limit from the environment
2. If empty → return 3 (not defined)
3. If zero or non-numeric → return 5 (defined incorrectly)
4. Use `find` to count files matching `ibr*.dat` (case-insensitive) in the receive directory
5. If count > limit → return 7
6. Otherwise → return 1

**Output:** None (status only).

**Return Values / Status Codes:**

| Code | Meaning |
|------|---------|
| 1 | File count is within limits |
| 3 | Warning limit is not defined |
| 5 | Warning limit is not defined correctly (zero or non-numeric) |
| 7 | Warning limit has been **exceeded** — backlog detected |

**Failure Scenarios:**
- Directory does not exist → `find` returns 0 files (count = 0, within limits)

**VMS Equivalent:** `IBCC` subroutine — uses `F$SEARCH("tap_ib_receive_from_sdm:ibr*.dat;*")` in a loop to count files one by one. The Linux version counts all matching files at once with `find | wc -l`, which is more efficient.

---

### 4.8 `check_obcc()`

**Purpose:** Counts outbound call collection files (`cd*.dat` + `td*.dat`) and checks against the warning limit.

**Input:**
- Environment variable `TAP_OBCC_FILE_WARNING_LIMIT`
- Files matching `cd*.dat` and `td*.dat` in `TAP_OB_RECEIVE_FROM_DCH`

**Internal Logic:**
1. Validate the limit (same pattern as IBCC)
2. Count `cd*.dat` files
3. Count `td*.dat` files
4. Sum both counts
5. If total > limit → return 7

**Output:** None (status only).

**Return Values / Status Codes:** Same as `check_ibcc()` (1, 3, 5, 7).

**Failure Scenarios:** Same as IBCC.

**VMS Equivalent:** `OBCC` subroutine — two separate `F$SEARCH` loops (one for `cd*.dat`, one for `td*.dat`).

---

### 4.9 `check_rowcounts()`

**Purpose:** Queries the Oracle database for outbound pipeline counts and background job configuration.

**Input:**
- Oracle database connection (OS-authenticated)
- Work directory `TAP_WRK_DIR` for the spool file

**Internal Logic:**
1. Run a multi-query SQL block via `sqlplus -s /`
2. SQL queries:
   - Count rows in `incoming_outbound_call_files` with status `AP` → prefixed `OBVP-`
   - Count rows with status `AS` → prefixed `OBSP-`
   - Get GAPS batch queue name → prefixed `GAPQ-`
   - Get GAPS process name → prefixed `GAPN-`
   - Get GSDM batch queue name → prefixed `GSDQ-`
   - Get GSDM process name → prefixed `GSDN-`
3. Spool output to a temporary file (`tap_monitor.lis`)
4. Exit with code 77 to verify success
5. Parse the spool file line by line:
   - Strip whitespace
   - Split on `-` delimiter
   - Assign to variables: `OBVP`, `OBSP`, `GAPQ`, `GAPN`, `GSDQ`, `GSDN`
6. Delete the spool file
7. Export all variables for use by subsequent checks

**Output:** Sets global variables: `OBVP`, `OBSP`, `GAPQ`, `GAPN`, `GSDQ`, `GSDN`.

**Return Values / Status Codes:**

| Code | Meaning |
|------|---------|
| 1 | Success — all values extracted |
| 3 | Oracle query failed (exit code ≠ 77) |
| 5 | Spool file could not be read |

**Failure Scenarios:**
- Oracle is down → exit code ≠ 77 → status 3
- Spool file missing (disk full, permissions) → status 5
- Table does not exist → `WHENEVER SQLERROR EXIT` triggers non-77 exit

**VMS Equivalent:** `ROWCOUNTS` subroutine — identical SQL queries. VMS uses `DEFINE/NOLOG/JOB TAPTEMP` to create a logical name pointing to the spool file, then `OPEN/READ` and `READ` in a loop with `F$ELEMENT` to parse the `key-value` format. The Linux version uses `read` in a `while` loop with shell parameter expansion.

---

### 4.10 `check_obvp()`

**Purpose:** Checks if the outbound validation/pricing queue depth exceeds the warning limit.

**Input:**
- Environment variable `TAP_OBVP_FILE_WARNING_LIMIT`
- Global variable `OBVP` (set by `check_rowcounts`)

**Internal Logic:**
1. Validate the limit (empty → 3, zero/non-numeric → 5)
2. Compare `OBVP` (from database) against the limit
3. If exceeded → return 7

**Output:** None (status only).

**Return Values / Status Codes:** Same pattern (1, 3, 5, 7).

**VMS Equivalent:** `OBVP` subroutine — same logic using VMS global symbol `obvp`.

---

### 4.11 `check_obsp()`

**Purpose:** Checks if the outbound splitting queue depth exceeds the warning limit.

**Input:**
- Environment variable `TAP_OBSP_FILE_WARNING_LIMIT`
- Global variable `OBSP` (set by `check_rowcounts`)

**Internal Logic:** Identical to `check_obvp()` but uses `OBSP` and `TAP_OBSP_FILE_WARNING_LIMIT`.

**Return Values / Status Codes:** Same pattern (1, 3, 5, 7).

**VMS Equivalent:** `OBSP` subroutine.

---

### 4.12 `check_gaps()`

**Purpose:** Ensures the GAPS (Gap Analysis Processing System) background job is running. If not, submits it.

**Input:**
- Global variables `GAPQ` (queue name) and `GAPN` (process name) from `check_rowcounts`
- `TAP_COM_DIR` (path to the job startup script)

**Internal Logic:**
1. If `GAPQ` is empty → return 3 (queue name not found in database)
2. If `GAPN` is empty → return 5 (process name not found)
3. Use `pgrep -f "TAP_GAPS_01"` to check if the process is running
4. If running → return 1 (all good)
5. If not running → submit the job:
   - Check that `tap_job_startup.sh` exists and is executable
   - Run it via `nohup ... &` (background, survives terminal close)
   - Log the submission
6. If submission fails → return 7

**Output:** Possibly starts a background process; logs the action.

**Return Values / Status Codes:**

| Code | Meaning |
|------|---------|
| 1 | GAPS job is running (or was successfully submitted) |
| 3 | Queue name not found in Oracle configuration |
| 5 | Process name not found in Oracle configuration |
| 7 | Error submitting the job |

**Failure Scenarios:**
- `tap_job_startup.sh` does not exist → return 7
- The started job crashes immediately → will be detected on the next loop iteration

**VMS Equivalent:** `GAPS` subroutine — uses `F$CONTEXT`/`F$PID` to search for a running process named `TAP_GAPS_01`, then `SUBMIT` to a VMS batch queue. The Linux version uses `pgrep` and `nohup` as the equivalent mechanisms.

---

### 4.13 `check_gsdm()`

**Purpose:** Ensures the GSDM (Generic SDM) background job is running. If not, submits it.

**Input:** Same pattern as `check_gaps()` but uses `GSDQ`, `GSDN`, and process name `TAP_GSDM_01`.

**Internal Logic:** Identical structure to `check_gaps()`.

**Return Values / Status Codes:** Same pattern (1, 3, 5, 7).

**VMS Equivalent:** `GSDM` subroutine.

---

### 4.14 `main()`

**Purpose:** Orchestrates the entire monitoring process.

**Input:** Command-line arguments (not currently used).

**Internal Logic:**
1. Call `check_singleton()` to enforce single-instance
2. Log startup message
3. Initialize row-count variables (`OBVP`, `OBSP`, etc.) to safe defaults
4. Enter the main `while true` loop:
   - a. Check shutdown signals (`TAP_CLOSEDOWN_MONITOR`, `TAP_CLOSEDOWN_ALL`)
   - b. Run each check function in sequence
   - c. Evaluate return codes and send alerts where needed
   - d. Sleep for `TAP_FILE_CHECK_PERIOD` seconds
5. On loop exit → log completion message

**Output:** Log entries, alerts, possibly started background jobs.

**Return Values:** Implicit 0 on normal exit.

**VMS Equivalent:** The `LOOP:` label and the main command flow in the VMS script body.

---

## 5. Status Code Design

All check functions use a consistent set of numeric return codes:

| Status Code | Meaning | Action Taken |
|:-----------:|---------|--------------|
| **1** | **Success** — check passed, no issues | No alert; continue |
| **3** | **Not defined** — a required environment variable or configuration is missing | Alert sent; default may be applied |
| **5** | **Defined incorrectly** — value is present but invalid (e.g., non-numeric, zero) | Alert sent; default may be applied |
| **7** | **Threshold exceeded** — a monitored value is above the warning limit | Alert sent |

### How Status Codes Influence Control Flow

```
  check_xxx()  ──returns status──►  main loop evaluates status
                                         │
             ┌───────────────────────────┼──────────────────────────┐
             │                           │                          │
        status = 3                  status = 5                status = 7
    "not defined" alert         "defined incorrectly"     "exceeded" alert
                                      alert
```

The main loop calls each check function, captures the return code, and uses `[ ${status} -eq N ] && send_request "..."` to conditionally send alerts. The loop always continues regardless of the status — no check failure causes the script to exit.

---

## 6. External Dependencies

### 6.1 Oracle Database (`sqlplus`)

| Usage | Purpose |
|-------|---------|
| `sqlplus -s / EXIT 77` | Connectivity test — checks if Oracle is reachable |
| `sqlplus -s /` with SQL block | Query `incoming_outbound_call_files` for pipeline counts; query `tap_system_configuration` for GAPS/GSDM job info |

- Requires **OS-authenticated** Oracle access (no username/password — uses the OS user's Oracle credentials)
- Requires `ORACLE_HOME` and `ORACLE_SID` (or `TWO_TASK`) environment variables to be set
- Requires the `sqlplus` binary on `PATH`

### 6.2 File System Directories

| Directory Variable | Purpose |
|--------------------|---------|
| `TAP_IB_RECEIVE_FROM_SDM` | Inbound files from SDM (partner network records arriving) |
| `TAP_OB_RECEIVE_FROM_DCH` | Outbound files from DCH (records being dispatched) |
| `TAP_WRK_DIR` | Work directory for temporary spool files |
| `TAP_LOG_DIR` | Log directory for the monitor's log file |
| `TAP_COM_DIR` | Command/script directory containing `tap_job_startup.sh` |

### 6.3 OS Utilities

| Utility | Purpose |
|---------|---------|
| `find` | Counts files matching patterns in monitored directories |
| `pgrep` | Checks if GAPS/GSDM background processes are running |
| `nohup` | Launches background jobs that survive terminal close |
| `logger` | Sends alerts to the system syslog |
| `mailx` | Sends email alerts to operators |
| `date` | Generates timestamps for logging and shutdown time comparison |
| `kill -0` | Tests if a PID is alive (singleton check) |

---

## 7. Configuration (Environment Variables / Logical Names)

| Variable | Description | Required | Default | Example |
|----------|-------------|:--------:|---------|---------|
| `TAP_FILE_CHECK_PERIOD` | How often the monitor checks (in seconds) | No | `900` (15 min) | `600` |
| `TAP_IBCC_FILE_WARNING_LIMIT` | Max inbound collection files before alert | No | *(none — check skipped)* | `100` |
| `TAP_OBCC_FILE_WARNING_LIMIT` | Max outbound collection files before alert | No | *(none — check skipped)* | `200` |
| `TAP_OBVP_FILE_WARNING_LIMIT` | Max outbound validation/pricing rows before alert | No | *(none — check skipped)* | `500` |
| `TAP_OBSP_FILE_WARNING_LIMIT` | Max outbound splitting rows before alert | No | *(none — check skipped)* | `300` |
| `TAP_CLOSEDOWN_MONITOR` | Set to any value to trigger shutdown | No | *(unset)* | `Y` |
| `TAP_CLOSEDOWN_ALL` | Datetime string; shutdown if current time exceeds this | No | *(unset)* | `2026-03-25 23:00:00` |
| `OPERATOR_EMAIL` | Email address for operator alerts | Yes | `operator@localhost` | `tapops@company.com` |
| `TAP_IB_RECEIVE_FROM_SDM` | Inbound receive directory path | Yes (hardcoded) | `/data/call_data/tap/ib/receive_from_sdm` | *(same)* |
| `TAP_OB_RECEIVE_FROM_DCH` | Outbound receive directory path | Yes (hardcoded) | `/data/call_data/tap/ob/receive_from_dch` | *(same)* |
| `TAP_WRK_DIR` | Working directory for temp files | Yes (hardcoded) | `/data/call_data/tap/wrk` | *(same)* |
| `TAP_LOG_DIR` | Log output directory | Yes (hardcoded) | `/data/call_data/tap/log` | *(same)* |
| `TAP_COM_DIR` | Command/scripts directory | Yes (hardcoded) | `/data/call_data/tap/com` | *(same)* |
| `ORACLE_HOME` | Oracle installation directory | Yes (external) | *(system-dependent)* | `/opt/oracle/product/19c` |
| `ORACLE_SID` | Oracle System Identifier | Yes (external) | *(system-dependent)* | `TAPDB` |

**Note on VMS logical names:** In VMS, these were defined as "logical names" (similar to environment variables but persistent, system-wide, and hierarchically scoped). They were set at system startup or by operator procedures. On Linux, they must be set as environment variables before running the script (e.g., in a systemd unit file, `.bashrc`, or wrapper script).

---

## 8. Error Handling and Alerting

### How Errors Are Detected

Each check function returns a status code. The main loop evaluates these codes and determines whether an alert is needed. The system does **not** attempt to fix problems — it only **detects and reports** them (with the exception of restarting stopped GAPS/GSDM jobs).

### How Alerts Are Triggered

```
  Problem detected
       │
       ▼
  send_request("alert message")
       │
       ├──► log_msg() → writes to log file
       ├──► logger  → writes to syslog (/var/log/messages or journald)
       └──► mailx   → sends email to OPERATOR_EMAIL
```

### What Happens When Failures Occur Repeatedly

The script does **not** suppress repeated alerts. If Oracle stays down for 5 cycles, the operator will receive 5 separate alerts (one per cycle, every 15 minutes by default). This is intentional — persistent alerts indicate a persistent problem.

Similarly, if a file count exceeds the threshold and stays high, the alert is sent on every iteration.

### Error in the VMS Version

The VMS version has a dedicated `ERROR:` label that:
1. Captures the error text (from `$STATUS` or a manual string)
2. Displays it on screen (interactive mode) or logs it
3. Sends it to the operator via `REQUEST/TO=OPER8`
4. Exits the script

The Linux version does not have a centralized error handler — each function handles its own errors via return codes. Fatal errors (like the singleton check) cause an immediate `exit 1`.

---

## 9. Differences Between VMS Script and Bash Script

| Aspect | VMS (`TAP_MONITOR.COM`) | Linux (`tap_monitor.sh`) |
|--------|------------------------|--------------------------|
| **Singleton mechanism** | `SET PROCESS/NAME="TAP$MONITOR"` — OS-enforced unique process name | PID file in `/tmp` — convention-based |
| **Operator alerts** | `REQUEST/REPLY/TO=OPER8` — VMS OPCOM terminal message system | `logger` (syslog) + `mailx` (email) |
| **Alert retrying** | Spawns a subprocess for each alert; waits 30 sec and retries if subprocess limit reached | No retry mechanism — fire-and-forget |
| **Check interval format** | VMS delta time string `"00:15:00"` (hours:minutes:seconds) | Integer seconds `900` |
| **Shutdown time comparison** | `F$CVTIME()` returns VMS-format datetime; compared with `.GTS.` | `date '+%Y-%m-%d %H:%M:%S'` compared with string comparison `>` |
| **File counting** | `F$SEARCH()` in a loop — one file per iteration | `find ... | wc -l` — counts all at once (more efficient) |
| **Process detection** | `F$CONTEXT`/`F$PID` — VMS process context search | `pgrep -f` — searches process command line |
| **Job submission** | `SUBMIT /QUEUE=...` — VMS batch queue system | `nohup ... &` — background execution |
| **Interactive mode** | Detects `F$MODE()` interactive vs. batch; suppresses output, adjusts terminal settings | No interactive mode distinction — always runs the same way |
| **VT terminal codes** | Extensive VT100/VT200 escape codes for screen formatting | None — output is plain text |
| **Global symbols** | VMS uses `==` (global symbols) to share state between subroutines | Bash uses global variables and `export` |
| **Inbound checks (IBVP, IBSP)** | Originally included, later commented out ("Sahara" project) | Not included (conversion reflects the commented-out state) |
| **Error handler** | Centralized `ERROR:` label with operator notification and exit | Per-function return codes; no centralized handler |

### Risks and Behavioral Changes

1. **Singleton reliability:** The PID file approach is less robust than VMS process naming. If the script is killed with `kill -9`, the PID file may not be cleaned up, requiring manual removal.

2. **Alert delivery:** VMS `REQUEST/REPLY` blocks until the operator acknowledges. The Linux `mailx` approach is non-blocking — alerts may be missed if email is not monitored.

3. **File counting efficiency:** The VMS version counts files one at a time in a loop and stops as soon as the limit is exceeded (short-circuit). The Linux version counts all files at once. For very large directories (millions of files), the Linux approach may be slightly slower but is generally more efficient for typical counts.

4. **Shutdown time format:** VMS uses its native datetime format. The Linux version uses `YYYY-MM-DD HH:MM:SS`. Operators must use the correct format when setting `TAP_CLOSEDOWN_ALL`.

5. **No `set -o nounset` protection in VMS:** VMS DCL does not fail on undefined variables — it treats them as empty strings. The Linux version uses `set -o nounset`, which causes the script to exit if an unset variable is referenced without a default (`${VAR:-}`). This is a safety improvement but could cause unexpected exits if variables are not properly initialized.

---

## 10. Real-World Example Scenarios

### Scenario 1: File Count Exceeds Threshold

**Setup:**
- `TAP_IBCC_FILE_WARNING_LIMIT=50`
- 75 `ibr*.dat` files are in `TAP_IB_RECEIVE_FROM_SDM`

**What happens:**
1. The monitor wakes up from its 15-minute sleep
2. `check_ibcc()` runs and counts 75 files
3. 75 > 50 → function returns status 7
4. Main loop sees status 7 → calls `send_request "TAP_IBCC_FILE_WARNING_LIMIT has been exceeded"`
5. Alert is logged, sent to syslog, and emailed to the operator
6. The operator investigates why inbound files are piling up (perhaps the collection process is stalled)
7. On the next cycle (15 minutes later), if 80 files are still there, another alert is sent

### Scenario 2: Oracle Is Down

**Setup:**
- Oracle database is stopped for maintenance

**What happens:**
1. `check_oracle()` runs `sqlplus -s / EXIT 77`
2. sqlplus cannot connect → exits with a non-77 code
3. Function returns status 3
4. Main loop calls `send_request "ORACLE is not running"`
5. `check_rowcounts()` also fails (returns 3) → `send_request "Cannot extract rowcounts from ORACLE"`
6. `OBVP`, `OBSP`, `GAPQ`, `GAPN`, `GSDQ`, `GSDN` remain at their default values (0 or "")
7. `check_gaps()` and `check_gsdm()` see empty queue names → return 3 → additional alerts
8. **Net result:** The operator receives multiple alerts indicating Oracle is down and dependent checks cannot run

### Scenario 3: GAPS Job Has Crashed

**Setup:**
- Oracle is up and returns `GAPQ=TAP_BATCH_Q` and `GAPN=GAPS_PROC`
- But the `TAP_GAPS_01` process is not running

**What happens:**
1. `check_rowcounts()` succeeds and sets `GAPQ` and `GAPN`
2. `check_gaps()` runs `pgrep -f "TAP_GAPS_01"` → no match found
3. The function launches `tap_job_startup.sh "GAPS" "01" "GAPS_PROC"` via `nohup`
4. Logs: `"TAP_MONITOR - GAPS, TAP_GAPS_01 has been submitted to queue TAP_BATCH_Q"`
5. On the next cycle, `pgrep` finds the process → no action needed

### Scenario 4: Environment Variable Not Set

**Setup:**
- `TAP_OBSP_FILE_WARNING_LIMIT` is not set in the environment

**What happens:**
1. `check_obsp()` checks the variable → it is empty
2. Returns status 3
3. Main loop calls `send_request "TAP_OBSP_FILE_WARNING_LIMIT not defined"`
4. The OBSP check is effectively skipped (no comparison can be made without a limit)
5. This alert repeats every cycle until the variable is defined

---

## 11. Summary

The **TAP Monitor** is a long-running watchdog process for a telecom roaming billing system. It runs in a continuous loop (default: every 15 minutes) and performs the following checks:

- **Oracle database availability** — Is the database reachable?
- **File backlog detection** — Are inbound and outbound directories accumulating too many unprocessed files?
- **Database queue depth** — Are Oracle pipeline tables filling up with records awaiting validation or splitting?
- **Background job health** — Are the GAPS and GSDM processing jobs running? If not, restart them.

When any check fails or a threshold is exceeded, the system sends alerts via syslog and email. The script was originally written for VMS in 1998 and has been converted to Linux Bash, preserving the same monitoring logic, alert messages, and check sequence. The primary differences are in the mechanisms used for process management (PID files vs. VMS process names), alerting (email vs. operator terminal messages), and job submission (`nohup` vs. VMS batch queues).
