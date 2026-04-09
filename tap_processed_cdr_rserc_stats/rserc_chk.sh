#!/bin/bash
###############################################################################
# Script Name    : rserc_chk.sh
# Converted From : RSERC_CHK.COM (OpenVMS DCL)
# Description    : Monitors TAP outbound processing directories for file
#                  backlog, generates hourly RSERC/CDR reports via Oracle,
#                  emails alerts and reports, and auto-recovers failed RSERCs.
#                  Runs continuously from 06:00 until 23:00 each day,
#                  re-submitting itself for the next day at 06:00.
#
# Environment    : Linux / Bash 4+
# Dependencies   : Oracle sqlplus (on PATH, OS-authenticated),
#                  mailx (with a functioning MTA — postfix/sendmail),
#                  cron or at daemon (for next-day scheduling)
#
# Original Author : (VMS legacy — RSERC_CHK.COM)
# Converted By    : VMS-to-Linux migration
#
# ------- OpenVMS-to-Linux Section Mapping -------
#   VMS DCL Label / Command              ->  Linux Bash Function
#   ────────────────────────────────────────────────────────────
#   $ set proc/priv=all                  ->  (run as appropriate OS user)
#   $ submit/after=tomorrow"+6"...       ->  schedule_next_run()
#   $ sqlplus ... SPOOL spid_list.lis    ->  generate_spid_list()
#   $ start:                             ->  check_tap_directories()
#     notify_check: / to_price_check:
#     priced_check: / loop:
#   $ Rserc_created_and_CDRs_processed:  ->  generate_hourly_reports()
#   $ rserc_check:                       ->  (inside generate_hourly_reports)
#   $ start_1:                           ->  check_rserc_failures()
#   $ check_hour: / wait / goto          ->  main() loop control
#   $ finish:                            ->  cleanup_and_exit()
#
# ------- Usage -------
#   Direct run (foreground):
#       ./rserc_chk.sh
#
#   Background (production):
#       nohup ./rserc_chk.sh >> /data/tap/.../LOG/rserc_chk.log 2>&1 &
#
#   Cron (recommended for daily scheduling):
#       0 6 * * * /path/to/rserc_chk.sh >> .../LOG/rserc_chk.log 2>&1
#
#   Source for unit testing (does NOT execute main):
#       source rserc_chk.sh
#       # now call individual functions: log_msg "test", etc.
#
# ------- Environment Variable Overrides -------
#   All TAP_* directory paths, MAX, SPLIT_MAX, WORK_DIR, LOG_FILE,
#   RERUN_RSERC_SQL can be overridden via environment variables before
#   running the script. See CONFIGURATION section below.
###############################################################################

###############################################################################
#                       CONFIGURATION
###############################################################################

# --- Email recipients ---
EMAIL_L2="Telefonica_UK.L2@accenture.com"
EMAIL_APOLLO="VMO2_ApolloL2@accenture.com"
EMAIL_TAP_SUPPORT="TAPSupport@o2.com"

# --- Directory mappings (VMS logical -> Linux path) ---
# Defaults can be overridden via environment variables (for testing/deployment)
TAP_ARCHIVE_DIR="${TAP_ARCHIVE_DIR:-/data/tap/R53_TAPLIVE/TAP/ARCHIVE}"
TAP_COLLECT_DIR="${TAP_COLLECT_DIR:-/data/tap/R53_TAPLIVE/TAP/COLLECT}"
TAP_READY_FOR_PRICING="${TAP_READY_FOR_PRICING:-/data/tap/R53_TAPLIVE/TAP/TO_PRICE}"
TAP_OB_PRICED="${TAP_OB_PRICED:-/data/tap/R53_TAPLIVE/TAP/PRICED}"
TAP_OB_SPLIT="${TAP_OB_SPLIT:-/data/tap/R53_TAPLIVE/TAP/SPLIT}"
TAP_OUTGOING_SP="${TAP_OUTGOING_SP:-/data/tap/R53_TAPLIVE/TAP/OG_SP}"
TAP_PERIOD_DIR="${TAP_PERIOD_DIR:-/data/tap/R53_TAPLIVE/TAP/PERIOD}"
TAP_LOG_DIR="${TAP_LOG_DIR:-/data/tap/R53_TAPLIVE/TAP/LOG}"

# --- Thresholds (VMS: max=400, split_max=600) ---
MAX="${MAX:-400}"
SPLIT_MAX="${SPLIT_MAX:-600}"

# --- Working directory for temp files ---
WORK_DIR="${WORK_DIR:-/tmp/rserc_chk_$$}"
mkdir -p "${WORK_DIR}"

# --- Log file ---
LOG_FILE="${LOG_FILE:-${TAP_LOG_DIR}/rserc_chk.log}"

# --- SQL script for RSERC re-run (VMS: @rerun_rserc) ---
RERUN_RSERC_SQL="${RERUN_RSERC_SQL:-rerun_rserc.sql}"

# --- Guard against double cleanup ---
_CLEANUP_DONE=0

# --- Run counter (tracks hourly iterations) ---
run_count=0

###############################################################################
#                       FUNCTIONS
###############################################################################

# Function: log_msg
# Purpose: Writes a timestamped message to both stdout and the log file.
#          Mirrors the VMS pattern: wso "''dttm' - <message>" where wso is
#          WRITE SYS$OUTPUT and f$time() provides the timestamp.
# Inputs:
#   $1 — The message text to log
# Outputs:
#   Prints "DD-Mon-YYYY HH:MM:SS - <message>" to stdout
#   Appends the same line to ${LOG_FILE}
# Side Effects:
#   - Appends to the log file (creates it if it does not exist)
#   - Uses date(1) to generate the timestamp
# Usage:
#   log_msg "RSERC CHK started"
#   log_msg "There are 450 files in tap collection"
log_msg() {
    local msg="$1"
    local dttm
    # Generate timestamp in DD-Mon-YYYY HH:MM:SS format
    # VMS equivalent: dttm=f$time()
    dttm=$(date '+%d-%b-%Y %H:%M:%S')
    # Write to stdout AND append to log file simultaneously
    # VMS only wrote to SYS$OUTPUT; the batch queue redirected to the log.
    echo "${dttm} - ${msg}" | tee -a "${LOG_FILE}"
}

# Function: send_alert
# Purpose: Sends an email alert with an empty body (subject-only notification)
#          and logs the alert message. Mirrors VMS: mail NL: "addr"/sub="..."
#          where NL: is the null device (empty body).
# Inputs:
#   $1 — The email subject line / alert message text
# Outputs:
#   Sends an email to EMAIL_L2 with empty body and the given subject
#   Logs the subject text via log_msg()
# Side Effects:
#   - Invokes mailx(1) which requires a functioning MTA (postfix/sendmail)
#   - Mail delivery failures are silently suppressed (2>/dev/null)
# Usage:
#   send_alert "No Call files processed by TAP collection in last four hours"
#   send_alert "There are 450 files in tap collection"
send_alert() {
    local subject="$1"
    # Pipe empty string as body — VMS equivalent: mail NL: "addr"/sub="..."
    echo "" | mailx -s "${subject}" "${EMAIL_L2}" 2>/dev/null
    log_msg "${subject}"
}

# Function: send_report
# Purpose: Sends an email with a file as the email body to one or more
#          recipients. Mirrors VMS: MAIL/SUBJ="..." file "recipient"
# Inputs:
#   $1       — Email subject line
#   $2       — Path to the file whose contents become the email body
#   $3...$N  — One or more recipient email addresses
# Outputs:
#   Sends one email per recipient, each containing the file contents as body
# Side Effects:
#   - Invokes mailx(1) once per recipient
#   - Mail delivery failures are silently suppressed (2>/dev/null)
#   - Reads the file via stdin redirection (< file)
# Usage:
#   send_report "TAP - Report" "/tmp/report.lis" "user1@example.com"
#   send_report "TAP - Report" "/tmp/report.lis" "user1@ex.com" "user2@ex.com"
send_report() {
    local subject="$1"
    local file="$2"
    shift 2
    # Loop through all recipients — VMS required one MAIL command per recipient
    for recipient in "$@"; do
        mailx -s "${subject}" "${recipient}" < "${file}" 2>/dev/null
    done
}

# Function: schedule_next_run
# Purpose: Schedules this script to execute again at 06:00 tomorrow.
#          Mirrors VMS: submit/after=tomorrow"+6"/keep/log=tap_log_dir:rserc_chk.log/noprint
#          The VMS SUBMIT command placed the job in the batch queue scheduler;
#          on Linux we use the 'at' daemon or rely on cron.
# Inputs:
#   None (uses $0 to determine this script's own path)
# Outputs:
#   On success: a job is registered with the 'at' daemon for 06:00 tomorrow
#   On failure: a WARNING message is logged suggesting cron configuration
# Side Effects:
#   - Invokes at(1); requires atd service to be running
#   - Uses readlink(1) to resolve the script's absolute path
#   - If 'at' is unavailable, no job is scheduled (cron must be configured)
# Usage:
#   schedule_next_run
#   # Alternative (recommended): use crontab instead:
#   # 0 6 * * * /path/to/rserc_chk.sh >> .../LOG/rserc_chk.log 2>&1
schedule_next_run() {
    # Resolve absolute path of this script and pipe to 'at' for next-day 06:00
    echo "$(readlink -f "$0")" | at 06:00 tomorrow 2>/dev/null || \
        log_msg "WARNING: Could not schedule next run via 'at'. Ensure cron is configured."
}

# Function: generate_spid_list
# Purpose: Queries Oracle for all Service Provider IDs (SP_ID) from the
#          service_providers table and writes them to a file (one per line).
#          This list is used later by check_tap_directories() to iterate
#          through per-SPID split directories.
#          Mirrors VMS: sqlplus -s / -> SPOOL spid_list.lis -> SELECT SP_ID...
# Inputs:
#   None (uses OS-authenticated Oracle connection via sqlplus /)
# Outputs:
#   Creates file ${WORK_DIR}/spid_list.lis containing one SP_ID per line
#   Sets global variable SPID_LIST to the file path
#   Logs "Creating SPID list" message
# Side Effects:
#   - Executes sqlplus(1) — requires ORACLE_HOME, ORACLE_SID, and
#     OS-authenticated Oracle access
#   - Writes to WORK_DIR
# Usage:
#   generate_spid_list
#   cat "${SPID_LIST}"   # inspect the output
generate_spid_list() {
    log_msg "Creating SPID list"
    SPID_LIST="${WORK_DIR}/spid_list.lis"

    # Quoted heredoc (<<'EOSQL') prevents shell variable expansion inside SQL.
    # SET commands suppress Oracle banners so only raw SP_ID values are output.
    sqlplus -s / <<'EOSQL' > "${SPID_LIST}"
SET VERIFY OFF
SET FEEDBACK OFF
SET TERMOUT OFF
SET PAGESIZE 0
SELECT SP_ID FROM service_providers;
EXIT
EOSQL
}

# Function: check_tap_directories
# Purpose: Monitors five categories of TAP pipeline directories for file
#          backlogs and sends email alerts when thresholds are exceeded.
#          Mirrors VMS sections: start: -> notify_check: -> to_price_check:
#          -> priced_check: -> loop: (per-SPID split check)
#
#          The five checks are:
#          1. Archive — cd*.dat files modified within last 4 hours (zero = alert)
#          2. Collect — CD?????GBRCN*.dat file count > MAX (400) = alert
#          3. To-Price — CD?????GBRCN*.DAT file count > MAX (400) = alert
#          4. Priced  — CD?????GBRCN*.PRC file count > MAX (400) = alert
#          5. Per-SPID Split — CD*.SPLIT file count > SPLIT_MAX (600) = alert
#
# Inputs:
#   Environment: TAP_ARCHIVE_DIR, TAP_COLLECT_DIR, TAP_READY_FOR_PRICING,
#                TAP_OB_PRICED, TAP_OB_SPLIT (directory paths)
#   Globals:     MAX (threshold, default 400), SPLIT_MAX (default 600),
#                SPID_LIST (file path from generate_spid_list),
#                run_count (incremented each call)
# Outputs:
#   Sends email alerts via send_alert() when thresholds are exceeded
#   Increments the global run_count by 1
# Side Effects:
#   - Invokes find(1) on each TAP directory
#   - May send emails via send_alert() -> mailx
#   - Reads SPID_LIST file line by line
# Usage:
#   check_tap_directories   # call once per hourly cycle
check_tap_directories() {
    log_msg "Checking TAP directories"
    run_count=$((run_count + 1))

    # ---- Archive check (VMS: dir .../sin="-4" — files from last 4 hours) ----
    # VMS: if dir fails ($status .nes. "%X00000001") -> no files -> alert
    local archive_count
    archive_count=$(find "${TAP_ARCHIVE_DIR}" -maxdepth 1 -iname 'cd*.dat' -mmin -240 2>/dev/null | wc -l)
    if [ "${archive_count}" -eq 0 ]; then
        send_alert "No Call files processed by TAP collection in last four hours"
    fi

    # ---- Collect directory (VMS: CD%%%%%GBRCN*.dat) ----
    # VMS: count files, if count > max -> alert
    local collect_count
    collect_count=$(find "${TAP_COLLECT_DIR}" -maxdepth 1 -iname 'CD?????GBRCN*.dat' 2>/dev/null | wc -l)
    if [ "${collect_count}" -gt "${MAX}" ]; then
        send_alert "There are ${collect_count} files in tap collection"
    fi

    # ---- To-Price directory (VMS: CD%%%%%GBRCN*.DAT) ----
    local toprice_count
    toprice_count=$(find "${TAP_READY_FOR_PRICING}" -maxdepth 1 -iname 'CD?????GBRCN*.DAT' 2>/dev/null | wc -l)
    if [ "${toprice_count}" -gt "${MAX}" ]; then
        send_alert "There are ${toprice_count} files in TAP pricing"
    fi

    # ---- Priced directory (VMS: CD%%%%%GBRCN*.PRC) ----
    local priced_count
    priced_count=$(find "${TAP_OB_PRICED}" -maxdepth 1 -iname 'CD?????GBRCN*.PRC' 2>/dev/null | wc -l)
    if [ "${priced_count}" -gt "${MAX}" ]; then
        send_alert "There are ${priced_count} files in TAP spliting"
    fi

    # ---- Per-SPID split directories ----
    # VMS: read spid_list.lis, zero-pad to 3 digits, check split dir
    if [ -f "${SPID_LIST}" ]; then
        while IFS= read -r inpro; do
            local spid
            spid=$(printf "%03d" "$(echo "${inpro}" | tr -d '[:space:]')" 2>/dev/null) || continue

            local split_dir="${TAP_OB_SPLIT}/${spid}"
            if [ -d "${split_dir}" ]; then
                local split_count
                split_count=$(find "${split_dir}" -maxdepth 1 -iname 'CD*.SPLIT' 2>/dev/null | wc -l)
                if [ "${split_count}" -gt "${SPLIT_MAX}" ]; then
                    send_alert "There are ${split_count} files in TAP Distribute for spid ${spid}"
                fi
            fi
        done < "${SPID_LIST}"
    fi
}

# Function: generate_hourly_reports
# Purpose: Queries Oracle for hourly RSERC file-creation and roaming CDR
#          processing statistics, emails the reports to L2/Apollo, and
#          checks whether zero RSERCs have been created in the last 4 hours.
#          Mirrors VMS sections: Rserc_created_and_CDRs_processed: and
#          rserc_check:
#
#          Three Oracle spool outputs are produced:
#            files_created.lis  — Hourly RSERC file creation (grouped by hour)
#            files_created1.lis — Count of RSERCs created in last 4 hours
#            recs_created.lis   — Hourly roaming CDR stats (grouped by hour)
#
# Inputs:
#   Globals: WORK_DIR, EMAIL_L2, EMAIL_APOLLO, run_count
#   Oracle:  outgoing_outbound_call_files table, PROCESS_STATISTICS table
# Outputs:
#   Emails files_created.lis to EMAIL_L2
#   Emails recs_created.lis to EMAIL_L2 and EMAIL_APOLLO
#   Sends zero-RSERC alert if FILE_COUNT=0 and run_count > 1
# Side Effects:
#   - Executes a single sqlplus session producing three spool files
#   - Sends up to 3 emails (2 reports + 1 optional alert)
#   - Creates and then deletes temporary spool files in WORK_DIR
#   - Uses pushd/popd to run sqlplus from WORK_DIR so that SPOOL
#     creates files there (SQL*Plus SPOOL resolves relative to CWD)
# Usage:
#   run_count=2
#   generate_hourly_reports
generate_hourly_reports() {
    log_msg "Creating Tap hourly reports"

    local FILES_CREATED="${WORK_DIR}/files_created.lis"
    local FILES_CREATED1="${WORK_DIR}/files_created1.lis"
    local RECS_CREATED="${WORK_DIR}/recs_created.lis"

    # Change to WORK_DIR so SQL*Plus SPOOL creates files there, not in CWD.
    # Quoted heredoc (<<'EOSQL') is safe — no shell variables needed inside SQL.
    pushd "${WORK_DIR}" > /dev/null 2>&1 || true
    sqlplus -s / <<'EOSQL'
SET VERIFY OFF
SET FEEDBACK OFF
SET PAGESIZE 1
BREAK ON DAT SKIP 1
SET NUMFORMAT 9,999,999,990
COMPUTE SUM LABEL 'DAY TOTAL' OF FILES_PROCESSED ON DAT
SET TRANSACTION READ ONLY;
SPOOL files_created.lis
SET HEADING OFF;
SELECT ' ** Tap hourly report ** ' FROM DUAL;
SET HEADING ON;
SELECT TO_CHAR(SYSDATE, 'DD-MON-YYYY HH24:MI:SS') DATE_TIME FROM DUAL;
SELECT 'DATE            HOUR     FILES_PROCESSED' FROM DUAL;
SELECT SUBSTR(TO_CHAR(OOCF_CREATED_DTTM,'YYYY-MM-DD HH24'),1,10) DAT,
       SUBSTR(TO_CHAR(OOCF_CREATED_DTTM,'YYYY-MM-DD HH24'),12,2) HOUR_OF_THE_DAY,
       COUNT(*) FILES_PROCESSED
  FROM outgoing_outbound_call_files
 WHERE TRUNC(OOCF_CREATED_DTTM)=TRUNC(SYSDATE)
 GROUP BY TO_CHAR(OOCF_CREATED_DTTM,'YYYY-MM-DD HH24')
 ORDER BY TO_CHAR(OOCF_CREATED_DTTM,'YYYY-MM-DD HH24');
SPOOL OFF
SET NUMFORMAT 999999999
SPOOL files_created1.lis
SELECT 'FILE_COUNT=',COUNT(*) FROM outgoing_outbound_call_files
 WHERE TRUNC(OOCF_CREATED_DTTM)=TRUNC(SYSDATE-4/24);
SPOOL OFF
BREAK ON DATR SKIP 1
SET NUMFORMAT 9,999,999,990
COMPUTE SUM LABEL 'DAY TOTAL' OF RECORDS_PROCESSED ON DATR
SPOOL recs_created.lis
SET HEADING OFF;
SELECT ' ** Tap hourly report for incoming roaming CDRs** ' FROM DUAL;
SET HEADING ON;
SELECT TO_CHAR(SYSDATE, 'DD-MON-YYYY HH24:MI:SS') DATE_TIME FROM DUAL;
SELECT 'DATE            HOUR     RECORDS_PROCESSED' FROM DUAL;
SELECT SUBSTR(TO_CHAR(PS_RUN_DTTM,'YYYY-MM-DD HH24'),1,10) DATR,
       SUBSTR(TO_CHAR(PS_RUN_DTTM,'YYYY-MM-DD HH24'),12,2) HOUR_OF_THE_DAY,
       SUM(PS_RECORD_COUNT) RECORDS_PROCESSED
  FROM PROCESS_STATISTICS
 WHERE TRUNC(PS_RUN_DTTM)=TRUNC(SYSDATE) AND PS_PROCESS_NAME='PRICING'
 GROUP BY TO_CHAR(PS_RUN_DTTM,'YYYY-MM-DD HH24')
 ORDER BY TO_CHAR(PS_RUN_DTTM,'YYYY-MM-DD HH24');
SPOOL OFF
EXIT
EOSQL
    popd > /dev/null 2>&1 || true

    # ---- Email RSERC file report ----
    if [ -f "${FILES_CREATED}" ]; then
        send_report "TAP - Processed RESRC File Report" "${FILES_CREATED}" "${EMAIL_L2}"
        log_msg "TAP - Processed RESRC File Report sent to L2"
    fi

    # ---- Email roaming CDRs report ----
    if [ -f "${RECS_CREATED}" ]; then
        send_report "TAP - Processed roaming CDRs Report" "${RECS_CREATED}" "${EMAIL_L2}" "${EMAIL_APOLLO}"
        log_msg "TAP - Processed roaming CDRs Report sent to L2"
    fi

    # ---- RSERC zero-file check (VMS: rserc_check:) ----
    # Alert if no RSERCs created in last 4 hours (skip on first run)
    if [ -f "${FILES_CREATED1}" ]; then
        local total_files=0
        local file_line
        file_line=$(grep "FILE_COUNT=" "${FILES_CREATED1}" 2>/dev/null | head -1)
        if [ -n "${file_line}" ]; then
            total_files=$(echo "${file_line}" | sed 's/.*FILE_COUNT=[[:space:]]*//' | tr -d '[:space:]')
            total_files=$((total_files + 0))
        fi

        if [ "${total_files}" -eq 0 ] && [ "${run_count}" -ne 1 ]; then
            send_alert "There are no RSERC created in last 4 hours"
        fi
    fi

    # ---- Cleanup temp spool files ----
    rm -f "${FILES_CREATED}" "${FILES_CREATED1}" "${RECS_CREATED}" 2>/dev/null
}

# Function: check_rserc_failures
# Purpose: Detects failed RSERC assembly runs by inspecting the outgoing SP
#          directory for orphaned .don and .tmp files. If .tmp files are found,
#          the function performs automatic recovery: it identifies affected
#          SP_IDs from mrlog*.tmp filenames, deletes the orphaned files, and
#          re-triggers RSERC assembly via sqlplus @rerun_rserc.sql per SP_ID.
#          Mirrors VMS section: start_1: -> .don check -> .tmp check -> loop.
#
#          Flow:
#          1. Check if assembly/dist processes are running (ps -ef). If yes,
#             skip checks — the process is still active.
#          2. Check for .don files -> alert TAP Support + L2 (no auto-fix).
#          3. Check for .tmp files -> alert + auto-recovery:
#             a. List mrlog*.tmp filenames
#             b. Delete all .tmp from TAP_OUTGOING_SP and TAP_PERIOD_DIR
#             c. Extract SP_ID from position 35 of each mrlog filename
#             d. Call sqlplus @rerun_rserc.sql for each unique SP_ID
#
# Inputs:
#   Globals: TAP_OUTGOING_SP, TAP_PERIOD_DIR, WORK_DIR, RERUN_RSERC_SQL,
#            EMAIL_TAP_SUPPORT, EMAIL_L2
# Outputs:
#   Sends alert emails if .don or .tmp files found
#   Re-triggers RSERC assembly for each affected SP_ID
# Side Effects:
#   - Invokes ps(1) to check running processes
#   - DELETES .tmp files from TAP_OUTGOING_SP and TAP_PERIOD_DIR
#   - Invokes sqlplus @rerun_rserc.sql for recovery
#   - Creates and deletes temp files in WORK_DIR
#   - Note: "Procudure" in the .tmp alert is the original VMS typo, preserved
# Usage:
#   check_rserc_failures   # called every 10 minutes in the inner loop
check_rserc_failures() {
    log_msg "Checking for RSERC failures"

    local RSERC_CHK_LIS="${WORK_DIR}/rserc_chk.lis"

    # VMS: sh que *ass*/out=rserc_chk.lis; sea rserc_chk.lis dist
    ps -ef | grep -i "assemb\|dist" | grep -v grep > "${RSERC_CHK_LIS}" 2>/dev/null

    # VMS: if "dist" found -> goto check_hour (skip failure checks)
    if grep -qi "dist" "${RSERC_CHK_LIS}" 2>/dev/null; then
        rm -f "${RSERC_CHK_LIS}" 2>/dev/null
        return 0
    fi

    # ---- .don file check (VMS: dir tap_outgoing_sp:*.don;*) ----
    local don_count
    don_count=$(find "${TAP_OUTGOING_SP}" -maxdepth 1 -iname '*.don' 2>/dev/null | wc -l)
    if [ "${don_count}" -gt 0 ]; then
        local RSERC_FAILURE_2="${WORK_DIR}/rserc_failure_2.txt"
        find "${TAP_OUTGOING_SP}" -maxdepth 1 -iname '*.don' -ls > "${RSERC_FAILURE_2}" 2>/dev/null

        send_report "RSERC Failure - Procedure 841 - *.DON files left out" "${RSERC_FAILURE_2}" \
            "${EMAIL_TAP_SUPPORT}" "${EMAIL_L2}"
        log_msg "RSERC Failure - Procedure 841 - *.DON files left out"
    fi

    # ---- .tmp file check + auto-recovery ----
    local tmp_count
    tmp_count=$(find "${TAP_OUTGOING_SP}" -maxdepth 1 -iname '*.tmp' 2>/dev/null | wc -l)
    if [ "${tmp_count}" -gt 0 ]; then
        local RSERC_FAILURE_1="${WORK_DIR}/rserc_failure_1.txt"
        find "${TAP_OUTGOING_SP}" -maxdepth 1 -iname '*.tmp' -ls > "${RSERC_FAILURE_1}" 2>/dev/null

        # "Procudure" is the original VMS typo, preserved for consistency
        send_report "RSERC Failure - Procudure 841 - *.TMP files left out - Recovering" "${RSERC_FAILURE_1}" \
            "${EMAIL_TAP_SUPPORT}" "${EMAIL_L2}"
        log_msg "RSERC Failure - Procudure 841 - *.TMP files left out - Recovering"

        # ---- Recovery: list mrlog*.tmp FIRST, then delete all .tmp ----
        local MRLOG_LIS="${WORK_DIR}/mrlog.lis"

        # VMS: dir/nohead/notrail tap_outgoing_sp:mrlog*.tmp;*/excl=*.dat/out=mrlog.lis
        find "${TAP_OUTGOING_SP}" -maxdepth 1 -iname 'mrlog*.tmp' ! -iname '*.dat' \
            -exec basename {} \; > "${MRLOG_LIS}" 2>/dev/null

        # VMS: del tap_outgoing_sp:*.tmp;* / del tap_ob_period:*.tmp;*
        find "${TAP_OUTGOING_SP}" -maxdepth 1 -iname '*.tmp' -delete 2>/dev/null
        find "${TAP_PERIOD_DIR}" -maxdepth 1 -iname '*.tmp' -delete 2>/dev/null

        # VMS: sort/nodup/key=(pos:35,siz=3) mrlog.lis
        # VMS f$extract(34,3,rec) operates on full VMS DIR output that
        # includes the path prefix DISK$CALL_DATA:[TAP.OB.OG_SP] (29 chars).
        # Position 35 (1-based) in VMS = position 6 within the filename.
        # Real filenames are MRLOG{SP_ID}.TMP (e.g. MRLOG007.TMP), so the
        # SP_ID starts at character 6 of the filename (1-based awk).
        if [ -s "${MRLOG_LIS}" ]; then
            local MRLOG_SORTED="${WORK_DIR}/mrlog_sorted.lis"
            awk '{ print substr($0, 6, 3) }' "${MRLOG_LIS}" | sort -u > "${MRLOG_SORTED}"

            while IFS= read -r sp_id; do
                sp_id=$(echo "${sp_id}" | tr -d '[:space:]')
                if [ -n "${sp_id}" ]; then
                    log_msg "Re-running RSERC for SP_ID: ${sp_id}"
                    sqlplus -s / "@${RERUN_RSERC_SQL}" "${sp_id}" 2>&1 | tee -a "${LOG_FILE}"
                fi
            done < "${MRLOG_SORTED}"

            rm -f "${MRLOG_SORTED}" 2>/dev/null
        fi

        rm -f "${MRLOG_LIS}" 2>/dev/null
    fi

    rm -f "${RSERC_CHK_LIS}" 2>/dev/null
}

# Function: main
# Purpose: Orchestrates the entire monitoring process with a two-level loop.
#          Mirrors the VMS flow: start: -> start_1: -> check_hour: -> wait/goto.
#
#          Outer loop (runs each time the clock hour advances):
#            1. check_tap_directories() — full directory backlog scan
#            2. generate_hourly_reports() — Oracle reports + zero-RSERC check
#            3. Record last_hour
#
#          Inner loop (runs every 10 minutes within an hour):
#            1. check_rserc_failures() — failure detection + auto-recovery
#            2. If hour == 23 → exit (triggers cleanup via EXIT trap)
#            3. If hour advanced → break to outer loop
#            4. Otherwise → sleep 600 seconds (10 min)
#
# Inputs:
#   Command-line arguments (not currently used)
#   All environment variables / globals (see CONFIGURATION section)
# Outputs:
#   Log entries, email alerts, email reports, RSERC re-runs
# Side Effects:
#   - Calls schedule_next_run() (at daemon or cron)
#   - Calls generate_spid_list() (Oracle query)
#   - Runs from startup until hour 23, then returns 0
#   - EXIT trap invokes cleanup_and_exit()
#   - Sleeps for 600 seconds between inner-loop iterations
# Usage:
#   main "$@"   # called from the entry-point guard at bottom of script
main() {
    schedule_next_run
    log_msg "RSERC CHK started"
    generate_spid_list
    run_count=0

    local last_hour
    last_hour=$(date '+%H')

    while true; do
        check_tap_directories
        generate_hourly_reports

        # VMS: last_hour=f$extract(12,2,dttm)
        last_hour=$(date '+%H')

        # Inner loop: failure check every 10 min (VMS: start_1: -> check_hour:)
        while true; do
            check_rserc_failures

            local cur_hour
            cur_hour=$(date '+%H')

            # VMS: if cur_hour .eqs. "23" then goto finish
            if [ "${cur_hour}" = "23" ]; then
                return 0
            fi

            # VMS: if cur_hour .gt. last_hour then goto start
            if [ "${cur_hour}" -gt "${last_hour}" ]; then
                break
            fi

            # VMS: wait 00:10:00
            log_msg "Waiting for 10 mins"
            sleep 600
        done
    done
}

# Function: cleanup_and_exit
# Purpose: End-of-day cleanup — removes old log files (>30 days), temporary
#          work files, and the WORK_DIR directory. Includes a double-call
#          guard to prevent duplicate execution when triggered by both the
#          normal exit path and a signal handler (trap).
#          Mirrors VMS: finish: section (del/bef="-30-" ..., del rserc_failure*, etc.)
# Inputs:
#   Globals: _CLEANUP_DONE, TAP_LOG_DIR, WORK_DIR, LOG_FILE
# Outputs:
#   Logs "RSERC_CHK completed"
#   Deletes log files older than 30 days
#   Removes temporary files and WORK_DIR
# Side Effects:
#   - Invokes find(1) -delete on TAP_LOG_DIR for old logs
#   - Removes WORK_DIR recursively (rm -rf)
#   - Sets _CLEANUP_DONE=1 to prevent re-entry
# Usage:
#   cleanup_and_exit   # typically called via: trap cleanup_and_exit EXIT SIGTERM SIGINT
cleanup_and_exit() {
    # Double-call guard: prevent duplicate cleanup if triggered by trap + normal exit
    if [ "${_CLEANUP_DONE}" -eq 1 ]; then
        return 0
    fi
    _CLEANUP_DONE=1

    log_msg "RSERC_CHK completed"

    # VMS: del/bef="-30-" tap_log_dir:rserc_chk.log;*
    find "${TAP_LOG_DIR}" -name 'rserc_chk.log*' -mtime +30 -delete 2>/dev/null

    # VMS: del rserc_failure*.txt;* / del rserc_chk.lis;* / delete spid_list.lis;*
    rm -f "${WORK_DIR}"/rserc_failure*.txt 2>/dev/null
    rm -f "${WORK_DIR}"/rserc_chk.lis 2>/dev/null
    rm -f "${WORK_DIR}"/spid_list.lis 2>/dev/null
    rm -rf "${WORK_DIR}" 2>/dev/null
}

###############################################################################
#  ENTRY POINT — guarded so the script can be sourced for unit testing
###############################################################################

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap cleanup_and_exit EXIT SIGTERM SIGINT
    main "$@"
fi
