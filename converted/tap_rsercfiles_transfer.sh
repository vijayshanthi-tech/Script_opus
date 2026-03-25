#!/bin/bash
###############################################################################
# Script Name   : tap_rsercfiles_transfer.sh
# Converted From: TAP_RSERCFILES_TRANSFER.COM (VMS DCL)
# Description   : Transfers generated RSERC and MRLOG files from the TAP
#                 system to the ABS system via SFTP. Runs continuously,
#                 batching up to 50 files of each type per cycle. Uses a
#                 temporary file extension (.sftp_tmp_rs) during transfer
#                 to prevent partial pickup on the remote side. Includes
#                 self-recovery from previous failed transfers.
#
# Environment   : Linux / Bash 4+ / RHEL 9
# Dependencies  : sftp (OpenSSH), SSH key-based auth to ABS server
#
# Original Author : Mahalakshmi / Arul Mani (VMS legacy)
# Converted By    : VMS-to-Linux conversion
#
# VMS Sections Mapped:
#   SAVE_ENVIRONMENT       -> Configuration section + lock file
#   CHECK_INSTANCES        -> acquire_lock()  (flock-based)
#   Logical checks         -> validate_environment()
#   HOUSE_KEEP             -> housekeeping()
#   EXTRACT_SFTP           -> read_sftp_config()
#   SELF_RECOVERY          -> self_recovery()
#   MAIN_LOOP              -> main_loop()
#   RSERC_FILE_COUNT       -> collect_rserc_files()
#   MRLOG_FILE_COUNT       -> collect_mrlog_files()
#   SFTP_PROCESS           -> sftp_transfer()
#   FINAL_CHECK            -> should_shutdown()
#   ERROR                  -> error_exit()
#   CLEAN_FINISH / EXIT    -> cleanup_and_exit()
#
# Prerequisites:
#   1. SSH key-based authentication configured for SFTP to ABS server
#   2. Config file RSERC_SFTP.CFG in TAP_CFG_DIR (line1=user, line2=host)
#   3. All directory environment variables set (see CONFIGURATION below)
#   4. RSERC_TRANS_SHUTDOWN env var or flag file for graceful shutdown
#   5. Write access to SFTP_TMP_DIR, TAP_DAT_DIR, TAP_LOG_DIR
###############################################################################

set -o pipefail

###############################################################################
#                       CONFIGURATION
###############################################################################

# --- Directory mappings (VMS logical -> Linux path) ---
# Defaults can be overridden via environment variables (for testing/deployment)
TAP_CFG_DIR="${TAP_CFG_DIR:-/app/tap/R53_TAPLIVE/TAP/CFG}"
TAP_DAT_DIR="${TAP_DAT_DIR:-/data/tap/R53_TAPLIVE/TAP/DAT}"
TAP_LOG_DIR="${TAP_LOG_DIR:-/data/tap/R53_TAPLIVE/TAP/LOG}"
TAP_COM_DIR="${TAP_COM_DIR:-/app/tap/R53_TAPLIVE/TAP/COM}"
FCS_RSERC_DIR="${FCS_RSERC_DIR:-/data/tap/R53_TAPLIVE/TAP/FCS_RSERC}"
TAP_RSERC_DIR="${TAP_RSERC_DIR:-/data/tap/R53_TAPLIVE/TAP/RSERC}"
SFTP_TMP_DIR="${SFTP_TMP_DIR:-/data/tap/R53_TAPLIVE/TAP/DAT/SFTP_TMP}"

# --- Shutdown controls (VMS: RSERC_TRANS_SHUTDOWN logical, TAP_CLOSEDOWN_ALL) ---
RSERC_TRANS_SHUTDOWN="${RSERC_TRANS_SHUTDOWN:-N}"
# When set to "N", time-based closedown is disabled (VMS: comparing a timestamp
# against "N" always evaluates false because digits sort before letters).
TAP_CLOSEDOWN_ALL="${TAP_CLOSEDOWN_ALL:-N}"

# --- SFTP config file (VMS: TAP_CFG_DIR:RSERC_SFTP.CFG) ---
SFTP_CFG_FILE="${TAP_CFG_DIR}/RSERC_SFTP.CFG"

# --- Batch size limit (VMS: .GT. 50) ---
MAX_BATCH_SIZE=50

# --- Remote directory on ABS server (VMS: "cd xi_dat") ---
REMOTE_DIR="xi_dat"

# --- Log file ---
SCRIPT_NAME="$(basename "$0" .sh)"
LOG_FILE="${TAP_LOG_DIR}/${SCRIPT_NAME}.log"

# --- Lock file for single-instance enforcement ---
LOCK_FILE="/var/lock/${SCRIPT_NAME}.lock"

# --- Flag file for in-progress tracking (VMS: SFTP_ABS_IN_PROGRESS.FLAG) ---
FLAG_FILE="${TAP_DAT_DIR}/SFTP_ABS_IN_PROGRESS.FLAG"

# --- Guard against double cleanup ---
_CLEANUP_DONE=0

# --- File descriptor for lock ---
LOCK_FD=9

###############################################################################
#                       FUNCTIONS
###############################################################################

# ---- Logging helper (VMS: @TAP_COM_DIR:TAPLOG_MESS + WSO) ----
log_msg() {
    local msg="$1"
    local dttm
    dttm=$(date '+%d-%b-%Y %H:%M:%S')
    echo "${dttm} - ${msg}" | tee -a "${LOG_FILE}"
}

# ---- Error exit (VMS: ERROR section) ----
# Logs error, optionally notifies operator, exits with code 4
error_exit() {
    local error_text="$1"
    local phase="${2:-UNKNOWN}"

    log_msg "ERROR: *** ${SCRIPT_NAME} - ${phase}, ${error_text}"

    # VMS: REQUEST/REPLY/TO=OPER — log to syslog as substitute
    logger -t "${SCRIPT_NAME}" "ERROR - ${phase}: ${error_text}"

    cleanup_and_exit 4
}

# ---- Cleanup (VMS: EXIT section + temp file removal) ----
cleanup_and_exit() {
    local exit_code="${1:-0}"

    if [ "${_CLEANUP_DONE}" -eq 1 ]; then
        exit "${exit_code}"
    fi
    _CLEANUP_DONE=1

    log_msg "${SCRIPT_NAME} exiting with code ${exit_code} at $(date '+%d-%b-%Y %H:%M:%S')"

    # Release lock
    if [ -n "${LOCK_FD}" ]; then
        eval "exec ${LOCK_FD}>&-" 2>/dev/null
    fi

    exit "${exit_code}"
}

# ---- Acquire exclusive lock (VMS: SET PROCESS /NAME= for instance check) ----
acquire_lock() {
    eval "exec ${LOCK_FD}>${LOCK_FILE}"
    if ! flock -n "${LOCK_FD}"; then
        echo "$(date '+%d-%b-%Y %H:%M:%S') - ${SCRIPT_NAME} exiting - process already running." | tee -a "${LOG_FILE}"
        exit 0
    fi
}

# ---- Validate environment (VMS: logical name checks) ----
validate_environment() {
    local phase="VALIDATE_ENVIRONMENT"

    # Check required directories exist
    for dir_var in TAP_CFG_DIR TAP_DAT_DIR TAP_LOG_DIR FCS_RSERC_DIR TAP_RSERC_DIR SFTP_TMP_DIR; do
        local dir_val="${!dir_var}"
        if [ -z "${dir_val}" ]; then
            error_exit "*** Fatal: Environment variable ${dir_var} is not set." "${phase}"
        fi
        if [ ! -d "${dir_val}" ]; then
            error_exit "*** Fatal: Directory ${dir_val} (${dir_var}) does not exist." "${phase}"
        fi
    done

    # Check SFTP config file exists
    if [ ! -f "${SFTP_CFG_FILE}" ]; then
        error_exit "ERROR WHILE SEARCHING FOR ${SFTP_CFG_FILE} FILE" "${phase}"
    fi
}

# ---- Housekeeping (VMS: HOUSE_KEEP — delete logs older than 7 days) ----
housekeeping() {
    log_msg "Housekeeping: removing log files older than 7 days"
    find "${TAP_LOG_DIR}" -maxdepth 1 -name "${SCRIPT_NAME}.log.*" -mtime +7 -delete 2>/dev/null || true
}

# ---- Read SFTP config (VMS: EXTRACT_SFTP — read username and hostname) ----
read_sftp_config() {
    local phase="EXTRACT_SFTP"

    if [ ! -f "${SFTP_CFG_FILE}" ]; then
        error_exit "SFTP config file not found: ${SFTP_CFG_FILE}" "${phase}"
    fi

    # VMS: line 1 = username, line 2 = hostname
    {
        read -r DEST_USERNAME
        read -r DEST_HOSTNAME
    } < "${SFTP_CFG_FILE}"

    if [ -z "${DEST_USERNAME}" ] || [ -z "${DEST_HOSTNAME}" ]; then
        error_exit "SFTP config file is incomplete (need username and hostname)" "${phase}"
    fi

    log_msg "SFTP target: ${DEST_USERNAME}@${DEST_HOSTNAME}"
}

# ---- Self-recovery (VMS: SELF_RECOVERY section) ----
# Cleans up from a previous failed transfer attempt
self_recovery() {
    local phase="SELF_RECOVERY"
    log_msg "Checking for recovery from previous failure"

    # Clean temp directory (VMS: DELETE SFTP_TMP_DIR:*.*;*)
    rm -f "${SFTP_TMP_DIR:?}"/* 2>/dev/null || true

    # Check if a previous transfer was in progress
    if [ ! -f "${FLAG_FILE}" ]; then
        log_msg "No recovery needed"
        return 0
    fi

    log_msg "Found in-progress flag — performing recovery"
    rm -f "${FLAG_FILE}"

    # RECOVERY_1: If SFTP control file exists, remote files may have partial uploads
    # Note: must match the lowercase name used in main_loop() — Linux is case-sensitive
    local ctrl_file="${TAP_DAT_DIR}/sftp_ctrl_file.dat"
    if [ -f "${ctrl_file}" ]; then
        log_msg "Recovery stage 1: Removing partial uploads from remote server"

        # Create SFTP batch to remove partial files on remote
        local recover_batch="${TAP_DAT_DIR}/sftp_recover.dat"
        cat > "${recover_batch}" <<EOF
cd ${REMOTE_DIR}
rm *.sftp_tmp_rs
exit
EOF
        if ! sftp -b "${recover_batch}" "${DEST_USERNAME}@${DEST_HOSTNAME}"; then
            error_exit "ERROR WHILE RECOVERING THE PREVIOUS FAILURE - Remove SFTP PROCESS" "${phase}"
        fi
        rm -f "${recover_batch}"
        rm -f "${ctrl_file}"
        rm -f "${TAP_DAT_DIR}/rename_sftpd_files_tmp.sh"
        rm -f "${TAP_DAT_DIR}/delete_sftpd_files_tmp.sh"
        return 0
    fi

    # RECOVERY_2: If rename script exists, uploads completed but rename didn't
    # VMS: This section is commented out in original — rename recovery disabled
    # The original VMS code has RECOVERY_2 commented out, so we skip it too
    local ren_file="${TAP_DAT_DIR}/rename_sftpd_files_tmp.sh"
    if [ -f "${ren_file}" ]; then
        log_msg "Recovery stage 2: Rename script found but recovery skipped (as per VMS original)"
        # Note: VMS original has this section commented out
        # If needed in future, would run SFTP rename batch here
        error_exit "ERROR WHILE RECOVERING THE PREVIOUS FAILURE - Rename SFTP PROCESS" "${phase}"
    fi

    # RECOVERY_3: If delete script exists, remote side is done but local cleanup didn't complete
    local del_file="${TAP_DAT_DIR}/delete_sftpd_files_tmp.sh"
    if [ -f "${del_file}" ]; then
        log_msg "Recovery stage 3: Running pending local file deletions"
        if ! bash "${del_file}"; then
            error_exit "ERROR WHILE RECOVERING THE PREVIOUS FAILURE - Delete in TAP XI_DAT" "${phase}"
        fi
        rm -f "${del_file}"
    fi
}

# ---- Collect RSERC files for transfer ----
# VMS: RSERC_FILE_COUNT loop — searches FCS_RSERC_DIR:RSERC%%%%%%.DAT
# Copies to temp dir with .sftp_tmp_rs extension, adds to batch files
# Returns: sets RSERC_COUNT variable
collect_rserc_files() {
    RSERC_COUNT=0
    local sftp_fd="$1"      # File descriptor for SFTP batch commands
    local rename_fd="$2"    # File descriptor for remote rename commands
    local delete_fd="$3"    # File descriptor for local delete commands

    # VMS pattern RSERC%%%%%%.DAT -> bash pattern RSERC??????.DAT
    while IFS= read -r -d '' rserc_file; do
        if [ "${RSERC_COUNT}" -ge "${MAX_BATCH_SIZE}" ]; then
            break
        fi

        local filename
        filename=$(basename "${rserc_file}")
        local name="${filename%.*}"
        local tmp_name="${name}.sftp_tmp_rs"

        # Copy to temp dir with temporary extension (VMS: COPY/LOG)
        if cp "${rserc_file}" "${SFTP_TMP_DIR}/${tmp_name}"; then
            echo "put ${tmp_name}" >> "${sftp_fd}"
            echo "rename ${tmp_name} ${filename}" >> "${rename_fd}"
            echo "rm -f \"${rserc_file}\"" >> "${delete_fd}"
            RSERC_COUNT=$((RSERC_COUNT + 1))
            log_msg "Staged RSERC file: ${filename}"
        else
            log_msg "WARNING: Failed to copy ${rserc_file} to staging"
        fi
    done < <(find "${FCS_RSERC_DIR}" -maxdepth 1 -name 'RSERC??????.DAT' -print0 2>/dev/null)
}

# ---- Collect MRLOG files for transfer ----
# VMS: MRLOG_FILE_COUNT loop — searches TAP_RSERC_DIR:MRLOG%%%%%%.DAT
# Same approach as RSERC collection
# Returns: sets MRLOG_COUNT variable
collect_mrlog_files() {
    MRLOG_COUNT=0
    local sftp_fd="$1"
    local rename_fd="$2"
    local delete_fd="$3"

    # VMS pattern MRLOG%%%%%%.DAT -> bash pattern MRLOG??????.DAT
    while IFS= read -r -d '' mrlog_file; do
        if [ "${MRLOG_COUNT}" -ge "${MAX_BATCH_SIZE}" ]; then
            break
        fi

        local filename
        filename=$(basename "${mrlog_file}")
        local name="${filename%.*}"
        local tmp_name="${name}.sftp_tmp_rs"

        if cp "${mrlog_file}" "${SFTP_TMP_DIR}/${tmp_name}"; then
            echo "put ${tmp_name}" >> "${sftp_fd}"
            echo "rename ${tmp_name} ${filename}" >> "${rename_fd}"
            echo "rm -f \"${mrlog_file}\"" >> "${delete_fd}"
            MRLOG_COUNT=$((MRLOG_COUNT + 1))
            log_msg "Staged MRLOG file: ${filename}"
        else
            log_msg "WARNING: Failed to copy ${mrlog_file} to staging"
        fi
    done < <(find "${TAP_RSERC_DIR}" -maxdepth 1 -name 'MRLOG??????.DAT' -print0 2>/dev/null)
}

# ---- SFTP transfer process ----
# VMS: SFTP_PROCESS section
# 1. Upload files via SFTP batch
# 2. Rename files on remote (.sftp_tmp_rs -> .DAT)
# 3. Delete local source files
sftp_transfer() {
    local phase="SFTP_PROCESS"
    local sftp_batch="$1"
    local rename_batch="$2"
    local delete_script="$3"

    log_msg "SFTP PROCESS FOR TRANSFER OF RSERC AND MRLOG FILES STARTED AT $(date '+%d-%b-%Y %H:%M:%S')"

    # Set in-progress flag (VMS: create TAP_DAT_DIR:SFTP_ABS_IN_PROGRESS.FLAG)
    touch "${FLAG_FILE}"

    # Step 1: Upload files via SFTP
    if ! sftp -b "${sftp_batch}" "${DEST_USERNAME}@${DEST_HOSTNAME}"; then
        error_exit "ERROR WHILE TRANSFERRING THE RSERCS AND MRLOG FILES FROM TAP TO ABS - SFTP PROCESS" "${phase}"
    fi
    rm -f "${sftp_batch}"

    # Step 2: Rename files on remote server (.sftp_tmp_rs -> .DAT)
    if ! sftp -b "${rename_batch}" "${DEST_USERNAME}@${DEST_HOSTNAME}"; then
        error_exit "ERROR WHILE RENAMING THE RSERCS AND MRLOG FILES FROM .SFTP_TMP_RS TO .DAT IN ABS - SFTP PROCESS" "${phase}"
    fi
    rm -f "${rename_batch}"

    # Clean staging directory (VMS: DELETE SFTP_TMP_DIR:*.*;*)
    rm -f "${SFTP_TMP_DIR:?}"/* 2>/dev/null || true

    # Step 3: Delete local source files
    if ! bash "${delete_script}"; then
        error_exit "ERROR WHILE DELETING SFTPD FILES FROM XI_DAT DIRECTORY" "${phase}"
    fi
    rm -f "${delete_script}"

    # Remove in-progress flag
    rm -f "${FLAG_FILE}"

    log_msg "SFTP PROCESS FOR TRANSFER OF RSERC AND MRLOG FILES COMPLETED AT $(date '+%d-%b-%Y %H:%M:%S')"
}

# ---- Check if shutdown is requested ----
# VMS: FINAL_CHECK — checks TAP_CLOSEDOWN_ALL time and RSERC_TRANS_SHUTDOWN flag
should_shutdown() {
    # Check shutdown flag (VMS: F$TRNLNM("RSERC_TRANS_SHUTDOWN") .EQS. "Y")
    if [ "${RSERC_TRANS_SHUTDOWN}" = "Y" ]; then
        log_msg "Shutdown requested via RSERC_TRANS_SHUTDOWN flag"
        return 0
    fi

    # Re-read flag in case it was changed externally
    if [ -f "${TAP_DAT_DIR}/RSERC_TRANS_SHUTDOWN.FLAG" ]; then
        log_msg "Shutdown requested via flag file"
        return 0
    fi

    # Check time-based closedown (VMS: F$CVTIME() .GTS. F$TRNLNM("TAP_CLOSEDOWN_ALL"))
    # When TAP_CLOSEDOWN_ALL is "N", time-based shutdown is disabled.
    if [ "${TAP_CLOSEDOWN_ALL}" != "N" ]; then
        local current_time
        current_time=$(date '+%H:%M')
        if [[ "${current_time}" > "${TAP_CLOSEDOWN_ALL}" ]]; then
            log_msg "Past closedown time (${TAP_CLOSEDOWN_ALL}), shutting down"
            return 0
        fi
    fi

    return 1
}

# ---- Main transfer loop ----
# VMS: MAIN_PARA -> MAIN_LOOP
main_loop() {
    local phase="MAIN_LOOP"

    while true; do
        # Prepare batch files
        local sftp_batch="${TAP_DAT_DIR}/sftp_ctrl_file.dat"
        local rename_batch="${TAP_DAT_DIR}/rename_sftpd_files_tmp.sh"
        local delete_script="${TAP_DAT_DIR}/delete_sftpd_files_tmp.sh"

        # Create SFTP upload batch header
        # VMS: WRITE SFTP_CTRL_FILE "binary" / "lcd SFTP_TMP_DIR" / "cd xi_dat"
        # Note: "binary" is an FTP command, not valid in OpenSSH sftp.
        # SFTP always transfers in binary mode — no mode switch needed.
        cat > "${sftp_batch}" <<EOF
lcd ${SFTP_TMP_DIR}
cd ${REMOTE_DIR}
EOF

        # Create remote rename batch header
        # VMS: WRITE RENAME_TMP_FILE "cd xi_dat"
        cat > "${rename_batch}" <<EOF
cd ${REMOTE_DIR}
EOF

        # Create local delete script header
        cat > "${delete_script}" <<'EOF'
#!/bin/bash
# Auto-generated: delete source files after successful SFTP transfer
EOF

        # Collect RSERC files (VMS: RSERC_FILE_COUNT loop)
        collect_rserc_files "${sftp_batch}" "${rename_batch}" "${delete_script}"

        # Collect MRLOG files (VMS: MRLOG_FILE_COUNT loop)
        collect_mrlog_files "${sftp_batch}" "${rename_batch}" "${delete_script}"

        if [ "${RSERC_COUNT}" -gt 0 ] || [ "${MRLOG_COUNT}" -gt 0 ]; then
            log_msg "Batch: ${RSERC_COUNT} RSERC files, ${MRLOG_COUNT} MRLOG files"

            # Finalize batch files
            echo "exit" >> "${sftp_batch}"
            echo "exit" >> "${rename_batch}"

            # Execute the transfer
            sftp_transfer "${sftp_batch}" "${rename_batch}" "${delete_script}"
        else
            # No files to transfer — clean up empty batch files
            rm -f "${sftp_batch}" "${rename_batch}" "${delete_script}"

            log_msg "No files to transfer, waiting 10 minutes"
            sleep 600
        fi

        # Check if we should shut down (VMS: FINAL_CHECK)
        if should_shutdown; then
            break
        fi
    done
}

###############################################################################
#                       MAIN
###############################################################################

main() {
    # Set up signal handling (VMS: ON ERROR THEN GOTO ERROR)
    trap 'error_exit "Caught signal, aborting" "SIGNAL"' SIGTERM SIGINT
    trap cleanup_and_exit EXIT

    log_msg "${SCRIPT_NAME} has started at $(date '+%d-%b-%Y %H:%M:%S')"

    # Single instance check (VMS: CHECK_INSTANCES / SET PROCESS /NAME=)
    acquire_lock

    # Validate environment (VMS: logical name checks)
    validate_environment

    # Housekeeping (VMS: HOUSE_KEEP)
    housekeeping

    # Read SFTP connection details (VMS: EXTRACT_SFTP)
    read_sftp_config

    # Self-recovery from previous failure (VMS: SELF_RECOVERY)
    self_recovery

    # Enter main transfer loop (VMS: MAIN_PARA)
    main_loop

    # Clean exit
    log_msg "${SCRIPT_NAME} has completed successfully at $(date '+%d-%b-%Y %H:%M:%S')"
}

# ---- Script guard: allow sourcing for testing without executing main ----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
