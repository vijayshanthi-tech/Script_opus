#!/bin/bash
###############################################################################
# Script Name    : generic_sftp.sh
# Converted From : SFTP_TRANSFER.COM (generic_sftp.txt — OpenVMS DCL)
# Description    : Generic SFTP script to push and/or pull files to/from
#                  remote servers.  All transfer parameters (host, user,
#                  directories, patterns, retry settings) are read from a
#                  configuration file.
#
# Environment    : Linux / Bash 4+
# Dependencies   : sftp (OpenSSH), gzip, mailx (optional for log_mess),
#                  flock (for singleton locking)
#
# ------- Input Parameters -------
#   $1 (CfgFileID)       — Name of the configuration file inside SFTP_CFG_DIR
#   $2 (ActionOnSuccess)  — Action after successful transfer:
#                            "NOCHANGE" — leave the source as-is
#                            "DELETE"   — delete the source file
#                            "GZ"       — gzip the source file
#                            ".<ext>"   — rename with extension (e.g. ".COPIED")
#
# ------- Config File Keys -------
#   SftpType:           push | pull | both
#   DestHostname:       Remote hostname/IP
#   DestUsername:        Remote SSH user
#   TransferType:       (reserved, unused on Linux — always binary)
#   SrcDir:             Local source directory (push)
#   DestDir:            Remote destination directory (push)
#   DestFileName:       Source file name/pattern on local side (push)
#   DestFilePattern:    Optional rename pattern on remote side (push)
#   DestFilePermission: chmod value for remote file (push)
#   PullSrcDir:         Remote source directory (pull)
#   PullDestDir:        Local destination directory (pull)
#   PullTempDir:        Local temp staging directory (pull)
#   PullFilePattern:    Remote file pattern to pull
#   RetryAttempts:      Number of SFTP retries (default 3)
#   RetryWaitSeconds:   Seconds between retries (default 60)
#
# ------- OpenVMS-to-Linux Section Mapping -------
#   VMS DCL Label / Phase          ->  Linux Bash Function
#   ────────────────────────────────────────────────────────
#   SAVE_ENVIRONMENT               ->  (env vars / script preamble)
#   CHECK_PREV_ERROR               ->  check_singleton()
#   CHECK_LOGICALS                 ->  validate_environment()
#   GET_INPUT_PARAMS               ->  validate_params()
#   SFTP_PARAMETERS                ->  parse_config_file()
#   PREPARE_SFTP                   ->  prepare_sftp_batch()
#   PUSH_SFTP / FILE_SEARCH_LOOP  ->  push_sftp()
#   PULL_SFTP                      ->  pull_sftp()
#   RUN_SFTP_TRANSFER              ->  run_sftp_transfer()
#   ACTION_ON_SUCCESS              ->  action_on_success()
#   HOUSE_KEEP / Housekeep1       ->  housekeep()
#   CLEAN_FINISH                   ->  clean_finish()
#   VMS_ERROR / REG_ERROR         ->  reg_error()
#   SET_PROCESS_NAME               ->  check_singleton()
#
# ------- Usage -------
#   ./generic_sftp.sh  <config_file>  [ActionOnSuccess]
#
#   Examples:
#     ./generic_sftp.sh RSERC_SFTP.CFG NOCHANGE
#     ./generic_sftp.sh FCS_PUSH.CFG   DELETE
#     ./generic_sftp.sh PULL_CDR.CFG   .COPIED
#     ./generic_sftp.sh BOTH_CFG.CFG   GZ
#
#   Source for unit testing (does NOT execute main):
#       source generic_sftp.sh
#
# ------- Environment Variable Requirements -------
#   SFTP_COM_DIR  — Directory containing SFTP COM/scripts
#   SFTP_CFG_DIR  — Directory containing SFTP config files
#   SFTP_LOG_DIR  — (optional) Log directory; defaults to SFTP_CFG_DIR
#   SFTP_PURGE_DAYS — (optional) Days to retain old logs (default 10)
###############################################################################

###############################################################################
#                       CONFIGURATION
###############################################################################

PROCNAME="$(basename "$0" .sh)"
LOG_FILE="${SFTP_LOG_DIR:-${SFTP_CFG_DIR:-.}}/generic_sftp.log"
WORK_DIR="${WORK_DIR:-/tmp/generic_sftp_$$}"
LOCK_DIR="${LOCK_DIR:-/tmp}"
SFTP_PURGE_DAYS="${SFTP_PURGE_DAYS:-10}"

# --- State variables (populated by parse_config_file) ---
CfgFileID=""
ActionOnSuccess=""
SftpType=""
SrcDir=""
DestHostname=""
DestUsername=""
DestDir=""
DestFileName=""
DestFilePattern=""
DestFilePermission=""
TransferType=""
PullSrcDir=""
PullDestDir=""
PullTempDir=""
PullFilePattern=""
RetryAttempts=3
RetryWaitSeconds=60

# Guard
_CLEANUP_DONE=0

###############################################################################
#                       FUNCTIONS
###############################################################################

# ---------- Logging ----------

log_msg() {
    local msg="$1"
    local dttm
    dttm=$(date '+%d-%b-%Y %H:%M:%S')
    echo "${dttm} - ${msg}" | tee -a "${LOG_FILE}"
}

log_error() {
    local phase="$1"
    local detail="$2"
    log_msg "*** ${PROCNAME} - ${phase},(${CfgFileID}) ${detail}"
}

# ---------- Singleton / Lock ----------
# VMS equivalent: SET_PROCESS_NAME subroutine + SHOW ENTRY retained check
# Prevents two instances with the same config from running simultaneously.

check_singleton() {
    local lock_name
    lock_name=$(echo "${CfgFileID}" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_')
    LOCK_FILE="${LOCK_DIR}/generic_sftp_${lock_name}.lock"

    exec 200>"${LOCK_FILE}"
    if ! flock -n 200; then
        log_error "CHECK_PREV_ERROR" "${CfgFileID} is already running"
        return 1
    fi
    # Lock held until process exits (fd 200 stays open)
    return 0
}

# ---------- Environment Validation ----------

validate_environment() {
    if [ -z "${SFTP_CFG_DIR}" ]; then
        log_error "CHECK_LOGICALS" "SFTP_CFG_DIR environment variable not defined"
        return 1
    fi

    if [ ! -d "${SFTP_CFG_DIR}" ]; then
        log_error "CHECK_LOGICALS" "SFTP_CFG_DIR directory does not exist: ${SFTP_CFG_DIR}"
        return 1
    fi

    return 0
}

# ---------- Input Parameter Validation ----------

validate_params() {
    if [ -z "${CfgFileID}" ]; then
        log_error "GET_INPUT_PARAMS" "Config file parameter (P1) is empty"
        return 1
    fi

    if [ ! -f "${SFTP_CFG_DIR}/${CfgFileID}" ]; then
        log_error "GET_INPUT_PARAMS" "Config file not found: ${SFTP_CFG_DIR}/${CfgFileID}"
        return 1
    fi

    if [ -z "${ActionOnSuccess}" ]; then
        ActionOnSuccess="NOCHANGE"
    fi

    # Validate ActionOnSuccess
    case "${ActionOnSuccess}" in
        DELETE|GZ|NOCHANGE) ;;
        .*)                 ;;
        *)
            log_error "GET_INPUT_PARAMS" "Invalid ActionOnSuccess value: ${ActionOnSuccess}"
            return 1
            ;;
    esac

    return 0
}

# ---------- Configuration File Parser ----------
# VMS equivalent: read_next_param loop over the .CFG file

parse_config_file() {
    local cfg_path="${SFTP_CFG_DIR}/${CfgFileID}"

    while IFS= read -r line || [ -n "${line}" ]; do
        # Skip comments (VMS: lines starting with !)
        [[ "${line}" =~ ^[[:space:]]*! ]] && continue
        [[ -z "${line}" ]] && continue

        local key value
        key="${line%%:*}"
        value="${line#*:}"
        value="$(echo "${value}" | tr -d '[:space:]')"

        case "${key}" in
            SftpType)           SftpType="${value}" ;;
            DestHostname)       DestHostname="${value}" ;;
            DestUsername)       DestUsername="${value}" ;;
            TransferType)       TransferType="${value}" ;;
            SrcDir)             SrcDir="${value}" ;;
            DestDir)            DestDir="${value}" ;;
            DestFileName)       DestFileName="${value}" ;;
            DestFilePattern)    DestFilePattern="${value}" ;;
            DestFilePermission) DestFilePermission="${value}" ;;
            PullSrcDir)         PullSrcDir="${value}" ;;
            PullDestDir)        PullDestDir="${value}" ;;
            PullTempDir)        PullTempDir="${value}" ;;
            PullFilePattern)    PullFilePattern="${value}" ;;
            RetryAttempts)      RetryAttempts="${value}" ;;
            RetryWaitSeconds)   RetryWaitSeconds="${value}" ;;
        esac
    done < "${cfg_path}"

    # Apply defaults
    RetryAttempts="${RetryAttempts:-3}"
    RetryWaitSeconds="${RetryWaitSeconds:-60}"

    # Validate mandatory fields based on SftpType
    local sftp_lower
    sftp_lower="$(echo "${SftpType}" | tr '[:upper:]' '[:lower:]')"
    SftpType="${sftp_lower}"

    if [ "${SftpType}" != "push" ] && [ "${SftpType}" != "pull" ] && [ "${SftpType}" != "both" ]; then
        log_error "SFTP_PARAMETERS" "Invalid or missing SftpType: ${SftpType}"
        return 1
    fi

    if [ -z "${DestHostname}" ] || [ "${DestHostname}" = ":" ]; then
        log_error "SFTP_PARAMETERS" "Mandatory field (DestHostname) in the configuration file is blank/absent"
        return 1
    fi

    if [ -z "${DestUsername}" ] || [ "${DestUsername}" = ":" ]; then
        log_error "SFTP_PARAMETERS" "Mandatory field (DestUsername) in the configuration file is blank/absent"
        return 1
    fi

    if [ "${SftpType}" = "push" ] || [ "${SftpType}" = "both" ]; then
        if [ -z "${SrcDir}" ] || [ "${SrcDir}" = ":" ]; then
            log_error "SFTP_PARAMETERS" "Mandatory field (SrcDir) in the configuration file is blank/absent"
            return 1
        fi
        if [ -z "${DestDir}" ] || [ "${DestDir}" = ":" ]; then
            log_error "SFTP_PARAMETERS" "Mandatory field (DestDir) in the configuration file is blank/absent"
            return 1
        fi
        if [ -z "${DestFileName}" ] || [ "${DestFileName}" = ":" ]; then
            log_error "SFTP_PARAMETERS" "Mandatory field (DestFileName) in the configuration file is blank/absent"
            return 1
        fi
        if [ ! -d "${SrcDir}" ]; then
            log_error "SFTP_PARAMETERS" "Source directory does not exist: ${SrcDir}"
            return 1
        fi
    fi

    if [ "${SftpType}" = "pull" ] || [ "${SftpType}" = "both" ]; then
        if [ -z "${PullFilePattern}" ] || [ "${PullFilePattern}" = ":" ]; then
            log_error "SFTP_PARAMETERS" "Mandatory field (PullFilePattern) in the configuration file is blank/absent"
            return 1
        fi
        if [ -z "${PullSrcDir}" ] || [ "${PullSrcDir}" = ":" ]; then
            log_error "SFTP_PARAMETERS" "Mandatory field (PullSrcDir) in the configuration file is blank/absent"
            return 1
        fi
        if [ -z "${PullDestDir}" ] || [ "${PullDestDir}" = ":" ]; then
            log_error "SFTP_PARAMETERS" "Mandatory field (PullDestDir) in the configuration file is blank/absent"
            return 1
        fi
        # Default PullTempDir
        PullTempDir="${PullTempDir:-${WORK_DIR}/pull_tmp}"
        mkdir -p "${PullTempDir}"
        if [ ! -d "${PullDestDir}" ]; then
            log_error "SFTP_PARAMETERS" "Pull destination directory does not exist: ${PullDestDir}"
            return 1
        fi
    fi

    if [ "${RetryAttempts}" -le 0 ] 2>/dev/null; then
        log_error "SFTP_PARAMETERS" "RetryAttempts must be a positive integer"
        return 1
    fi

    if [ "${RetryWaitSeconds}" -le 0 ] 2>/dev/null; then
        log_error "SFTP_PARAMETERS" "RetryWaitSeconds must be a positive integer"
        return 1
    fi

    return 0
}

# ---------- Run SFTP Transfer (with retries) ----------
# VMS equivalent: RUN_SFTP_TRANSFER subroutine with SFTP_LOOP / RE_TRY

run_sftp_transfer() {
    local batch_file="$1"
    local sftp_count=0

    while true; do
        log_msg "SFTP attempt $((sftp_count + 1)) of ${RetryAttempts} using batch: $(basename "${batch_file}")"

        if sftp -b "${batch_file}" "${DestUsername}@${DestHostname}" 2>>"${LOG_FILE}"; then
            log_msg "SFTP transfer succeeded"
            rm -f "${batch_file}" 2>/dev/null
            return 0
        fi

        sftp_count=$((sftp_count + 1))
        if [ "${sftp_count}" -ge "${RetryAttempts}" ]; then
            log_error "RUN_SFTP_TRANSFER" "All ${RetryAttempts} SFTP attempts failed"
            rm -f "${batch_file}" 2>/dev/null
            return 1
        fi

        log_msg "SFTP attempt failed. Retrying in ${RetryWaitSeconds} seconds..."
        sleep "${RetryWaitSeconds}"
    done
}

# ---------- Action on Success ----------
# VMS equivalent: ACTION_ON_SUCCESS subroutine

action_on_success() {
    local file_path="$1"

    if [ ! -f "${file_path}" ]; then
        return 0
    fi

    case "${ActionOnSuccess}" in
        DELETE)
            log_msg "Deleting source file: ${file_path}"
            rm -f "${file_path}"
            ;;
        GZ)
            log_msg "Compressing source file: ${file_path}"
            gzip -f "${file_path}" 2>>"${LOG_FILE}"
            ;;
        NOCHANGE)
            # Do nothing
            ;;
        .*)
            local new_name="${file_path}${ActionOnSuccess}"
            log_msg "Renaming source file: ${file_path} -> ${new_name}"
            mv "${file_path}" "${new_name}"
            ;;
    esac
}

# ---------- Push SFTP ----------
# VMS equivalent: PUSH_SFTP / FILE_SEARCH_LOOP section

push_sftp() {
    log_msg "Starting PUSH operation from ${SrcDir}"

    local file_pattern="${DestFileName}"
    local found_files=0

    while IFS= read -r -d '' src_file; do
        found_files=1
        local filename
        filename="$(basename "${src_file}")"

        # Create SFTP batch file
        local batch_file="${WORK_DIR}/sftp_push_$$.batch"
        {
            # Always binary on Linux (TransferType is a VMS legacy)
            echo "binary"

            if [ -n "${DestDir}" ] && [ "${DestDir}" != "DEFAULT" ]; then
                echo "cd \"${DestDir}\""
            fi

            # Upload with .SFTP_TMP extension first (atomic put)
            echo "put \"${src_file}\" \"${filename}.SFTP_TMP\""

            # Set permissions if configured (VMS v2.6: chmod 775)
            if [ -n "${DestFilePermission}" ]; then
                echo "chmod ${DestFilePermission} \"${filename}.SFTP_TMP\""
            else
                echo "chmod 775 \"${filename}.SFTP_TMP\""
            fi

            # Rename to final name on remote (atomic)
            local remote_name="${filename}"
            if [ -n "${DestFilePattern}" ]; then
                # Apply pattern-based renaming if configured
                remote_name="${DestFilePattern}"
            fi
            echo "rename \"${filename}.SFTP_TMP\" \"${remote_name}\""

            echo "exit"
        } > "${batch_file}"

        if run_sftp_transfer "${batch_file}"; then
            action_on_success "${src_file}"
        else
            log_error "PUSH_SFTP" "Failed to transfer file: ${filename}"
        fi
    done < <(find "${SrcDir}" -maxdepth 1 -name "${file_pattern}" -type f -print0 2>/dev/null)

    if [ "${found_files}" -eq 0 ]; then
        log_msg "No files matching '${file_pattern}' found in ${SrcDir}"
    fi
}

# ---------- Pull SFTP ----------
# VMS equivalent: PULL_SFTP section

pull_sftp() {
    log_msg "Starting PULL operation to ${PullDestDir}"

    # Clean previous temp files (VMS: delete CELL0_DAT:PullFilePattern)
    if [ -d "${PullTempDir}" ]; then
        find "${PullTempDir}" -maxdepth 1 -name "${PullFilePattern}" -delete 2>/dev/null
    fi

    # Create SFTP batch file for pull
    local batch_file="${WORK_DIR}/sftp_pull_$$.batch"
    {
        echo "binary"

        if [ -n "${PullSrcDir}" ] && [ "${PullSrcDir}" != "DEFAULT" ]; then
            echo "cd \"${PullSrcDir}\""
        fi

        echo "lcd \"${PullTempDir}\""
        echo "get ${PullFilePattern}"
        echo "exit"
    } > "${batch_file}"

    if ! run_sftp_transfer "${batch_file}"; then
        log_error "PULL_SFTP" "Failed to pull files from remote server"
        return 1
    fi

    # Check if any files were received
    local pull_count
    pull_count=$(find "${PullTempDir}" -maxdepth 1 -name "${PullFilePattern}" 2>/dev/null | wc -l)
    if [ "${pull_count}" -eq 0 ]; then
        log_msg "The files for pull are not present in the remote server"
        return 0
    fi

    # Copy received files to destination directory
    log_msg "Copying ${pull_count} pulled file(s) to ${PullDestDir}"
    if ! cp "${PullTempDir}"/${PullFilePattern} "${PullDestDir}/" 2>>"${LOG_FILE}"; then
        log_error "PULL_SFTP" "Error copying pulled files to target directory"
        return 1
    fi

    # Handle remote file action (DELETE or rename on remote)
    if [ "${ActionOnSuccess}" = "DELETE" ]; then
        local del_batch="${WORK_DIR}/sftp_pull_del_$$.batch"
        {
            if [ -n "${PullSrcDir}" ] && [ "${PullSrcDir}" != "DEFAULT" ]; then
                echo "cd \"${PullSrcDir}\""
            fi
            echo "rm ${PullFilePattern}"
            echo "exit"
        } > "${del_batch}"

        if ! run_sftp_transfer "${del_batch}"; then
            log_error "PULL_SFTP" "Failed to delete remote files after pull"
        fi
    elif [[ "${ActionOnSuccess}" == .* ]]; then
        # Rename files on remote server with extension
        for pulled_file in "${PullTempDir}"/${PullFilePattern}; do
            [ -f "${pulled_file}" ] || continue
            local fname
            fname="$(basename "${pulled_file}")"
            local rename_batch="${WORK_DIR}/sftp_pull_ren_$$.batch"
            {
                if [ -n "${PullSrcDir}" ] && [ "${PullSrcDir}" != "DEFAULT" ]; then
                    echo "cd \"${PullSrcDir}\""
                fi
                echo "rename \"${fname}\" \"${fname}${ActionOnSuccess}\""
                echo "exit"
            } > "${rename_batch}"

            run_sftp_transfer "${rename_batch}" || \
                log_error "PULL_SFTP" "Failed to rename remote file: ${fname}"
        done
    fi

    # Clean temp directory (VMS: delete CELL0_DAT:PullFilePattern)
    if [ "${PullTempDir}" != "${PullDestDir}" ]; then
        find "${PullTempDir}" -maxdepth 1 -name "${PullFilePattern}" -delete 2>/dev/null
    fi
}

# ---------- Housekeeping ----------
# VMS equivalent: HOUSE_KEEP subroutine + Housekeep1

housekeep() {
    # Delete old .sftp batch files (older than 2 days)
    find "${SFTP_CFG_DIR}" -maxdepth 1 -iname '*.sftp' -mtime +2 -delete 2>/dev/null

    # Delete old log files
    if [ -n "${SFTP_LOG_DIR}" ] && [ -d "${SFTP_LOG_DIR}" ]; then
        find "${SFTP_LOG_DIR}" -maxdepth 1 -iname 'GENERIC_SFTP*' -mtime +"${SFTP_PURGE_DAYS}" -delete 2>/dev/null
    fi

    # Clean up work directory
    rm -rf "${WORK_DIR}" 2>/dev/null
}

# ---------- Clean Finish ----------

clean_finish() {
    if [ "${_CLEANUP_DONE}" -eq 1 ]; then
        return 0
    fi
    _CLEANUP_DONE=1
    housekeep
    log_msg "${PROCNAME} has completed successfully"
}

# ---------- Error Exit ----------

reg_error() {
    local phase="$1"
    local detail="$2"
    if [ "${_CLEANUP_DONE}" -eq 1 ]; then
        return
    fi
    _CLEANUP_DONE=1
    housekeep
    log_error "${phase}" "${detail}"
    exit 1
}

# ---------- Cleanup Trap ----------

cleanup_and_exit() {
    if [ "${_CLEANUP_DONE}" -eq 0 ]; then
        _CLEANUP_DONE=1
        housekeep
        log_msg "${PROCNAME} interrupted — cleaned up"
    fi
}

###############################################################################
#                       MAIN
###############################################################################

main() {
    CfgFileID="$1"
    ActionOnSuccess="${2:-NOCHANGE}"

    mkdir -p "${WORK_DIR}"

    # Signal handlers
    trap cleanup_and_exit EXIT SIGTERM SIGINT

    log_msg "${PROCNAME} has started"

    # Phase: CHECK_LOGICALS
    validate_environment || exit 1

    # Phase: GET_INPUT_PARAMS
    validate_params || exit 1

    # Phase: CHECK_PREV_ERROR / SET_PROCESS_NAME
    check_singleton || exit 1

    # Phase: SFTP_PARAMETERS
    parse_config_file || exit 1

    # Phase: PUSH_SFTP
    if [ "${SftpType}" = "push" ] || [ "${SftpType}" = "both" ]; then
        push_sftp
    fi

    # Phase: PULL_SFTP
    if [ "${SftpType}" = "pull" ] || [ "${SftpType}" = "both" ]; then
        pull_sftp
    fi

    # Phase: CLEAN_FINISH
    clean_finish
}

# Entry-point guard: do not run main when sourced (enables unit testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
