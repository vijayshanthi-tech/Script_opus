#!/bin/bash
###############################################################################
# Script Name  : tap_monitor.sh
# Converted From: TAP_MONITOR.COM (VMS DCL)
# Case ID       : TAPOP0280 / Spec ID: TAPSO280.DOC
# Description   : Monitors TAP files and processes in a continuous loop.
#                 Checks: Oracle connectivity, file warning limits for
#                 IBCC/OBCC/OBVP/OBSP directories, Oracle row counts,
#                 and ensures GAPS/GSDM background jobs are running.
#                 Sends operator alerts when thresholds are exceeded.
#
# Environment   : Linux / Bash
# Dependencies  : Oracle sqlplus, mailx (or wall for operator messages)
#
# Original Authors: S.R.Campbell (1998), P.Murphy (2001), Goutam B (2008),
#                   Rajesh K (2008)
# Converted By   : Automated VMS-to-Linux conversion
###############################################################################

set -o nounset

###############################################################################
#                       CONFIGURATION — EDIT THESE
###############################################################################

# --- Operator notification method ---
# VMS used REQUEST/REPLY/TO=operator. On Linux, use logger or mail.
OPERATOR_EMAIL="operator@localhost"

# --- Process name (for singleton check) ---
PROC_NAME="TAP_MONITOR"

# --- Default check interval (VMS: TAP_FILE_CHECK_PERIOD) ---
DEFAULT_CHECK_PERIOD=900   # 15 minutes in seconds (VMS: "00:15:00")

# --- Environment variables that should be defined (VMS logicals) ---
# These should be set as environment variables before running:
#   TAP_FILE_CHECK_PERIOD   - Check interval in seconds (default: 900)
#   TAP_IBCC_FILE_WARNING_LIMIT - Inbound call collection file limit
#   TAP_OBCC_FILE_WARNING_LIMIT - Outbound call collection file limit
#   TAP_OBVP_FILE_WARNING_LIMIT - Outbound validation/pricing file limit
#   TAP_OBSP_FILE_WARNING_LIMIT - Outbound splitting file limit
#   TAP_CLOSEDOWN_MONITOR   - Set to any value to trigger shutdown
#   TAP_CLOSEDOWN_ALL       - Datetime string; shutdown if current time > this

# --- Directory mappings (VMS logicals → Linux paths) ---
TAP_IB_RECEIVE_FROM_SDM="/data/call_data/tap/ib/receive_from_sdm"

# --- PID file for singleton enforcement ---
PID_FILE="/tmp/${PROC_NAME}.pid"
LOG_FILE="${TAP_LOG_DIR}/tap_monitor.log"

###############################################################################
#                       FUNCTIONS
###############################################################################

log_msg() {
    local dttm
    dttm=$(date '+%d-%b-%Y %H:%M:%S')
    echo "${dttm} - $1" | tee -a "${LOG_FILE}" 2>/dev/null
}

# ---- Operator notification (VMS: REQUEST/REPLY/TO=operator) ----
send_request() {
    local message="$1"
    log_msg "ALERT: ${message}"
    # Send via logger (syslog) for operator visibility
    logger -t "${PROC_NAME}" "ALERT: ${message}" 2>/dev/null
    # Also send email alert
    echo "${message}" | mailx -s "${PROC_NAME} Alert: ${message}" "${OPERATOR_EMAIL}" 2>/dev/null
}

# ---- Singleton check: ensure only one instance runs ----
check_singleton() {
    if [ -f "${PID_FILE}" ]; then
        local existing_pid
        existing_pid=$(cat "${PID_FILE}" 2>/dev/null)
        if [ -n "${existing_pid}" ] && kill -0 "${existing_pid}" 2>/dev/null; then
            echo "${PROC_NAME} is already running (PID: ${existing_pid})"
            exit 1
        fi
    fi
    echo $$ > "${PID_FILE}"
}

# ---- Cleanup on exit ----
cleanup() {
    rm -f "${PID_FILE}" 2>/dev/null
    log_msg "${PROC_NAME} exiting"
}
trap cleanup EXIT SIGTERM SIGINT

###############################################################################
#  CHECK: File check period logical/env
###############################################################################

check_file_check_period() {
    local status=1
    local period="${TAP_FILE_CHECK_PERIOD:-}"

    if [ -z "${period}" ]; then
        TAP_FILE_CHECK_PERIOD="${DEFAULT_CHECK_PERIOD}"
        export TAP_FILE_CHECK_PERIOD
        status=3
        return ${status}
    fi

    # Validate it's a number
    if ! [[ "${period}" =~ ^[0-9]+$ ]]; then
        TAP_FILE_CHECK_PERIOD="${DEFAULT_CHECK_PERIOD}"
        export TAP_FILE_CHECK_PERIOD
        status=5
        return ${status}
    fi

    return ${status}
}

###############################################################################
#  CHECK: Oracle connectivity
###############################################################################

check_oracle() {
    local status=1
    local result
    result=$(sqlplus -s / <<'EOSQL' 2>&1
EXIT 77
EOSQL
)
    local exit_code=$?
    # sqlplus exit 77 means Oracle is reachable
    if [ "${exit_code}" -ne 77 ]; then
        status=3
    fi
    return ${status}
}

###############################################################################
#  CHECK: Inbound call collection files (IBCC)
###############################################################################

check_ibcc() {
    local status=1
    local limit="${TAP_IBCC_FILE_WARNING_LIMIT:-}"

    if [ -z "${limit}" ]; then return 3; fi
    if [ "${limit}" -eq 0 ] 2>/dev/null; then return 5; fi
    if ! [[ "${limit}" =~ ^[0-9]+$ ]]; then return 5; fi

    local count
    count=$(find "${TAP_IB_RECEIVE_FROM_SDM}" -maxdepth 1 -iname 'ibr*.dat' 2>/dev/null | wc -l)

    if [ "${count}" -gt "${limit}" ]; then
        return 7
    fi

    return ${status}
}

###############################################################################
#  CHECK: Outbound call collection files (OBCC)
###############################################################################

check_obcc() {
    local status=1
    local limit="${TAP_OBCC_FILE_WARNING_LIMIT:-}"

    if [ -z "${limit}" ]; then return 3; fi
    if [ "${limit}" -eq 0 ] 2>/dev/null; then return 5; fi
    if ! [[ "${limit}" =~ ^[0-9]+$ ]]; then return 5; fi

    local count=0
    # Count cd*.dat files
    count=$((count + $(find "${TAP_COLLECT_DIR}" -maxdepth 1 -iname 'cd*.dat' 2>/dev/null | wc -l)))
    # Count td*.dat files
    count=$((count + $(find "${TAP_COLLECT_DIR}" -maxdepth 1 -iname 'td*.dat' 2>/dev/null | wc -l)))

    if [ "${count}" -gt "${limit}" ]; then
        return 7
    fi

    return ${status}
}

###############################################################################
#  CHECK: Oracle row counts + queue/process configuration
###############################################################################

check_rowcounts() {
    local status=1
    local TAPTEMP="${TAP_WRK_DIR}/tap_monitor.lis"

    sqlplus -s / <<EOSQL > /dev/null 2>&1
WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT OSCODE
SET TERMOUT OFF
SET HEAD OFF
SET ECHO OFF
SET VERIFY OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SPOOL ${TAPTEMP}
SELECT 'OBVP-'||COUNT(*) FROM incoming_outbound_call_files WHERE iocf_call_file_status_id = 'AP';
SELECT 'OBSP-'||COUNT(*) FROM incoming_outbound_call_files WHERE iocf_call_file_status_id = 'AS';
SELECT 'GAPQ-'||tsc_batch_queue  FROM tap_system_configuration WHERE tsc_process_code = 'GAPS';
SELECT 'GAPN-'||tsc_process_name FROM tap_system_configuration WHERE tsc_process_code = 'GAPS';
SELECT 'GSDQ-'||tsc_batch_queue  FROM tap_system_configuration WHERE tsc_process_code = 'GSDM';
SELECT 'GSDN-'||tsc_process_name FROM tap_system_configuration WHERE tsc_process_code = 'GSDM';
SPOOL OFF
EXIT 77
EOSQL
    local exit_code=$?

    if [ "${exit_code}" -ne 77 ]; then
        return 3
    fi

    if [ ! -f "${TAPTEMP}" ]; then
        return 5
    fi

    # Parse the spool file to extract values
    OBVP=0; OBSP=0; GAPQ=""; GAPN=""; GSDQ=""; GSDN=""

    while IFS= read -r line; do
        line=$(echo "${line}" | tr -d '[:space:]')
        local key="${line%%-*}"
        local value="${line#*-}"
        case "${key}" in
            OBVP) OBVP="${value}" ;;
            OBSP) OBSP="${value}" ;;
            GAPQ) GAPQ="${value}" ;;
            GAPN) GAPN="${value}" ;;
            GSDQ) GSDQ="${value}" ;;
            GSDN) GSDN="${value}" ;;
        esac
    done < "${TAPTEMP}"

    rm -f "${TAPTEMP}" 2>/dev/null

    # Export for use by other checks
    export OBVP OBSP GAPQ GAPN GSDQ GSDN
    return ${status}
}

###############################################################################
#  CHECK: Outbound validation/pricing (OBVP)
###############################################################################

check_obvp() {
    local status=1
    local limit="${TAP_OBVP_FILE_WARNING_LIMIT:-}"

    if [ -z "${limit}" ]; then return 3; fi
    if [ "${limit}" -eq 0 ] 2>/dev/null; then return 5; fi
    if ! [[ "${limit}" =~ ^[0-9]+$ ]]; then return 5; fi

    if [ "${OBVP:-0}" -gt "${limit}" ]; then
        return 7
    fi

    return ${status}
}

###############################################################################
#  CHECK: Outbound splitting (OBSP)
###############################################################################

check_obsp() {
    local status=1
    local limit="${TAP_OBSP_FILE_WARNING_LIMIT:-}"

    if [ -z "${limit}" ]; then return 3; fi
    if [ "${limit}" -eq 0 ] 2>/dev/null; then return 5; fi
    if ! [[ "${limit}" =~ ^[0-9]+$ ]]; then return 5; fi

    if [ "${OBSP:-0}" -gt "${limit}" ]; then
        return 7
    fi

    return ${status}
}

###############################################################################
#  CHECK: GAPS job submission
###############################################################################

check_gaps() {
    local status=1

    if [ -z "${GAPQ:-}" ]; then return 3; fi
    if [ -z "${GAPN:-}" ]; then return 5; fi

    # Check if TAP_GAPS_01 process is already running
    if pgrep -f "TAP_GAPS_01" > /dev/null 2>&1; then
        return ${status}
    fi

    # Submit the GAPS job
    log_msg "Submitting TAP_GAPS_01 to queue ${GAPQ}"
    if [ -x "${TAP_SH_DIR}/tap_job_startup.sh" ]; then
        nohup "${TAP_SH_DIR}/tap_job_startup.sh" "GAPS" "01" "${GAPN}" \
            >> "${TAP_LOG_DIR}/tap_gaps_01.log" 2>&1 &
        if [ $? -ne 0 ]; then
            return 7
        fi
        log_msg "${PROC_NAME} - GAPS, TAP_GAPS_01 has been submitted to queue ${GAPQ}"
    else
        log_msg "WARNING: ${TAP_SH_DIR}/tap_job_startup.sh not found"
        return 7
    fi

    return ${status}
}

###############################################################################
#  CHECK: GSDM job submission
###############################################################################

check_gsdm() {
    local status=1

    if [ -z "${GSDQ:-}" ]; then return 3; fi
    if [ -z "${GSDN:-}" ]; then return 5; fi

    # Check if TAP_GSDM_01 process is already running
    if pgrep -f "TAP_GSDM_01" > /dev/null 2>&1; then
        return ${status}
    fi

    # Submit the GSDM job
    log_msg "Submitting TAP_GSDM_01 to queue ${GSDQ}"
    if [ -x "${TAP_SH_DIR}/tap_job_startup.sh" ]; then
        nohup "${TAP_SH_DIR}/tap_job_startup.sh" "GSDM" "01" "${GSDN}" \
            >> "${TAP_LOG_DIR}/tap_gsdm_01.log" 2>&1 &
        if [ $? -ne 0 ]; then
            return 7
        fi
        log_msg "${PROC_NAME} - GSDM, TAP_GSDM_01 has been submitted to queue ${GSDQ}"
    else
        log_msg "WARNING: ${TAP_SH_DIR}/tap_job_startup.sh not found"
        return 7
    fi

    return ${status}
}

###############################################################################
#  MAIN LOOP
###############################################################################

main() {
    check_singleton
    log_msg "${PROC_NAME} started"

    # Initialize row count variables
    OBVP=0; OBSP=0; GAPQ=""; GAPN=""; GSDQ=""; GSDN=""

    while true; do
        # ---- Check for shutdown signals ----
        if [ -n "${TAP_CLOSEDOWN_MONITOR:-}" ]; then
            log_msg "Shutdown signal received (TAP_CLOSEDOWN_MONITOR)"
            break
        fi
        if [ -n "${TAP_CLOSEDOWN_ALL:-}" ]; then
            if [[ "$(date '+%Y-%m-%d %H:%M:%S')" > "${TAP_CLOSEDOWN_ALL}" ]]; then
                log_msg "Closedown time reached (TAP_CLOSEDOWN_ALL=${TAP_CLOSEDOWN_ALL})"
                break
            fi
        fi

        # ---- File check period ----
        check_file_check_period
        local fcp_status=$?
        [ ${fcp_status} -eq 3 ] && send_request "TAP_FILE_CHECK_PERIOD not defined"
        [ ${fcp_status} -eq 5 ] && send_request "TAP_FILE_CHECK_PERIOD not defined correctly"

        # ---- Oracle check ----
        check_oracle
        local ora_status=$?
        [ ${ora_status} -eq 3 ] && send_request "ORACLE is not running"

        # ---- IBCC check ----
        #check_ibcc
        #local ibcc_status=$?
        #[ ${ibcc_status} -eq 3 ] && send_request "TAP_IBCC_FILE_WARNING_LIMIT not defined"
        #[ ${ibcc_status} -eq 5 ] && send_request "TAP_IBCC_FILE_WARNING_LIMIT not defined correctly"
        #[ ${ibcc_status} -eq 7 ] && send_request "TAP_IBCC_FILE_WARNING_LIMIT has been exceeded"

        # ---- OBCC check ----
        check_obcc
        local obcc_status=$?
        [ ${obcc_status} -eq 3 ] && send_request "TAP_OBCC_FILE_WARNING_LIMIT not defined"
        [ ${obcc_status} -eq 5 ] && send_request "TAP_OBCC_FILE_WARNING_LIMIT not defined correctly"
        [ ${obcc_status} -eq 7 ] && send_request "TAP_OBCC_FILE_WARNING_LIMIT has been exceeded"

        # ---- Row counts (also fetches GAPS/GSDM queue info) ----
        check_rowcounts
        local rc_status=$?
        [ ${rc_status} -eq 3 ] && send_request "Cannot extract rowcounts from ORACLE"
        [ ${rc_status} -eq 5 ] && send_request "Error reading spoolfile"

        # ---- OBVP check ----
        check_obvp
        local obvp_status=$?
        [ ${obvp_status} -eq 3 ] && send_request "TAP_OBVP_FILE_WARNING_LIMIT not defined"
        [ ${obvp_status} -eq 5 ] && send_request "TAP_OBVP_FILE_WARNING_LIMIT not defined correctly"
        [ ${obvp_status} -eq 7 ] && send_request "TAP_OBVP_FILE_WARNING_LIMIT has been exceeded"

        # ---- OBSP check ----
        check_obsp
        local obsp_status=$?
        [ ${obsp_status} -eq 3 ] && send_request "TAP_OBSP_FILE_WARNING_LIMIT not defined"
        [ ${obsp_status} -eq 5 ] && send_request "TAP_OBSP_FILE_WARNING_LIMIT not defined correctly"
        [ ${obsp_status} -eq 7 ] && send_request "TAP_OBSP_FILE_WARNING_LIMIT has been exceeded"

        # ---- GAPS check ----
        check_gaps
        local gaps_status=$?
        [ ${gaps_status} -eq 3 ] && send_request "Queue name not found for Gap Check"
        [ ${gaps_status} -eq 5 ] && send_request "Process name not found for Gap Check"
        [ ${gaps_status} -eq 7 ] && send_request "Error submitting TAP_GAPS_01 to queue ${GAPQ}"

        # ---- GSDM check ----
        check_gsdm
        local gsdm_status=$?
        [ ${gsdm_status} -eq 3 ] && send_request "Queue name not found for GSDM Check"
        [ ${gsdm_status} -eq 5 ] && send_request "Process name not found for GSDM Check"
        [ ${gsdm_status} -eq 7 ] && send_request "Error submitting TAP_GSDM_01 to queue ${GSDQ}"

        # ---- Wait for next check interval ----
        log_msg "Sleeping ${TAP_FILE_CHECK_PERIOD} seconds"
        sleep "${TAP_FILE_CHECK_PERIOD}"
    done

    log_msg "${PROC_NAME} completed"
}

###############################################################################
#  ENTRY POINT
###############################################################################

main "$@"
