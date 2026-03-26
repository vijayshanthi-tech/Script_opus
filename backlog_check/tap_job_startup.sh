#!/bin/bash
###############################################################################
# Script Name   : tap_job_startup.sh
# Converted From: TAP_JOB_STARTUP.COM (VMS DCL)
# Case ID       : TAPOP0190  /  Spec ID: TAPSO190.DOC
#
# Description   : Generic TAP job startup wrapper.
#                 Validates three mandatory parameters (process type, instance,
#                 program name), sets the process identity, locates the
#                 executable, runs it, and cleans up the per-process
#                 closedown flag on exit.
#
# Usage         : tap_job_startup.sh <PROCESS_TYPE> <INSTANCE> <PROGRAM>
#                 Example: tap_job_startup.sh GAPS 01 GAPS_PROC
#
# Environment   : Linux / Bash 4+
# Dependencies  : The target program must exist in TAP_EXE_DIR as an
#                 executable file (binary or script).
#
# Original Author : S.R.Campbell (1998)
# Converted By    : Automated VMS-to-Linux conversion
###############################################################################

set -o nounset

###############################################################################
#                       CONFIGURATION
###############################################################################

# --- Directory mappings (VMS logicals → Linux paths) ---
TAP_EXE_DIR="${TAP_EXE_DIR:-/data/call_data/tap/exe}"
TAP_LOG_DIR="${TAP_LOG_DIR:-/data/call_data/tap/log}"
TAP_COM_DIR="${TAP_COM_DIR:-/data/call_data/tap/com}"

# --- Closedown control ---
# Per-process closedown flag files live here.
# VMS stores them as group logicals; Linux uses flag files.
TAP_CLOSEDOWN_DIR="${TAP_CLOSEDOWN_DIR:-/data/call_data/tap/closedown}"

# --- Logging ---
LOG_FILE="${TAP_LOG_DIR}/tap_job_startup.log"

###############################################################################
#                       FUNCTIONS
###############################################################################

# ---- Logging (replaces @TAP_COM_DIR:TAPLOG_MESS) ----
log_msg() {
    local dttm
    dttm=$(date '+%d-%b-%Y %H:%M:%S')
    echo "${dttm} - $1" | tee -a "${LOG_FILE}" 2>/dev/null
}

# ---- Operator notification (replaces REQUEST/TO=operator) ----
send_alert() {
    local message="$1"
    log_msg "ALERT: ${message}"
    logger -t "TAP_${P1}_${P2}" "ALERT: ${message}" 2>/dev/null
}

# ---- Error handler (VMS: error/exit labels) ----
error_exit() {
    local phase="$1"
    local error_text="$2"
    local procname="${PROCNAME:-UNKNOWN}"

    log_msg " *** ${procname} - ${phase}, ${error_text}"
    send_alert "${procname} - ${phase}, ${error_text}"

    # Clean up closedown flag on error too (VMS: deassign/group)
    cleanup_closedown

    exit 1
}

# ---- Remove our per-process closedown logical/flag ----
cleanup_closedown() {
    local flag_file="${TAP_CLOSEDOWN_DIR}/TAP_${P1}_${P2}_CLOSEDOWN"
    if [ -f "${flag_file}" ]; then
        rm -f "${flag_file}" 2>/dev/null
        log_msg "Removed closedown flag: ${flag_file}"
    fi
}

###############################################################################
#                       PARAMETER VALIDATION
###############################################################################

PHASE="STARTING"

# VMS: p1, p2, p3 — three mandatory positional parameters
P1="${1:-}"    # Process type   (e.g., GAPS, GSDM)
P2="${2:-}"    # Instance       (e.g., 01)
P3="${3:-}"    # Program name   (e.g., GAPS_PROC)

if [ -z "${P1}" ] || [ -z "${P2}" ] || [ -z "${P3}" ]; then
    error_exit "${PHASE}" "Parameter must be provided (usage: $0 <TYPE> <INSTANCE> <PROGRAM>)"
fi

###############################################################################
#                       SINGLETON CHECK
###############################################################################

PHASE="SAVE_ENVIRONMENT"

# Build the process name (VMS: SET PROCESS/NAME="TAP_p1_p2")
PROCNAME="TAP_${P1}_${P2}"

# Use flock to ensure only one instance with this identity runs.
LOCK_FILE="/tmp/${PROCNAME}.lock"

exec 200>"${LOCK_FILE}"
if ! flock -n 200; then
    error_exit "${PHASE}" "Process name cannot be set — ${PROCNAME} is already running"
fi
# Lock is held for the lifetime of this process via fd 200.

log_msg "${PROCNAME} started (PID $$)"

###############################################################################
#                       MAIN — LOCATE AND RUN THE PROGRAM
###############################################################################

PHASE="MAIN"

# VMS: f$search("tap_exe_dir:''p3'.exe")
# On Linux, look for the program as an executable file (binary or script).
PROGRAM=""
if [ -x "${TAP_EXE_DIR}/${P3}" ]; then
    PROGRAM="${TAP_EXE_DIR}/${P3}"
elif [ -x "${TAP_EXE_DIR}/${P3}.sh" ]; then
    PROGRAM="${TAP_EXE_DIR}/${P3}.sh"
else
    error_exit "${PHASE}" "${P3} unavailable in ${TAP_EXE_DIR}"
fi

log_msg "${PROCNAME} executing: ${PROGRAM}"

# VMS: RUN TAP_EXE_DIR:'p3'
"${PROGRAM}"
RUN_STATUS=$?

# ---- Clean up closedown flag (VMS: DEASSIGN/GROUP mylog) ----
cleanup_closedown

if [ ${RUN_STATUS} -ne 0 ]; then
    error_exit "${PHASE}" "Error returned from program ${P3} (exit code ${RUN_STATUS})"
fi

###############################################################################
#                       SUCCESSFUL EXIT
###############################################################################

PHASE="EXIT"

log_msg "${PROCNAME} completed successfully"

# Release lock (fd 200 closes automatically on exit, but be explicit)
flock -u 200 2>/dev/null
rm -f "${LOCK_FILE}" 2>/dev/null

exit 0
