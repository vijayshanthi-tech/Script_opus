# RSERC_CHK — Unit Test Document

| Field          | Value                        |
|----------------|------------------------------|
| Script         | `rserc_chk.sh`               |
| VMS Original   | `RSERC_CHK.COM`              |
| Test Platform  | Linux / Bash 4+              |
| Oracle Version | (as deployed)                |
| Tester         | ____________________________  |
| Test Date      | ____________________________  |

---

## How to Source the Script for Testing

The script contains an entry-point guard that prevents `main()` from executing
when sourced. This allows individual functions to be tested in isolation:

```bash
# Source the script (does NOT execute main)
# The script uses its default configuration paths:
#   TAP_LOG_DIR=/data/tap/R53_TAPLIVE/TAP/LOG
#   LOG_FILE=/data/tap/R53_TAPLIVE/TAP/LOG/rserc_chk.log
#   WORK_DIR=/tmp/rserc_chk_$$  (created automatically)
source /path/to/rserc_chk.sh
```

All functions are now available to call directly.

---

## Test Prerequisites (Global)

| Prerequisite        | Required For            | How to Verify                      |
|---------------------|-------------------------|------------------------------------|
| Bash 4+             | All functions           | `bash --version`                   |
| `mailx` installed   | send_alert, send_report | `which mailx`                      |
| MTA running         | send_alert, send_report | `systemctl status postfix`         |
| Oracle `sqlplus`     | generate_spid_list, generate_hourly_reports, check_rserc_failures | `which sqlplus` |
| OS Oracle auth      | Above + DB queries      | `sqlplus -s / <<< "SELECT 1 FROM DUAL; EXIT;"` |
| `at` daemon running | schedule_next_run       | `systemctl status atd`             |
| `tee`, `find`, `wc` | Multiple functions      | Available in coreutils (standard)  |

---

## 1. Function: `log_msg`

### 1.1 Test: Basic Message Logging

**Purpose:** Verify that `log_msg` writes a timestamped message to both stdout and the log file.

**Test Steps:**
1. Source the script (see "How to Source" above)
2. Run: `log_msg "Test message from UT"`
3. Check stdout for the message
4. Check the log file: `tail -1 "${LOG_FILE}"`

**Inputs Required:**
| Input        | Value                          |
|--------------|--------------------------------|
| `$1` (msg)   | `"Test message from UT"`       |
| `LOG_FILE`   | `${TAP_LOG_DIR}/rserc_chk.log` |

**Expected Output:**
- stdout: `DD-Mon-YYYY HH:MM:SS - Test message from UT` (current timestamp)
- Log file last line: same as stdout

**Actual Output:**
```
____[R53_TAPLIVE@dmmlw-esxvm-1048 SH]$ tail -1 "${LOG_FILE}"
26-Mar-2026 12:41:55 - Test message from UT
[R53_TAPLIVE@dmmlw-esxvm-1048 SH]$______________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 1.2 Test: Log File Creation

**Purpose:** Verify that `log_msg` creates the log file if it does not already exist.

**Test Steps:**
1. Source the script
2. Remove the log file: `rm -f "${LOG_FILE}"`
3. Run: `log_msg "First log entry"`
4. Verify file exists: `ls -la "${LOG_FILE}"`
5. Verify content: `cat "${LOG_FILE}"`

**Inputs Required:**
| Input        | Value                          |
|--------------|--------------------------------|
| `$1` (msg)   | `"First log entry"`            |
| `LOG_FILE`   | (should not exist before test) |

**Expected Output:**
- Log file is created
- Contains exactly one line: `DD-Mon-YYYY HH:MM:SS - First log entry`

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

## 2. Function: `send_alert`

### 2.1 Test: Email Alert Dispatch

**Purpose:** Verify that `send_alert` sends an email with an empty body and logs the subject.

**Test Steps:**
1. Source the script
2. Set `EMAIL_L2` to a test mailbox you can check (or use a local user)
3. Run: `send_alert "UT - Test alert subject"`
4. Check the log file for the subject line
5. Check the recipient mailbox for the email

**Inputs Required:**
| Input        | Value                            |
|--------------|----------------------------------|
| `$1` (subject) | `"UT - Test alert subject"`   |
| `EMAIL_L2`   | Test email address               |

**Expected Output:**
- Email received with subject `UT - Test alert subject` and empty body
- Log file contains: `DD-Mon-YYYY HH:MM:SS - UT - Test alert subject`

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 2.2 Test: Graceful Handling When mailx is Unavailable

**Purpose:** Verify that `send_alert` does not crash when `mailx` is not installed or MTA is down.

**Test Steps:**
1. Source the script
2. Temporarily rename `mailx`: `sudo mv /usr/bin/mailx /usr/bin/mailx.bak`
3. Run: `send_alert "UT - No mailx test"`
4. Check that the log line still appears
5. Restore: `sudo mv /usr/bin/mailx.bak /usr/bin/mailx`

**Inputs Required:**
| Input        | Value                         |
|--------------|-------------------------------|
| `$1` (subject) | `"UT - No mailx test"`     |

**Expected Output:**
- No crash/termination (exit code 0 from `log_msg`)
- Log file contains the message (even though email failed silently)

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

## 3. Function: `send_report`

### 3.1 Test: Email with File Body

**Purpose:** Verify that `send_report` sends an email containing the file's contents as the body.

**Test Steps:**
1. Source the script
2. Create a test file: `echo "Line 1 of report" > ${WORK_DIR}/test_report.lis`
3. Run: `send_report "UT - Report Subject" "${WORK_DIR}/test_report.lis" "youremail@example.com"`
4. Check the recipient mailbox for the email body content

**Inputs Required:**
| Input          | Value                            |
|----------------|----------------------------------|
| `$1` (subject) | `"UT - Report Subject"`          |
| `$2` (file)    | `${WORK_DIR}/test_report.lis`    |
| `$3` (recipient) | Your test email address        |

**Expected Output:**
- Email received with subject `UT - Report Subject`
- Email body contains: `Line 1 of report`

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 3.2 Test: Multiple Recipients

**Purpose:** Verify that `send_report` sends the email to all specified recipients.

**Test Steps:**
1. Source the script
2. Create a test file: `echo "Multi-recipient test" > ${WORK_DIR}/test_multi.lis`
3. Run: `send_report "UT Multi" "${WORK_DIR}/test_multi.lis" "user1@test.com" "user2@test.com"`
4. Check both mailboxes

**Inputs Required:**
| Input            | Value                           |
|------------------|---------------------------------|
| `$1` (subject)   | `"UT Multi"`                   |
| `$2` (file)      | `${WORK_DIR}/test_multi.lis`   |
| `$3`, `$4` (recipients) | Two test addresses       |

**Expected Output:**
- Both recipients receive the email with the same subject and body

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

## 4. Function: `schedule_next_run`

### 4.1 Test: Job Scheduled with `at`

**Purpose:** Verify that the script schedules itself for 06:00 tomorrow using `at`.

**Test Steps:**
1. Ensure `atd` is running: `systemctl status atd`
2. Source the script
3. Run: `schedule_next_run`
4. Check the at queue: `atq`
5. Inspect the job: `at -c <job_id>` (use the job ID from `atq`)

**Inputs Required:**
| Input      | Value                |
|------------|----------------------|
| `atd`      | Must be running      |
| `$0`       | Path to the script   |

**Expected Output:**
- `atq` shows a new job scheduled for 06:00 tomorrow
- The job command contains the script path

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 4.2 Test: Fallback When `at` is Unavailable

**Purpose:** Verify that the function logs a WARNING when `at` cannot be used.

**Test Steps:**
1. Temporarily disable or rename: `sudo mv /usr/bin/at /usr/bin/at.bak`
2. Source the script
3. Run: `schedule_next_run`
4. Check for log output containing "WARNING: Could not schedule"
5. Restore: `sudo mv /usr/bin/at.bak /usr/bin/at`

**Inputs Required:**
| Input      | Value                      |
|------------|----------------------------|
| `at`       | Must NOT be available      |

**Expected Output:**
- Log message: `WARNING: Could not schedule next run via 'at'. Ensure cron is configured.`

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

## 5. Function: `generate_spid_list`

### 5.1 Test: SPID List Population from Oracle

**Purpose:** Verify that the function queries Oracle and writes SP_IDs to a file.

**Test Steps:**
1. Ensure Oracle `sqlplus` is available and OS-authenticated
2. Source the script
3. Run: `generate_spid_list`
4. Check the output file: `cat "${SPID_LIST}"`
5. Verify each line contains a numeric SP_ID

**Inputs Required:**
| Input             | Value                       |
|-------------------|-----------------------------|
| Oracle access     | OS-authenticated            |
| `WORK_DIR`        | Must exist (writable)       |
| `service_providers` table | Must contain data   |

**Expected Output:**
- File `${WORK_DIR}/spid_list.lis` exists
- Contains one SP_ID per line (numeric values)
- No SQL*Plus banner text in the file

**Actual Output:**
```
____________________________________________________________________

```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 5.2 Test: Empty Table Handling

**Purpose:** Verify behaviour when the `service_providers` table is empty.

**Test Steps:**
1. (If possible on test DB) Ensure the `service_providers` table has no rows
2. Source the script
3. Run: `generate_spid_list`
4. Check: `cat "${SPID_LIST}"` — should be empty or contain only whitespace

**Inputs Required:**
| Input                    | Value                 |
|--------------------------|-----------------------|
| `service_providers` table | Empty (zero rows)   |

**Expected Output:**
- File is created but is empty (0 bytes or whitespace only)
- No errors on stderr

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

## 6. Function: `check_tap_directories`

### 6.1 Test: Archive Check — Files Present (No Alert)

**Purpose:** Verify no alert is sent when recent archive files exist.

**Test Steps:**
1. Verify recent files exist: `find /data/tap/R53_TAPLIVE/TAP/ARCHIVE -maxdepth 1 -iname 'cd*.dat' -mmin -240 | head -5`
2. Source the script
3. Run: `check_tap_directories`
4. Verify NO "No Call files processed" alert in log

**Inputs Required:**
| Input              | Value                              |
|--------------------|------------------------------------|
| `TAP_ARCHIVE_DIR`  | `/data/tap/R53_TAPLIVE/TAP/ARCHIVE` |
| Files in dir       | At least one `cd*.dat` < 4hr old  |

**Expected Output:**
- Log shows "Checking TAP directories" but NO archive alert

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 6.2 Test: Archive Check — No Files (Alert Expected)

**Purpose:** Verify that an alert is sent when no `cd*.dat` files are found within 4 hours.

**Test Steps:**
1. Verify no recent files exist: `find /data/tap/R53_TAPLIVE/TAP/ARCHIVE -maxdepth 1 -iname 'cd*.dat' -mmin -240 | wc -l` (should be 0)
2. Temporarily move recent files out if any: `mkdir -p /data/tap/R53_TAPLIVE/TAP/ARCHIVE/ut_bak && mv /data/tap/R53_TAPLIVE/TAP/ARCHIVE/cd*.dat /data/tap/R53_TAPLIVE/TAP/ARCHIVE/ut_bak/ 2>/dev/null`
3. Source the script
4. Run: `check_tap_directories`
5. Check log for: "No Call files processed by TAP collection in last four hours"
6. Restore files: `mv /data/tap/R53_TAPLIVE/TAP/ARCHIVE/ut_bak/* /data/tap/R53_TAPLIVE/TAP/ARCHIVE/ 2>/dev/null && rmdir /data/tap/R53_TAPLIVE/TAP/ARCHIVE/ut_bak`

**Inputs Required:**
| Input              | Value                                      |
|--------------------|--------------------------------------------|
| `TAP_ARCHIVE_DIR`  | `/data/tap/R53_TAPLIVE/TAP/ARCHIVE`         |
| Files in dir       | None (temporarily moved out for test)       |

**Expected Output:**
- Log contains: `No Call files processed by TAP collection in last four hours`
- Email sent to EMAIL_L2 with same subject

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 6.3 Test: Collect Directory — Over Threshold (Alert)

**Purpose:** Verify alert when collect directory has more files than MAX threshold.

**Test Steps:**
1. Check current file count: `find /data/tap/R53_TAPLIVE/TAP/COLLECT -maxdepth 1 -iname 'CD?????GBRCN*.dat' | wc -l`
2. Lower threshold below current count: `export MAX=2`
3. If fewer than 3 files exist, create test files:
   ```bash
   touch /data/tap/R53_TAPLIVE/TAP/COLLECT/CD00001GBRCN_ut_a.dat
   touch /data/tap/R53_TAPLIVE/TAP/COLLECT/CD00002GBRCN_ut_b.dat
   touch /data/tap/R53_TAPLIVE/TAP/COLLECT/CD00003GBRCN_ut_c.dat
   ```
4. Source the script
5. Run: `check_tap_directories`
6. Check log for "There are N files in tap collection" (where N > MAX)
7. Cleanup test files: `rm -f /data/tap/R53_TAPLIVE/TAP/COLLECT/CD*GBRCN_ut_*.dat`

**Inputs Required:**
| Input              | Value                              |
|--------------------|------------------------------------|
| `TAP_COLLECT_DIR`  | `/data/tap/R53_TAPLIVE/TAP/COLLECT` |
| `MAX`              | `2` (lowered for testing)            |
| Files              | 3+ files matching `CD?????GBRCN*`    |

**Expected Output:**
- Log contains: `There are 3 files in tap collection`

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 6.4 Test: Collect Directory — Under Threshold (No Alert)

**Purpose:** Verify no alert when file count is within threshold.

**Test Steps:**
1. Use actual collect directory: `/data/tap/R53_TAPLIVE/TAP/COLLECT`
2. Set threshold to default: `export MAX=400`
3. Source and run: `check_tap_directories`
4. Verify NO "files in tap collection" alert in log (file count should be below 400)

**Inputs Required:**
| Input              | Value                              |
|--------------------|------------------------------------|
| `MAX`              | `400`                              |
| Files              | 3 (below threshold)                |

**Expected Output:**
- No alert for collect directory

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 6.5 Test: Per-SPID Split Directory Check

**Purpose:** Verify per-SPID split directory threshold alerting using SPID_LIST.

**Test Steps:**
1. Ensure SPID list exists: `cat "${SPID_LIST}"` (generated by `generate_spid_list`)
2. Pick a valid SPID from the list (e.g., `7` → zero-padded to `007`)
3. Check existing files: `ls /data/tap/R53_TAPLIVE/TAP/SPLIT/007/ | wc -l`
4. Create test files exceeding threshold:
   ```bash
   for i in $(seq 1 5); do touch "/data/tap/R53_TAPLIVE/TAP/SPLIT/007/CD_ut_test_${i}.SPLIT"; done
   ```
5. Lower threshold: `export SPLIT_MAX=2`
6. Source the script and run: `check_tap_directories`
7. Check log for: "There are N files in TAP Distribute for spid 007"
8. Cleanup test files: `rm -f /data/tap/R53_TAPLIVE/TAP/SPLIT/007/CD_ut_test_*.SPLIT`

**Inputs Required:**
| Input            | Value                              |
|------------------|------------------------------------|
| `TAP_OB_SPLIT`   | `/data/tap/R53_TAPLIVE/TAP/SPLIT`  |
| `SPLIT_MAX`      | `2` (lowered for testing)           |
| `SPID_LIST`      | `${WORK_DIR}/spid_list.lis` (from Oracle) |

**Expected Output:**
- Log contains: `There are 5 files in TAP Distribute for spid 007`

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

## 7. Function: `generate_hourly_reports`

### 7.1 Test: Report Files Generated and Emailed

**Purpose:** Verify that Oracle spool files are generated, emailed, and cleaned up.

**Test Steps:**
1. Ensure Oracle sqlplus is available
2. Source the script
3. Set `run_count=2` (to enable zero-RSERC check)
4. Run: `generate_hourly_reports`
5. Check log for:
   - "Creating Tap hourly reports"
   - "TAP - Processed RESRC File Report sent to L2"
   - "TAP - Processed roaming CDRs Report sent to L2"
6. Verify spool files were cleaned up: `ls ${WORK_DIR}/files_created*` (should fail)
7. Check email delivery

**Inputs Required:**
| Input              | Value                              |
|--------------------|------------------------------------|
| Oracle connection  | OS-authenticated, DB accessible    |
| `run_count`        | `2`                                |
| `EMAIL_L2`         | Test address                       |
| `EMAIL_APOLLO`     | Test address                       |

**Expected Output:**
- Three emails sent (files_created, recs_created ×2)
- Temp files deleted after sending
- Log messages as listed above

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 7.2 Test: Zero-RSERC Alert (run_count > 1)

**Purpose:** Verify that a zero-RSERC alert fires when no files were created in last 4 hours.

**Test Steps:**
1. Source the script
2. Set `run_count=3`
3. Run: `generate_hourly_reports`
4. If the Oracle query returns FILE_COUNT=0 for 4-hour window, check log for:
   `"There are no RSERC created in last 4 hours"`
5. If data exists, manually create a mock `files_created1.lis`:
   ```bash
   echo "FILE_COUNT=        0" > "${WORK_DIR}/files_created1.lis"
   ```
   Then call the file-checking portion manually.

**Inputs Required:**
| Input           | Value                              |
|-----------------|------------------------------------|
| `run_count`     | > 1                                |
| `FILE_COUNT`    | `0` (from Oracle or mock file)     |

**Expected Output:**
- Alert: `"There are no RSERC created in last 4 hours"`

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 7.3 Test: Zero-RSERC — First Run (No Alert)

**Purpose:** Verify that the zero-RSERC alert is suppressed on the first hourly run (run_count=1).

**Test Steps:**
1. Source the script
2. Set `run_count=1`
3. Create mock file: `echo "FILE_COUNT=        0" > "${WORK_DIR}/files_created1.lis"`
4. Observe that NO alert is sent (check log)

**Inputs Required:**
| Input           | Value                              |
|-----------------|------------------------------------|
| `run_count`     | `1`                                |
| `FILE_COUNT`    | `0`                                |

**Expected Output:**
- NO alert is sent (first run is excluded)

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

## 8. Function: `check_rserc_failures`

### 8.1 Test: Assembly/Dist Process Running (Skip Check)

**Purpose:** Verify that failure checks are skipped when assembly/distribution processes are active.

**Test Steps:**
1. Start a dummy process: `sleep 600 &` and rename it conceptually via `ps` (or run a script named `dist_test`)
2. Alternative: Create a background process matching "dist":
   ```bash
   bash -c 'exec -a dist_test sleep 600' &
   DIST_PID=$!
   ```
3. Source the script, run: `check_rserc_failures`
4. Verify log shows "Checking for RSERC failures" but returns immediately (no .don/.tmp checks)
5. Kill dummy: `kill $DIST_PID`

**Inputs Required:**
| Input                 | Value                              |
|-----------------------|------------------------------------|
| Running process       | Process with "dist" in name/args   |

**Expected Output:**
- Function returns without .don or .tmp checking
- Log shows only "Checking for RSERC failures"

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 8.2 Test: .don Files Detected (Alert)

**Purpose:** Verify that .don files trigger an alert email.

**Test Steps:**
1. Create a test .don file: `touch /data/tap/R53_TAPLIVE/TAP/OG_SP/ut_test_file.don`
2. Ensure no "dist" or "assemb" processes are running: `ps -ef | grep -i 'assemb\|dist' | grep -v grep`
3. Source the script, run: `check_rserc_failures`
4. Check log for: "RSERC Failure - Procedure 841 - *.DON files left out"
5. Cleanup test file: `rm -f /data/tap/R53_TAPLIVE/TAP/OG_SP/ut_test_file.don`

**Inputs Required:**
| Input              | Value                              |
|--------------------|------------------------------------|
| `TAP_OUTGOING_SP`  | `/data/tap/R53_TAPLIVE/TAP/OG_SP`  |
| .don files         | At least one present               |

**Expected Output:**
- Alert email sent to TAP Support and L2
- Log contains: `RSERC Failure - Procedure 841 - *.DON files left out`

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 8.3 Test: .tmp Files Detected (Alert + Recovery)

**Purpose:** Verify that .tmp files trigger an alert AND automatic RSERC recovery.

**Test Steps:**
1. Create test .tmp and mrlog files in actual directories:
   ```bash
   touch /data/tap/R53_TAPLIVE/TAP/OG_SP/MRLOG007.tmp
   touch /data/tap/R53_TAPLIVE/TAP/OG_SP/ut_other_file.tmp
   ```
2. Ensure no "dist" or "assemb" processes are running: `ps -ef | grep -i 'assemb\|dist' | grep -v grep`
3. Source the script, run: `check_rserc_failures`
4. Check log for:
   - "RSERC Failure - Procudure 841" (note: typo preserved from VMS)
   - "Re-running RSERC for SP_ID: ..."
5. Verify .tmp files were deleted: `ls /data/tap/R53_TAPLIVE/TAP/OG_SP/*.tmp` (should fail)

**Inputs Required:**
| Input             | Value                                |
|-------------------|--------------------------------------|
| `TAP_OUTGOING_SP` | `/data/tap/R53_TAPLIVE/TAP/OG_SP` (with test .tmp files) |
| `TAP_PERIOD_DIR`  | `/data/tap/R53_TAPLIVE/TAP/PERIOD`                       |
| `RERUN_RSERC_SQL` | Path to valid SQL or mock script     |

**Expected Output:**
- Alert email with "Procudure 841" (typo preserved)
- .tmp files deleted from both directories
- SP_ID extracted and RSERC re-run triggered
- Log: `Re-running RSERC for SP_ID: <extracted_id>`

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

> **Note:** The VMS original used `f$extract(34,3,rec)` at position 35 (1-based)
> against the full VMS DIR output including the path prefix
> `DISK$CALL_DATA:[TAP.OB.OG_SP]` (29 chars). On Linux, `basename` strips the
> path, so the offset is position 6 (1-based) within the filename. Real VMS
> filenames follow the format `MRLOG{3-digit-SP_ID}.TMP` (e.g. `MRLOG007.TMP`),
> giving `awk '{ print substr($0, 6, 3) }'` → `007`.

---

### 8.4 Test: No .don or .tmp Files (Clean State)

**Purpose:** Verify that no alerts are sent when directories are clean.

**Test Steps:**
1. Verify no .don or .tmp files in actual directory: `ls /data/tap/R53_TAPLIVE/TAP/OG_SP/*.don /data/tap/R53_TAPLIVE/TAP/OG_SP/*.tmp 2>/dev/null | wc -l` (should be 0)
2. Source the script, run: `check_rserc_failures`
3. Verify log shows only "Checking for RSERC failures" — no alerts

**Inputs Required:**
| Input              | Value                                       |
|--------------------|---------------------------------------------|
| `TAP_OUTGOING_SP`  | `/data/tap/R53_TAPLIVE/TAP/OG_SP` (clean)   |

**Expected Output:**
- No alert emails
- Log: only "Checking for RSERC failures"

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

## 9. Function: `main`

### 9.1 Test: Startup Sequence

**Purpose:** Verify that `main()` calls `schedule_next_run`, `generate_spid_list`, and enters the loop correctly.

**Test Steps:**
1. This is best tested by running the full script in a controlled environment
2. Override directories to test dirs (see above)
3. Run: `./rserc_chk.sh` (or `bash rserc_chk.sh`)
4. Watch log output for:
   - "RSERC CHK started"
   - "Creating SPID list"
   - "Checking TAP directories"
   - "Creating Tap hourly reports"
   - "Checking for RSERC failures"
   - "Waiting for 10 mins"
5. Let it run for one cycle, then Ctrl+C to stop

**Inputs Required:**
| Input              | Value                              |
|--------------------|------------------------------------|
| All env vars       | Pointing to test directories       |
| Oracle             | Available                          |
| MTA                | Running                            |

**Expected Output:**
- Log shows the complete startup sequence listed above
- Script loops every 10 minutes and checks for failures
- Hourly checks execute when the clock hour changes

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 9.2 Test: Exit at Hour 23

**Purpose:** Verify that the script exits cleanly when the clock hour reaches 23.

**Test Steps:**
1. Create a fake `date` wrapper that returns hour 23:
   ```bash
   mkdir -p /tmp/fake_bin
   cat > /tmp/fake_bin/date <<'EOF'
   #!/bin/bash
   if [[ "$1" == "+%H" ]]; then
     echo "23"
   else
     /usr/bin/date "$@"
   fi
   EOF
   chmod +x /tmp/fake_bin/date
   ```
2. Run the script with the fake `date` first on PATH:
   ```bash
   PATH="/tmp/fake_bin:$PATH" ./rserc_chk.sh
   ```
3. Verify log shows: "RSERC_CHK completed"
4. Verify temp files in WORK_DIR are cleaned up
5. Cleanup the fake wrapper:
   ```bash
   rm -rf /tmp/fake_bin
   ```

**Inputs Required:**
| Input              | Value                                      |
|--------------------|--------------------------------------------|
| `/tmp/fake_bin/date` | Wrapper returning `23` for `date '+%H'`  |
| `PATH`             | `/tmp/fake_bin` prepended to original PATH |

**Expected Output:**
- Script exits with code 0
- Cleanup executed (old logs deleted, WORK_DIR removed)
- Log: "RSERC_CHK completed"

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

## 10. Function: `cleanup_and_exit`

### 10.1 Test: Normal Cleanup

**Purpose:** Verify that `cleanup_and_exit` removes temp files and old logs.

**Test Steps:**
1. Source the script
2. Create temp files in WORK_DIR:
   ```bash
   touch "${WORK_DIR}/rserc_failure_1.txt"
   touch "${WORK_DIR}/rserc_chk.lis"
   touch "${WORK_DIR}/spid_list.lis"
   ```
3. Create an old log file:
   ```bash
   touch -d "40 days ago" "${TAP_LOG_DIR}/rserc_chk.log.old"
   ```
4. Run: `cleanup_and_exit`
5. Verify:
   - WORK_DIR removed: `ls "${WORK_DIR}"` (should fail)
   - Old log deleted: `ls "${TAP_LOG_DIR}/rserc_chk.log.old"` (should fail)
   - Log shows: "RSERC_CHK completed"

**Inputs Required:**
| Input           | Value                              |
|-----------------|------------------------------------|
| `WORK_DIR`      | Directory with temp files          |
| `TAP_LOG_DIR`   | Directory with old log (>30 days)  |

**Expected Output:**
- WORK_DIR removed
- Old logs (>30 days) deleted
- Recent logs preserved
- Log: "RSERC_CHK completed"

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 10.2 Test: Double-Call Guard

**Purpose:** Verify that calling `cleanup_and_exit` twice does not produce duplicate log entries.

**Test Steps:**
1. Source the script
2. Reset guard: `_CLEANUP_DONE=0`
3. Run: `cleanup_and_exit`
4. Run again: `cleanup_and_exit`
5. Count "RSERC_CHK completed" entries in the log: `grep -c "RSERC_CHK completed" "${LOG_FILE}"`

**Inputs Required:**
| Input            | Value                              |
|------------------|------------------------------------|
| `_CLEANUP_DONE`  | `0` (before first call)            |

**Expected Output:**
- "RSERC_CHK completed" appears exactly ONCE in the log
- Second call returns immediately with exit code 0

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

## 11. Entry-Point Guard

### 11.1 Test: Sourcing Does Not Execute Main

**Purpose:** Verify that sourcing the script makes functions available without running `main()`.

**Test Steps:**
1. Run: `source ./rserc_chk.sh`
2. Verify no "RSERC CHK started" in stdout
3. Verify functions are available: `type log_msg` (should show function definition)

**Inputs Required:**
| Input      | Value       |
|------------|-------------|
| None       |             |

**Expected Output:**
- No output from sourcing (main does not execute)
- `type log_msg` shows: `log_msg is a function`

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

### 11.2 Test: Direct Execution Runs Main

**Purpose:** Verify that running the script directly invokes `main()` and sets up the EXIT trap.

**Test Steps:**
1. Run: `bash rserc_chk.sh` (with appropriate env vars set)
2. Verify "RSERC CHK started" appears in log
3. Ctrl+C to trigger the SIGINT trap
4. Verify "RSERC_CHK completed" appears (cleanup triggered)

**Inputs Required:**
| Input       | Value                              |
|-------------|------------------------------------|
| Env vars    | All TAP_* paths, Oracle access     |

**Expected Output:**
- "RSERC CHK started" in log
- On Ctrl+C: "RSERC_CHK completed" logged, temp files cleaned

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

**Notes / Observations:**
```
____________________________________________________________________
```

---

## Test Summary

| #    | Function                | Test Case                         | Pass/Fail | Tester Initials |
|------|-------------------------|-----------------------------------|-----------|-----------------|
| 1.1  | `log_msg`               | Basic message logging             | ________  | ________        |
| 1.2  | `log_msg`               | Log file creation                 | ________  | ________        |
| 2.1  | `send_alert`            | Email alert dispatch              | ________  | ________        |
| 2.2  | `send_alert`            | mailx unavailable                 | ________  | ________        |
| 3.1  | `send_report`           | Email with file body              | ________  | ________        |
| 3.2  | `send_report`           | Multiple recipients               | ________  | ________        |
| 4.1  | `schedule_next_run`     | Job scheduled with at             | ________  | ________        |
| 4.2  | `schedule_next_run`     | Fallback when at unavailable      | ________  | ________        |
| 5.1  | `generate_spid_list`    | SPID list from Oracle             | ________  | ________        |
| 5.2  | `generate_spid_list`    | Empty table handling              | ________  | ________        |
| 6.1  | `check_tap_directories` | Archive — files present           | ________  | ________        |
| 6.2  | `check_tap_directories` | Archive — no files                | ________  | ________        |
| 6.3  | `check_tap_directories` | Collect — over threshold          | ________  | ________        |
| 6.4  | `check_tap_directories` | Collect — under threshold         | ________  | ________        |
| 6.5  | `check_tap_directories` | Per-SPID split check              | ________  | ________        |
| 7.1  | `generate_hourly_reports` | Reports generated & emailed     | ________  | ________        |
| 7.2  | `generate_hourly_reports` | Zero-RSERC alert (run > 1)      | ________  | ________        |
| 7.3  | `generate_hourly_reports` | Zero-RSERC — first run          | ________  | ________        |
| 8.1  | `check_rserc_failures`  | Process running (skip)            | ________  | ________        |
| 8.2  | `check_rserc_failures`  | .don files detected               | ________  | ________        |
| 8.3  | `check_rserc_failures`  | .tmp files + recovery             | ________  | ________        |
| 8.4  | `check_rserc_failures`  | Clean state (no alerts)           | ________  | ________        |
| 9.1  | `main`                  | Startup sequence                  | ________  | ________        |
| 9.2  | `main`                  | Exit at hour 23                   | ________  | ________        |
| 10.1 | `cleanup_and_exit`      | Normal cleanup                    | ________  | ________        |
| 10.2 | `cleanup_and_exit`      | Double-call guard                 | ________  | ________        |
| 11.1 | Entry-point guard       | Sourcing does not execute main    | ________  | ________        |
| 11.2 | Entry-point guard       | Direct execution runs main        | ________  | ________        |

---

**Sign-off:**

| Role           | Name              | Date       | Signature  |
|----------------|-------------------|------------|------------|
| Tester         | _________________ | __________ | __________ |
| Reviewer       | _________________ | __________ | __________ |
| Approver       | _________________ | __________ | __________ |
