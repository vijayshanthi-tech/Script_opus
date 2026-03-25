#!/bin/bash
###############################################################################
# Script Name  : rserc_chk.sh
# Converted From: RSERC_CHK.COM (VMS DCL)
# Description   : Monitors TAP outbound processing directories for file
#                 backlog, generates hourly RSERC/CDR reports via Oracle,
#                 emails alerts and reports, and auto-recovers failed RSERCs.
#                 Runs continuously from 06:00 until 23:00 each day,
#                 re-submitting itself for the next day at 06:00.
#
# Environment   : Linux / Bash 4+
# Dependencies  : Oracle sqlplus, mailx, cron or at (for scheduling)
#
# Original Author : (VMS legacy — RSERC_CHK.COM)
# Converted By    : VMS-to-Linux conversion
#
# VMS Sections Mapped:
#   set proc/priv=all              -> run as appropriate user
#   submit/after=tomorrow"+6"      -> schedule_next_run()
#   start:                         -> check_tap_directories()
#   Rserc_created_and_CDRs_processed: -> generate_hourly_reports()
#   rserc_check:                   -> (inside generate_hourly_reports)
#   start_1:                       -> check_rserc_failures()
#   check_hour:                    -> main() loop control
#   finish:                        -> cleanup_and_exit()
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

# ---- Logging helper (VMS: wso "message") ----
log_msg() {
    local msg="$1"
    local dttm
    dttm=$(date '+%d-%b-%Y %H:%M:%S')
    echo "${dttm} - ${msg}" | tee -a "${LOG_FILE}"
}

# ---- Send email alert with empty body (VMS: mail NL: "addr"/sub="subject") ----
send_alert() {
    local subject="$1"
    echo "" | mailx -s "${subject}" "${EMAIL_L2}" 2>/dev/null
    log_msg "${subject}"
}

# ---- Send email with file body (VMS: MAIL file "addr"/sub="subject") ----
send_report() {
    local subject="$1"
    local file="$2"
    shift 2
    for recipient in "$@"; do
        mailx -s "${subject}" "${recipient}" < "${file}" 2>/dev/null
    done
}

###############################################################################
#  Schedule next day's run (VMS: submit/after=tomorrow"+6"/keep/log=...)
#  On Linux, prefer a crontab entry:
#    0 6 * * * /path/to/rserc_chk.sh >> .../LOG/rserc_chk.log 2>&1
###############################################################################

schedule_next_run() {
    echo "$(readlink -f "$0")" | at 06:00 tomorrow 2>/dev/null || \
        log_msg "WARNING: Could not schedule next run via 'at'. Ensure cron is configured."
}

###############################################################################
#  Generate SPID list from Oracle
#  VMS: sqlplus -s / -> SPOOL spid_list.lis -> select SP_ID from service_providers
###############################################################################

generate_spid_list() {
    log_msg "Creating SPID list"
    SPID_LIST="${WORK_DIR}/spid_list.lis"

    sqlplus -s / <<'EOSQL' > "${SPID_LIST}"
SET VERIFY OFF
SET FEEDBACK OFF
SET TERMOUT OFF
SET PAGESIZE 0
SELECT SP_ID FROM service_providers;
EXIT
EOSQL
}

###############################################################################
#  Check TAP directories for file backlog
#  VMS sections: start: -> notify_check: -> to_price_check: -> priced_check: ->
#                loop: (per-SPID split check)
###############################################################################

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

###############################################################################
#  Generate RSERC and CDR hourly reports via Oracle, email them, check zero
#  VMS sections: Rserc_created_and_CDRs_processed: -> rserc_check:
###############################################################################

generate_hourly_reports() {
    log_msg "Creating Tap hourly reports"

    local FILES_CREATED="${WORK_DIR}/files_created.lis"
    local FILES_CREATED1="${WORK_DIR}/files_created1.lis"
    local RECS_CREATED="${WORK_DIR}/recs_created.lis"

    # Unquoted heredoc (<<EOSQL) so shell variables in SPOOL paths expand.
    # SQL single-quotes are safe — bash heredocs do not interpret them.
    sqlplus -s / <<EOSQL
SET VERIFY OFF
SET FEEDBACK OFF
SET PAGESIZE 1
BREAK ON DAT SKIP 1
SET NUMFORMAT 9,999,999,990
COMPUTE SUM LABEL 'DAY TOTAL' OF FILES_PROCESSED ON DAT
SET TRANSACTION READ ONLY;
SPOOL ${FILES_CREATED}
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
SPOOL ${FILES_CREATED1}
SELECT 'FILE_COUNT=',COUNT(*) FROM outgoing_outbound_call_files
 WHERE TRUNC(OOCF_CREATED_DTTM)=TRUNC(SYSDATE-4/24);
SPOOL OFF
BREAK ON DATR SKIP 1
SET NUMFORMAT 9,999,999,990
COMPUTE SUM LABEL 'DAY TOTAL' OF RECORDS_PROCESSED ON DATR
SPOOL ${RECS_CREATED}
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

###############################################################################
#  Check for RSERC failures and auto-recover
#  VMS sections: start_1: -> .don check -> .tmp check -> recovery loop
###############################################################################

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
        # VMS f$extract(34,3,rec) operates on full VMS DIR output (includes path).
        # On Linux we output filenames only. Position 35 (1-based awk) must be
        # verified against actual mrlog filenames. Adjust offset if SP_ID is
        # at a different position in the filename.
        if [ -s "${MRLOG_LIS}" ]; then
            local MRLOG_SORTED="${WORK_DIR}/mrlog_sorted.lis"
            awk '{ print substr($0, 35, 3) }' "${MRLOG_LIS}" | sort -u > "${MRLOG_SORTED}"

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

###############################################################################
#  Main execution loop
#  VMS: start: -> start_1: -> check_hour: loop structure
#  Outer loop = hourly full cycle (dirs + reports)
#  Inner loop = 10-minute RSERC failure checks until hour changes
###############################################################################

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

###############################################################################
#  Cleanup and exit (VMS: finish: section)
###############################################################################

cleanup_and_exit() {
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
