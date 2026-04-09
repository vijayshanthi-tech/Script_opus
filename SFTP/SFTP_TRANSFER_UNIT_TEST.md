# SFTP_TRANSFER — Unit Test Document

| Field          | Value                                        |
|----------------|----------------------------------------------|
| Scripts        | `generic_sftp.sh`, `param_generic_sftp.sh`   |
| VMS Originals  | `SFTP_TRANSFER.COM` (two variants)           |
| Test Platform  | Linux / Bash 4+                              |
| Tester         | ____________________________                  |
| Test Date      | ____________________________                  |

---

## How to Source the Scripts for Testing

Both scripts contain an entry-point guard that prevents `main()` from executing
when sourced. This allows individual functions to be tested in isolation:

```bash
# Set up a temporary test environment
export WORK_DIR="/tmp/sftp_test_$$"
export SFTP_CFG_DIR="/tmp/sftp_test_cfg_$$"
export SFTP_LOG_DIR="/tmp/sftp_test_log_$$"
export LOG_FILE="${SFTP_LOG_DIR}/test.log"
export LOCK_DIR="/tmp"
mkdir -p "${WORK_DIR}" "${SFTP_CFG_DIR}" "${SFTP_LOG_DIR}"

# Source the config-driven variant (does NOT execute main)
source /path/to/generic_sftp.sh

# OR source the param-driven variant
source /path/to/param_generic_sftp.sh
```

All functions are now available to call directly.

---

## Test Prerequisites (Global)

| Prerequisite        | Required For            | How to Verify                      |
|---------------------|-------------------------|------------------------------------|
| Bash 4+             | All functions           | `bash --version`                   |
| `sftp` (OpenSSH)    | run_sftp_transfer       | `which sftp`                       |
| `gzip`              | action_on_success (GZ)  | `which gzip`                       |
| `flock`             | check_singleton         | `which flock` or `flock --version` |
| `find`, `cp`, `mv`  | Multiple functions      | Available in coreutils (standard)  |
| SSH key configured   | push_sftp, pull_sftp    | `ssh -o BatchMode=yes user@host exit` |

---

## PART A: Config-Driven Variant (`generic_sftp.sh`)

---

## 1. Function: `log_msg`

### 1.1 Test: Basic Message Logging

**Purpose:** Verify that `log_msg` writes a timestamped message to both stdout and the log file.

**Test Steps:**
1. Source the script (see "How to Source" above)
2. Run: `log_msg "Test SFTP log message"`
3. Check stdout for the message
4. Check the log file: `tail -1 "${LOG_FILE}"`

**Inputs Required:**
| Input        | Value                     |
|--------------|---------------------------|
| `$1` (msg)   | `"Test SFTP log message"` |
| `LOG_FILE`   | `${SFTP_LOG_DIR}/test.log` |

**Expected Output:**
- stdout: `DD-Mon-YYYY HH:MM:SS - Test SFTP log message`
- Log file last line: same as stdout

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

### 1.2 Test: Log File Append (Not Overwrite)

**Purpose:** Verify that `log_msg` appends to the log file.

**Test Steps:**
1. Source the script
2. Run: `log_msg "First message"`
3. Run: `log_msg "Second message"`
4. Check: `wc -l < "${LOG_FILE}"` → should be 2
5. Check: `grep "First" "${LOG_FILE}"` → should exist
6. Check: `grep "Second" "${LOG_FILE}"` → should exist

**Expected Output:**
- Log file contains 2 lines

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

## 2. Function: `log_error`

### 2.1 Test: Structured Error Message

**Purpose:** Verify that `log_error` produces the correct format.

**Test Steps:**
1. Source the script
2. Set: `CfgFileID="RSERC_SFTP.CFG"`
3. Run: `log_error "SFTP_PARAMETERS" "DestHostname is blank"`
4. Check log for: `*** generic_sftp - SFTP_PARAMETERS,(RSERC_SFTP.CFG) DestHostname is blank`

**Inputs Required:**
| Input        | Value                          |
|--------------|--------------------------------|
| `$1` (phase) | `"SFTP_PARAMETERS"`           |
| `$2` (detail)| `"DestHostname is blank"`     |
| `CfgFileID`  | `"RSERC_SFTP.CFG"`           |

**Expected Output:**
- Log contains: `*** generic_sftp - SFTP_PARAMETERS,(RSERC_SFTP.CFG) DestHostname is blank`

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

## 3. Function: `check_singleton`

### 3.1 Test: Lock Acquisition (First Instance)

**Purpose:** Verify that the first instance acquires the lock successfully.

**Test Steps:**
1. Source the script
2. Set: `CfgFileID="TEST_LOCK.CFG"` and `LOCK_DIR="/tmp"`
3. Run: `check_singleton`
4. Check: `echo $?` → should be 0

**Expected Output:**
- Return code 0 (lock acquired)

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 3.2 Test: Lock Contention (Second Instance)

**Purpose:** Verify that a second instance with the same config is rejected.

**Test Steps:**
1. In Terminal 1: Source and `check_singleton` with `CfgFileID="TEST_LOCK.CFG"`
2. In Terminal 2: Source and `check_singleton` with same `CfgFileID`
3. Check Terminal 2: `echo $?` → should be 1
4. Check log for: "is already running"

**Inputs Required:**
| Input        | Value                |
|--------------|----------------------|
| `CfgFileID`  | `"TEST_LOCK.CFG"` (same in both terminals) |

**Expected Output:**
- Terminal 1: return 0 (lock acquired)
- Terminal 2: return 1, log message about lock failure

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 3.3 Test: Different Configs Don't Conflict

**Purpose:** Verify that different config files can run simultaneously.

**Test Steps:**
1. Terminal 1: `CfgFileID="CONFIG_A.CFG"` → `check_singleton` → expect 0
2. Terminal 2: `CfgFileID="CONFIG_B.CFG"` → `check_singleton` → expect 0

**Expected Output:**
- Both return 0 (different lock files)

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

## 4. Function: `validate_environment`

### 4.1 Test: SFTP_CFG_DIR Set and Exists

**Purpose:** Verify success when SFTP_CFG_DIR is properly configured.

**Test Steps:**
1. Set: `export SFTP_CFG_DIR="/tmp/sftp_test_cfg"`
2. Create dir: `mkdir -p "${SFTP_CFG_DIR}"`
3. Source and run: `validate_environment`
4. Check: `echo $?` → should be 0

**Expected Output:**
- Return code 0

**Actual Output:**
```
____________________________________________________________________
```

---

### 4.2 Test: SFTP_CFG_DIR Not Set

**Purpose:** Verify error when SFTP_CFG_DIR is not defined.

**Test Steps:**
1. Set: `export SFTP_CFG_DIR=""`
2. Source and run: `validate_environment`
3. Check: `echo $?` → should be 1
4. Check log for: "SFTP_CFG_DIR environment variable not defined"

**Expected Output:**
- Return code 1; error logged

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 4.3 Test: SFTP_CFG_DIR Does Not Exist

**Purpose:** Verify error when SFTP_CFG_DIR points to a non-existent directory.

**Test Steps:**
1. Set: `export SFTP_CFG_DIR="/nonexistent/path"`
2. Source and run: `validate_environment`
3. Check: `echo $?` → should be 1
4. Check log for: "SFTP_CFG_DIR directory does not exist"

**Expected Output:**
- Return code 1; error logged

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

## 5. Function: `validate_params`

### 5.1 Test: Valid Parameters (Push)

**Purpose:** Verify success with valid push configuration.

**Test Steps:**
1. Create config file:
   ```bash
   echo "SftpType:push" > "${SFTP_CFG_DIR}/VALID.CFG"
   ```
2. Set: `CfgFileID="VALID.CFG"` and `ActionOnSuccess="DELETE"`
3. Run: `validate_params`
4. Check: `echo $?` → 0

**Expected Output:**
- Return 0; ActionOnSuccess = "DELETE"

**Actual Output:**
```
____________________________________________________________________
```

---

### 5.2 Test: Empty Config File ID

**Purpose:** Verify error when CfgFileID is empty.

**Test Steps:**
1. Set: `CfgFileID=""`
2. Run: `validate_params`
3. Check: `echo $?` → 1
4. Check log for: "Config file parameter (P1) is empty"

**Expected Output:**
- Return 1; error logged

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 5.3 Test: Config File Not Found

**Purpose:** Verify error when the config file does not exist.

**Test Steps:**
1. Set: `CfgFileID="NONEXISTENT.CFG"`
2. Run: `validate_params`
3. Check: `echo $?` → 1
4. Check log for: "Config file not found"

**Expected Output:**
- Return 1; error logged

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 5.4 Test: Invalid ActionOnSuccess

**Purpose:** Verify error when ActionOnSuccess is invalid.

**Test Steps:**
1. Create: `echo "test" > "${SFTP_CFG_DIR}/TEST.CFG"`
2. Set: `CfgFileID="TEST.CFG"` and `ActionOnSuccess="INVALID"`
3. Run: `validate_params`
4. Check: `echo $?` → 1
5. Check log for: "Invalid ActionOnSuccess"

**Expected Output:**
- Return 1; error logged

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 5.5 Test: Default ActionOnSuccess (NOCHANGE)

**Purpose:** Verify that empty ActionOnSuccess defaults to NOCHANGE.

**Test Steps:**
1. Create: `echo "test" > "${SFTP_CFG_DIR}/DEF.CFG"`
2. Set: `CfgFileID="DEF.CFG"` and `ActionOnSuccess=""`
3. Run: `validate_params`
4. Check: `echo "${ActionOnSuccess}"` → "NOCHANGE"

**Expected Output:**
- ActionOnSuccess = "NOCHANGE"

**Actual Output:**
```
____________________________________________________________________
```

---

### 5.6 Test: Extension ActionOnSuccess (.COPIED)

**Purpose:** Verify that extension-style ActionOnSuccess is accepted.

**Test Steps:**
1. Create: `echo "test" > "${SFTP_CFG_DIR}/EXT.CFG"`
2. Set: `CfgFileID="EXT.CFG"` and `ActionOnSuccess=".COPIED"`
3. Run: `validate_params`
4. Check: `echo $?` → 0

**Expected Output:**
- Return 0

**Actual Output:**
```
____________________________________________________________________
```

---

## 6. Function: `parse_config_file`

### 6.1 Test: Full Push Configuration

**Purpose:** Verify all push config values are correctly parsed.

**Test Steps:**
1. Create config file:
   ```bash
   cat > "${SFTP_CFG_DIR}/PUSH_TEST.CFG" << 'EOF'
   ! Push transfer configuration
   SftpType:push
   DestHostname:sftp.example.com
   DestUsername:tapuser
   DestDir:/remote/incoming
   SrcDir:/tmp/sftp_test_src
   DestFileName:*.dat
   DestFilePattern:CDR_*
   DestFilePermission:644
   RetryAttempts:5
   RetryWaitSeconds:30
   EOF
   mkdir -p /tmp/sftp_test_src
   ```
2. Set: `CfgFileID="PUSH_TEST.CFG"`
3. Run: `parse_config_file`
4. Verify: `echo "${SftpType}" "${DestHostname}" "${DestUsername}" "${RetryAttempts}"`

**Expected Output:**
- SftpType=push, DestHostname=sftp.example.com, DestUsername=tapuser
- DestDir=/remote/incoming, DestFileName=*.dat, DestFilePermission=644
- RetryAttempts=5, RetryWaitSeconds=30

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
____________________________________________________________________
```

---

### 6.2 Test: Full Pull Configuration

**Purpose:** Verify all pull config values are correctly parsed.

**Test Steps:**
1. Create config file:
   ```bash
   cat > "${SFTP_CFG_DIR}/PULL_TEST.CFG" << 'EOF'
   SftpType:pull
   DestHostname:sftp.partner.com
   DestUsername:pulluser
   PullSrcDir:/remote/outgoing
   PullDestDir:/tmp/sftp_test_dest
   PullFilePattern:*.csv
   RetryAttempts:2
   RetryWaitSeconds:10
   EOF
   mkdir -p /tmp/sftp_test_dest
   ```
2. Set: `CfgFileID="PULL_TEST.CFG"`
3. Run: `parse_config_file`
4. Verify all variables

**Expected Output:**
- SftpType=pull, PullSrcDir=/remote/outgoing, PullDestDir=/tmp/sftp_test_dest
- PullFilePattern=*.csv, RetryAttempts=2

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 6.3 Test: Missing Mandatory Field (DestHostname)

**Purpose:** Verify error when DestHostname is missing from config.

**Test Steps:**
1. Create config without DestHostname:
   ```bash
   cat > "${SFTP_CFG_DIR}/BAD.CFG" << 'EOF'
   SftpType:push
   DestUsername:user
   SrcDir:/tmp
   DestDir:/remote
   DestFileName:*.txt
   EOF
   ```
2. Set: `CfgFileID="BAD.CFG"`
3. Run: `parse_config_file`
4. Check: `echo $?` → 1
5. Check log for: "Mandatory field (DestHostname)"

**Expected Output:**
- Return 1; error about missing DestHostname

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 6.4 Test: Comment Lines Skipped

**Purpose:** Verify that lines starting with `!` are ignored.

**Test Steps:**
1. Create config with many comment lines:
   ```bash
   cat > "${SFTP_CFG_DIR}/COMMENT.CFG" << 'EOF'
   ! This is a comment
   SftpType:push
   ! Another comment
   DestHostname:host.example.com
   DestUsername:user
   ! DestHostname:wrong.host.com
   SrcDir:/tmp/sftp_test_src
   DestDir:/remote
   DestFileName:*.txt
   EOF
   mkdir -p /tmp/sftp_test_src
   ```
2. Set: `CfgFileID="COMMENT.CFG"`
3. Run: `parse_config_file`
4. Check: `echo "${DestHostname}"` → "host.example.com" (not "wrong.host.com")

**Expected Output:**
- DestHostname = "host.example.com"

**Actual Output:**
```
____________________________________________________________________
```

---

### 6.5 Test: Default RetryAttempts/RetryWaitSeconds

**Purpose:** Verify defaults are applied when RetryAttempts/RetryWaitSeconds are not in config.

**Test Steps:**
1. Create config without retry settings:
   ```bash
   cat > "${SFTP_CFG_DIR}/NORETRY.CFG" << 'EOF'
   SftpType:push
   DestHostname:host.com
   DestUsername:user
   SrcDir:/tmp/sftp_test_src
   DestDir:/remote
   DestFileName:*.dat
   EOF
   mkdir -p /tmp/sftp_test_src
   ```
2. Run: `parse_config_file`
3. Check: `echo "${RetryAttempts}"` → 3 and `echo "${RetryWaitSeconds}"` → 60

**Expected Output:**
- RetryAttempts=3, RetryWaitSeconds=60

**Actual Output:**
```
____________________________________________________________________
```

---

### 6.6 Test: Invalid SftpType

**Purpose:** Verify error when SftpType is invalid.

**Test Steps:**
1. Create config with invalid SftpType:
   ```bash
   echo "SftpType:invalid" > "${SFTP_CFG_DIR}/BADTYPE.CFG"
   echo "DestHostname:host" >> "${SFTP_CFG_DIR}/BADTYPE.CFG"
   echo "DestUsername:user" >> "${SFTP_CFG_DIR}/BADTYPE.CFG"
   ```
2. Set: `CfgFileID="BADTYPE.CFG"`
3. Run: `parse_config_file`
4. Check: `echo $?` → 1
5. Check log for: "Invalid or missing SftpType"

**Expected Output:**
- Return 1; error logged

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

## 7. Function: `action_on_success`

### 7.1 Test: DELETE Action

**Purpose:** Verify that the file is deleted when ActionOnSuccess=DELETE.

**Test Steps:**
1. Create test file: `echo "data" > /tmp/sftp_test_del.txt`
2. Set: `ActionOnSuccess="DELETE"`
3. Run: `action_on_success "/tmp/sftp_test_del.txt"`
4. Check: `ls /tmp/sftp_test_del.txt` → file should not exist

**Expected Output:**
- File deleted

**Actual Output:**
```
____________________________________________________________________
```

---

### 7.2 Test: GZ Action

**Purpose:** Verify that the file is compressed when ActionOnSuccess=GZ.

**Test Steps:**
1. Create test file: `echo "compress me" > /tmp/sftp_test_gz.txt`
2. Set: `ActionOnSuccess="GZ"`
3. Run: `action_on_success "/tmp/sftp_test_gz.txt"`
4. Check: `ls /tmp/sftp_test_gz.txt.gz` → should exist
5. Check: `ls /tmp/sftp_test_gz.txt` → should NOT exist

**Expected Output:**
- `/tmp/sftp_test_gz.txt.gz` exists; original deleted

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 7.3 Test: NOCHANGE Action

**Purpose:** Verify that the file is untouched when ActionOnSuccess=NOCHANGE.

**Test Steps:**
1. Create test file: `echo "leave me" > /tmp/sftp_test_nc.txt`
2. Set: `ActionOnSuccess="NOCHANGE"`
3. Record: `md5sum /tmp/sftp_test_nc.txt`
4. Run: `action_on_success "/tmp/sftp_test_nc.txt"`
5. Check: `md5sum /tmp/sftp_test_nc.txt` → same as step 3

**Expected Output:**
- File unchanged, same checksum

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 7.4 Test: Extension Rename (.COPIED)

**Purpose:** Verify that the file is renamed with the extension.

**Test Steps:**
1. Create test file: `echo "rename me" > /tmp/sftp_test_ren.txt`
2. Set: `ActionOnSuccess=".COPIED"`
3. Run: `action_on_success "/tmp/sftp_test_ren.txt"`
4. Check: `ls /tmp/sftp_test_ren.txt.COPIED` → should exist
5. Check: `ls /tmp/sftp_test_ren.txt` → should NOT exist

**Expected Output:**
- File renamed to `.COPIED` extension

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 7.5 Test: Non-Existent File (Graceful)

**Purpose:** Verify no error when the file does not exist.

**Test Steps:**
1. Run: `action_on_success "/tmp/nonexistent_file"`
2. Check: `echo $?` → 0 (no error)

**Expected Output:**
- Returns 0 without error

**Actual Output:**
```
____________________________________________________________________
```

---

## 8. Function: `run_sftp_transfer`

### 8.1 Test: Successful Transfer (Mock)

**Purpose:** Verify behaviour when sftp succeeds.

**Test Steps:**
1. Create a mock `sftp` that always succeeds:
   ```bash
   mkdir -p /tmp/mock_bin
   cat > /tmp/mock_bin/sftp << 'MOCK'
   #!/bin/bash
   echo "MOCK_SFTP: $@" >> /tmp/sftp_mock.log
   exit 0
   MOCK
   chmod +x /tmp/mock_bin/sftp
   export PATH="/tmp/mock_bin:$PATH"
   ```
2. Create batch file: `echo "exit" > /tmp/test_batch.sftp`
3. Set: `DestUsername="testuser"`, `DestHostname="testhost"`, `RetryAttempts=3`
4. Run: `run_sftp_transfer "/tmp/test_batch.sftp"`
5. Check: `echo $?` → 0
6. Check log for: "SFTP transfer succeeded"

**Expected Output:**
- Return 0; log shows success on first attempt

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 8.2 Test: All Retries Exhausted (Mock)

**Purpose:** Verify behaviour when sftp always fails.

**Test Steps:**
1. Create a mock `sftp` that always fails:
   ```bash
   cat > /tmp/mock_bin/sftp << 'MOCK'
   #!/bin/bash
   exit 1
   MOCK
   chmod +x /tmp/mock_bin/sftp
   export PATH="/tmp/mock_bin:$PATH"
   ```
2. Create batch file: `echo "exit" > /tmp/test_batch.sftp`
3. Set: `RetryAttempts=2`, `RetryWaitSeconds=1`
4. Run: `run_sftp_transfer "/tmp/test_batch.sftp"`
5. Check: `echo $?` → 1
6. Check log for: "All 2 SFTP attempts failed"

**Expected Output:**
- Return 1; 2 attempts logged then failure

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 8.3 Test: Retry Then Succeed (Mock)

**Purpose:** Verify that a transient failure followed by success works.

**Test Steps:**
1. Create a mock `sftp` that fails once then succeeds:
   ```bash
   cat > /tmp/mock_bin/sftp << 'MOCK'
   #!/bin/bash
   COUNTER_FILE="/tmp/sftp_attempt_counter"
   if [ ! -f "${COUNTER_FILE}" ]; then echo 0 > "${COUNTER_FILE}"; fi
   COUNT=$(cat "${COUNTER_FILE}")
   COUNT=$((COUNT + 1))
   echo ${COUNT} > "${COUNTER_FILE}"
   if [ ${COUNT} -lt 2 ]; then exit 1; fi
   exit 0
   MOCK
   chmod +x /tmp/mock_bin/sftp
   echo 0 > /tmp/sftp_attempt_counter
   ```
2. Set: `RetryAttempts=3`, `RetryWaitSeconds=1`
3. Run: `run_sftp_transfer "/tmp/test_batch.sftp"`
4. Check: `echo $?` → 0

**Expected Output:**
- Return 0; first attempt fails, second succeeds

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

## 9. Function: `housekeep`

### 9.1 Test: Old Batch Files Deleted

**Purpose:** Verify that `.sftp` files older than 2 days are cleaned up.

**Test Steps:**
1. Create old batch files:
   ```bash
   touch -d "3 days ago" "${SFTP_CFG_DIR}/old_batch.sftp"
   touch "${SFTP_CFG_DIR}/new_batch.sftp"
   ```
2. Run: `housekeep`
3. Check: `ls "${SFTP_CFG_DIR}/old_batch.sftp"` → should NOT exist
4. Check: `ls "${SFTP_CFG_DIR}/new_batch.sftp"` → should still exist

**Expected Output:**
- Old file deleted, new file retained

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 9.2 Test: Work Directory Removed

**Purpose:** Verify that WORK_DIR is cleaned up.

**Test Steps:**
1. Create: `mkdir -p "${WORK_DIR}" && touch "${WORK_DIR}/tempfile"`
2. Run: `housekeep`
3. Check: `ls -d "${WORK_DIR}"` → should NOT exist

**Expected Output:**
- WORK_DIR removed

**Actual Output:**
```
____________________________________________________________________
```

---

## 10. Function: `push_sftp` (Integration)

### 10.1 Test: Push with Mock SFTP

**Purpose:** End-to-end push test with a mock sftp command.

**Test Steps:**
1. Set up mock sftp (see 8.1)
2. Create source files:
   ```bash
   mkdir -p /tmp/sftp_push_src
   echo "file1 data" > /tmp/sftp_push_src/CDR001.dat
   echo "file2 data" > /tmp/sftp_push_src/CDR002.dat
   ```
3. Set globals:
   ```bash
   SrcDir="/tmp/sftp_push_src"
   DestFileName="*.dat"
   DestDir="/remote/incoming"
   DestFilePattern=""
   DestFilePermission="775"
   ActionOnSuccess="NOCHANGE"
   DestUsername="testuser"
   DestHostname="testhost"
   RetryAttempts=1
   RetryWaitSeconds=1
   ```
4. Run: `push_sftp`
5. Check log for: "Starting PUSH operation"
6. Check: `/tmp/sftp_mock.log` for mock sftp calls
7. Check: both .dat files still exist (NOCHANGE)

**Expected Output:**
- 2 SFTP calls (one per file); both source files retained

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
____________________________________________________________________
```

---

### 10.2 Test: Push with No Matching Files

**Purpose:** Verify graceful handling when no files match the pattern.

**Test Steps:**
1. Set: `SrcDir="/tmp/sftp_push_src"`, `DestFileName="*.xyz"` (no matches)
2. Run: `push_sftp`
3. Check log for: "No files matching '*.xyz' found"

**Expected Output:**
- Informational log message, no error

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 10.3 Test: Push with DELETE Action

**Purpose:** Verify that source files are deleted after successful push.

**Test Steps:**
1. Create: `echo "del me" > /tmp/sftp_push_src/DELETE_ME.dat`
2. Set: `ActionOnSuccess="DELETE"`, `DestFileName="DELETE_ME.dat"`
3. Run: `push_sftp`
4. Check: `ls /tmp/sftp_push_src/DELETE_ME.dat` → should NOT exist

**Expected Output:**
- File deleted after push

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

## 11. Function: `pull_sftp` (Integration)

### 11.1 Test: Pull with Mock SFTP

**Purpose:** End-to-end pull test with mock sftp that creates files.

**Test Steps:**
1. Create a mock sftp that simulates file download:
   ```bash
   cat > /tmp/mock_bin/sftp << 'MOCK'
   #!/bin/bash
   # Parse -b flag to find batch file
   while getopts "b:" opt; do
       case $opt in b) BATCH="$OPTARG" ;; esac
   done
   # Find lcd directory in batch and create a test file there
   LCD_DIR=$(grep "lcd" "${BATCH}" | sed 's/lcd "\(.*\)"/\1/')
   if [ -n "${LCD_DIR}" ]; then
       echo "pulled data" > "${LCD_DIR}/test_pull.csv"
   fi
   exit 0
   MOCK
   chmod +x /tmp/mock_bin/sftp
   ```
2. Set globals:
   ```bash
   PullSrcDir="/remote/outgoing"
   PullDestDir="/tmp/sftp_pull_dest"
   PullTempDir="${WORK_DIR}/pull_tmp"
   PullFilePattern="*.csv"
   ActionOnSuccess="NOCHANGE"
   DestUsername="pulluser"
   DestHostname="remotehost"
   RetryAttempts=1
   RetryWaitSeconds=1
   mkdir -p "${PullDestDir}" "${PullTempDir}"
   ```
3. Run: `pull_sftp`
4. Check: `ls "${PullDestDir}/test_pull.csv"` → should exist

**Expected Output:**
- File pulled and copied to destination

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
____________________________________________________________________
```

---

### 11.2 Test: Pull — No Files on Remote

**Purpose:** Verify graceful handling when no files are pulled.

**Test Steps:**
1. Use mock sftp that does nothing (creates no files):
   ```bash
   cat > /tmp/mock_bin/sftp << 'MOCK'
   #!/bin/bash
   exit 0
   MOCK
   chmod +x /tmp/mock_bin/sftp
   ```
2. Set: `PullFilePattern="*.xyz"` (nothing will match)
3. Run: `pull_sftp`
4. Check log for: "files for pull are not present in the remote server"

**Expected Output:**
- Informational log message, no error

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

## PART B: Parameter-Driven Variant (`param_generic_sftp.sh`)

---

## 12. Functions Shared with Config-Driven Variant

The following functions are identical between both variants and are tested above:
- `log_msg` (Section 1)
- `log_error` (Section 2)
- `check_singleton` (Section 3)
- `run_sftp_transfer` (Section 8)
- `action_on_success` (Section 7)
- `housekeep` (Section 9)

Only the differences are tested below.

---

## 13. Function: `validate_params` (Param Variant)

### 13.1 Test: Valid Push Parameters

**Purpose:** Verify validation passes for valid push params.

**Test Steps:**
1. Source `param_generic_sftp.sh`
2. Create: `echo "DestHostname:host" > "${SFTP_CFG_DIR}/PARAM.CFG"`
3. Set:
   ```bash
   CfgFileID="PARAM.CFG"
   SftpType="push"
   SrcDir="/tmp/sftp_push_src"
   DestFileName="*.dat"
   ActionOnSuccess="DELETE"
   mkdir -p /tmp/sftp_push_src
   touch /tmp/sftp_push_src/test.dat
   ```
4. Run: `validate_params`
5. Check: `echo $?` → 0

**Expected Output:**
- Return 0

**Actual Output:**
```
____________________________________________________________________
```

---

### 13.2 Test: Missing SrcDir for Push

**Purpose:** Verify error when SrcDir is empty for push.

**Test Steps:**
1. Set: `SftpType="push"`, `SrcDir=""`
2. Run: `validate_params`
3. Check: `echo $?` → 1
4. Check log for: "Mandatory field (SrcDir) is not passed as parameter properly"

**Expected Output:**
- Return 1; error logged

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 13.3 Test: Missing PullFilePattern for Pull

**Purpose:** Verify error when PullFilePattern is empty for pull.

**Test Steps:**
1. Set: `SftpType="pull"`, `PullDestDir="/tmp/test"`, `PullFilePattern=""`
2. Run: `validate_params`
3. Check: `echo $?` → 1
4. Check log for: "Mandatory field (PullFilePattern) is not passed as parameter properly"

**Expected Output:**
- Return 1; error logged

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

### 13.4 Test: Invalid SftpType ("both" Not Allowed)

**Purpose:** Verify that "both" is not accepted in the param variant.

**Test Steps:**
1. Set: `SftpType="both"`
2. Run: `validate_params`
3. Check: `echo $?` → 1
4. Check log for: "Invalid SftpType (P2)"

**Expected Output:**
- Return 1; error logged

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

## 14. Function: `parse_config_file` (Param Variant)

### 14.1 Test: Only Host/User/Dir Read from Config

**Purpose:** Verify that param variant reads only DestHostname, DestUsername, DestDir, TransferType, PullSrcDir.

**Test Steps:**
1. Create config with many keys (some of which should be ignored):
   ```bash
   cat > "${SFTP_CFG_DIR}/MIXED.CFG" << 'EOF'
   SftpType:pull
   DestHostname:host.example.com
   DestUsername:remoteuser
   DestDir:/remote/path
   PullSrcDir:/remote/src
   SrcDir:/should/be/ignored
   DestFileName:should_be_ignored.dat
   PullDestDir:/should/be/ignored
   PullFilePattern:ignored*.csv
   RetryAttempts:99
   EOF
   ```
2. Source `param_generic_sftp.sh`
3. Set: `CfgFileID="MIXED.CFG"`, `SftpType="pull"`
4. Run: `parse_config_file`
5. Check:
   - `echo "${DestHostname}"` → "host.example.com" (read)
   - `echo "${DestUsername}"` → "remoteuser" (read)
   - `echo "${PullSrcDir}"` → "/remote/src" (read)
   - `echo "${RetryAttempts}"` → 3 (NOT 99 — param variant ignores this key)

**Expected Output:**
- Only the expected keys are read from config; others retain their defaults

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
____________________________________________________________________
```

---

## 15. End-to-End Integration Tests

### 15.1 Test: Config-Driven Full Push Cycle (Mock)

**Purpose:** Full `main` execution for push with mock sftp.

**Test Steps:**
1. Set up mock sftp, create config file, create source files
2. Run: `./generic_sftp.sh PUSH_TEST.CFG DELETE`
3. Verify:
   - Log shows "has started", "PUSH operation", "SFTP transfer succeeded", "has completed"
   - Source files are deleted (ActionOnSuccess=DELETE)
   - Lock file cleaned up

**Expected Output:**
- Clean execution, all phases logged

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
____________________________________________________________________
```

---

### 15.2 Test: Param-Driven Full Push Cycle (Mock)

**Purpose:** Full `main` execution for parameter-driven push.

**Test Steps:**
1. Run: `./param_generic_sftp.sh CFG.cfg push /tmp/src "*.dat" "" NOCHANGE`
2. Verify similar to 15.1

**Expected Output:**
- Clean execution with parameters from command line

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
____________________________________________________________________
```

---

### 15.3 Test: Error Exit — Missing Environment

**Purpose:** Verify clean error exit when SFTP_CFG_DIR is not set.

**Test Steps:**
1. Unset: `unset SFTP_CFG_DIR`
2. Run: `./generic_sftp.sh TEST.CFG NOCHANGE`
3. Check: exit code = 1
4. Check log for: "SFTP_CFG_DIR environment variable not defined"

**Expected Output:**
- Exit 1; error logged; housekeeping runs

**Actual Output:**
```
____________________________________________________________________
____________________________________________________________________
```

---

## 16. Cleanup

After all testing is complete, remove temporary test artifacts:

```bash
rm -rf /tmp/sftp_test* /tmp/param_sftp_* /tmp/mock_bin
rm -f /tmp/sftp_mock.log /tmp/sftp_attempt_counter
rm -f /tmp/generic_sftp_*.lock /tmp/param_sftp_*.lock
```
