#!/bin/bash
#=============================================================================
#
# Script Name    : generic_sftp.sh
#
# Description    : Generic SFTP script to push and pull files to/from
#                  other servers. Faithfully converted from OpenVMS DCL
#                  (SFTP_TRANSFER.COM) to Linux Bash.
#
# Input Params   : Two input parameters required:
#   Param 1 (P1): Config file name (located in $TAP_CFG_DIR)
#                  Contains remote host, user, dirs, file patterns, etc.
#   Param 2 (P2): Action On Success after SFTP transfer:
#                  "NOCHANGE" | "DELETE" | "GZ" | ".<EXT>" (e.g. ".COPIED")
#
# Original Author : Vimalraj Ganesan (28 May 2015)
# Contributors    : Amreet, Prasad
# Converted to SH : Migration from OpenVMS DCL to Linux Bash
#
# Version History:
#   1.0  Vimalraj              Initial version
#   2.0  Amreet                Modified SFTP call logic for process SSH commands
#   2.1  Prasad                Modified SFTP for PULL DELETE AND RENAME
#   2.2  Prasad  15-Mar-2018   Modified process SSH to open SSH commands
#   2.3  Amreet  24-Mar-2018   Fixed deletion logic of *.SFTP to actual file.SFTP
#   2.4  Prasad  30-Jul-2018   Pull temp file changes
#   2.5  Prasad  15-Oct-2018   Added Housekeep for *.sftp files
#   2.6  Prasad  05-Feb-2019   Added Changemode permission; ascii/binary via config
#   3.0  Migration             Converted from OpenVMS DCL to Linux Bash
#   3.1  Vijayashanthi         Applied TAP predefined logicals
#
#=============================================================================
#
# TAP LOGICAL MAPPING (VMS to Linux Environment Variables)
#
#   VMS Logical       Linux Env Variable     R53 Path
#   -------------     ------------------     ----------------------------------------
#   SFTP_COM_DIR  ->  TAP_SH_DIR             /app/tap/R53_TAPLIVE/TAP/SH
#   SFTP_CFG_DIR  ->  TAP_CFG_DIR            /app/tap/R53_TAPLIVE/TAP/CFG
#   cell0_log     ->  TAP_LOG_DIR            /data/tap/R53_TAPLIVE/TAP/LOG
#   cell0_dat     ->  TAP_SFTP_TMP_DIR       /data/tap/R53_TAPLIVE/TAP/DAT/SFTP_TMP
#   (new)         ->  TAP_TMP_DIR            /data/tap/R53_TAPLIVE/TAP/TMP
#   cell0_com     ->  TAP_SH_DIR             /app/tap/R53_TAPLIVE/TAP/SH
#   (runtime)     ->  SFTP_PURGE_DAYS        (default: 10)
#
# Directory Purpose:
#   TAP_SH_DIR         Script/shell directory (where this script lives)
#   TAP_CFG_DIR        SFTP config files (.cfg) and parameter files
#   TAP_LOG_DIR        All log files (generic_sftp_*.log)
#   TAP_SFTP_TMP_DIR   Temp .sftp batch files, SFTP output, PullTempDir default
#   TAP_TMP_DIR        Lock files (.lock) for single-instance protection
#
#=============================================================================
 
set -uo pipefail
 
#=============================================================================
# GLOBAL VARIABLES & ERROR MESSAGES
#=============================================================================
PROCNAME="$(basename "$0" .sh)"
LOGFILE=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
 
# Error message constants (mirrors COM symbols)
SFTP_WrongParam="generic_sftp.sh called with wrong parameter"
SFTP_BadJobInBatch="Lock file found - indicates previous run incomplete or crash. Correction required."
E_SFTPAttempt="SFTP attempt failed"
F_SFTPFailed="All attempts failed. Correction required."
F_SFTPCfgVSrcDirExist="Source directory does not exist"
 
STATUS=""
PHASE="SAVE_ENVIRONMENT"
SFTP_DONE=0
LOCK_FILE=""
 
# Config parameters (initialized empty)
CfgFileID=""
ActionOnSuccess=""
SftpType=""
SrcDir=""
DestHostname=""
DestUsername=""
DestDir=""
DestFileName=""
DestFilePattern=""
TransferType=""
RemoteOS=""
SshCompatMode=""
DestFilePermission=""
PullSrcDir=""
PullDestDir=""
PullTempDir=""
PullFilePattern=""
RetryAttempts=""
RetryWaitSeconds=""
 
# Temp SFTP batch file trackers
sftp_tmp_file_push=""
sftp_tmp_file_pull=""
sftp_tmp_file_pull_d=""
 
# Save original working directory
ORIG_DIR="$(pwd)"
 
#=============================================================================
# LOGGING FUNCTION  (replaces @cell0_com:log_mess from the COM script)
# Writes to TAP_LOG_DIR (was cell0_log in VMS)
#=============================================================================
log_mess() {
local prefix="${1:-}"
local message="${2:-}"
local timestamp
timestamp="$(date '+%d-%b-%Y %H:%M:%S')"
local log_line="${timestamp} | ${prefix} ${message}"
echo "${log_line}"
if [[ -n "${LOGFILE}" ]]; then
echo "${log_line}" >> "${LOGFILE}" 2>/dev/null || true
fi
}
 
#=============================================================================
# HOUSEKEEPING: Delete temporary .sftp batch files created this run
# Cleans from TAP_SFTP_TMP_DIR (was cell0_dat in VMS)
#=============================================================================
housekeep_sftp_temps() {
local f
for f in "$sftp_tmp_file_push" "$sftp_tmp_file_pull" "$sftp_tmp_file_pull_d"; do
if [[ -n "$f" && -n "${TAP_SFTP_TMP_DIR:-}" && -f "${TAP_SFTP_TMP_DIR}/${f}" ]]; then
rm -f "${TAP_SFTP_TMP_DIR}/${f}"
log_mess "   " "Housekeep: removed temp batch ${f}"
fi
done
}
 
#=============================================================================
# HOUSEKEEPING: Purge old .sftp files (>2 days) and old log files
# .sftp files purged from TAP_SFTP_TMP_DIR
# .log  files purged from TAP_LOG_DIR
# (mirrors v2.5 housekeep addition in COM)
#=============================================================================
housekeep_all() {
# Delete .sftp temp batch files older than 2 days from TAP_SFTP_TMP_DIR
if [[ -n "${TAP_SFTP_TMP_DIR:-}" && -d "${TAP_SFTP_TMP_DIR}" ]]; then
find "${TAP_SFTP_TMP_DIR}" -maxdepth 1 -name "*.sftp" -type f -mtime +2 \
    -delete 2>/dev/null || true
fi
 
# Purge old log files from TAP_LOG_DIR (default retention: 10 days)
local purge_days="${SFTP_PURGE_DAYS:-10}"
if [[ -n "${TAP_LOG_DIR:-}" && -d "${TAP_LOG_DIR}" ]]; then
find "${TAP_LOG_DIR}" -maxdepth 1 -name "generic_sftp*.log" -type f \
    -mtime +"${purge_days}" -delete 2>/dev/null || true
fi
}
 
#=============================================================================
# LOCK FILE MANAGEMENT
# Lock files stored in TAP_TMP_DIR (was VMS retained job check)
# (replaces VMS "PIPE SHOW ENTRY / SEARCH RETAINED" duplicate-run check)
#=============================================================================
acquire_lock() {
local lock_dir="${TAP_TMP_DIR:-${TAP_CFG_DIR}}"
LOCK_FILE="${lock_dir}/${CfgFileID}.lock"
if [[ -f "$LOCK_FILE" ]]; then
local lock_pid
lock_pid="$(cat "$LOCK_FILE" 2>/dev/null || echo "")"
if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
STATUS="${SFTP_BadJobInBatch} (PID: ${lock_pid})"
reg_error
else
log_mess "   " "Stale lock file detected (PID: ${lock_pid}). Removing."
rm -f "$LOCK_FILE"
fi
fi
echo $$ > "$LOCK_FILE"
}
 
release_lock() {
if [[ -n "${LOCK_FILE:-}" && -f "${LOCK_FILE:-}" ]]; then
rm -f "$LOCK_FILE"
fi
}
 
#=============================================================================
# ERROR HANDLERS  (mirrors REG_ERROR and VMS_ERROR labels in COM)
#=============================================================================
reg_error() {
PHASE="REG_ERROR"
housekeep_all
housekeep_sftp_temps
log_mess "***" "ERROR: ${PROCNAME} | Phase: ${PHASE} | Config: ${CfgFileID} | ${STATUS}"
echo "ERROR: ${PROCNAME} - ${PHASE}, (${CfgFileID}) ${STATUS}" >&2
release_lock
cd "${ORIG_DIR}" 2>/dev/null || true
exit 4
}
 
vms_error() {
PHASE="VMS_ERROR"
housekeep_all
housekeep_sftp_temps
local error_text="${STATUS}"
[[ -z "$error_text" ]] && error_text="Unknown system error"
log_mess "***" "ERROR: ${PROCNAME} | Phase: ${PHASE} | Config: ${CfgFileID} | ${error_text}"
echo "ERROR: ${PROCNAME} - ${PHASE}, (${CfgFileID}) ${error_text}" >&2
release_lock
cd "${ORIG_DIR}" 2>/dev/null || true
exit 4
}
 
#=============================================================================
# CLEAN FINISH  (mirrors CLEAN_FINISH label in COM)
#=============================================================================
clean_finish() {
PHASE="CLEAN_FINISH"
housekeep_all
housekeep_sftp_temps
log_mess "   " "${PROCNAME} completed successfully at $(date '+%d-%b-%Y %H:%M:%S')"
release_lock
cd "${ORIG_DIR}" 2>/dev/null || true
# Disable trap before clean exit
trap - EXIT
exit 0
}
 
#=============================================================================
# TRAP for unexpected exits
#=============================================================================
trap_handler() {
local exit_code=$?
if [[ $exit_code -ne 0 ]]; then
log_mess "***" "${PROCNAME} - Unexpected termination (exit ${exit_code}) in phase: ${PHASE}"
housekeep_sftp_temps
release_lock
cd "${ORIG_DIR}" 2>/dev/null || true
fi
}
trap trap_handler EXIT
 
#=============================================================================
# GENERATE UNIQUE SFTP BATCH FILENAME
#=============================================================================
generate_sftp_tmp() {
local tmp_name
tmp_name="sftp_${RANDOM}_$(date +%s%N)_$$.sftp"
echo "${tmp_name}"
}
 
#=============================================================================
# RUN SFTP TRANSFER  (with retry logic - mirrors COM retry loop)
# Retries up to RetryAttempts times, sleeping RetryWaitSeconds between.
# Batch files read from TAP_SFTP_TMP_DIR, output appended to LOGFILE
#=============================================================================
 
#=============================================================================
# DUAL-PLATFORM SUPPORT FUNCTIONS
#=============================================================================
 
#-----------------------------------------------------------------------------
# convert_before_push: Convert line endings BEFORE pushing to remote server
# Only converts when: TransferType=A (text) AND RemoteOS=openvms
#-----------------------------------------------------------------------------
convert_before_push() {
    local file="$1"
    if [[ "${TransferType}" == "A" && "${RemoteOS}" == "openvms" ]]; then
        log_mess "   " "Converting LF -> CRLF for OpenVMS text transfer: $(basename "$file")"
        if command -v unix2dos &>/dev/null; then
            unix2dos "$file" 2>/dev/null
        else
            sed -i 's/$/\r/' "$file"
        fi
    elif [[ "${TransferType}" == "A" ]]; then
        log_mess "   " "TransferType=A with RemoteOS=${RemoteOS} — no line-ending conversion needed."
    fi
}
 
#-----------------------------------------------------------------------------
# convert_after_pull: Convert line endings AFTER pulling from remote server
# Only converts when: TransferType=A (text) AND RemoteOS=openvms
#-----------------------------------------------------------------------------
convert_after_pull() {
    local file="$1"
    if [[ "${TransferType}" == "A" && "${RemoteOS}" == "openvms" ]]; then
        log_mess "   " "Converting CRLF -> LF from OpenVMS text transfer: $(basename "$file")"
        if command -v dos2unix &>/dev/null; then
            dos2unix "$file" 2>/dev/null
        else
            sed -i 's/\r$//' "$file"
        fi
    elif [[ "${TransferType}" == "A" ]]; then
        log_mess "   " "TransferType=A with RemoteOS=${RemoteOS} — no line-ending conversion needed."
    fi
}
 
#-----------------------------------------------------------------------------
# get_sftp_options: Returns SSH/SFTP options based on RemoteOS/SshCompatMode
# For OpenVMS: adds legacy cipher, key exchange, and host key options
#-----------------------------------------------------------------------------
get_sftp_options() {
    local opts=""
    if [[ "${SshCompatMode}" == "yes" ]]; then
        opts="-oKexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1"
        opts="${opts} -oHostKeyAlgorithms=+ssh-rsa,ssh-dss"
        opts="${opts} -oCiphers=+aes128-cbc,aes256-cbc"
        opts="${opts} -oStrictHostKeyChecking=no"
        log_mess "   " "SSH compat mode enabled for ${RemoteOS}"
    fi
    echo "${opts}"
}
run_sftp_transfer() {
local batch_file="$1"
local sftp_count=0
 
PHASE="RUN_SFTP_TRANSFER"
 
while true; do
sftp_count=$((sftp_count + 1))
log_mess "   " "SFTP attempt ${sftp_count}/${RetryAttempts} | Batch: ${batch_file}"
 
set +e
sftp $(get_sftp_options) -b "${TAP_SFTP_TMP_DIR}/${batch_file}" \
    "${DestUsername}@${DestHostname}" \
>> "${LOGFILE}" 2>&1
local sftp_rc=$?
set -e
 
if [[ $sftp_rc -eq 0 ]]; then
log_mess "   " "SFTP transfer succeeded on attempt ${sftp_count}."
return 0
else
if [[ $sftp_count -ge $RetryAttempts ]]; then
STATUS="${F_SFTPFailed}"
log_mess "***" "${E_SFTPAttempt} | All ${RetryAttempts} attempts exhausted."
return 1
else
log_mess "***" "${E_SFTPAttempt} | Waiting ${RetryWaitSeconds}s before retry..."
sleep "${RetryWaitSeconds}"
fi
fi
done
}
 
#=============================================================================
# ACTION ON SUCCESS  (post-transfer action on LOCAL source file after PUSH)
# Mirrors COM logic: NOCHANGE / DELETE / GZ / .<EXT>
#=============================================================================
action_on_success() {
local work_dir="$1"
local file_base="$2"
local orig_ext="$3"
local sftp_tmp_ext=".SFTP_TMP"
 
cd "${work_dir}"
 
case "${ActionOnSuccess}" in
DELETE)
if [[ -f "${file_base}${sftp_tmp_ext}" ]]; then
mv "${file_base}${sftp_tmp_ext}" "${file_base}${orig_ext}"
rm -f "${file_base}${orig_ext}"
log_mess "   " "ACTION_ON_SUCCESS: Deleted ${file_base}${orig_ext}"
fi
;;
GZ)
if [[ -f "${file_base}${sftp_tmp_ext}" ]]; then
mv "${file_base}${sftp_tmp_ext}" "${file_base}${orig_ext}"
gzip -f "${file_base}${orig_ext}"
log_mess "   " "ACTION_ON_SUCCESS: Compressed ${file_base}${orig_ext} -> .gz"
fi
;;
NOCHANGE)
if [[ -f "${file_base}${sftp_tmp_ext}" ]]; then
mv "${file_base}${sftp_tmp_ext}" "${file_base}${orig_ext}"
log_mess "   " "ACTION_ON_SUCCESS: Restored ${file_base}${orig_ext} (no change)"
fi
;;
.*)
if [[ -f "${file_base}${sftp_tmp_ext}" ]]; then
mv "${file_base}${sftp_tmp_ext}" "${file_base}${orig_ext}"
mv "${file_base}${orig_ext}" "${file_base}${ActionOnSuccess}"
log_mess "   " "ACTION_ON_SUCCESS: Renamed to ${file_base}${ActionOnSuccess}"
fi
;;
esac
}
 
 
#=============================================================================
#=============================================================================
#                          M A I N   S C R I P T
#=============================================================================
#=============================================================================
 
# ======= PHASE: GET INPUT PARAMETERS =======================================
PHASE="GET_INPUT_PARAMS"
 
CfgFileID="${1:-}"
ActionOnSuccess="${2:-NOCHANGE}"
 
if [[ -z "$CfgFileID" ]]; then
STATUS="${SFTP_WrongParam}: Param 1 (Config file) is missing."
echo "Usage: $0 <config_file> [NOCHANGE|DELETE|GZ|.<EXT>]" >&2
echo "" >&2
echo "  <config_file>    Name of config file in \$TAP_CFG_DIR" >&2
echo "  Action options:" >&2
echo "    NOCHANGE        Keep source file as-is after transfer (default)" >&2
echo "    DELETE           Delete source file after successful transfer" >&2
echo "    GZ               Gzip source file after successful transfer" >&2
echo "    .<EXT>           Rename source with extension (.COPIED, .DONE)" >&2
reg_error
fi
 
# Validate ActionOnSuccess value
case "${ActionOnSuccess}" in
DELETE|GZ|NOCHANGE) ;;
.*)  ;;
*)
STATUS="${SFTP_WrongParam}: Param 2 invalid value '${ActionOnSuccess}'. Expected NOCHANGE|DELETE|GZ|.<EXT>"
reg_error
;;
esac
 
# ======= PHASE: CHECK ENVIRONMENT VARIABLES ================================
PHASE="CHECK_ENVIRONMENT"
 
# TAP_SH_DIR (replaces SFTP_COM_DIR — script/shell directory)
if [[ -z "${TAP_SH_DIR:-}" ]]; then
STATUS="TAP_SH_DIR environment variable not defined. (Replaces SFTP_COM_DIR)"
reg_error
fi
 
# TAP_CFG_DIR (replaces SFTP_CFG_DIR — config file directory)
if [[ -z "${TAP_CFG_DIR:-}" ]]; then
STATUS="TAP_CFG_DIR environment variable not defined. (Replaces SFTP_CFG_DIR)"
reg_error
fi
 
# TAP_LOG_DIR (replaces cell0_log — log file directory)
if [[ -z "${TAP_LOG_DIR:-}" ]]; then
STATUS="TAP_LOG_DIR environment variable not defined. (Log directory required)"
reg_error
fi
 
# TAP_SFTP_TMP_DIR (replaces cell0_dat — temp batch/staging directory)
if [[ -z "${TAP_SFTP_TMP_DIR:-}" ]]; then
STATUS="TAP_SFTP_TMP_DIR environment variable not defined. (SFTP temp directory required)"
reg_error
fi
 
# TAP_TMP_DIR (optional — lock file directory, defaults to TAP_CFG_DIR)
TAP_TMP_DIR="${TAP_TMP_DIR:-${TAP_CFG_DIR}}"
 
# Validate directories exist
if [[ ! -d "${TAP_SH_DIR}" ]]; then
STATUS="TAP_SH_DIR directory does not exist: ${TAP_SH_DIR}"
reg_error
fi
 
if [[ ! -d "${TAP_CFG_DIR}" ]]; then
STATUS="TAP_CFG_DIR directory does not exist: ${TAP_CFG_DIR}"
reg_error
fi
 
if [[ ! -d "${TAP_LOG_DIR}" ]]; then
STATUS="TAP_LOG_DIR directory does not exist: ${TAP_LOG_DIR}"
reg_error
fi
 
if [[ ! -d "${TAP_SFTP_TMP_DIR}" ]]; then
STATUS="TAP_SFTP_TMP_DIR directory does not exist: ${TAP_SFTP_TMP_DIR}"
reg_error
fi
 
if [[ ! -d "${TAP_TMP_DIR}" ]]; then
STATUS="TAP_TMP_DIR directory does not exist: ${TAP_TMP_DIR}"
reg_error
fi
 
# Initialize log file in TAP_LOG_DIR (was cell0_log in VMS)
LOGFILE="${TAP_LOG_DIR}/${PROCNAME}_$(date +%Y%m%d_%H%M%S).log"
 
# ======= Check config file exists ==========================================
CFG_FILE_PATH="${TAP_CFG_DIR}/${CfgFileID}"
if [[ ! -f "$CFG_FILE_PATH" ]]; then
STATUS="Config file '${CfgFileID}' not found in ${TAP_CFG_DIR}"
reg_error
fi
 
# ======= Start Logging =====================================================
log_mess "   " "================================================================="
log_mess "   " "${PROCNAME} STARTED at $(date '+%d-%b-%Y %H:%M:%S')"
log_mess "   " "Config: ${CfgFileID} | ActionOnSuccess: ${ActionOnSuccess}"
log_mess "   " "TAP_SH_DIR:       ${TAP_SH_DIR}"
log_mess "   " "TAP_CFG_DIR:      ${TAP_CFG_DIR}"
log_mess "   " "TAP_LOG_DIR:      ${TAP_LOG_DIR}"
log_mess "   " "TAP_SFTP_TMP_DIR: ${TAP_SFTP_TMP_DIR}"
log_mess "   " "TAP_TMP_DIR:      ${TAP_TMP_DIR}"
log_mess "   " "================================================================="
 
# ======= PHASE: CHECK PREVIOUS ERROR (Lock File) ===========================
PHASE="CHECK_PREV_ERROR"
acquire_lock
 
#=============================================================================
# PHASE: PARSE CONFIG FILE
# Reads key:value pairs; skips lines starting with '!'
#=============================================================================
PHASE="SFTP_PARAMETERS"
 
while IFS= read -r line || [[ -n "$line" ]]; do
# Trim leading whitespace
line_trimmed="$(echo "$line" | sed 's/^[[:space:]]*//')"
 
# Skip comment lines (starting with !) and blank lines
[[ "$line_trimmed" =~ ^! ]] && continue
[[ -z "$line_trimmed" ]] && continue
 
# Only process lines containing a colon
if [[ "$line_trimmed" != *:* ]]; then
continue
fi
 
# Extract key (before first colon) and value (everything after)
key="$(echo "$line_trimmed" | cut -d':' -f1 | xargs 2>/dev/null || echo "")"
value="$(echo "$line_trimmed" | cut -d':' -f2- | xargs 2>/dev/null || echo "")"
 
case "$key" in
SftpType)            SftpType="$value" ;;
SrcDir)              SrcDir="$value" ;;
DestHostname)        DestHostname="$value" ;;
DestUsername)         DestUsername="$value" ;;
DestDir)             DestDir="$value" ;;
DestFileName)        DestFileName="$value" ;;
DestFilePattern)     DestFilePattern="$value" ;;
TransferType)        TransferType="$value" ;;
RemoteOS)            RemoteOS="$value" ;;
SshCompatMode)       SshCompatMode="$value" ;;
DestFilePermission)  DestFilePermission="$value" ;;
PullSrcDir)          PullSrcDir="$value" ;;
PullDestDir)         PullDestDir="$value" ;;
PullTempDir)         PullTempDir="$value" ;;
PullFilePattern)     PullFilePattern="$value" ;;
RetryAttempts)       RetryAttempts="$value" ;;
RetryWaitSeconds)    RetryWaitSeconds="$value" ;;
esac
done < "$CFG_FILE_PATH"
 
log_mess "   " "Config file parsed successfully: ${CfgFileID}"
 
# ======= Apply Defaults ====================================================
RetryAttempts="${RetryAttempts:-3}"
RetryWaitSeconds="${RetryWaitSeconds:-60}"
TransferType="${TransferType:-B}"
RemoteOS="${RemoteOS:-linux}"
SshCompatMode="${SshCompatMode:-no}"
 
# Auto-enable SSH compat mode for OpenVMS
if [[ "${RemoteOS}" == "openvms" && "${SshCompatMode}" == "no" ]]; then
    SshCompatMode="yes"
fi
 
# ======= Validate Mandatory Fields =========================================
if [[ -z "$SftpType" ]] || \
   [[ "$SftpType" != "push" && "$SftpType" != "pull" && "$SftpType" != "both" ]]; then
STATUS="Mandatory field (SftpType) is blank/absent/invalid. Must be push|pull|both."
reg_error
fi
 
if [[ -z "$DestHostname" ]]; then
STATUS="Mandatory field (DestHostname) is blank/absent."
reg_error
fi
 
if [[ -z "$DestUsername" ]]; then
STATUS="Mandatory field (DestUsername) is blank/absent."
reg_error
fi
 
if ! [[ "$RetryAttempts" =~ ^[0-9]+$ ]] || [[ "$RetryAttempts" -le 0 ]]; then
STATUS="RetryAttempts must be a positive integer. Got: '${RetryAttempts}'"
reg_error
fi
 
if ! [[ "$RetryWaitSeconds" =~ ^[0-9]+$ ]] || [[ "$RetryWaitSeconds" -le 0 ]]; then
STATUS="RetryWaitSeconds must be a positive integer. Got: '${RetryWaitSeconds}'"
reg_error
fi
 
log_mess "   " "SftpType=${SftpType} | Host=${DestHostname} | User=${DestUsername}"
log_mess "   " "Retry=${RetryAttempts} attempts x ${RetryWaitSeconds}s | TransferType=${TransferType}"
log_mess "   " "RemoteOS=${RemoteOS} | SshCompatMode=${SshCompatMode}"
 
#=============================================================================
# PUSH VALIDATIONS
#=============================================================================
if [[ "$SftpType" == "push" || "$SftpType" == "both" ]]; then
if [[ -z "$SrcDir" ]]; then
STATUS="Mandatory field (SrcDir) is blank/absent."
reg_error
fi
if [[ ! -d "$SrcDir" ]]; then
STATUS="${F_SFTPCfgVSrcDirExist}: ${SrcDir}"
reg_error
fi
if [[ -z "$DestDir" ]]; then
STATUS="Mandatory field (DestDir) is blank/absent."
reg_error
fi
if [[ -z "$DestFileName" ]]; then
STATUS="Mandatory field (DestFileName) is blank/absent."
reg_error
fi
fi
 
#=============================================================================
# PULL VALIDATIONS
#=============================================================================
if [[ "$SftpType" == "pull" || "$SftpType" == "both" ]]; then
if [[ -z "$PullFilePattern" ]]; then
STATUS="Mandatory field (PullFilePattern) is blank/absent."
reg_error
fi
if [[ -z "$PullSrcDir" ]]; then
STATUS="Mandatory field (PullSrcDir) is blank/absent."
reg_error
fi
if [[ -z "$PullDestDir" ]]; then
STATUS="Mandatory field (PullDestDir) is blank/absent."
reg_error
fi
# Default PullTempDir to TAP_SFTP_TMP_DIR (was cell0_dat in VMS) (v2.4)
PullTempDir="${PullTempDir:-${TAP_SFTP_TMP_DIR}}"
mkdir -p "$PullTempDir"
fi
 
#=============================================================================
#=============================================================================
#                          P U S H   S F T P
#=============================================================================
#=============================================================================
if [[ "$SftpType" == "push" || "$SftpType" == "both" ]]; then
PHASE="PUSH_SFTP"
log_mess "   " "========== Starting PUSH SFTP =========="
 
cd "${SrcDir}"
 
# Find files matching DestFileName pattern
shopt -s nullglob
file_list=( ${DestFileName} )
shopt -u nullglob
 
if [[ ${#file_list[@]} -eq 0 ]]; then
log_mess "   " "No source files matching '${DestFileName}' in ${SrcDir}. Nothing to push."
if [[ "$SftpType" == "push" ]]; then
clean_finish
fi
else
log_mess "   " "Found ${#file_list[@]} file(s) to push."
 
for src_file in "${file_list[@]}"; do
# Skip directories
[[ -d "$src_file" ]] && continue
 
filename="$(basename "$src_file")"
file_base="${filename%.*}"
file_ext=".${filename##*.}"
# Handle files without an extension
if [[ "$filename" == "$file_base" ]]; then
file_ext=""
fi
 
SFTP_TMP_EXT=".SFTP_TMP"
 
log_mess "   " "----- Processing PUSH: ${filename} -----"
 
# Rename to .SFTP_TMP for atomic safety (prevents double processing)
mv "${filename}" "${file_base}${SFTP_TMP_EXT}"
log_mess "   " "Renamed ${filename} -> ${file_base}${SFTP_TMP_EXT}"
 
# Generate unique SFTP batch file in TAP_SFTP_TMP_DIR
sftp_tmp_file_push="$(generate_sftp_tmp)"
local_batch="${TAP_SFTP_TMP_DIR}/${sftp_tmp_file_push}"
 
# PATCH: Convert line endings before building SFTP batch (OpenVMS support)
convert_before_push "${SrcDir}/${file_base}${SFTP_TMP_EXT}"
 
# ------- Build SFTP batch commands -------
{
 
# Change to remote destination directory
if [[ -n "$DestDir" && "$DestDir" != "DEFAULT" ]]; then
echo "cd ${DestDir}"
fi
 
# Upload file with temporary extension
echo "put ${file_base}${SFTP_TMP_EXT}"
 
# v2.6: Set file permissions on remote
perm="${DestFilePermission:-775}"
echo "chmod ${perm} ${file_base}${SFTP_TMP_EXT}"
 
# Rename on remote from .SFTP_TMP to final name
if [[ -n "$DestFilePattern" ]]; then
echo "rename ${file_base}${SFTP_TMP_EXT} ${file_base}${file_ext}"
else
echo "rename ${file_base}${SFTP_TMP_EXT} ${filename}"
fi
 
echo "bye"
} > "${local_batch}"
 
log_mess "   " "SFTP batch created: ${sftp_tmp_file_push}"
 
# Execute SFTP transfer with retry
cd "${SrcDir}"
if ! run_sftp_transfer "${sftp_tmp_file_push}"; then
STATUS="SFTP push failed for ${filename}"
reg_error
fi
 
# Post-transfer action on local source file
action_on_success "${SrcDir}" "${file_base}" "${file_ext}"
 
log_mess "   " "PUSH completed for: ${filename}"
done
fi
 
SFTP_DONE=1
log_mess "   " "========== PUSH SFTP finished =========="
fi
 
#=============================================================================
#=============================================================================
#                          P U L L   S F T P
#=============================================================================
#=============================================================================
if [[ "$SftpType" == "pull" || "$SftpType" == "both" ]]; then
PHASE="PULL_SFTP"
log_mess "   " "========== Starting PULL SFTP =========="
 
# v2.4: Clean previous files in temp directory
cd "${PullTempDir}"
shopt -s nullglob
prev_files=( ${PullFilePattern} )
shopt -u nullglob
if [[ ${#prev_files[@]} -gt 0 ]]; then
rm -f ${PullFilePattern} 2>/dev/null || true
log_mess "   " "Cleaned ${#prev_files[@]} old file(s) from temp dir."
fi
 
# Generate SFTP batch for PULL (GET) in TAP_SFTP_TMP_DIR
sftp_tmp_file_pull="$(generate_sftp_tmp)"
local_batch="${TAP_SFTP_TMP_DIR}/${sftp_tmp_file_pull}"
 
{
# Transfer mode
# Change to remote source directory
if [[ -n "$PullSrcDir" && "$PullSrcDir" != "DEFAULT" ]]; then
echo "cd ${PullSrcDir}"
fi
 
# Set local directory to temp
echo "lcd ${PullTempDir}"
 
# Download files matching pattern
echo "mget ${PullFilePattern}"
 
echo "bye"
} > "${local_batch}"
 
log_mess "   " "SFTP PULL batch created: ${sftp_tmp_file_pull}"
 
# Execute SFTP PULL with retry
if ! run_sftp_transfer "${sftp_tmp_file_pull}"; then
STATUS="SFTP pull failed."
reg_error
fi
 
# Check received files
cd "${PullTempDir}"
shopt -s nullglob
pulled_files=( ${PullFilePattern} )
shopt -u nullglob
 
if [[ ${#pulled_files[@]} -eq 0 ]]; then
log_mess "   " "No files matching '${PullFilePattern}' received. Nothing to process."
clean_finish
fi
 
log_mess "   " "Received ${#pulled_files[@]} file(s) from remote server."
 
# Copy pulled files to final destination directory
if [[ -n "$PullDestDir" ]]; then
if [[ ! -d "$PullDestDir" ]]; then
STATUS="Pull destination directory does not exist: ${PullDestDir}"
reg_error
fi
 
real_dest="$(realpath "$PullDestDir" 2>/dev/null || echo "$PullDestDir")"
real_tmp="$(realpath "$PullTempDir" 2>/dev/null || echo "$PullTempDir")"
 
if [[ "$real_dest" != "$real_tmp" ]]; then
for pf in "${pulled_files[@]}"; do
cp "$pf" "${PullDestDir}/"
log_mess "   " "Copied ${pf} -> ${PullDestDir}/"
convert_after_pull "${PullDestDir}/${pf}"
done
fi
fi
 
# ---- Post-pull actions on REMOTE server (v2.1) ----
case "${ActionOnSuccess}" in
DELETE)
log_mess "   " "Deleting files on remote server..."
sftp_tmp_file_pull_d="$(generate_sftp_tmp)"
local_batch_d="${TAP_SFTP_TMP_DIR}/${sftp_tmp_file_pull_d}"
{
if [[ -n "$PullSrcDir" && "$PullSrcDir" != "DEFAULT" ]]; then
echo "cd ${PullSrcDir}"
fi
for pf in "${pulled_files[@]}"; do
echo "rm $(basename "$pf")"
done
echo "bye"
} > "${local_batch_d}"
 
if ! run_sftp_transfer "${sftp_tmp_file_pull_d}"; then
log_mess "***" "Warning: Could not delete remote files after pull."
else
log_mess "   " "Remote files deleted successfully."
fi
;;
 
NOCHANGE)
log_mess "   " "No action on remote files (NOCHANGE)."
;;
 
.*)
log_mess "   " "Renaming files on remote server to *${ActionOnSuccess}..."
for pf in "${pulled_files[@]}"; do
pf_base="$(basename "$pf")"
pf_name="${pf_base%.*}"
pf_ext=".${pf_base##*.}"
[[ "$pf_base" == "$pf_name" ]] && pf_ext=""
 
sftp_tmp_file_pull_d="$(generate_sftp_tmp)"
local_batch_d="${TAP_SFTP_TMP_DIR}/${sftp_tmp_file_pull_d}"
{
if [[ -n "$PullSrcDir" && "$PullSrcDir" != "DEFAULT" ]]; then
echo "cd ${PullSrcDir}"
fi
echo "rename ${pf_base} ${pf_name}${ActionOnSuccess}"
echo "bye"
} > "${local_batch_d}"
 
if ! run_sftp_transfer "${sftp_tmp_file_pull_d}"; then
log_mess "***" "Warning: Could not rename remote file: ${pf_base}"
else
log_mess "   " "Renamed remote: ${pf_base} -> ${pf_name}${ActionOnSuccess}"
fi
done
;;
esac
 
# Clean temp directory (if different from PullDestDir)
real_dest="$(realpath "$PullDestDir" 2>/dev/null || echo "$PullDestDir")"
real_tmp="$(realpath "$PullTempDir" 2>/dev/null || echo "$PullTempDir")"
if [[ "$real_dest" != "$real_tmp" ]]; then
cd "${PullTempDir}"
rm -f ${PullFilePattern} 2>/dev/null || true
log_mess "   " "Cleaned temp directory: ${PullTempDir}"
fi
 
log_mess "   " "========== PULL SFTP finished =========="
fi
 
#=============================================================================
# CLEAN FINISH
#=============================================================================
clean_finish