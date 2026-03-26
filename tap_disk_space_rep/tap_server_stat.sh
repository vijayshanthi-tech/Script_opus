#!/bin/bash
###############################################################################
# Script Name  : tap_server_stat.sh
# Converted From: TAP_SERVER_STAT.COM (VMS DCL)
# Description   : Collects disk usage statistics for specific disk devices
#                 (originally _DSA10:, _DSA11:, _DSA50: on VMS), formats the
#                 output, and emails the results. Also checks for EDLIVE server
#                 stats and emails those. Self-schedules to run on the 2nd of
#                 each month at 08:00.
#
# Environment   : Linux / Bash
# Dependencies  : disk_check.sh, mailx, at/cron
#
# Original Author: (VMS legacy — user varrej1)
# Converted By   : Automated VMS-to-Linux conversion
###############################################################################

set -o nounset

###############################################################################
#                       CONFIGURATION — EDIT THESE
###############################################################################

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="/tmp/tap_server_stat_$$"
mkdir -p "${WORK_DIR}"

# VMS: DISK$USERDISK:[USER.varrej1]  → Linux working directory
USER_DIR="${HOME}"

# VMS: DISK$CALL_DATA:[TAP.LOG]
TAP_LOG_DIR="/data/call_data/tap/log"

# Email distribution file (VMS: @EMAIL.DIS)
# On Linux, list recipients one per line or use a comma-separated list
EMAIL_RECIPIENTS_FILE="${SCRIPT_DIR}/email.dis"

# Disk filter patterns (VMS: _DSA10:, _DSA11:, _DSA50:)
# On Linux, filter df output for specific mount points or device names
DISK_FILTERS=("/dev/sda" "/dev/sdb" "/dev/sdc")

# EDLIVE server stat file location (may come from another host)
EDLIVE_STAT_FILE="${USER_DIR}/EDLIVE_SERVER_STAT.TXT"

# --- Log file ---
LOG_FILE="${TAP_LOG_DIR}/tap_server_stat.log"

###############################################################################
#                       FUNCTIONS
###############################################################################

log_msg() {
    local dttm
    dttm=$(date '+%d-%b-%Y %H:%M:%S')
    echo "${dttm} - $1" | tee -a "${LOG_FILE}" 2>/dev/null
}

get_email_recipients() {
    if [ -f "${EMAIL_RECIPIENTS_FILE}" ]; then
        # Read recipients from distribution file (one per line)
        tr '\n' ',' < "${EMAIL_RECIPIENTS_FILE}" | sed 's/,$//'
    else
        echo ""
    fi
}

###############################################################################
#  STEP 1: Run disk_check.sh and capture output
###############################################################################

log_msg "TAP_SERVER_STAT started"

ASMA_FILE="${WORK_DIR}/asma.txt"
SERVER_STAT_FILE="${WORK_DIR}/SERVER_STAT.txt"
TAPLIV_STAT_FILE="${WORK_DIR}/TAPLIV_SERVER_STAT.TXT"

# Run the disk check script and capture all output
"${SCRIPT_DIR}/disk_check.sh" U T > "${ASMA_FILE}" 2>&1

###############################################################################
#  STEP 2: Filter for specific disks/devices
###############################################################################

# VMS: SEA ASMA.TXT "_DSA10:","_DSA11:","_DSA50:"/out=SERVER_STAT.txt
# Build a grep pattern from the filter list
GREP_PATTERN=$(printf "|%s" "${DISK_FILTERS[@]}")
GREP_PATTERN="${GREP_PATTERN:1}"  # Remove leading |

grep -iE "${GREP_PATTERN}" "${ASMA_FILE}" > "${SERVER_STAT_FILE}" 2>/dev/null

###############################################################################
#  STEP 3: Parse filtered output and create formatted stat file
###############################################################################

if [ ! -s "${SERVER_STAT_FILE}" ]; then
    log_msg "ERROR: No matching disk entries found in disk_check output"
    rm -rf "${WORK_DIR}"
    exit 1
fi

# VMS logic: Extract columns from each line
# VMS: f$extract(0,8,line) + " " + f$extract(18,13,line) + " " + f$extract(46,12,line)
# This extracts: device name (8 chars), volume/mount info (13 chars), usage info (12 chars)
v=0
> "${TAPLIV_STAT_FILE}"

while IFS= read -r READ_LINE; do
    # Extract fields using cut/awk (character positions matching VMS f$extract)
    field1=$(echo "${READ_LINE}" | cut -c1-8)
    field2=$(echo "${READ_LINE}" | cut -c19-31)
    field3=$(echo "${READ_LINE}" | cut -c47-58)

    formatted_line="${field1} ${field2} ${field3}"
    echo "${formatted_line}"
    echo "${formatted_line}" >> "${TAPLIV_STAT_FILE}"
    v=$((v + 1))
done < "${SERVER_STAT_FILE}"

###############################################################################
#  STEP 4: Email the TAPLIV server stats
###############################################################################

RECIPIENTS=$(get_email_recipients)

if [ -n "${RECIPIENTS}" ]; then
    mailx -s "SERVER_STATS_TAPLIV" ${RECIPIENTS} < "${TAPLIV_STAT_FILE}" 2>/dev/null
    log_msg "TAPLIV server stats emailed"
else
    log_msg "WARNING: No email recipients configured in ${EMAIL_RECIPIENTS_FILE}"
fi

###############################################################################
#  STEP 5: Email EDLIVE server stats (if available)
###############################################################################

if [ ! -f "${EDLIVE_STAT_FILE}" ]; then
    echo "EDLIVE SERVER STAT NOT FOUND. PLEASE RUN THE SER_STAT SCRIPT FROM FLAMUSER AND TRY AGAIN"
    log_msg "EDLIVE SERVER STAT NOT FOUND"
else
    if [ -n "${RECIPIENTS}" ]; then
        mailx -s "SERVER_STATS_EDLIV" ${RECIPIENTS} < "${EDLIVE_STAT_FILE}" 2>/dev/null
        log_msg "EDLIVE server stats emailed"
    fi
fi

###############################################################################
#  STEP 6: Self-schedule for 2nd of next month at 08:00
#  VMS: SUBMIT ... /AFTER="''SecLastOfNextMonth'+08:00:00"
#  NOTE: The VMS logic calculates the 2nd of next month.
#        On Linux, use 'at' or preferably a cron entry:
#        0 8 2 * * /path/to/tap_server_stat.sh
###############################################################################

schedule_next_run() {
    # Calculate 2nd of next month
    local next_month_2nd
    next_month_2nd=$(date -d "$(date +%Y-%m-01) +1 month +1 day" '+%H:%M %Y-%m-%d' 2>/dev/null)
    if [ -n "${next_month_2nd}" ]; then
        echo "$(readlink -f "$0")" | at "08:00 $(date -d "$(date +%Y-%m-01) +1 month +1 day" '+%Y-%m-%d')" 2>/dev/null || \
            log_msg "WARNING: Could not schedule next run. Configure cron: 0 8 2 * * $(readlink -f "$0")"
    fi
}

schedule_next_run

###############################################################################
#  STEP 7: Cleanup
###############################################################################

rm -rf "${WORK_DIR}" 2>/dev/null
log_msg "TAP_SERVER_STAT completed"

exit 0
