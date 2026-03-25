# TAP RSERC Files Transfer — Comprehensive Technical Document

**Script Name:** `tap_rsercfiles_transfer.sh` (Linux Bash)
**Converted From:** `TAP_RSERCFILES_TRANSFER.COM` (VMS DCL)
**Description:** RSERC and MRLOG file transfer from TAP to ABS via SFTP

---

## 1. Overview

### What is this system?

The TAP RSERC Files Transfer script is an **automated file transfer daemon** that runs continuously within a telecom billing environment. It moves two types of generated billing data files — **RSERC** (Roaming Settlement and Error Correction) files and **MRLOG** (Metering Record Log) files — from the TAP system to the ABS (Accounting & Billing System) server using SFTP.

### What problem does it solve?

In a mobile network, when roaming calls are processed by the TAP system, two categories of output are generated:

- **RSERC files** — Contain settlement records and error corrections for inter-operator billing. These are generated in the `FCS_RSERC` directory.
- **MRLOG files** — Contain metering/usage logs for audit and reconciliation. These are generated in the `XI_DAT` directory.

These files must be reliably transferred to the ABS server for downstream billing and financial processing. The transfer must be:

1. **Atomic** — The ABS system must never pick up a partially uploaded file
2. **Recoverable** — If the script crashes mid-transfer, the next run must clean up and resume
3. **Continuous** — The script runs in a loop, checking for new files every cycle
4. **Throttled** — No more than 50 files of each type are sent per batch to avoid overloading the connection

### Where is it used?

This script runs on a **Linux/RHEL 9 production server** (migrated from OpenVMS) as part of the TAP billing pipeline. It operates as a long-running background process, typically started at system boot and running until a configured shutdown time or explicit shutdown signal.

---

## 2. High-Level Workflow

### End-to-End Flow (Step by Step)

```
   ┌───────────────────────────────────────────────────┐
   │                 SCRIPT STARTS                      │
   └───────────────────┬───────────────────────────────┘
                       │
                       ▼
   ┌───────────────────────────────────────────────────┐
   │  SIGNAL HANDLERS                                  │
   │  Set up traps for SIGTERM, SIGINT, EXIT           │
   └───────────────────┬───────────────────────────────┘
                       │
                       ▼
   ┌───────────────────────────────────────────────────┐
   │  ACQUIRE LOCK (Singleton Check)                   │
   │  Another instance running? → Exit immediately     │
   │  No → Lock acquired, continue                    │
   └───────────────────┬───────────────────────────────┘
                       │
                       ▼
   ┌───────────────────────────────────────────────────┐
   │  VALIDATE ENVIRONMENT                             │
   │  Check all directories exist                      │
   │  Check SFTP config file exists                    │
   │  Any missing → Fatal error, exit code 4          │
   └───────────────────┬───────────────────────────────┘
                       │
                       ▼
   ┌───────────────────────────────────────────────────┐
   │  HOUSEKEEPING                                     │
   │  Delete log files older than 7 days               │
   └───────────────────┬───────────────────────────────┘
                       │
                       ▼
   ┌───────────────────────────────────────────────────┐
   │  READ SFTP CONFIG                                 │
   │  Parse RSERC_SFTP.CFG → username + hostname      │
   └───────────────────┬───────────────────────────────┘
                       │
                       ▼
   ┌───────────────────────────────────────────────────┐
   │  SELF-RECOVERY                                    │
   │  Clean temp directory                             │
   │  Check for SFTP_ABS_IN_PROGRESS.FLAG              │
   │    Flag missing → No recovery needed             │
   │    Flag exists → Determine failure stage:        │
   │      Stage 1: SFTP ctrl file → clean remote     │
   │      Stage 2: Rename script → error (disabled)  │
   │      Stage 3: Delete script → run local cleanup │
   └───────────────────┬───────────────────────────────┘
                       │
                       ▼
  ┌──────────────────── MAIN LOOP ──────────────────────┐
  │                                                      │
  │  1. PREPARE BATCH FILES                              │
  │     Create: sftp_ctrl_file.dat (upload commands)     │
  │     Create: rename_sftpd_files_tmp.sh (rename cmds)  │
  │     Create: delete_sftpd_files_tmp.sh (delete cmds)  │
  │                                                      │
  │  2. COLLECT RSERC FILES (up to 50)                   │
  │     Find RSERC??????.DAT in FCS_RSERC_DIR            │
  │     Copy to SFTP_TMP_DIR with .sftp_tmp_rs extension │
  │     Add put/rename/delete commands to batch files    │
  │                                                      │
  │  3. COLLECT MRLOG FILES (up to 50)                   │
  │     Find MRLOG??????.DAT in XI_DAT                   │
  │     Same staging and batch file approach             │
  │                                                      │
  │  4. TRANSFER DECISION                                │
  │     ┌───────────────────────────────────┐            │
  │     │ Files found?                      │            │
  │     │ YES → Execute SFTP Transfer      │            │
  │     │ NO  → Sleep 10 minutes           │            │
  │     └───────────────────────────────────┘            │
  │                                                      │
  │  5. SFTP TRANSFER (3-phase)                          │
  │     a. Set SFTP_ABS_IN_PROGRESS.FLAG                 │
  │     b. UPLOAD: sftp -b batch → put files (.tmp_rs)  │
  │     c. RENAME: sftp -b batch → .tmp_rs → .DAT      │
  │     d. CLEANUP: Clean staging dir                    │
  │     e. DELETE: Run delete script (remove source)     │
  │     f. Remove FLAG                                   │
  │                                                      │
  │  6. CHECK SHUTDOWN                                   │
  │     - RSERC_TRANS_SHUTDOWN = "Y"? → EXIT            │
  │     - Shutdown flag file exists? → EXIT             │
  │     - TAP_CLOSEDOWN_ALL ≠ "N" AND time > it? → EXIT│
  │     - Otherwise → GO TO STEP 1                     │
  │                                                      │
  └──────────────────────────────────────────────────────┘
                       │
                       ▼ (on exit)
  ┌───────────────────────────────────────────────────┐
  │  CLEANUP AND EXIT                                  │
  │  Release flock                                     │
  │  Log exit message                                  │
  └───────────────────────────────────────────────────┘
```

### Startup Behavior

1. Signal handlers are registered (SIGTERM/SIGINT call `error_exit`; EXIT calls `cleanup_and_exit`).
2. The script acquires an exclusive file lock (`flock`) to prevent duplicate instances.
3. All required directories and the SFTP config file are validated.
4. Old log files (>7 days) are purged.
5. SFTP connection details (username and hostname) are read from the config file.
6. Any leftover artifacts from a previously crashed run are cleaned up (self-recovery).

### Loop Behavior

The script runs in an infinite `while true` loop. Each iteration:
- Scans for RSERC and MRLOG files (up to 50 each)
- If files are found, performs a 3-phase SFTP transfer (upload, rename, local delete)
- If no files are found, sleeps for 10 minutes
- Checks whether shutdown has been requested

### Exit Conditions

The loop exits when any of these is true:
- `RSERC_TRANS_SHUTDOWN` environment variable is set to `"Y"`
- A shutdown flag file (`RSERC_TRANS_SHUTDOWN.FLAG`) exists in `TAP_DAT_DIR`
- `TAP_CLOSEDOWN_ALL` is set to a time value (not `"N"`) and the current time exceeds it

---

## 3. Core Functional Areas

### 3.1 Configuration Handling

The script uses environment variables to define all directory paths, shutdown controls, and batch limits. Each variable has a default value that can be overridden for different deployments or test environments. The SFTP connection credentials (username and remote hostname) are read from a separate config file (`RSERC_SFTP.CFG`).

### 3.2 File Collection and Staging

Two file types are collected from two different source directories:
- **RSERC files** (`RSERC??????.DAT` — 6-character wildcard) from `FCS_RSERC_DIR`
- **MRLOG files** (`MRLOG??????.DAT` — 6-character wildcard) from `XI_DAT`

Files are copied to a staging directory (`SFTP_TMP_DIR`) with a temporary extension (`.sftp_tmp_rs`) rather than transferring directly from the source. This ensures:
- The source file remains intact until the transfer is confirmed
- The remote ABS system will not pick up partially uploaded files (it only looks for `.DAT` files)

### 3.3 Three-Phase SFTP Transfer

The transfer uses a deliberate three-phase approach for atomicity:

| Phase | Action | Purpose |
|-------|--------|---------|
| **1. Upload** | `sftp -b` with `put` commands | Files land on ABS with `.sftp_tmp_rs` extension (invisible to ABS processing) |
| **2. Rename** | `sftp -b` with `rename` commands | Files atomically renamed from `.sftp_tmp_rs` to `.DAT` (now visible to ABS) |
| **3. Delete** | Local bash script with `rm -f` | Source files removed from TAP after confirmed delivery |

### 3.4 Self-Recovery System

If the script crashes mid-transfer, it leaves behind artifacts that indicate how far it got. On the next startup, it inspects these artifacts and recovers:

| Artifact Found | What It Means | Recovery Action |
|----------------|---------------|-----------------|
| `SFTP_CTRL_FILE.DAT` | Upload may be incomplete | Remove `.sftp_tmp_rs` files from remote server |
| `rename_sftpd_files_tmp.sh` | Upload done, rename failed | Error (recovery disabled, matching VMS original) |
| `delete_sftpd_files_tmp.sh` | Remote transfer done, local delete didn't finish | Run the delete script to clean up source files |
| No artifacts | Previous run completed normally | Skip recovery |

### 3.5 Shutdown Control

Three mechanisms can trigger a graceful shutdown:
1. **Environment variable:** `RSERC_TRANS_SHUTDOWN=Y`
2. **Flag file:** `RSERC_TRANS_SHUTDOWN.FLAG` in `TAP_DAT_DIR`
3. **Time-based:** When `TAP_CLOSEDOWN_ALL` is set to a time (e.g., `"23:00"`) and the current time exceeds it

When `TAP_CLOSEDOWN_ALL` is set to `"N"` (the default), time-based shutdown is entirely disabled. This matches the VMS behavior where comparing a timestamp against the string `"N"` always evaluates false.

---

## 4. Function-by-Function Explanation

---

### 4.1 `log_msg()`

**Purpose:** Writes a timestamped message to both stdout and the log file.

**Input:**
- `$1` — The message text

**Internal Logic:**
1. Generate timestamp in `DD-Mon-YYYY HH:MM:SS` format
2. Construct: `<timestamp> - <message>`
3. Write to stdout and append to `LOG_FILE` via `tee -a`

**Output:** Formatted log line on stdout; appended to the log file.

**Return Values:** Always 0.

**Failure Scenarios:**
- If `TAP_LOG_DIR` does not exist, `tee -a` will fail silently

**VMS Equivalent:** `@TAP_COM_DIR:TAPLOG_MESS` + `WRITE SYS$OUTPUT` (`WSO`)

---

### 4.2 `error_exit()`

**Purpose:** Handles fatal errors — logs the error, notifies the operator via syslog, and exits with code 4.

**Input:**
- `$1` — Error text describing what went wrong
- `$2` — Phase name (which part of the script was running), defaults to `"UNKNOWN"`

**Internal Logic:**
1. Call `log_msg` with the formatted error: `ERROR: *** <script> - <phase>, <error_text>`
2. Send the error to syslog via `logger -t <script_name>`
3. Call `cleanup_and_exit 4`

**Output:** Log entry, syslog entry. Script terminates with exit code 4.

**Return Values:** Does not return (calls `exit`).

**Failure Scenarios:**
- If `logger` is not available, syslog notification is silently skipped
- The exit code is always 4 regardless of the error type

**VMS Equivalent:** The `ERROR:` label section:
```
$  WSO  "ERROR: *** ''ERROR_TEXT'"
$  @TAP_COM_DIR:TAPLOG_MESS " ***" "''PROCNAME' - ''PHASE', ''ERROR_TEXT'" " "
$  REQUEST/REPLY/TO='OPERATOR' "''PROCNAME' - ''PHASE', ''ERROR_TEXT' FAILED AT ''F$TIME()'"
$  EXIT 4
```

**Key Difference:** VMS uses `REQUEST/REPLY/TO=OPER8` which sends an interactive message to the operator console; Linux uses `logger` (syslog) as a substitute.

---

### 4.3 `cleanup_and_exit()`

**Purpose:** Performs cleanup operations and exits the script. Protected against double-invocation via a guard flag.

**Input:**
- `$1` — Exit code (defaults to 0)

**Internal Logic:**
1. Check `_CLEANUP_DONE` guard — if already 1, just `exit` immediately (prevents recursive cleanup)
2. Set `_CLEANUP_DONE=1`
3. Log the exit with code and timestamp
4. Release the file lock by closing `LOCK_FD`
5. Call `exit` with the given code

**Output:** Log entry; lock released.

**Return Values:** Does not return (calls `exit`).

**Failure Scenarios:**
- If the lock FD was already closed, the `eval` is silently ignored

**VMS Equivalent:** The `EXIT:` label section:
```
$  SET MESSAGE 'messcodes'
$  SET DEFAULT 'def_dir'
$  EXIT
```

---

### 4.4 `acquire_lock()`

**Purpose:** Acquires an exclusive file lock to enforce single-instance execution.

**Input:**
- Uses globals `LOCK_FD` (file descriptor number) and `LOCK_FILE` (path)

**Internal Logic:**
1. Open the lock file on file descriptor 9: `exec 9>/var/lock/<script>.lock`
2. Attempt a non-blocking exclusive lock: `flock -n 9`
3. If lock fails → another instance is running → log message and `exit 0`
4. If lock succeeds → continue (lock held until FD is closed or process exits)

**Output:** Lock acquired on success; process exits on failure.

**Return Values:** Returns normally if lock acquired; calls `exit 0` if another instance is running.

**Failure Scenarios:**
- `/var/lock/` directory does not exist → `exec` fails → script exits with error
- Filesystem does not support `flock` → rare, mainly on NFS

**VMS Equivalent:** `CHECK_INSTANCES` section:
```
$  SET PROCESS /NAME='current_process'
$  IF .NOT. $STATUS THEN GOTO ERROR
```
VMS uses process naming as an OS-enforced atomic singleton mechanism. The Linux `flock` approach is the standard POSIX equivalent and is more robust than PID files.

---

### 4.5 `validate_environment()`

**Purpose:** Verifies that all required directories exist and the SFTP config file is present.

**Input:**
- Environment variables: `TAP_CFG_DIR`, `TAP_DAT_DIR`, `TAP_LOG_DIR`, `FCS_RSERC_DIR`, `XI_DAT`, `SFTP_TMP_DIR`
- Config file path: `SFTP_CFG_FILE`

**Internal Logic:**
1. Loop through each required directory variable:
   - If the variable is empty → `error_exit` with "not set"
   - If the path does not exist as a directory → `error_exit` with "does not exist"
2. Check that `RSERC_SFTP.CFG` exists at the expected path
   - If missing → `error_exit`

**Output:** None if successful; fatal error if any check fails.

**Return Values:** Returns 0 on success; does not return on failure (calls `error_exit`).

**Failure Scenarios:**
- Any missing directory or config file causes immediate script termination

**VMS Equivalent:** The logical name checks:
```
$  IF F$TRNLNM("TAP_CFG_DIR") .EQS. "" THEN GOTO ERROR
$  IF F$TRNLNM("XI_DAT") .EQS. "" THEN GOTO ERROR
   ...
$  SFTP_CFG_FILE=F$SEARCH("TAP_CFG_DIR:RSERC_SFTP.CFG;*")
$  IF SFTP_CFG_FILE .EQS. "" THEN GOTO ERROR
```

**Difference:** The VMS version also checks `RSERC_TRANS_SHUTDOWN` as a required logical. The Linux version does not require it (defaults to `"N"`).

---

### 4.6 `housekeeping()`

**Purpose:** Deletes old log files to prevent disk space from filling up.

**Input:**
- `TAP_LOG_DIR` — directory to clean
- `SCRIPT_NAME` — used to match log files

**Internal Logic:**
1. Log the housekeeping action
2. Use `find` to locate files matching `<script_name>.log.*` older than 7 days
3. Delete them with `-delete`

**Output:** Log message; old files removed.

**Return Values:** Always 0 (errors suppressed by `|| true`).

**Failure Scenarios:**
- If no old files exist, nothing happens
- If deletion fails (permissions), the error is silently ignored

**VMS Equivalent:**
```
$  DELETE/BEFORE="TODAY-7-00" TAP_LOG_DIR:TAP_RSERCFILES_TRANSFER.LOG;*
```

---

### 4.7 `read_sftp_config()`

**Purpose:** Reads the SFTP connection details (username and hostname) from the config file.

**Input:**
- `SFTP_CFG_FILE` — path to `RSERC_SFTP.CFG`

**Internal Logic:**
1. Verify the config file exists (fatal error if not)
2. Read line 1 → `DEST_USERNAME`
3. Read line 2 → `DEST_HOSTNAME`
4. Validate both are non-empty (fatal error if either is empty)
5. Log the SFTP target: `username@hostname`

**Output:** Sets global variables `DEST_USERNAME` and `DEST_HOSTNAME`.

**Return Values:** Returns 0 on success; does not return on failure.

**Failure Scenarios:**
- File missing → fatal error
- File has only one line → `DEST_HOSTNAME` is empty → fatal error
- File is empty → both empty → fatal error

**VMS Equivalent:** `EXTRACT_SFTP` section:
```
$  OPEN/READ  SFTP_TMP_FILE  TAP_CFG_DIR:RSERC_SFTP.CFG;
$  READ       SFTP_TMP_FILE  DESTUSERNAME
$  READ       SFTP_TMP_FILE  DESTHOSTNAME
$  CLOSE      SFTP_TMP_FILE
```

---

### 4.8 `self_recovery()`

**Purpose:** Cleans up from a previously failed transfer attempt to ensure a consistent state before starting the main loop.

**Input:**
- `SFTP_TMP_DIR` — staging directory to clean
- `FLAG_FILE` — `SFTP_ABS_IN_PROGRESS.FLAG`
- `TAP_DAT_DIR` — location of control/recovery files
- `DEST_USERNAME`, `DEST_HOSTNAME` — SFTP credentials (must be read first)

**Internal Logic:**
1. **Always:** Delete all files in `SFTP_TMP_DIR` (clean staging area)
2. Check if `SFTP_ABS_IN_PROGRESS.FLAG` exists:
   - **No flag** → log "No recovery needed", return
   - **Flag exists** → delete it, proceed to recovery stages
3. **Recovery Stage 1** — Check for `SFTP_CTRL_FILE.DAT`:
   - If present → The upload was in progress or completed, but subsequent steps didn't finish
   - Action: Create an SFTP batch to remove `*.sftp_tmp_rs` files from the remote server
   - Run `sftp -b` to execute the cleanup
   - Delete all local control files
   - Return
4. **Recovery Stage 2** — Check for `rename_sftpd_files_tmp.sh`:
   - If present → Uploads completed but rename on remote didn't execute
   - Action: Call `error_exit` (this recovery path is disabled, matching the VMS original where it was commented out)
5. **Recovery Stage 3** — Check for `delete_sftpd_files_tmp.sh`:
   - If present → Remote transfer and rename completed, but local source files were not deleted
   - Action: Run the delete script to clean up local source files
   - Delete the script file

**Output:** Staging directory cleaned; remote partial uploads removed; local cleanup completed.

**Return Values:** Returns 0 on successful recovery; does not return if recovery SFTP fails.

**Failure Scenarios:**
- Remote SFTP cleanup fails (network issue) → fatal error
- Delete script fails → fatal error
- Recovery Stage 2 always fails by design (disabled in VMS original)

**VMS Equivalent:** `SELF_RECOVERY`, `RECOVERY_1`, `RECOVERY_2`, `RECOVERY_3` sections. The VMS RECOVERY_2 code is commented out with `$!` — the Linux version preserves this by calling `error_exit` instead of attempting the rename recovery.

---

### 4.9 `collect_rserc_files()`

**Purpose:** Finds RSERC files ready for transfer, copies them to the staging directory with a temporary extension, and writes commands to the batch files.

**Input:**
- `$1` (`sftp_fd`) — Path to the SFTP upload batch file
- `$2` (`rename_fd`) — Path to the remote rename batch file
- `$3` (`delete_fd`) — Path to the local delete script
- `FCS_RSERC_DIR` — Source directory for RSERC files
- `MAX_BATCH_SIZE` — Maximum files per batch (default: 50)

**Internal Logic:**
1. Set `RSERC_COUNT=0`
2. Use `find` with `-print0` to locate files matching `RSERC??????.DAT`
3. For each file (up to `MAX_BATCH_SIZE`):
   - Extract the filename and construct the temp name (e.g., `RSERC000001.sftp_tmp_rs`)
   - Copy the source file to `SFTP_TMP_DIR/<temp_name>`
   - Append `put <temp_name>` to the SFTP batch
   - Append `rename <temp_name> <original_name>` to the rename batch
   - Append `rm -f "<source_path>"` to the delete script
   - Increment `RSERC_COUNT`
   - Log each staged file

**Output:** Sets global `RSERC_COUNT`. Files copied to staging. Batch files populated.

**Return Values:** Implicit 0. Count available in `RSERC_COUNT`.

**Failure Scenarios:**
- `cp` fails for a specific file → warning logged, file skipped, count not incremented
- No files found → `RSERC_COUNT` stays 0, no batch commands written

**VMS Equivalent:** `RSERC_FILE_COUNT` section:
```
$  RSERC_FILE = F$SEARCH("FCS_RSERC_DIR:RSERC%%%%%%.DAT;*",1)
   ...
$  COPY/LOG 'RSERC_FILE SFTP_TMP_DIR:'FILE_TMP
$  WRITE SFTP_CTRL_FILE "put ''FILE_TMP'"
$  WRITE RENAME_TMP_FILE "rename ''FILE_TMP' ''FILENAME'"
$  WRITE DELETE_TMP_FILE "$DELETE/LOG FCS_RSERC_DIR:''FILENAME'"
```

**Key Differences:**
- VMS uses `F$SEARCH` in a loop (one file per call); Linux uses `find -print0` piped to a `while` loop
- VMS pattern `%%%%%%` (6 single-char wildcards) maps to `??????` in Bash
- VMS appends the file version number (`;*`) to the temp extension; Linux does not (Linux has no file versioning)

---

### 4.10 `collect_mrlog_files()`

**Purpose:** Identical to `collect_rserc_files()` but for MRLOG files from the `XI_DAT` directory.

**Input:**
- Same parameters as `collect_rserc_files()`
- Source directory: `XI_DAT` instead of `FCS_RSERC_DIR`
- Pattern: `MRLOG??????.DAT` instead of `RSERC??????.DAT`

**Internal Logic:** Same 8-step process as `collect_rserc_files()`.

**Output:** Sets global `MRLOG_COUNT`.

**VMS Equivalent:** `MRLOG_FILE_COUNT` section — same structure as RSERC but searches `XI_DAT:MRLOG%%%%%%.DAT;*`.

---

### 4.11 `sftp_transfer()`

**Purpose:** Executes the three-phase SFTP transfer: upload, rename, delete.

**Input:**
- `$1` (`sftp_batch`) — Path to the SFTP upload batch file
- `$2` (`rename_batch`) — Path to the remote rename batch file
- `$3` (`delete_script`) — Path to the local delete script
- `DEST_USERNAME`, `DEST_HOSTNAME` — SFTP credentials
- `FLAG_FILE` — In-progress flag path
- `SFTP_TMP_DIR` — Staging directory to clean after upload

**Internal Logic:**
1. Log transfer start with timestamp
2. Create `SFTP_ABS_IN_PROGRESS.FLAG` (marks transfer as in-progress for recovery)
3. **Phase 1 — Upload:** Run `sftp -b <sftp_batch> user@host`
   - If fails → `error_exit` (flag and batch files remain for recovery)
   - If succeeds → delete the batch file
4. **Phase 2 — Rename:** Run `sftp -b <rename_batch> user@host`
   - If fails → `error_exit`
   - If succeeds → delete the rename batch; clean staging directory
5. **Phase 3 — Local Delete:** Run `bash <delete_script>`
   - If fails → `error_exit`
   - If succeeds → delete the script file
6. Remove `SFTP_ABS_IN_PROGRESS.FLAG`
7. Log transfer completion with timestamp

**Output:** Files transferred to remote; source files deleted; staging cleaned; flag removed.

**Return Values:** Returns 0 on success; does not return on failure.

**Failure Scenarios:**

| Failure Point | Artifacts Left Behind | Recovery Action (Next Run) |
|---------------|----------------------|---------------------------|
| Upload fails | FLAG + sftp_ctrl_file.dat | Recovery Stage 1: remove remote `.sftp_tmp_rs` |
| Rename fails | FLAG + rename_sftpd_files_tmp.sh | Recovery Stage 2: error (disabled) |
| Delete fails | FLAG + delete_sftpd_files_tmp.sh | Recovery Stage 3: run delete script |

**VMS Equivalent:** `SFTP_PROCESS` section — identical three-phase logic with the same error messages.

---

### 4.12 `should_shutdown()`

**Purpose:** Determines whether the script should stop looping and exit gracefully.

**Input:**
- `RSERC_TRANS_SHUTDOWN` — Environment variable (checked for `"Y"`)
- `TAP_DAT_DIR/RSERC_TRANS_SHUTDOWN.FLAG` — Flag file (checked for existence)
- `TAP_CLOSEDOWN_ALL` — Time-based shutdown threshold

**Internal Logic:**
1. If `RSERC_TRANS_SHUTDOWN` = `"Y"` → log message, return 0 (shutdown)
2. If `RSERC_TRANS_SHUTDOWN.FLAG` file exists → log message, return 0 (shutdown)
3. If `TAP_CLOSEDOWN_ALL` ≠ `"N"`:
   - Get current time as `HH:MM`
   - If current time > `TAP_CLOSEDOWN_ALL` → log message, return 0 (shutdown)
4. Otherwise → return 1 (continue looping)

**Output:** Log message explaining why shutdown was triggered (if applicable).

**Return Values:**
- `0` — Shutdown requested (loop should break)
- `1` — Continue running

**Failure Scenarios:** None — this function always returns cleanly.

**VMS Equivalent:** `FINAL_CHECK` section:
```
$  IF (F$CVTIME() .GTS. F$TRNLNM("TAP_CLOSEDOWN_ALL")) .OR.
     (F$TRNLNM("RSERC_TRANS_SHUTDOWN") .EQS. "Y")
$  THEN GOTO EXIT
$  ELSE GOTO MAIN_LOOP
```

**Key Difference:** When `TAP_CLOSEDOWN_ALL` is `"N"`, the VMS comparison `F$CVTIME() .GTS. "N"` always evaluates to false (timestamps like `"2026-03-25"` sort before `"N"` in ASCII). The Linux version explicitly skips the time comparison when the value is `"N"`, achieving the same behavior. The Linux version also adds a flag file mechanism (`RSERC_TRANS_SHUTDOWN.FLAG`) as an alternative shutdown trigger not present in VMS.

---

### 4.13 `main_loop()`

**Purpose:** The core transfer loop that repeatedly scans for files, transfers them, and checks for shutdown.

**Input:** All global configuration variables.

**Internal Logic:**
1. Enter `while true` loop
2. Create three batch files with appropriate headers:
   - SFTP batch: `binary`, `lcd <staging_dir>`, `cd xi_dat`
   - Rename batch: `cd xi_dat`
   - Delete script: bash shebang + comment
3. Call `collect_rserc_files` — populates batch files, sets `RSERC_COUNT`
4. Call `collect_mrlog_files` — populates batch files, sets `MRLOG_COUNT`
5. If either count > 0:
   - Log the batch summary
   - Append `exit` to SFTP and rename batches
   - Call `sftp_transfer` to execute the 3-phase transfer
6. If both counts = 0:
   - Remove empty batch files
   - Log "No files to transfer, waiting 10 minutes"
   - Sleep 600 seconds
7. Call `should_shutdown` — if true, `break` out of the loop

**Output:** Files transferred; log entries written.

**Return Values:** Returns when shutdown is triggered.

**VMS Equivalent:** `MAIN_PARA` / `MAIN_LOOP` labels — the same logic with VMS file I/O (`OPEN/WRITE`, `WRITE`, `CLOSE`) instead of shell redirection.

---

### 4.14 `main()`

**Purpose:** The top-level orchestrator that runs the complete lifecycle.

**Input:** Command-line arguments (not used).

**Internal Logic:**
1. Register signal handlers:
   - `SIGTERM`, `SIGINT` → `error_exit "Caught signal, aborting" "SIGNAL"`
   - `EXIT` → `cleanup_and_exit`
2. Log script start
3. Call `acquire_lock` (singleton enforcement)
4. Call `validate_environment` (directory/config checks)
5. Call `housekeeping` (purge old logs)
6. Call `read_sftp_config` (parse SFTP credentials)
7. Call `self_recovery` (clean up from previous failure)
8. Call `main_loop` (enter the transfer loop)
9. Log successful completion

**Output:** All of the above.

**Return Values:** Implicit 0 on normal completion.

**VMS Equivalent:** The sequential flow from `SAVE_ENVIRONMENT` through `CHECK_INSTANCES`, logical checks, `HOUSE_KEEP`, `EXTRACT_SFTP`, `SELF_RECOVERY`, to `MAIN_PARA`.

---

## 5. Status Code Design

Unlike the TAP Monitor script which uses numeric status codes within its loop, the RSERC Transfer script uses a **binary success/failure** model:

| Approach | Description |
|----------|-------------|
| **Success** | Function returns normally (exit code 0) |
| **Fatal Failure** | Function calls `error_exit()` which terminates the script with exit code **4** |

### Exit Codes

| Code | Meaning | When Used |
|:----:|---------|-----------|
| **0** | Normal exit | Shutdown requested, or another instance already running |
| **4** | Error exit | Any fatal error (SFTP failure, missing directories, recovery failure, signal caught) |

### Why Exit Code 4?

This preserves the VMS convention. VMS uses `EXIT 4` in the `ERROR` section, where 4 is a VMS severity code for "fatal error" (VMS severity codes: 0=warning, 1=success, 2=error, 3=info, 4=fatal).

---

## 6. External Dependencies

### 6.1 SFTP (OpenSSH)

| Usage | Purpose |
|-------|---------|
| `sftp -b <batch_file> user@host` | Upload files to ABS server |
| `sftp -b <batch_file> user@host` | Rename files on ABS server |
| `sftp -b <batch_file> user@host` | Remove partial uploads during recovery |

- Requires SSH key-based authentication (no interactive password prompts)
- The `sftp` binary must be on `PATH`
- The remote server must have an SFTP subsystem enabled
- Batch mode (`-b`) means the SFTP session runs non-interactively

### 6.2 File System Directories

| Directory Variable | Purpose | VMS Logical |
|--------------------|---------|-------------|
| `TAP_CFG_DIR` | Configuration files (SFTP credentials) | `TAP_CFG_DIR:` |
| `TAP_DAT_DIR` | Data/batch files, control files, flag files | `TAP_DAT_DIR:` |
| `TAP_LOG_DIR` | Log file output | `TAP_LOG_DIR:` |
| `TAP_COM_DIR` | Command scripts (referenced but not directly used) | `TAP_COM_DIR:` |
| `FCS_RSERC_DIR` | Source RSERC files to transfer | `FCS_RSERC_DIR:` |
| `XI_DAT` | Source MRLOG files to transfer | `XI_DAT:` |
| `SFTP_TMP_DIR` | Staging directory for files being uploaded | `SFTP_TMP_DIR:` |

### 6.3 OS Utilities

| Utility | Purpose |
|---------|---------|
| `flock` | File locking for singleton enforcement |
| `find` | Locate RSERC and MRLOG files matching naming patterns |
| `cp` | Copy source files to staging directory |
| `rm` | Delete staged files, flag files, control files |
| `logger` | Send error messages to syslog |
| `date` | Generate timestamps for logging and shutdown comparison |
| `basename` | Extract script name from path |
| `tee` | Write to both stdout and log file simultaneously |
| `sleep` | Wait 10 minutes when no files to transfer |
| `bash` | Execute the auto-generated delete script |

### 6.4 Config File

| File | Location | Format |
|------|----------|--------|
| `RSERC_SFTP.CFG` | `TAP_CFG_DIR/RSERC_SFTP.CFG` | Line 1: SFTP username; Line 2: SFTP hostname |

---

## 7. Configuration (Environment Variables / Logical Names)

| Variable | Description | Required | Default | Example |
|----------|-------------|:--------:|---------|---------|
| `TAP_CFG_DIR` | Config directory (SFTP credentials file) | Yes | `/app/tap/R53_TAPLIVE/TAP/CFG` | `/app/tap/CFG` |
| `TAP_DAT_DIR` | Data directory (batch files, flags) | Yes | `/data/tap/R53_TAPLIVE/TAP/DAT` | `/data/tap/DAT` |
| `TAP_LOG_DIR` | Log file directory | Yes | `/data/tap/R53_TAPLIVE/TAP/LOG` | `/data/tap/LOG` |
| `TAP_COM_DIR` | Command/script directory | Yes | `/app/tap/R53_TAPLIVE/TAP/COM` | `/app/tap/COM` |
| `FCS_RSERC_DIR` | Source directory for RSERC files | Yes | `/data/tap/R53_TAPLIVE/TAP/FCS_RSERC` | `/data/tap/FCS_RSERC` |
| `XI_DAT` | Source directory for MRLOG files | Yes | `/data/tap/R53_TAPLIVE/TAP/XI_DAT` | `/data/tap/XI_DAT` |
| `SFTP_TMP_DIR` | Staging directory for SFTP uploads | Yes | `/data/tap/R53_TAPLIVE/TAP/DAT/SFTP_TMP` | `/data/tap/SFTP_TMP` |
| `RSERC_TRANS_SHUTDOWN` | Shutdown flag (`"Y"` to stop) | No | `N` | `Y` |
| `TAP_CLOSEDOWN_ALL` | Time-based shutdown (`"N"` disables, `"HH:MM"` enables) | No | `N` | `23:00` |
| `MAX_BATCH_SIZE` | Max files per batch (hardcoded) | — | `50` | — |
| `REMOTE_DIR` | Remote directory on ABS (hardcoded) | — | `xi_dat` | — |

---

## 8. Error Handling and Alerting

### How Errors Are Detected

Every critical operation checks its return code:
- `sftp -b` → exit code checked; non-zero is fatal
- `cp` → checked per-file; failure logs a warning but does not abort
- `bash <delete_script>` → exit code checked; non-zero is fatal
- Directory existence → checked at startup; missing is fatal
- Config file → checked at startup and before read; missing is fatal

### How Alerts Are Triggered

```
  Fatal error detected
       │
       ▼
  error_exit(error_text, phase)
       │
       ├──► log_msg() → "ERROR: *** <script> - <phase>, <error_text>"
       │                  └─► Written to log file + stdout
       │
       ├──► logger   → Sent to syslog (journald / /var/log/messages)
       │
       └──► cleanup_and_exit(4) → Release lock, exit with code 4
```

### What Happens When Failures Occur

| Failure Type | Behavior |
|-------------|----------|
| SFTP upload fails | Script exits immediately; flag + ctrl file left for recovery |
| SFTP rename fails | Script exits; flag + rename script left (recovery disabled) |
| Local delete fails | Script exits; flag + delete script left for recovery |
| Missing directory | Script exits at startup before any transfers |
| Missing config | Script exits at startup |
| Copy to staging fails | Warning logged; individual file skipped; other files still processed |
| Recovery SFTP fails | Script exits |

### Repeated Failure Behavior

Unlike TAP Monitor which loops and re-alerts, the RSERC Transfer script exits on any fatal error. The assumption is that an external scheduler (cron, systemd timer, or operator) will restart it. On restart, the self-recovery mechanism cleans up from the previous failure before resuming normal operation.

---

## 9. Differences Between VMS Script and Bash Script

| Aspect | VMS (`TAP_RSERCFILES_TRANSFER.COM`) | Linux (`tap_rsercfiles_transfer.sh`) |
|--------|-------------------------------------|--------------------------------------|
| **Singleton mechanism** | `SET PROCESS /NAME=RSERC_TRANS` — OS-enforced unique process name | `flock -n` — file-based exclusive lock |
| **Lock cleanup** | Automatic on process exit (VMS releases process name) | Explicit FD close in `cleanup_and_exit`; lock file persists on disk |
| **Error handling** | `ON ERROR THEN GOTO ERROR` — global handler catches all errors | `set -o pipefail` + explicit error checks per operation |
| **Operator notification** | `REQUEST/REPLY/TO=OPER8` — interactive operator terminal message | `logger` (syslog) — non-interactive |
| **File versioning** | VMS files have versions (`;1`, `;2`). Temp extension includes version: `name.SFTP_TMP_RS;1` | No versioning. Temp extension is just `name.sftp_tmp_rs` |
| **File search** | `F$SEARCH("pattern",stream)` — call repeatedly to iterate | `find ... -print0` — returns all matches at once |
| **Pattern wildcards** | `%%%%%%` — VMS single-char wildcard is `%` | `??????` — Bash single-char wildcard is `?` |
| **Delete command in script** | `$DELETE/LOG FCS_RSERC_DIR:'FILENAME'` — DCL command | `rm -f "<full_path>"` — shell command |
| **Batch file naming** | `.COM` (VMS command procedure) and `.DAT` | `.sh` (shell script) and `.dat` |
| **SFTP lcd path** | `lcd SFTP_TMP_DIR` (VMS logical translated by sftp) | `lcd /data/tap/.../SFTP_TMP` (full Linux path) |
| **Shutdown check** | `F$CVTIME() .GTS. F$TRNLNM("TAP_CLOSEDOWN_ALL")` — VMS datetime comparison; `"N"` disables naturally | Explicit `!= "N"` check added; `date '+%H:%M'` comparison |
| **Shutdown flag file** | Not present in VMS (only env var/logical check) | Added `RSERC_TRANS_SHUTDOWN.FLAG` as additional mechanism |
| **Recovery Stage 2** | Commented out with `$!` — dead code | Preserved as dead code; calls `error_exit` if triggered |
| **Cleanup guard** | Not needed (VMS `EXIT` is only reached once) | `_CLEANUP_DONE` flag prevents double cleanup (traps can re-enter) |
| **Script sourcing** | Not applicable (VMS always executes) | `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard allows sourcing for testing |
| **VT terminal codes** | Extensive CSI/ESC codes for terminal formatting | None — plain text output |

### Risks

1. **VMS file versions lost:** VMS `F$SEARCH` returns files with version numbers (e.g., `RSERC000001.DAT;3`). The temp extension in VMS includes this version. Linux has no file versioning — if a file is created with the same name, it overwrites. This should not be an issue in practice since filenames include unique sequence numbers.

2. **Recovery Stage 2 is permanently broken:** Both VMS and Linux versions have this recovery path disabled. If a failure occurs between the upload and rename phases, manual intervention is required.

3. **Concurrent file creation:** If the TAP system creates a new RSERC file while `collect_rserc_files()` is running, the `find` command may or may not include it. This is the same race condition as VMS `F$SEARCH` and is benign — the file will be picked up on the next cycle.

4. **Large batch performance:** VMS processes files one at a time via `F$SEARCH` loops. Linux `find` collects all matches at once. For very large directories, this is more efficient on Linux.

---

## 10. Real-World Example Scenarios

### Scenario 1: Normal Transfer Cycle

**Setup:**
- 5 RSERC files in `FCS_RSERC_DIR`: `RSERC000001.DAT` through `RSERC000005.DAT`
- 3 MRLOG files in `XI_DAT`: `MRLOG000001.DAT` through `MRLOG000003.DAT`
- `TAP_CLOSEDOWN_ALL="N"` (no time-based shutdown)

**What happens:**
1. Script enters the main loop
2. `collect_rserc_files` finds 5 files → copies each to `SFTP_TMP_DIR` as `.sftp_tmp_rs`
3. `collect_mrlog_files` finds 3 files → same staging process
4. Log: `"Batch: 5 RSERC files, 3 MRLOG files"`
5. `sftp_transfer` runs:
   - Phase 1: Uploads 8 `.sftp_tmp_rs` files to ABS server's `xi_dat/` directory
   - Phase 2: Renames all 8 files from `.sftp_tmp_rs` to `.DAT` on ABS
   - Phase 3: Deletes all 8 source files from `FCS_RSERC_DIR` and `XI_DAT`
6. `should_shutdown` returns 1 → loop continues
7. Next iteration finds 0 files → sleeps 10 minutes

### Scenario 2: Batch Overflow (>50 Files)

**Setup:**
- 60 RSERC files and 10 MRLOG files

**What happens:**
1. `collect_rserc_files` finds 60 but stops at 50 (MAX_BATCH_SIZE)
2. `collect_mrlog_files` finds 10 → stages all 10
3. Batch: 50 RSERC + 10 MRLOG = 60 files transferred
4. `should_shutdown` returns 1 → loop immediately (no sleep since files were transferred)
5. Next iteration: remaining 10 RSERC files are picked up

### Scenario 3: SFTP Upload Fails

**Setup:**
- Network connectivity to ABS server is lost after files are staged

**What happens:**
1. Files are staged in `SFTP_TMP_DIR`
2. `FLAG_FILE` (`SFTP_ABS_IN_PROGRESS.FLAG`) is created
3. `sftp -b <batch> user@host` fails → returns non-zero
4. `error_exit` is called:
   - Logs: `"ERROR: *** tap_rsercfiles_transfer - SFTP_PROCESS, ERROR WHILE TRANSFERRING..."`
   - Sends to syslog
   - Calls `cleanup_and_exit 4`
5. Script exits with code 4
6. **Left behind:** FLAG file + `sftp_ctrl_file.dat` + staged files
7. **On next startup:** `self_recovery` detects the flag and ctrl file → Recovery Stage 1 runs → removes `*.sftp_tmp_rs` from remote → cleans local artifacts → normal operation resumes

### Scenario 4: Shutdown via Flag

**Setup:**
- `TAP_CLOSEDOWN_ALL="N"` (time-based shutdown disabled)
- Operator creates `RSERC_TRANS_SHUTDOWN.FLAG` in `TAP_DAT_DIR`

**What happens:**
1. After the current transfer cycle completes (or after the 10-minute sleep)
2. `should_shutdown` checks `RSERC_TRANS_SHUTDOWN` → it is `"N"`, continue
3. Checks for `RSERC_TRANS_SHUTDOWN.FLAG` → file exists!
4. Logs: `"Shutdown requested via flag file"`
5. Returns 0 → main loop breaks
6. Script logs completion and exits with code 0

### Scenario 5: Recovery After Kill

**Setup:**
- The script was killed (`kill -9`) during Phase 3 (local delete)
- `SFTP_ABS_IN_PROGRESS.FLAG` exists
- `delete_sftpd_files_tmp.sh` exists (Phase 1 upload and Phase 2 rename already completed)
- `SFTP_CTRL_FILE.DAT` and `rename_sftpd_files_tmp.sh` were already deleted during normal flow

**What happens on restart:**
1. Self-recovery detects `FLAG_FILE`
2. Checks for `SFTP_CTRL_FILE.DAT` → not found (upload completed)
3. Checks for `rename_sftpd_files_tmp.sh` → not found (rename completed)
4. Checks for `delete_sftpd_files_tmp.sh` → found!
5. Runs the delete script → source files are cleaned up
6. Removes the delete script and flag
7. Normal operation resumes

---

## 11. Summary

The **TAP RSERC Files Transfer** script is an automated file transfer daemon for a telecom roaming billing system. It continuously monitors two source directories for newly generated billing files (RSERC settlement records and MRLOG metering logs) and transfers them to the ABS billing server via SFTP.

The transfer uses a **three-phase approach** (upload with temporary extension, rename to final name, delete source) to ensure atomicity — the ABS system never sees partially uploaded files. A built-in **self-recovery mechanism** uses flag files and control file artifacts to detect and clean up from previous failures, ensuring the system can always restart cleanly.

The script was originally written for OpenVMS in 2018 and has been converted to Linux Bash. Key architectural decisions from the VMS version are preserved: the 50-file batch limit, the `.sftp_tmp_rs` temporary extension, the three-phase transfer protocol, and the self-recovery design with its three stages. The primary conversion changes involve replacing VMS process naming with `flock`, VMS `F$SEARCH` with `find`, and VMS operator messages with syslog.
