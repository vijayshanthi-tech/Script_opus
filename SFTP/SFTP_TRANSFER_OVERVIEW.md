# SFTP_TRANSFER — VMS Script Overview & Conversion Notes

## 1. Purpose of the Original OpenVMS Scripts

**Scripts:**
1. `SFTP_TRANSFER.COM` (generic_sftp.txt) — **Config-driven variant** (v1.0–v2.6)
2. `SFTP_TRANSFER.COM` (param_generic_sftp.txt) — **Parameter-driven variant** (v2.0)

Both scripts are **generic SFTP transfer utilities** used within the TAP (Transferred Account Procedure) billing pipeline on OpenVMS. They push files to and/or pull files from remote servers using SFTP (SSH File Transfer Protocol).

| Feature                     | generic_sftp (config-driven)               | param_generic_sftp (parameter-driven)      |
|-----------------------------|--------------------------------------------|--------------------------------------------|
| Transfer params source      | All from `.CFG` configuration file          | Key params from command line (P1–P6); host/user from `.CFG` |
| SftpType support            | push / pull / both                          | push / pull (no "both")                     |
| RetryAttempts default       | 3 (from config, default 60s wait)           | 3 (hard-coded, 5s wait)                     |
| VMS version history         | v1.0 → v2.6 (6 revisions)                  | v2.0 (single Amreet revision)               |
| Use case                    | Scheduled batch transfers with fixed configs | Ad-hoc or called from other scripts with dynamic params |

---

## 2. How the VMS Scripts Work (Execution Flow)

### 2.1 Config-Driven Variant (generic_sftp.txt)

```
SFTP_TRANSFER.COM starts
    │
    ├── SAVE_ENVIRONMENT          ← Save DCL state, define error symbols
    ├── CHECK_PREV_ERROR          ← Check for retained jobs (previous crashes)
    ├── CHECK_LOGICALS            ← Verify SFTP_COM_DIR and SFTP_CFG_DIR exist
    ├── SET_PROCESS_NAME          ← Lock: rename process to prevent duplicates
    │
    ├── GET_INPUT_PARAMS          ← Validate P1 (config file) and P2 (action)
    │    └── ActionOnSuccess = DELETE | GZ | NOCHANGE | .<ext>
    │
    ├── SFTP_PARAMETERS           ← Parse .CFG file line by line:
    │    ├── SftpType, DestHostname, DestUsername
    │    ├── SrcDir, DestDir, DestFileName, DestFilePattern
    │    ├── PullSrcDir, PullDestDir, PullTempDir, PullFilePattern
    │    ├── TransferType, DestFilePermission
    │    └── RetryAttempts, RetryWaitSeconds
    │
    ├── PREPARE_SFTP / more_checks ← Validate paths, resolve directories
    │
    ├── PUSH_SFTP                 ← If SftpType = push | both:
    │    └── FILE_SEARCH_LOOP:
    │         ├── Find each matching file in SrcDir
    │         ├── Rename to .SFTP_TMP (safe staging)
    │         ├── Create SFTP batch file (cd, put, chmod, rename)
    │         ├── RUN_SFTP_TRANSFER (with retry loop)
    │         └── ACTION_ON_SUCCESS (delete/gz/rename/nochange)
    │
    ├── PULL_SFTP                 ← If SftpType = pull | both:
    │    ├── Clean previous pulled files from temp dir
    │    ├── Create SFTP batch (cd, get)
    │    ├── RUN_SFTP_TRANSFER
    │    ├── Copy pulled files from temp to PullDestDir
    │    ├── (If ActionOnSuccess != DELETE) Rename remote files via SFTP
    │    ├── (If ActionOnSuccess = DELETE) Delete remote files via SFTP
    │    └── Clean temp directory
    │
    ├── CLEAN_FINISH              ← Housekeep, log success, exit
    │
    ├── VMS_ERROR                 ← Error handler: housekeep, log, operator alert
    └── REG_ERROR                 ← Registered error: housekeep, log, operator alert
```

### 2.2 Parameter-Driven Variant (param_generic_sftp.txt)

```
SFTP_TRANSFER.COM starts with P1..P6
    │
    ├── Assign P1=CfgFileID, P2=SftpType, P6=ActionOnSuccess
    ├── If PUSH: SrcDir=P3, DestFileName=P4, DestFilePattern=P5
    ├── If PULL: PullDestDir=P3, PullFilePattern=P4
    │
    ├── CHECK_PREV_ERROR / CHECK_LOGICALS / SET_PROCESS_NAME
    ├── GET_INPUT_PARAMS (validate command-line params)
    │
    ├── SFTP_PARAMETERS           ← Parse .CFG for ONLY:
    │    ├── DestHostname, DestUsername, DestDir
    │    ├── TransferType, PullSrcDir
    │    └── (Skip SrcDir, DestFileName, PullDestDir, etc.)
    │
    ├── PUSH_SFTP / PULL_SFTP    ← Same flow as config-driven
    │
    └── CLEAN_FINISH / ERROR handlers
```

---

## 3. VMS Constructs Used in the Original Scripts

| VMS Construct                         | Meaning                                                                |
|---------------------------------------|------------------------------------------------------------------------|
| `$ set proc/priv=all`                 | Elevates process to full system privileges.                            |
| `$ set noverify`                      | Turns off command echoing (like `set +x` in bash).                     |
| `$ set noon`                          | Continue on error (`set +e`).                                          |
| `f$environment("PROCEDURE")`          | Gets the full path of the currently running procedure.                 |
| `f$parse(file,,,"NAME")`             | Extracts the filename portion from a VMS file spec.                    |
| `f$parse(file,,,"TYPE")`             | Extracts the file extension (type) from a VMS file spec.               |
| `f$search("pattern";*)`              | Searches for files matching a pattern (like `find` or `glob`).         |
| `f$file_attributes(file,"DIRECTORY")` | Checks if a file spec is a directory.                                  |
| `f$unique()`                          | Generates a unique string (used for temp file naming).                 |
| `f$extract(pos,len,str)`             | Extracts a substring.                                                  |
| `f$locate(char,str)`                 | Finds position of a character in a string.                             |
| `f$edit(str,"TRIM")`                 | Trims whitespace. `"COLLAPSE"` removes all internal whitespace too.    |
| `f$edit(str,"UPCASE")`               | Converts string to uppercase.                                          |
| `f$length(str)`                       | Returns string length.                                                 |
| `f$element(n,delim,str)`             | Splits string by delimiter, returns nth element.                       |
| `f$trnlnm("logical")`               | Translates (reads) a logical name (env variable).                      |
| `F$CONTEXT / F$PID / F$GETJPI`       | Process context functions used for singleton checking.                 |
| `SET PROCESS/NAME=`                   | Renames the current process (used as a lock mechanism).                |
| `REQUEST/REPLY/TO=OPER8`             | Sends a message to the VMS operator console and waits for reply.       |
| `PIPE ... \| ...`                     | VMS pipe operator (chains commands like `\|` on Linux).                |
| `SHOW ENTRY "name" \| SEARCH ... RETAINED` | Checks for retained (crashed) batch jobs in the queue.          |
| `define /process`                     | Defines a process-level logical name (scoped env variable).            |
| `open/read file` / `read /end=`      | Opens file for reading; reads line by line with EOF jump.              |
| `open/append file`                    | Opens file for appending (used to build SFTP batch files).             |
| `create/fdl=sys$input`               | Creates a file with specific record format (Stream_LF for SFTP batch). |
| `sftp/batchfile=`                     | VMS SFTP with a batch command file (like `sftp -b` on Linux).          |
| `on error then goto`                 | VMS error trap (like `trap` in bash).                                  |
| `call subroutine`                     | Calls a VMS subroutine (defined with `$subroutine`/`$endsubroutine`).  |
| `gosub label` / `return`             | Calls a gosub routine (like a function, but shares scope).             |
| `gzip :== $sys$system:gzip.exe`       | Defines gzip as a VMS foreign command pointing to the executable.      |
| `rename file1 file2`                  | Renames a file (like `mv` on Linux). VMS keeps version numbers.        |
| `delete/log file;*`                   | Deletes all versions of a file with logging.                           |
| `delete/log/before="TODAY-N-"`        | Deletes files older than N days (VMS date arithmetic).                 |
| `copy/lo file dir`                    | Copies file to directory with logging.                                 |

---

## 4. Dependencies & External Tools

### 4.1 SFTP / SSH

| Dependency          | Details                                                    |
|---------------------|------------------------------------------------------------|
| `sftp`              | OpenSSH SFTP client — must be on `$PATH`                   |
| SSH key auth        | SSH key must be configured for `DestUsername@DestHostname`  |
| Batch mode          | `sftp -b <batchfile>` replaces VMS `sftp/batchfile=`       |

### 4.2 System Utilities

| Utility             | Used For                                                    |
|---------------------|------------------------------------------------------------|
| `gzip`              | Compressing source files (ActionOnSuccess=GZ)               |
| `flock`             | File-level singleton locking (replaces VMS SET PROCESS/NAME)|
| `find`              | File discovery with pattern matching                        |
| `cp`, `mv`, `rm`    | File operations                                            |
| `tee -a`            | Simultaneous stdout + file logging                          |
| `date`              | Timestamp generation                                        |
| `basename`          | Filename extraction                                         |

### 4.3 Directory Structure Required

```
${SFTP_CFG_DIR}/           ← Configuration files (.CFG)
├── RSERC_SFTP.CFG
├── FCS_PUSH.CFG
└── ... other .CFG files

${SFTP_COM_DIR}/           ← Script/command directory
├── generic_sftp.sh
└── param_generic_sftp.sh

${SFTP_LOG_DIR}/           ← Log files (optional, defaults to SFTP_CFG_DIR)
└── generic_sftp.log

/tmp/                      ← Temp work directories and lock files
├── generic_sftp_<pid>/    ← Per-run working directory
└── generic_sftp_*.lock    ← Singleton lock files
```

### 4.4 Configuration File Format

Config files use a simple `Key:Value` format. Lines starting with `!` are comments:

```
! Example SFTP configuration file
SftpType:push
DestHostname:sftp.partner.com
DestUsername:tapuser
DestDir:/incoming/cdr
SrcDir:/data/tap/outgoing
DestFileName:*.dat
DestFilePattern:
DestFilePermission:775
TransferType:B
RetryAttempts:3
RetryWaitSeconds:60
```

---

## 5. Assumptions Made During Conversion

| #  | Assumption                                                                       | Impact              |
|----|----------------------------------------------------------------------------------|---------------------|
| 1  | SSH key-based authentication is configured for all remote hosts                  | SFTP will not prompt for passwords in batch mode |
| 2  | `flock` is available on the target Linux system (standard on RHEL/CentOS)        | Singleton locking    |
| 3  | VMS `CELL0_DAT` logical name is mapped to a temp staging directory on Linux      | Pull temp staging    |
| 4  | VMS `TransferType` (A=ASCII, B=Binary) is ignored — Linux SFTP always uses binary | No data corruption for binary files |
| 5  | VMS file version numbers (`;*`) are not present on Linux                         | File delete/rename is simplified |
| 6  | VMS `create/fdl=sys$input` (Stream_LF format) is replaced by standard file creation | Batch file creation |
| 7  | VMS `REQUEST/REPLY/TO=OPER8` (operator console alert) has no Linux equivalent    | Replaced by log_error() only |
| 8  | VMS `SET PROCESS/NAME` (singleton) is replaced by `flock` file locking           | Different mechanism, same goal |
| 9  | VMS `f$search("RESET_SEARCH_CONTEXT_BOGUS.TMP;0")` resets search context        | Not needed on Linux (no persistent search context) |
| 10 | The `.SFTP_TMP` intermediate name pattern is preserved for atomic remote writes  | Same behavior |

---

## 6. Non-Convertible Logic & Workarounds

### 6.1 VMS Process Naming (Singleton Lock)

**VMS:**
```dcl
$ current_process = f$extract(5,15,CfgFileID)
$ gosub set_process_name
```
The VMS script renames the running process to the config file name, then checks (`F$CONTEXT`, `F$PID`, `F$GETJPI`) if another process with the same name already exists on the same node. This is a sophisticated cluster-aware singleton check.

**Workaround:** Replaced with `flock -n` on a per-config lock file. This is the standard Linux approach for preventing duplicate process execution.

**Limitation:** `flock` is node-local only. If the script runs on a multi-node cluster, a shared-filesystem lock file or a distributed lock (e.g., Redis, etcd) would be needed.

---

### 6.2 VMS Operator Console Alerts

**VMS:**
```dcl
$ request/reply/to='operator' "SFTP-E ''procname' - ''phase' ..."
```
`REQUEST/REPLY/TO=OPER8` sends a message to the VMS operator terminal and **blocks** until the operator acknowledges it. This is a critical alert mechanism.

**Workaround:** Replaced with `log_error()` which writes to the log file. For production, integrate with your monitoring system (e.g., Nagios, Zabbix, or email alerts).

**Limitation:** No interactive operator acknowledgment on Linux. Consider adding `mailx` alerts in `log_error()` if critical alerts need human attention.

---

### 6.3 VMS SFTP Batch File Format

**VMS:**
```dcl
$ create/fdl=sys$input sftp_cfg_dir:'sftp_tmp_file'
    FILE
        ORGANIZATION                sequential
    RECORD
        CARRIAGE_CONTROL    carriage_return
        FORMAT              Stream_Lf
        SIZE                120
$ open/append sftp_file sftp_cfg_dir:'sftp_tmp_file'
$ write sftp_file "cd ""'/DestDir'"""
$ write sftp_file "put 'DestFile''sftp_file_tmp'"
$ write sftp_file "exit"
$ close sftp_file
```
VMS creates SFTP batch files using FDL (File Definition Language) to ensure `Stream_LF` record format. The batch is then passed to `sftp/batchfile=`.

**Workaround:** On Linux, a plain text file with commands works directly with `sftp -b`. No special record format needed.

---

### 6.4 VMS File Search Context

**VMS:**
```dcl
$ nextfile = f$search("RESET_SEARCH_CONTEXT_BOGUS.TMP;0")
$ nextfile = f$search("'DFile''type';*",1)
```
VMS `f$search()` maintains a persistent "search context" — each call returns the **next** matching file. The bogus file search resets this context. The second parameter (1, 2, 3...) selects different search streams.

**Workaround:** On Linux, `find` returns all matches at once. No context tracking needed. A `while read` loop iterates through results.

---

### 6.5 VMS Atomic Rename via .SFTP_TMP

**VMS:**
```dcl
$ rename/lo 'DestFile''type' 'DestFile''sftp_file_tmp'
$ write sftp_file "put 'DestFile''sftp_file_tmp'"
$ write sftp_file "rename 'DestFile''sftp_file_tmp' 'DestFile''type'"
```
The script renames the local file to `.SFTP_TMP` before uploading, then renames it back on the remote side. This prevents partial files from being processed.

**Workaround:** On Linux, the script uploads with `.SFTP_TMP` extension on the **remote** side only (using `put "file" "file.SFTP_TMP"` followed by `rename`), avoiding local rename. This is cleaner because the local file is untouched until `action_on_success`.

---

### 6.6 VMS File Versioning

**VMS:**
```dcl
$ delete/log/noconfirm CELL0_DAT:'PullFilePattern';*
$ rename 'just_name'-gz;* 'just_name'-gz-wip
```
VMS maintains file versions (`;1`, `;2` etc.). The `;*` wildcard operates on all versions.

**Workaround:** Linux has no file versioning. Standard `rm`, `mv`, `cp` operate on single files. The gzip workaround (renaming `-gz` to `-gz-wip`) is no longer needed — Linux `gzip` handles this natively.

---

### 6.7 VMS Search Context in Pull/Delete/Rename Loop

**VMS:**
The VMS pull + delete/rename section uses multiple nested `f$search()` calls with different stream IDs (1, 2, 3, 4, 5) to avoid conflicts between simultaneous search operations on the same file pattern.

**Workaround:** On Linux, separate `find` commands are fully independent. No stream management needed.

---

### 6.8 Cell0_dat Staging Directory

**VMS:**
```dcl
$ set def CELL0_DAT
$ copy/lo CELL0_DAT:'PullFilePattern' 'PullDestDir'
```
`CELL0_DAT` is a VMS logical name pointing to a shared staging directory. Files are pulled into this staging area first, then copied to the final destination.

**Workaround:** Replaced with a `PullTempDir` (defaulting to `${WORK_DIR}/pull_tmp`). The staging-then-copy pattern is preserved.
