# RSERC_CHK.SH — Dependency Analysis (Updated)

This document reflects the corrected `rserc_chk.sh` with user-configured paths under `/data/tap/R53_TAPLIVE/TAP/`.

---

## 1. External Command Dependencies

| Command | Purpose | Required | Fallback |
|---------|---------|----------|----------|
| `sqlplus` | Oracle SQL*Plus — queries DB, generates spool reports, re-runs failed RSERCs | **Yes** | None — script cannot function without Oracle |
| `mailx` | Sends email alerts and file-based reports | **Yes** | Alerts logged but not delivered if missing |
| `at` | Schedules next-day run at 06:00 | No | Falls back to log warning; use crontab instead |
| `find` (GNU) | File counting, mtime filtering, deletion | **Yes** | Requires `-mmin`, `-iname`, `-delete`, `-printf` |
| `date` | Timestamp generation, hour comparison | **Yes** | Standard in all Linux |
| `basename` | Extracts filename from path (mrlog recovery) | **Yes** | Via `-exec basename {} \;` in find |
| `awk` | SP_ID extraction from mrlog filenames | **Yes** | Position-based substr |
| `sort` | Deduplicates SP_IDs for recovery | **Yes** | `sort -u` |
| `grep` | Searches process list, file content | **Yes** | Standard |
| `ps` | Lists running processes (dist check) | **Yes** | Standard |
| `tee` | Splits output to log and stdout | **Yes** | Standard |
| `wc` | Counts files/lines | **Yes** | Standard |
| `sleep` | 10-minute wait between failure checks | **Yes** | Standard |
| `readlink` | Resolves script path for `at` scheduling | No | Only used in schedule_next_run |

---

## 2. Oracle Database Dependencies

| Object | Type | Access | SQL Function | Script Function |
|--------|------|--------|-------------|-----------------|
| `service_providers` | Table | SELECT | `SELECT SP_ID FROM service_providers` | `generate_spid_list()` |
| `outgoing_outbound_call_files` | Table | SELECT | Hourly file count by `OOCF_CREATED_DTTM` | `generate_hourly_reports()` |
| `PROCESS_STATISTICS` | Table | SELECT | Hourly CDR record count by `PS_RUN_DTTM` | `generate_hourly_reports()` |
| `rerun_rserc.sql` | SQL Script | Execute | `sqlplus -s / @rerun_rserc.sql <SP_ID>` | `check_rserc_failures()` |

**Authentication:** OS authentication (`sqlplus -s /`) — requires Oracle wallet or OS-level auth configured.

### Key Columns Referenced

| Table | Column | Usage |
|-------|--------|-------|
| `service_providers` | `SP_ID` | SPID list for per-provider split directory checks |
| `outgoing_outbound_call_files` | `OOCF_CREATED_DTTM` | Grouped by hour for RSERC report; filtered by `TRUNC(SYSDATE)` and `TRUNC(SYSDATE-4/24)` |
| `PROCESS_STATISTICS` | `PS_RUN_DTTM`, `PS_RECORD_COUNT`, `PS_PROCESS_NAME` | Filtered by `PS_PROCESS_NAME='PRICING'` and today's date |

---

## 3. File System Dependencies

### 3.1 Monitored Directories (Read-Only)

| Variable | Default Path | VMS Logical | File Pattern | Check Type |
|----------|-------------|-------------|-------------|------------|
| `TAP_ARCHIVE_DIR` | `/data/tap/R53_TAPLIVE/TAP/ARCHIVE` | `DISK$CALL_DATA2:[TAP.OB.ARCHIVE]` | `cd*.dat` | Recent files (mmin -240) |
| `TAP_COLLECT_DIR` | `/data/tap/R53_TAPLIVE/TAP/COLLECT` | `DISK$CALL_DATA:[TAP.OB.COLLECT]` | `CD?????GBRCN*.dat` | Count > MAX |
| `TAP_READY_FOR_PRICING` | `/data/tap/R53_TAPLIVE/TAP/TO_PRICE` | `DISK$CALL_DATA:[TAP.OB.TO_PRICE]` | `CD?????GBRCN*.DAT` | Count > MAX |
| `TAP_OB_PRICED` | `/data/tap/R53_TAPLIVE/TAP/PRICED` | `DISK$CALL_DATA:[TAP.OB.PRICED]` | `CD?????GBRCN*.PRC` | Count > MAX |
| `TAP_OB_SPLIT` | `/data/tap/R53_TAPLIVE/TAP/SPLIT` | `DISK$CALL_DATA:[TAP.OB.SPLIT.<spid>]` | `CD*.SPLIT` | Count > SPLIT_MAX (per SPID) |

### 3.2 Recovery Directories (Read/Write/Delete)

| Variable | Default Path | VMS Logical | Operations |
|----------|-------------|-------------|------------|
| `TAP_OUTGOING_SP` | `/data/tap/R53_TAPLIVE/TAP/OG_SP` | `tap_outgoing_sp:` | Read `.don`/`.tmp`; list `mrlog*.tmp`; delete `*.tmp` |
| `TAP_PERIOD_DIR` | `/data/tap/R53_TAPLIVE/TAP/PERIOD` | `tap_ob_period:` | Delete `*.tmp` during recovery |

### 3.3 Log Directory (Write)

| Variable | Default Path | VMS Logical | Operations |
|----------|-------------|-------------|------------|
| `TAP_LOG_DIR` | `/data/tap/R53_TAPLIVE/TAP/LOG` | `tap_log_dir:` | Write `rserc_chk.log`; delete logs older than 30 days |

### 3.4 Temporary Files (in WORK_DIR = `/tmp/rserc_chk_$$`)

| File | Created By | Used By | Cleaned By |
|------|-----------|---------|------------|
| `spid_list.lis` | `generate_spid_list()` | `check_tap_directories()` | `cleanup_and_exit()` |
| `files_created.lis` | `generate_hourly_reports()` (SPOOL) | Emailed as RSERC report | `generate_hourly_reports()` |
| `files_created1.lis` | `generate_hourly_reports()` (SPOOL) | Zero-RSERC check | `generate_hourly_reports()` |
| `recs_created.lis` | `generate_hourly_reports()` (SPOOL) | Emailed as CDR report | `generate_hourly_reports()` |
| `rserc_chk.lis` | `check_rserc_failures()` | Process "dist" check | `check_rserc_failures()` |
| `rserc_failure_1.txt` | `check_rserc_failures()` | Emailed as TMP alert | `cleanup_and_exit()` |
| `rserc_failure_2.txt` | `check_rserc_failures()` | Emailed as DON alert | `cleanup_and_exit()` |
| `mrlog.lis` | `check_rserc_failures()` | SP_ID extraction for rerun | `check_rserc_failures()` |
| `mrlog_sorted.lis` | `check_rserc_failures()` | Deduplicated SP_IDs | `check_rserc_failures()` |

---

## 4. Email / Notification Dependencies

| Recipient | Variable | Receives |
|-----------|----------|----------|
| `Telefonica_UK.L2@accenture.com` | `EMAIL_L2` | All alerts, RSERC report, CDR report, failure notifications |
| `VMO2_ApolloL2@accenture.com` | `EMAIL_APOLLO` | CDR report only |
| `TAPSupport@o2.com` | `EMAIL_TAP_SUPPORT` | RSERC failure alerts (.don/.tmp) |

**SMTP requirement:** `mailx` must be configured with a working MTA (postfix, sendmail, etc.).

---

## 5. Scheduling Dependencies

| Method | Command | Purpose |
|--------|---------|---------|
| Primary | `crontab -e`: `0 6 * * * /path/to/rserc_chk.sh` | Daily startup at 06:00 |
| Fallback | `at 06:00 tomorrow` | Self-scheduling (used in script) |

---

## 6. Inter-Script Dependencies

| Script | Called By | Relationship |
|--------|----------|-------------|
| `rserc_chk.sh` | cron/at | **Standalone** — does not call other converted scripts |
| `rerun_rserc.sql` | `rserc_chk.sh` (via sqlplus) | **Required** — must exist at `$RERUN_RSERC_SQL` path |
| `disk_check.sh` | `tap_server_stat.sh` | Not related to rserc_chk |
| `tap_monitor.sh` | cron | Not related to rserc_chk |
| `tap_server_stat.sh` | cron | Not related to rserc_chk |

---

## 7. Fixes Applied (This Revision)

| # | Issue | Severity | Fix |
|---|-------|----------|-----|
| 1 | SPOOL heredoc `<<'EOSQL'` prevented `${VAR}` expansion in SPOOL paths | **Critical** | Changed to `<<EOSQL` (unquoted) — SQL single-quotes are safe in unquoted heredocs |
| 2 | `count_files()` function defined but never called | Minor | Removed dead code |
| 3 | `recs_created.lis` not cleaned after use in `generate_hourly_reports()` | Minor | Added to `rm -f` cleanup line |
| 4 | `cleanup_and_exit()` called twice (trap EXIT + explicit) | Minor | Added `_CLEANUP_DONE` guard flag |
| 5 | Script not testable — no sourcing guard | Design | Added `BASH_SOURCE` guard so functions can be sourced without executing `main()` |
| 6 | SP_ID extraction position (awk position 35) based on VMS full paths | **Warning** | Documented — position must be verified against actual Linux `mrlog` filenames |

---

## 8. Configuration Overrides

All key paths and thresholds can be overridden via environment variables:

```bash
# Example: override for a test environment
export TAP_ARCHIVE_DIR="/test/archive"
export MAX=100
export SPLIT_MAX=200
./rserc_chk.sh
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `TAP_ARCHIVE_DIR` | `/data/tap/R53_TAPLIVE/TAP/ARCHIVE` | Archive check directory |
| `TAP_COLLECT_DIR` | `/data/tap/R53_TAPLIVE/TAP/COLLECT` | Collection check directory |
| `TAP_READY_FOR_PRICING` | `/data/tap/R53_TAPLIVE/TAP/TO_PRICE` | Pricing input directory |
| `TAP_OB_PRICED` | `/data/tap/R53_TAPLIVE/TAP/PRICED` | Priced output directory |
| `TAP_OB_SPLIT` | `/data/tap/R53_TAPLIVE/TAP/SPLIT` | Split base directory |
| `TAP_OUTGOING_SP` | `/data/tap/R53_TAPLIVE/TAP/OG_SP` | Outgoing SP directory |
| `TAP_PERIOD_DIR` | `/data/tap/R53_TAPLIVE/TAP/PERIOD` | Period directory |
| `TAP_LOG_DIR` | `/data/tap/R53_TAPLIVE/TAP/LOG` | Log directory |
| `MAX` | `400` | File count threshold for collect/price/priced |
| `SPLIT_MAX` | `600` | File count threshold per-SPID split dir |
| `WORK_DIR` | `/tmp/rserc_chk_$$` | Temporary working directory |
| `LOG_FILE` | `${TAP_LOG_DIR}/rserc_chk.log` | Log file path |
| `RERUN_RSERC_SQL` | `rerun_rserc.sql` | Path to rerun SQL script |
