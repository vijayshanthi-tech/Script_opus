# SFTP_TRANSFER — Comprehensive Technical Document

**Script Names:** `generic_sftp.sh` and `param_generic_sftp.sh` (Linux Bash)
**Converted From:** `SFTP_TRANSFER.COM` — two variants (OpenVMS DCL)
**Description:** Generic SFTP file transfer utilities for pushing/pulling files to/from remote servers with retry logic, housekeeping, and configurable post-transfer actions.

---

## 1. Overview

### What is this system?

The SFTP Transfer scripts are **generic file transfer utilities** used across the TAP (Transferred Account Procedure) telecom billing environment. They handle all SFTP-based file movement between the TAP processing server and external/partner servers — both uploading (push) and downloading (pull) of billing data files.

### Background: What is VMS and DCL?

- **VMS (Virtual Memory System)**, also called **OpenVMS**, is an operating system developed by Digital Equipment Corporation (DEC). It was widely used in telecom and banking for its stability and security. It is **not** Unix/Linux — it has its own file system, command language, batch queue system, and process management.
- **DCL (Digital Command Language)** is the scripting/command language of VMS — analogous to Bash on Linux. DCL scripts have the `.COM` extension and every command line starts with `$`.
- **Logical names** (VMS) are similar to Linux environment variables. For example, `SFTP_CFG_DIR:RSERC_SFTP.CFG` means `SFTP_CFG_DIR` is a logical name pointing to a directory, and `RSERC_SFTP.CFG` is the file within it.
- **VMS file versioning**: VMS keeps multiple versions of every file (`;1`, `;2`, etc.). `DEL file;*` deletes all versions. Linux has no equivalent.
- **VMS process names**: VMS allows renaming running processes — used here as a singleton locking mechanism. There is no direct Linux equivalent; we use `flock` instead.

### What problem does it solve?

In the TAP billing pipeline, files must be securely transferred between:
- The TAP processing server and partner operators (RSERC files, CDR files)
- The TAP server and internal systems (FCS files, reports)
- Staging areas and production directories

The SFTP Transfer scripts provide:
- **Configurable push and pull** — A single script handles both directions, driven by configuration
- **Atomic uploads** — Files are uploaded with a `.SFTP_TMP` extension, then renamed on the remote server to prevent partial-file processing
- **Retry logic** — Failed transfers are retried a configurable number of times with configurable delays
- **Post-transfer actions** — After successful transfer, the source file can be deleted, compressed, renamed, or left unchanged
- **Singleton protection** — Prevents two instances of the same config from running simultaneously
- **Housekeeping** — Automatic cleanup of temporary batch files and old log files

### Two Variants — When to Use Which

| Variant                    | Script                    | Use When                                                |
|----------------------------|---------------------------|---------------------------------------------------------|
| **Config-driven**          | `generic_sftp.sh`         | Scheduled batch jobs with fixed transfer configurations. All settings live in the `.CFG` file. |
| **Parameter-driven**       | `param_generic_sftp.sh`   | Called from other scripts that dynamically determine source dirs, file patterns, etc. at runtime. Only host/user come from `.CFG`. |

### Where is it used?

These scripts run on a **Linux/RHEL production server** (migrated from OpenVMS) as part of the TAP billing pipeline. They are invoked by:
- Cron jobs for scheduled transfers
- Other TAP processing scripts (`TAP_RSERCFILES_TRANSFER.COM`, etc.)
- Manual execution for ad-hoc transfers

---

## 2. High-Level Workflow

### 2.1 Config-Driven Variant — End-to-End Flow

```
   ┌───────────────────────────────────────────────────────┐
   │   generic_sftp.sh <config_file> [ActionOnSuccess]      │
   └──────────────────────┬────────────────────────────────┘
                          │
                          ▼
   ┌───────────────────────────────────────────────────────┐
   │  VALIDATE ENVIRONMENT                                 │
   │  Check SFTP_CFG_DIR is set and exists                 │
   └──────────────────────┬────────────────────────────────┘
                          │
                          ▼
   ┌───────────────────────────────────────────────────────┐
   │  VALIDATE PARAMETERS                                  │
   │  Check config file exists, ActionOnSuccess is valid    │
   └──────────────────────┬────────────────────────────────┘
                          │
                          ▼
   ┌───────────────────────────────────────────────────────┐
   │  SINGLETON CHECK (flock)                              │
   │  Prevent duplicate runs of same config                │
   └──────────────────────┬────────────────────────────────┘
                          │
                          ▼
   ┌───────────────────────────────────────────────────────┐
   │  PARSE CONFIG FILE                                    │
   │  Read all Key:Value pairs from .CFG                   │
   │  Validate mandatory fields for push/pull              │
   └──────────────────────┬────────────────────────────────┘
                          │
               ┌──────────┴──────────┐
               ▼                     ▼
   ┌───────────────────┐  ┌───────────────────┐
   │  PUSH (if push     │  │  PULL (if pull     │
   │  or both)          │  │  or both)          │
   │                    │  │                    │
   │  For each file:    │  │  1. Clean temp dir  │
   │  1. Create batch   │  │  2. Create batch    │
   │  2. put + rename   │  │  3. get files       │
   │  3. SFTP w/retry   │  │  4. SFTP w/retry    │
   │  4. Action on OK   │  │  5. Copy to dest    │
   └────────┬──────────┘  │  6. Remote action    │
            │              │  7. Clean temp       │
            │              └─────────┬───────────┘
            └──────────┬─────────────┘
                       ▼
   ┌───────────────────────────────────────────────────────┐
   │  CLEAN FINISH                                         │
   │  Housekeep old files, remove work dir, log success    │
   └───────────────────────────────────────────────────────┘
```

### 2.2 Parameter-Driven Variant — Differences

The flow is identical except:
1. **Parameter assignment** happens at the top: `$3`–`$5` are mapped to `SrcDir`/`DestFileName`/`DestFilePattern` (push) or `PullDestDir`/`PullFilePattern` (pull) based on `$2` (SftpType).
2. **Config parsing** reads only `DestHostname`, `DestUsername`, `DestDir`, `TransferType`, and `PullSrcDir` from the `.CFG` file.
3. **SftpType** is always only `push` or `pull` (no "both").

---

## 3. Core Functional Areas

### 3.1 Configuration File Parsing

The `.CFG` file uses a simple `Key:Value` format. Comments start with `!`.

**Config-driven variant** reads all keys:
| Key               | Required For | Description                              |
|-------------------|-------------|------------------------------------------|
| SftpType          | All          | Transfer direction: push, pull, or both  |
| DestHostname      | All          | Remote server hostname/IP                |
| DestUsername      | All          | Remote SSH username                      |
| TransferType      | (legacy)     | A=ASCII, B=Binary (ignored on Linux)     |
| SrcDir            | push/both    | Local source directory                   |
| DestDir           | push/both    | Remote destination directory             |
| DestFileName      | push/both    | Local file name/pattern to transfer      |
| DestFilePattern   | push (opt)   | Rename pattern on remote side            |
| DestFilePermission| push (opt)   | chmod value for remote file (default 775)|
| PullSrcDir        | pull/both    | Remote source directory                  |
| PullDestDir       | pull/both    | Local destination directory              |
| PullTempDir       | pull (opt)   | Local temp staging directory             |
| PullFilePattern   | pull/both    | Remote file pattern to download          |
| RetryAttempts     | (opt)        | Number of retries (default 3)            |
| RetryWaitSeconds  | (opt)        | Seconds between retries (default 60)     |

**Parameter-driven variant** reads only DestHostname, DestUsername, DestDir, TransferType, PullSrcDir from the config.

### 3.2 SFTP Push Operation

The push operation transfers local files to a remote server:

1. **File discovery**: `find ${SrcDir} -name "${DestFileName}"` locates matching files.
2. **Batch creation**: For each file, an SFTP batch command file is built:
   ```
   binary
   cd "/remote/dest/dir"
   put "localfile" "localfile.SFTP_TMP"
   chmod 775 "localfile.SFTP_TMP"
   rename "localfile.SFTP_TMP" "localfile"
   exit
   ```
3. **Transfer**: `sftp -b batchfile user@host` executes with retry loop.
4. **Post-action**: The local source file is processed per ActionOnSuccess.

The `.SFTP_TMP` staging pattern ensures remote consumers never see a partially uploaded file.

### 3.3 SFTP Pull Operation

The pull operation downloads files from a remote server:

1. **Temp cleanup**: Previous files matching PullFilePattern are removed from the temp staging area.
2. **Batch creation**:
   ```
   binary
   cd "/remote/source/dir"
   lcd "/local/temp/dir"
   get *.dat
   exit
   ```
3. **Transfer**: `sftp -b batchfile user@host` with retry.
4. **Copy**: Downloaded files are copied from temp to `PullDestDir`.
5. **Remote action** (optional):
   - `DELETE`: Another SFTP session deletes the original files from the remote server.
   - `.<ext>`: Another SFTP session renames remote files with the extension.
6. **Temp cleanup**: Staging directory is cleaned.

### 3.4 Retry Logic

Both scripts implement a retry loop around SFTP calls:

```
attempt = 0
while attempt < RetryAttempts:
    if sftp -b batch user@host succeeds:
        return SUCCESS
    attempt += 1
    if attempt >= RetryAttempts:
        LOG "All attempts failed"
        return FAILURE
    LOG "Retrying in N seconds"
    sleep RetryWaitSeconds
```

| Variant            | Default Attempts | Default Wait |
|--------------------|-----------------|--------------|
| Config-driven      | 3               | 60 seconds   |
| Parameter-driven   | 3               | 5 seconds    |

### 3.5 Singleton Protection

Prevents duplicate instances of the same config/transfer from running concurrently:

**VMS approach**: `SET PROCESS/NAME=<config>` renames the process. `F$CONTEXT`/`F$PID` checks if another process with that name exists on the cluster node.

**Linux approach**: `flock -n` acquires an exclusive, non-blocking lock on a per-config lock file. If the lock fails, another instance is running.

### 3.6 Housekeeping

Automatic cleanup runs at the end of every execution (success or error):
- Delete `.sftp` batch files older than 2 days from `SFTP_CFG_DIR`
- Delete `GENERIC_SFTP*.log` files older than `SFTP_PURGE_DAYS` (default 10) from `SFTP_LOG_DIR`
- Remove the per-run `WORK_DIR`

---

## 4. Function-by-Function Explanation

---

### 4.1 `log_msg()`

**Purpose:** Writes a timestamped message to both stdout and the log file.

**Input:** `$1` — The message text

**Internal Logic:**
1. Generate timestamp via `date '+%d-%b-%Y %H:%M:%S'`
2. Write `<timestamp> - <message>` to stdout and append to `LOG_FILE` via `tee -a`

**VMS Equivalent:**
```dcl
$ @cell0_com:log_mess "   " "''procname' has started at ''f$time()'" " "
```
On VMS, `log_mess` is a separate shared procedure stored in `cell0_com:`. It provides standardised logging with severity levels. On Linux, this is simplified to a single `tee` call.

**How to Test:**
```bash
export SFTP_CFG_DIR="/tmp/sftp_test"
export LOG_FILE="/tmp/sftp_test/test.log"
mkdir -p "${SFTP_CFG_DIR}"
source /path/to/generic_sftp.sh
log_msg "Test message"
cat "${LOG_FILE}"
# EXPECTED: DD-Mon-YYYY HH:MM:SS - Test message
```

---

### 4.2 `log_error()`

**Purpose:** Writes a structured error message including phase and config file name.

**Input:** `$1` — Phase name; `$2` — Detail message

**Internal Logic:** Calls `log_msg` with formatted string: `*** PROCNAME - PHASE,(CfgFileID) DETAIL`

**VMS Equivalent:**
```dcl
$ @cell0_com:log_mess " ***" "''procname' - ''phase',(''p1' file is ''p2') ''status' " " "
$ request/reply/to='operator' "SFTP-E ''procname' - ''phase',(''p1' file is ''p2') ''status' "
```
VMS logs the error AND sends an operator console alert. On Linux, only logging is performed. Operator alerts should be integrated via monitoring tools.

---

### 4.3 `check_singleton()`

**Purpose:** Prevents duplicate instances of the same config from running.

**Input:** Uses global `CfgFileID` to generate lock file name.

**Internal Logic:**
1. Sanitise config name to alphanumeric (for safe filename)
2. Open a lock file on file descriptor 200
3. Attempt non-blocking `flock -n 200`
4. If lock fails → another instance is running → return 1

**VMS Equivalent:**
```dcl
$ current_process = f$extract(5,15,CfgFileID)
$ gosub set_process_name
```
The VMS `SET_PROCESS_NAME` subroutine:
- `F$CONTEXT("PROCESS", ctx, "PRCNAM", name, "EQL")` — sets up a filter for processes named `name`
- `F$PID(ctx)` — iterates matching processes
- `F$GETJPI(pid, "NODENAME")` — gets the node name of a matching process
- `F$GETJPI(pid, "STATE")` — checks if the process is SUSPENDED
- `SET PROCESS/NAME=name` — renames the current process (acts as a "claim")

This is a cluster-aware check: if the same config is already running on another cluster node, it will also be detected. On Linux, `flock` is node-local only.

**How to Test:**
```bash
# Terminal 1:
source /path/to/generic_sftp.sh
CfgFileID="TEST_CFG"
LOCK_DIR="/tmp"
check_singleton
echo $?   # Should be 0 (lock acquired)

# Terminal 2 (while Terminal 1 holds lock):
source /path/to/generic_sftp.sh
CfgFileID="TEST_CFG"
LOCK_DIR="/tmp"
check_singleton
echo $?   # Should be 1 (lock failed — already running)
```

---

### 4.4 `validate_environment()`

**Purpose:** Checks that required environment variables are set and directories exist.

**Input:** `SFTP_CFG_DIR` environment variable

**Internal Logic:**
1. If `SFTP_CFG_DIR` is empty → error
2. If `SFTP_CFG_DIR` directory doesn't exist → error

**VMS Equivalent:**
```dcl
$ if (F$Trnlnm("SFTP_COM_DIR")) .eqs. "" then ...
$ if (F$Trnlnm("SFTP_CFG_DIR")) .eqs. "" then ...
```
`F$Trnlnm()` translates a logical name. If it returns empty, the logical is not defined. On VMS, both `SFTP_COM_DIR` and `SFTP_CFG_DIR` are checked. On Linux, `SFTP_COM_DIR` is not needed (the script knows its own location via `$0`).

---

### 4.5 `validate_params()`

**Purpose:** Validates command-line parameters before expensive operations begin.

**Input:** Global variables `CfgFileID`, `ActionOnSuccess`, plus `SftpType`, `SrcDir`, `DestFileName`, `PullDestDir`, `PullFilePattern` (param variant only)

**Internal Logic:**
1. Check CfgFileID is non-empty and file exists in `SFTP_CFG_DIR`
2. Validate ActionOnSuccess is one of: DELETE, GZ, NOCHANGE, or starts with `.`
3. (Config variant) Defer type-specific validation to `parse_config_file`
4. (Param variant) Validate SftpType, SrcDir/DestFileName (push), PullDestDir/PullFilePattern (pull)

**VMS Equivalent:**
```dcl
$ IF CfgFileID .eqs. "" THEN ...
$ IF ActionOnSuccess .eqs. "" THEN ActionOnSuccess="NOCHANGE"
$ if ActionOnSuccess .nes. "DELETE" .and. ActionOnSuccess .nes. "GZ" .and. ...
```
The VMS script validates across two phases: `GET_INPUT_PARAMS` (general validation) and `EOF_CFG` (type-specific validation after config parsing). On Linux, these are consolidated.

---

### 4.6 `parse_config_file()`

**Purpose:** Reads and validates the `.CFG` configuration file.

**Input:** `CfgFileID` — filename within `SFTP_CFG_DIR`

**Internal Logic:**
1. Read file line by line (skip `!` comment lines and blank lines)
2. Split each line at `:` into key and value
3. Strip whitespace from value
4. Assign to the appropriate global variable based on key name
5. After parsing, validate:
   - SftpType is push/pull/both (config variant) or already set (param variant)
   - DestHostname, DestUsername are non-empty
   - Push-specific: SrcDir, DestDir, DestFileName are non-empty, SrcDir directory exists
   - Pull-specific: PullFilePattern, PullSrcDir, PullDestDir are non-empty, PullDestDir exists
   - RetryAttempts > 0, RetryWaitSeconds > 0

**VMS Equivalent:**
```dcl
$ open/read param_file tmp_file:
$ read_next_param:
$   read /error=REG_ERROR /end_of_file=eof_cfg param_file parameter_line
$   if f$locate("SftpType:",parameter_line) .eq. 0
$   then
$     SftpType = f$edit(F$EXTRACT(F$LOCATE(":",parameter_line)+1,150,parameter_line),"COLLAPSE")
$     goto read_next_param
$   endif
```
The VMS version uses `F$LOCATE("Key:",line) .EQ. 0` to check if the line starts with the key. `F$EXTRACT` extracts everything after the `:`. `F$EDIT(...,"COLLAPSE")` removes all whitespace.

Key VMS constructs:
- `OPEN/READ` + `READ/END=` + `CLOSE` → replaced by `while IFS= read -r line` loop
- `F$LOCATE(":",line)` → replaced by `${line%%:*}` (Bash parameter expansion)
- `F$EXTRACT(pos,len,str)` → replaced by `${line#*:}` (remove up to first `:`)
- `F$EDIT(str,"COLLAPSE")` → replaced by `tr -d '[:space:]'`

**How to Test:**
```bash
# Create a test config
mkdir -p /tmp/sftp_test
cat > /tmp/sftp_test/TEST.CFG << 'EOF'
! Test config
SftpType:push
DestHostname:testhost.example.com
DestUsername:testuser
DestDir:/remote/dir
SrcDir:/tmp/sftp_test/source
DestFileName:*.txt
RetryAttempts:2
RetryWaitSeconds:5
EOF
mkdir -p /tmp/sftp_test/source
touch /tmp/sftp_test/source/test.txt

export SFTP_CFG_DIR="/tmp/sftp_test"
source /path/to/generic_sftp.sh
CfgFileID="TEST.CFG"
WORK_DIR="/tmp/sftp_test/work"
mkdir -p "${WORK_DIR}"
parse_config_file
echo "SftpType=${SftpType} Host=${DestHostname} User=${DestUsername}"
# EXPECTED: SftpType=push Host=testhost.example.com User=testuser
```

---

### 4.7 `run_sftp_transfer()`

**Purpose:** Executes an SFTP transfer using a batch command file, with configurable retry logic.

**Input:** `$1` — Path to the SFTP batch command file

**Internal Logic:**
1. Loop up to `RetryAttempts` times:
   a. Log the attempt number
   b. Execute `sftp -b <batchfile> <user@host>`
   c. If exit code is 0 → success → delete batch file → return 0
   d. If failed and attempts exhausted → log error → delete batch file → return 1
   e. If failed and attempts remain → log warning → sleep `RetryWaitSeconds` → retry

**VMS Equivalent:**
```dcl
$ RUN_SFTP_TRANSFER:
$   sftp_count = 0
$ SFTP_LOOP:
$   ON ERROR THEN GOTO RE_TRY
$   sftp/batchfile= SFTP_CFG_DIR:'sftp_tmp_file 'sftp_string
$   ON ERROR THEN GOTO reg_error
$   GOTO END_SFTP
$ RE_TRY:
$   sftp_count = sftp_count + 1
$   if sftp_count .ge. RetryAttempts then ...
$   call time_seconds 'RetryWaitSeconds
$   goto sftp_loop
$ END_SFTP:
$   gosub Housekeep1
$   RETURN
```
Key VMS constructs:
- `ON ERROR THEN GOTO RE_TRY` — VMS error trap. If any command fails, execution jumps to `RE_TRY`. On Linux, we check `$?` (the sftp exit code).
- `sftp/batchfile= <file> <user@host>` — VMS SFTP syntax. On Linux: `sftp -b <file> <user@host>`.
- `call time_seconds N` — Calls a subroutine that converts seconds to `HH:MM:SS` and `WAIT`s. On Linux: `sleep N`.
- `sftp_string` — VMS builds quoteduser@host: `"""" + user + "@" + host + """"`. The quadruple quotes (`""""`) produce a literal double-quote in VMS. On Linux, no special quoting needed.

**How to Test:**
```bash
# Create a test batch file that will fail (no real server)
echo "exit" > /tmp/sftp_test_batch.txt
source /path/to/generic_sftp.sh
DestUsername="fake_user"
DestHostname="nonexistent.example.com"
RetryAttempts=2
RetryWaitSeconds=1
run_sftp_transfer "/tmp/sftp_test_batch.txt"
echo "Exit: $?"   # EXPECTED: 1 (failure after 2 retries)
```

---

### 4.8 `action_on_success()`

**Purpose:** Performs the configured post-transfer action on the source file.

**Input:** `$1` — Full path to the source file

**Internal Logic:**
| ActionOnSuccess | Behaviour                                       |
|----------------|-------------------------------------------------|
| `DELETE`       | `rm -f <file>`                                   |
| `GZ`           | `gzip -f <file>`                                |
| `NOCHANGE`     | Do nothing                                       |
| `.<ext>`       | `mv <file> <file>.<ext>` (e.g., `.COPIED`)      |

**VMS Equivalent:**
```dcl
$ ACTION_ON_SUCCESS:
$   if ActionOnSuccess .eqs. "DELETE" then delete /log 'DestFileName';*
$   else if ActionOnSuccess .eqs. "GZ" then
$       gzip :== $sys$system:gzip.exe
$       gzip 'DestFileName'
$       rename 'just_name'-gz 'just_name'-gz-wip
$       rename 'just_name'-gz-wip;* 'just_name'-gz
$   else if F$EXTRACT(0,1,ActionOnSuccess) .eqs. "." then
$       rename /log 'DestFileName' *'ActionOnSuccess'
$   else if ActionOnSuccess .eqs. "NOCHANGE" then
$       rename/lo 'DestFile''sftp_file_tmp' 'DestFile''type'
```

Key differences:
- **GZ on VMS**: The gzip workaround (`-gz` → `-gz-wip` → `-gz`) handles VMS file versioning. Linux `gzip` just creates `file.gz` directly.
- **Rename on VMS**: `rename file *'ActionOnSuccess'` uses VMS wildcard rename (replace extension). On Linux: `mv file file.ext`.
- **NOCHANGE on VMS**: The VMS script renames from `.SFTP_TMP` back to the original name (because it renamed the local file before upload). On Linux, the local file was never renamed, so NOCHANGE truly does nothing.

---

### 4.9 `push_sftp()`

**Purpose:** Uploads all matching files from the local source directory to the remote server.

**Input:** Globals `SrcDir`, `DestFileName`, `DestDir`, `DestFilePattern`, `DestFilePermission`, `ActionOnSuccess`

**Internal Logic:**
1. Use `find "${SrcDir}" -name "${DestFileName}" -type f` to locate source files
2. For each file:
   a. Extract filename via `basename`
   b. Generate SFTP batch commands: cd, put (with `.SFTP_TMP`), chmod, rename, exit
   c. Call `run_sftp_transfer` with the batch file
   d. On success: call `action_on_success` on the local file
   e. On failure: log error and continue with next file
3. If no files found: log informational message

**VMS Equivalent (with detailed breakdown):**
```dcl
$ PUSH_SFTP:
$ IF SftpType .eqs. "push" .OR. SftpType .eqs. "both"
$ THEN
$ nextfile = f$search("RESET_SEARCH_CONTEXT_BOGUS.TMP;0")
```
This searches for a nonexistent file to **reset the VMS search context**. VMS `f$search()` maintains state between calls — if you searched for `*.dat` previously, the next `f$search()` might continue from where it left off. Searching for a bogus file resets this. On Linux, no equivalent is needed.

```dcl
$ set def 'SrcDir
$ FILE_SEARCH_LOOP:
$ nextfile = f$search("''DFile'''type';*",1)
$ if f$length(nextfile) .eq. 0 then goto SEARCH_DONE
$ if f$file_attributes(nextfile,"DIRECTORY") then goto FILE_SEARCH_LOOP
```
- `SET DEF` changes the working directory (like `cd`).
- `f$search(pattern,1)` returns the next matching file in search stream 1.
- Loop continues until `f$length(nextfile) .eq. 0` (no more matches).
- `f$file_attributes(file,"DIRECTORY")` skips directories.

On Linux, `find -type f -print0 | while read -r -d '' file` handles all of this in one pipeline.

```dcl
$ sftp_tmp_file = f$extract(6,32,f$unique())+".SFTP"
$ create/fdl=sys$input sftp_cfg_dir:'sftp_tmp_file'
```
VMS uses `f$unique()` to generate a unique temp filename, then creates the SFTP batch file with specific FDL (File Definition Language) attributes for Stream_LF format. On Linux, simple file creation suffices.

```dcl
$ rename/lo 'DestFile''type' 'DestFile''sftp_file_tmp'
$ write sftp_file "put ''DestFile'''sftp_file_tmp'"
$ write sftp_file "chmod 775 ''DestFile'''sftp_file_tmp'"
$ write sftp_file "rename ''DestFile'''sftp_file_tmp' ''DestFile'''type'"
```
The VMS version renames the LOCAL file to `.SFTP_TMP` before uploading, then the batch commands rename it back on the REMOTE side. The Linux version only uses `.SFTP_TMP` on the remote side (put as `.SFTP_TMP`, then rename remotely).

---

### 4.10 `pull_sftp()`

**Purpose:** Downloads files matching PullFilePattern from the remote server to LocalDestination.

**Input:** Globals `PullSrcDir`, `PullDestDir`, `PullTempDir`, `PullFilePattern`, `ActionOnSuccess`

**Internal Logic:**
1. Clean previous files in PullTempDir matching PullFilePattern
2. Create SFTP batch: cd to remote dir, lcd to local temp, get pattern, exit
3. Execute SFTP transfer with retry
4. Count pulled files; if zero → log and return
5. Copy pulled files from temp to PullDestDir
6. If ActionOnSuccess=DELETE → create another SFTP batch to `rm` files on remote
7. If ActionOnSuccess=.<ext> → create SFTP batch to `rename` each remote file
8. Clean temp directory

**VMS Equivalent (key sections):**
```dcl
$ PULL_SFTP:
$ set def 'CELL0_DAT_SFTP_TMP
$ previous_file=f$search("''PullFilePattern';*",2)
$ if f$length(previous_file) .ne. 0 then delete/lo 'CELL0_DAT_SFTP_TMP:'PullFilePattern';
```
Cleans the staging directory (`CELL0_DAT`/`PullTempDir`) before pulling. The `;` at the end of `delete` refers to the current version only (not `;*` for all versions).

```dcl
$ write sftp_file "get ''PullFilePattern'"
$ gosub RUN_SFTP_TRANSFER
$ nextfile = f$search("''PullFilePattern';*",3)
$ if f$length(nextfile) .eq. 0 then @cell0_com:log_mess "..." "The files for pull is not present in the remote server" "..."
$ else copy/lo CELL0_DAT:'PullFilePattern' 'PullDestDir'
```
After pulling, VMS checks if any files arrived and copies from staging to destination.

The DELETE/rename sections use separate `f$search()` streams (3, 4, 5) and create additional SFTP batches per file for remote-side operations.

---

### 4.11 `housekeep()`

**Purpose:** Cleans up temporary files and old logs.

**Input:** Globals `SFTP_CFG_DIR`, `SFTP_LOG_DIR`, `SFTP_PURGE_DAYS`, `WORK_DIR`

**Internal Logic:**
1. Delete `.sftp` batch files older than 2 days from `SFTP_CFG_DIR`
2. Delete `GENERIC_SFTP*` log files older than `SFTP_PURGE_DAYS` days from `SFTP_LOG_DIR`
3. Remove the per-run `WORK_DIR`

**VMS Equivalent:**
```dcl
$ HOUSE_KEEP:
$ subroutine
$   delete/log/before="TODAY-2-00:00:00" sftp_cfg_dir:*.sftp;*
$   sftp_purge_days = F$Trnlnm("SFTP_PURGE_DAYS")
$   If sftp_purge_days .eqs. "" Then sftp_purge_days = 10
$   delete/log/before="TODAY-''sftp_purge_days'-00:00:00" cell0_log:GENERIC_SFTP*.*;*
$ endsubroutine
$
$ Housekeep1:
$   if f$search("sftp_cfg_dir:''sftp_tmp_file_pull'") .nes. "" then delete ...
$   if f$search("sftp_cfg_dir:''sftp_tmp_file_push'") .nes. "" then delete ...
$   if f$search("sftp_cfg_dir:''sftp_tmp_file_pull_d'") .nes. "" then delete ...
$   Return
```
VMS has TWO housekeeping routines:
- `HOUSE_KEEP` subroutine — general cleanup of old files
- `Housekeep1` gosub — cleanup of the specific temp batch files created during this run

On Linux, these are merged into a single `housekeep()` function.

---

### 4.12 `clean_finish()` and `reg_error()`

**Purpose:** Exit handlers for success and error paths.

| Function        | Purpose                                  |
|----------------|------------------------------------------|
| `clean_finish` | Normal completion: housekeep + log success |
| `reg_error`    | Error exit: housekeep + log error + exit 1 |

Both set `_CLEANUP_DONE=1` to prevent double cleanup (the EXIT trap also calls cleanup).

**VMS Equivalent:**
```dcl
$ CLEAN_FINISH:
$   call HOUSE_KEEP 0
$   gosub Housekeep1
$   @cell0_com:log_mess "..." "''procname' has completed successfully at ''f$time()'" "..."
$   goto exit

$ REG_ERROR:
$   call HOUSE_KEEP 0
$   gosub Housekeep1
$   @cell0_com:log_mess " ***" "''procname' - ''phase',(''p1' file is ''p2') ''status' " "..."
$   request/reply/to='operator' "SFTP-E ..."
$   if f$search(DestFileName) .eqs. "" then exit 4

$ VMS_ERROR:
$   (same as REG_ERROR but uses $STATUS for error text)
```
VMS has three exit paths: `CLEAN_FINISH`, `REG_ERROR`, and `VMS_ERROR`. The first is for success; the latter two differ only in how they format the error message. On Linux, `reg_error()` handles both error cases.

Note: VMS `exit 4` is a warning-level exit status (%SYSTEM-W). On Linux, `exit 1` is used for all errors.

---

## 5. VMS-to-Linux Mapping Summary

| VMS Phase / Label          | Linux Function            | Key Changes                                  |
|---------------------------|---------------------------|----------------------------------------------|
| `SAVE_ENVIRONMENT`        | Script preamble            | No privilege elevation needed                |
| `CHECK_PREV_ERROR`        | `check_singleton()`       | `flock` replaces VMS job queue/process check |
| `CHECK_LOGICALS`          | `validate_environment()`  | `$SFTP_CFG_DIR` replaces `F$Trnlnm()`       |
| `SET_PROCESS_NAME`        | `check_singleton()`       | File lock replaces process rename            |
| `GET_INPUT_PARAMS`        | `validate_params()`       | Same validation logic                        |
| `SFTP_PARAMETERS`         | `parse_config_file()`     | Line-by-line parsing preserved               |
| `PREPARE_SFTP`            | Inside `push_sftp()`      | Batch file creation simplified               |
| `PUSH_SFTP` / `FILE_SEARCH_LOOP` | `push_sftp()`    | `find` replaces `f$search()` loop            |
| `PULL_SFTP`               | `pull_sftp()`             | Staging pattern preserved                    |
| `RUN_SFTP_TRANSFER`       | `run_sftp_transfer()`     | `sftp -b` replaces `sftp/batchfile=`         |
| `ACTION_ON_SUCCESS`       | `action_on_success()`     | GZ handling simplified                       |
| `HOUSE_KEEP` + `Housekeep1` | `housekeep()`          | Merged into one function                     |
| `CLEAN_FINISH`            | `clean_finish()`          | Same logic                                   |
| `VMS_ERROR` + `REG_ERROR` | `reg_error()`             | Merged; no operator console alert            |
| `EXIT`                    | EXIT trap                  | `trap cleanup_and_exit EXIT`                 |
| `time_seconds` subroutine | `sleep N`                 | Direct replacement                           |
