# RSERC_CHK — VMS Script Overview & Conversion Notes

## 1. Purpose of the Original OpenVMS Script

**Script:** `RSERC_CHK.COM` (DCL batch procedure)

`RSERC_CHK.COM` is a **daytime daemon** that monitors the TAP (Transferred Account Procedure) outbound roaming pipeline on an OpenVMS system. It runs continuously from **06:00** until **23:00** each day, performing three categories of work:

| Category               | What It Does                                                       | Frequency      |
|------------------------|--------------------------------------------------------------------|----------------|
| Directory monitoring   | Counts files in five TAP pipeline stages and alerts on backlogs    | Every hour     |
| Hourly Oracle reports  | Queries the Oracle DB for RSERC file-creation and roaming CDR stats, emails to L2/Apollo | Every hour |
| RSERC failure recovery | Detects orphaned `.don` / `.tmp` files in the outgoing SP directory, alerts, deletes, and re-triggers RSERC assembly | Every 10 min |

The script self-schedules for the next day at 06:00 using the VMS batch queue (`SUBMIT/AFTER`).

---

## 2. How the VMS Script Works (Execution Flow)

```
06:00  SUBMIT fires → RSERC_CHK.COM starts
        │
        ├── SET PROC/PRIV=ALL              ← Elevate privileges
        ├── SUBMIT/AFTER=tomorrow"+6"      ← Schedule next day's run
        ├── sqlplus → SPOOL spid_list.lis  ← Get all SP_IDs from Oracle
        │
        ▼
   ┌─→ start:                             ← OUTER LOOP (hourly)
   │    ├── Check ARCHIVE (files in last 4h?)
   │    ├── Check COLLECT  (count > 400?)
   │    ├── Check TO_PRICE (count > 400?)
   │    ├── Check PRICED   (count > 400?)
   │    ├── Check per-SPID SPLIT dirs (count > 600?)
   │    ├── sqlplus → Hourly file/CDR reports → email
   │    ├── Zero-RSERC check (alert if FILE_COUNT=0, run > 1)
   │    └── Record last_hour
   │
   │  ┌─→ start_1:                        ← INNER LOOP (10-min)
   │  │    ├── Show queues *ass* → search for "dist"
   │  │    │    ├── IF dist running → skip to check_hour
   │  │    │    └── ELSE:
   │  │    │         ├── Check *.don → alert
   │  │    │         └── Check *.tmp → alert + auto-recovery:
   │  │    │              ├── List mrlog*.tmp
   │  │    │              ├── Delete *.tmp
   │  │    │              ├── SORT/NODUP/KEY(pos:35,siz=3)
   │  │    │              └── sqlplus @rerun_rserc per SP_ID
   │  │    │
   │  │    ├── check_hour:
   │  │    │    ├── IF hour = 23 → goto finish
   │  │    │    ├── IF hour > last_hour → goto start (outer loop)
   │  │    │    └── WAIT 00:10:00 → goto start_1
   │  │    └──────────────┘
   │  └──────────────┘
   └──────────────┘

   finish:
    ├── Log "completed"
    ├── Delete logs older than 30 days
    ├── Delete temp files
    └── EXIT
```

---

## 3. VMS Constructs Used in the Original Script

| VMS Construct                         | Meaning                                                                |
|---------------------------------------|------------------------------------------------------------------------|
| `$ set proc/priv=all`                 | Elevates the process to full system privileges.                        |
| `$ set noverify`                      | Turns off command echoing (like `set +x` in bash).                     |
| `$ set noon`                          | Continue on error (`set +e` in bash / `ON ERROR THEN CONTINUE`).       |
| `$ submit/after=tomorrow"+6"/keep/log=.../noprint` | Submits the script to the VMS batch scheduler for 06:00 next day. |
| `$ wso="write sys$output"`            | Defines a shorthand symbol for writing to stdout.                      |
| `$ dttm=f$time()`                     | Gets the current date/time string.                                     |
| `f$extract(pos, len, string)`         | Extracts a substring (0-based position).                               |
| `f$element(n, delim, string)`         | Splits a string by delimiter and returns the nth element.              |
| `f$fao("!3ZL", value)`               | Formatted ASCII Output — zero-pads an integer to 3 digits.            |
| `f$integer(string)`                   | Converts a string to an integer.                                       |
| `f$edit(string, "trim")`             | Trims whitespace from a string.                                        |
| `f$trnlnm("name")`                   | Translates (reads) a logical name (like an env variable).              |
| `define/job name value`               | Defines a job-wide logical name (like `export VAR=value`).             |
| `dir ... /sin="-4"`                   | Lists files modified within the last 4 hours (`find -mmin -240`).      |
| `dir ... /tot /nohead`                | Lists files with totals, no column headers.                            |
| `dir ... /noout`                      | Checks if files exist (suppresses output; tests `$status`).           |
| `pip dir ... \| sea sys$input "..." \| (read sys$pipe ...)` | Piped file count extraction — counts matching files. |
| `$status`                             | Last command's exit status (`$?` in bash). `%X00000001` = success.     |
| `mail NL: "addr"/sub="..."`          | Sends email with null body (NL: = /dev/null equivalent).               |
| `MAIL/SUBJ="..." file "addr"`        | Sends email with file contents as body.                                |
| `sdcmg1::smtp%"addr"`                | DECnet-to-SMTP mail address (now replaced by direct SMTP).             |
| `open/read inpfile filename`          | Opens a file for reading.                                              |
| `read/end=label inpfile variable`     | Reads a line; jumps to `label` at EOF.                                 |
| `close inpfile`                       | Closes the file.                                                       |
| `sort/nodup/key=(pos:35,siz=3)`      | Sorts file, removes duplicates, using key at position 35, length 3.    |
| `sh que *ass*`                        | Shows VMS batch queues matching "*ass*" (assembly queues).             |
| `wait 00:10:00`                       | Waits 10 minutes (like `sleep 600`).                                   |
| `del/bef="-30-" file;*`              | Deletes file versions older than 30 days.                              |
| `delete file;*`                       | Deletes all versions of a file (VMS has file versioning).              |
| `goto label`                          | Jumps to a label (replaced by loops/functions in bash).                 |

---

## 4. Dependencies & External Tools

### 4.1 Oracle Database

| Dependency          | Details                                                    |
|---------------------|------------------------------------------------------------|
| `sqlplus`           | Must be on `$PATH`, with `ORACLE_HOME` and `ORACLE_SID` set |
| Authentication      | OS-authenticated (`sqlplus -s /` — no password needed)      |
| Tables accessed     | `service_providers`, `outgoing_outbound_call_files`, `PROCESS_STATISTICS` |
| SQL script          | `rerun_rserc.sql` — used for RSERC re-run recovery         |

### 4.2 Mail System

| Dependency          | Details                                                    |
|---------------------|------------------------------------------------------------|
| `mailx`             | Command-line mail client                                    |
| MTA                 | `postfix` or `sendmail` must be running                     |
| Recipients          | `Telefonica_UK.L2@accenture.com`, `VMO2_ApolloL2@accenture.com`, `TAPSupport@o2.com` |

### 4.3 System Utilities

| Utility             | Used For                                                    |
|---------------------|------------------------------------------------------------|
| `find`              | Directory scanning with pattern matching and age filters    |
| `wc -l`             | Counting files                                              |
| `awk`               | Substring extraction from mrlog filenames                   |
| `sort -u`           | Deduplication of SP_IDs                                     |
| `tee -a`            | Simultaneous stdout + file logging                          |
| `at` / `cron`       | Next-day scheduling                                         |
| `ps -ef`            | Checking for running assembly/dist processes                |
| `readlink -f`       | Resolving script's absolute path                            |
| `date`              | Timestamp generation                                        |
| `grep`, `sed`, `tr` | Text parsing                                                |

### 4.4 Directory Structure Required

```
/data/tap/R53_TAPLIVE/TAP/
├── ARCHIVE/           ← Archive of processed CDR files
├── COLLECT/           ← Incoming CDR files waiting for collection
├── TO_PRICE/          ← Files awaiting pricing engine
├── PRICED/            ← Priced files awaiting splitting
├── SPLIT/             ← Per-SPID subdirectories (e.g., SPLIT/007/)
│   ├── 001/
│   ├── 002/
│   └── .../
├── OG_SP/             ← Outgoing SP assembly area (.don, .tmp, mrlog*)
├── PERIOD/            ← Periodic RSERC consolidation area
└── LOG/               ← Log files
```

---

## 5. Assumptions Made During Conversion

| #  | Assumption                                                                       | Impact              |
|----|----------------------------------------------------------------------------------|---------------------|
| 1  | Linux user running the script has read access to all TAP directories             | Required for `find` |
| 2  | Oracle is accessible via OS authentication (`sqlplus -s /`) with no password     | Core data access    |
| 3  | `mailx` with a working MTA is sufficient to replace VMS MAIL + DECnet routing   | Email delivery      |
| 4  | The `at` daemon is available for next-day scheduling (or cron is configured)     | Job re-scheduling   |
| 5  | File patterns (e.g., `cd*.dat`, `CD?????GBRCN*`) match identically on Linux     | VMS patterns used `%` for single-char wildcard → converted to `?` |
| 6  | VMS file version numbers (`;*`) are not present on Linux — file deletion is straightforward | Cleanup logic |
| 7  | VMS batch queue inspection (`sh que *ass*`) is equivalent to `ps -ef \| grep dist` | Process detection |
| 8  | The `rerun_rserc.sql` script accepts an SP_ID as its first argument             | Recovery logic      |
| 9  | Oracle spool output format is compatible with the `grep`/`sed` parsing logic    | Report parsing      |
| 10 | The `mrlog*.tmp` filename structure places the SP_ID at byte offset 35 (1-based)| May need adjustment |

---

## 6. Non-Convertible Logic & Workarounds

### 6.1 VMS Batch Queue Scheduling

**VMS:**
```dcl
$ submit/after=tomorrow"+6"/keep/log=tap_log_dir:rserc_chk.log/noprint rserc_chk.com
```

**Issue:** VMS has a built-in batch queue scheduler that tracks jobs, retries, and logs. Linux has no direct equivalent.

**Workaround:** The bash script uses `at 06:00 tomorrow` for one-shot scheduling, but the **recommended** approach is a crontab entry:
```
0 6 * * * /path/to/rserc_chk.sh >> /data/tap/.../LOG/rserc_chk.log 2>&1
```

**Limitation:** `at` does not provide the same queue management, priority, and re-try semantics that VMS batch queues offer.

---

### 6.2 VMS Process Queue Inspection

**VMS:**
```dcl
$ sh que *ass*/out=rserc_chk.lis
$ sea rserc_chk.lis dist
```

**Issue:** VMS queues (`TAP$OB$ASSEMB$G2$TAPLIV`, etc.) are named batch/execution queues. Linux processes do not have equivalent named queues.

**Workaround:** Replaced with `ps -ef | grep -i "assemb\|dist"`. This checks if any process with "assemb" or "dist" in its command line is running.

**Limitation:** The `ps` approach is less specific — it may match unrelated processes. A more robust check would be to look for a PID file or use `systemctl status <service>`.

---

### 6.3 VMS Pipe Chain for File Counting

**VMS:**
```dcl
$ pip dir DISK$CALL_DATA:[TAP.OB.COLLECT]CD%%%%%GBRCN*.dat/tot | sea sys$input "Total of " | (read sys$pipe line ; lines=f$element(2," ",f$extract(0,30,line)) ; define/job file_count &lines)
```

**Issue:** This is a complex VMS pipe chain that: (1) lists files with totals, (2) searches for "Total of", (3) extracts the count using `f$element` and `f$extract`, and (4) defines a job-level logical name.

**Workaround:** Replaced with `find ... | wc -l` which directly counts matching files. This is simpler and more reliable.

**Limitation:** None — the Linux approach is equivalent and more robust.

---

### 6.4 VMS SORT with Key-Based Deduplication

**VMS:**
```dcl
$ sort/nodup/key=(pos:35,siz=3) mrlog.lis;1 mrlog.lis;2
```

**Issue:** VMS `SORT/NODUP/KEY` sorts a file, removes duplicate lines based on a key at a specific position (pos:35, length:3), and writes to a new file version.

**Workaround:** Replaced with:
```bash
awk '{ print substr($0, 35, 3) }' mrlog.lis | sort -u > mrlog_sorted.lis
```

**Limitation:** The position offset (35) was mapped from VMS `f$extract(34, 3, rec)` which operated on the FULL directory listing line (including path prefix). On Linux, `find -exec basename {}` outputs **filenames only**. The correct offset depends on the actual `mrlog*.tmp` filename structure. **This value must be verified and adjusted** when testing against real filenames.

---

### 6.5 DECnet Mail Addresses

**VMS:**
```dcl
$ mail rserc_failure_2.txt "sdcmg1::smtp%""TAPSupport@o2.com"""/sub="..."
```

**Issue:** `sdcmg1::smtp%"addr"` is a DECnet-to-SMTP mail routing syntax. DECnet is not available on Linux.

**Workaround:** Replaced with direct SMTP via `mailx -s "subject" addr < file`. Requires a functioning MTA (postfix/sendmail).

**Limitation:** None — direct SMTP is the standard approach on Linux.

---

### 6.6 VMS File Versioning

**VMS:**
```dcl
$ del rserc_failure*.txt;*
$ delete spid_list.lis;*
```

**Issue:** VMS keeps numbered versions of files (`;1`, `;2`, etc.). The `;*` wildcard deletes all versions.

**Workaround:** On Linux, files have no version numbers. Standard `rm -f file` is equivalent.

**Limitation:** None.

---

### 6.7 VMS Privilege Elevation

**VMS:**
```dcl
$ set proc/priv=all
```

**Issue:** Elevates the process to full system privileges. Linux does not have an equivalent runtime privilege escalation within a script.

**Workaround:** The script should be run as the appropriate OS user (e.g., `oracle` or a dedicated `tap` user) with proper file permissions and group memberships already configured.

**Limitation:** No runtime `sudo` is used. All permission issues must be resolved at deployment time via user/group configuration.

---

### 6.8 Commented-Out Queue Stop/Start

**VMS (commented out):**
```dcl
$!               stop/que/next TAP$OB$ASSEMB$G2$TAPLIV
$!               stop/que/next TAP$OB$ASSEMB$G3$TAPLIV
```

**Note:** These lines were already commented out in the original VMS script. They would have stopped the assembly queues during recovery. The bash conversion does not include this functionality. If queue/process stop/restart is needed, it should be implemented as a separate systemctl or kill/restart mechanism.

---

## 7. Key Conversion Decisions

| Decision                              | Rationale                                                      |
|---------------------------------------|----------------------------------------------------------------|
| Functions instead of `goto` labels    | Bash functions are testable, modular, and avoid spaghetti flow |
| `find \| wc -l` for file counting    | Simpler and more reliable than VMS pipe chains                 |
| Entry-point guard (`BASH_SOURCE`)     | Enables unit testing by sourcing without executing `main()`    |
| EXIT trap for cleanup                 | Ensures cleanup runs on normal exit, SIGTERM, and SIGINT       |
| Double-call guard on cleanup          | Prevents duplicate cleanup when trap + normal exit both fire   |
| Environment variable overrides        | All paths and thresholds can be overridden for testing         |
| Preserved "Procudure" typo           | Matches the original VMS alert text for consistency            |
| `2>/dev/null` on mailx calls         | Prevents script failure if MTA is temporarily unavailable      |

---

## 8. VMS-to-Linux Command Quick Reference

| VMS Command / Function          | Linux Equivalent                          |
|---------------------------------|-------------------------------------------|
| `write sys$output "text"`       | `echo "text"`                             |
| `f$time()`                      | `date '+%d-%b-%Y %H:%M:%S'`              |
| `f$extract(pos, len, str)`      | `${str:pos:len}` or `awk substr()`        |
| `f$element(n, " ", str)`        | `awk '{print $N}'`                        |
| `f$fao("!3ZL", val)`           | `printf "%03d" val`                       |
| `f$integer(str)`                | `$((str + 0))`                            |
| `f$edit(str, "trim")`          | `echo "$str" \| tr -d '[:space:]'`        |
| `define/job name value`         | `export name=value`                       |
| `f$trnlnm("name")`             | `${name}` or `printenv name`              |
| `dir file /sin="-4"`            | `find dir -name 'pat' -mmin -240`         |
| `dir file /noout`               | `find dir -name 'pat' \| head -1`         |
| `mail NL: "addr"/sub="s"`      | `echo "" \| mailx -s "s" addr`            |
| `MAIL/SUBJ="s" file "addr"`    | `mailx -s "s" addr < file`                |
| `submit/after=tomorrow"+6"`    | `echo cmd \| at 06:00 tomorrow` or cron   |
| `wait 00:10:00`                 | `sleep 600`                               |
| `goto label`                    | Function calls + `while/break/continue`   |
| `open/read`, `read/end=`        | `while IFS= read -r line; do ... done < file` |
| `sort/nodup/key=(p,s)`          | `awk substr + sort -u`                    |
| `del/bef="-30-" file;*`        | `find dir -name 'pat' -mtime +30 -delete` |
| `sh que *ass*`                  | `ps -ef \| grep "assemb\|dist"`           |
| `set proc/priv=all`             | Run as appropriate user with permissions  |
| `$status .eqs. "%X00000001"`    | `$? -eq 0` (or direct `if cmd; then`)     |

---

## 9. Files Produced by the Conversion

| File                              | Description                                          |
|-----------------------------------|------------------------------------------------------|
| `rserc_chk.sh`                    | Converted bash script with detailed function comments |
| `RSERC_CHK_UNIT_TEST.md`          | Unit test document with test steps and result fields  |
| `RSERC_CHK_OVERVIEW.md`           | This document                                         |
| `RSERC_CHK_TECHNICAL_DOCUMENT.md` | Detailed technical analysis (from prior session)      |
