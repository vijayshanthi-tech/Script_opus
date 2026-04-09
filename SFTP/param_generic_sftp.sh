#!/bin/bash
###############################################################################
# Script Name    : param_generic_sftp.sh
# Converted From : SFTP_TRANSFER.COM (param_generic_sftp.txt — OpenVMS DCL)
# Description    : Parameterised variant of the generic SFTP transfer script.
#                  Unlike generic_sftp.sh which reads ALL settings from a
#                  config file, this version receives key transfer parameters
#                  directly via the command line — the config file supplies
#                  only DestHostname, DestUsername, DestDir, TransferType,
#                  and PullSrcDir.
#
# Environment    : Linux / Bash 4+
# Dependencies   : sftp (OpenSSH), gzip, flock (singleton locking)
#
# ------- Input Parameters -------
#   $1 (CfgFileID)        — Config file name inside SFTP_CFG_DIR
#   $2 (SftpType)         — "push" or "pull"  (case-insensitive)
#   $3 (SrcDir/PullDestDir) — For push: local source directory
#                             For pull: local destination directory
#   $4 (DestFileName/PullFilePattern) — For push: source file name/glob
#                                       For pull: remote file pattern
#   $5 (DestFilePattern)  — For push: optional rename pattern on remote
#                           For pull: (unused)
#   $6 (ActionOnSuccess)  — NOCHANGE | DELETE | GZ | .<ext>
#
# ------- Config File Keys (subset — rest via params) -------
#   DestHostname:     Remote hostname/IP
#   DestUsername:     Remote SSH user
#   DestDir:          Remote destination directory (push)
#   TransferType:     (reserved — always binary on Linux)
#   PullSrcDir:       Remote source directory (pull)
#
# ------- Differences to generic_sftp.sh -------
#   • SftpType, SrcDir, DestFileName, DestFilePattern, PullDestDir,
#     PullFilePattern are passed as command-line arguments, NOT in the
#     config file.
#   • RetryAttempts/RetryWaitSeconds default to 3/5 (not read from config).
#   • The VMS param version (v2.0) does not read those from config; values
#     are hard-coded.
#
# ------- Usage -------
#   PUSH:
#     ./param_generic_sftp.sh RSERC_SFTP.CFG push /data/tap/outgoing "*.dat" "CDR_*" DELETE
#
#   PULL:
#     ./param_generic_sftp.sh RSERC_SFTP.CFG pull /data/tap/incoming "*.dat" "" NOCHANGE
#
#   Source for unit testing (does NOT execute main):
#       source param_generic_sftp.sh
#
# ------- Environment Variable Requirements -------
#   SFTP_CFG_DIR  — Directory containing SFTP config files
#   SFTP_LOG_DIR  — (optional) Log directory; defaults to SFTP_CFG_DIR
#   SFTP_PURGE_DAYS — (optional) Days to retain old logs (default 10)
###############################################################################

###############################################################################
#                       CONFIGURATION
###############################################################################

PROCNAME="$(basename "$0" .sh)"
LOG_FILE="${SFTP_LOG_DIR:-${SFTP_CFG_DIR:-.}}/param_generic_sftp.log"
WORK_DIR="${WORK_DIR:-/tmp/param_generic_sftp_$$}"
LOCK_DIR="${LOCK_DIR:-/tmp}"
SFTP_PURGE_DAYS="${SFTP_PURGE_DAYS:-10}"

# --- State ---
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
PullSrcDir=""
PullDestDir=""
PullFilePattern=""
RetryAttempts=3
RetryWaitSeconds=5

_CLEANUP_DONE=0

###############################################################################
#                       FUNCTIONS
###############################################################################

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

# ---------- Singleton ----------

check_singleton() {
    local lock_name
    lock_name=$(echo "${CfgFileID}" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_')
    LOCK_FILE="${LOCK_DIR}/param_sftp_${lock_name}.lock"

    exec 200>"${LOCK_FILE}"
    if ! flock -n 200; then
        log_error "CHECK_PREV_ERROR" "${CfgFileID} is already running"
        return 1
    fi
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
# VMS v2.0: params come from p1..p6 instead of entirely from config

validate_params() {
    if [ -z "${CfgFileID}" ]; then
        log_error "GET_INPUT_PARAMS" "Config file parameter (P1) is empty"
        return 1
    fi

    if [ ! -f "${SFTP_CFG_DIR}/${CfgFileID}" ]; then
        log_error "GET_INPUT_PARAMS" "Config file not found: ${SFTP_CFG_DIR}/${CfgFileID}"
        return 1
    fi

    # SftpType (p2)
    local sftp_lower
    sftp_lower="$(echo "${SftpType}" | tr '[:upper:]' '[:lower:]')"
    SftpType="${sftp_lower}"
    if [ "${SftpType}" != "push" ] && [ "${SftpType}" != "pull" ]; then
        log_error "GET_INPUT_PARAMS" "Invalid SftpType (P2): ${SftpType}. Must be push or pull."
        return 1
    fi

    # ActionOnSuccess (p6) — default NOCHANGE
    if [ -z "${ActionOnSuccess}" ]; then
        ActionOnSuccess="NOCHANGE"
    fi

    case "${ActionOnSuccess}" in
        DELETE|GZ|NOCHANGE) ;;
        .*)                 ;;
        *)
            log_error "GET_INPUT_PARAMS" "Invalid ActionOnSuccess (P6): ${ActionOnSuccess}"
            return 1
            ;;
    esac

    # Push validations
    if [ "${SftpType}" = "push" ]; then
        if [ -z "${SrcDir}" ]; then
            log_error "GET_INPUT_PARAMS" "Mandatory field (SrcDir) is not passed as parameter properly"
            return 1
        fi
        if [ -z "${DestFileName}" ]; then
            log_error "GET_INPUT_PARAMS" "Mandatory field (DestFileName) is not passed as parameter properly"
            return 1
        fi
        if [ ! -d "${SrcDir}" ]; then
            log_error "GET_INPUT_PARAMS" "Source directory does not exist: ${SrcDir}"
            return 1
        fi
        # Check source files exist
        local file_count
        file_count=$(find "${SrcDir}" -maxdepth 1 -name "${DestFileName}" -type f 2>/dev/null | wc -l)
        if [ "${file_count}" -eq 0 ]; then
            log_msg "Source file does not exist to transfer for Remote Server"
            return 0
        fi
    fi

    # Pull validations
    if [ "${SftpType}" = "pull" ]; then
        if [ -z "${PullDestDir}" ]; then
            log_error "GET_INPUT_PARAMS" "Mandatory field (PullDestDir) is not passed as parameter properly"
            return 1
        fi
        if [ -z "${PullFilePattern}" ]; then
            log_error "GET_INPUT_PARAMS" "Mandatory field (PullFilePattern) is not passed as parameter properly"
            return 1
        fi
        if [ ! -d "${PullDestDir}" ]; then
            log_error "GET_INPUT_PARAMS" "Pull destination directory does not exist: ${PullDestDir}"
            return 1
        fi
    fi

    return 0
}

# ---------- Config File Parser (partial — only reads host/user/dir) ----------

parse_config_file() {
    local cfg_path="${SFTP_CFG_DIR}/${CfgFileID}"

    while IFS= read -r line || [ -n "${line}" ]; do
        [[ "${line}" =~ ^[[:space:]]*! ]] && continue
        [[ -z "${line}" ]] && continue

        local key value
        key="${line%%:*}"
        value="${line#*:}"
        value="$(echo "${value}" | tr -d '[:space:]')"

        case "${key}" in
            DestHostname)  DestHostname="${value}" ;;
            DestUsername)   DestUsername="${value}" ;;
            DestDir)        DestDir="${value}" ;;
            TransferType)   TransferType="${value}" ;;
            PullSrcDir)     PullSrcDir="${value}" ;;
        esac
    done < "${cfg_path}"

    if [ -z "${DestHostname}" ] || [ "${DestHostname}" = ":" ]; then
        log_error "SFTP_PARAMETERS" "Mandatory field (DestHostname) in the configuration file is blank/absent"
        return 1
    fi

    if [ -z "${DestUsername}" ] || [ "${DestUsername}" = ":" ]; then
        log_error "SFTP_PARAMETERS" "Mandatory field (DestUsername) in the configuration file is blank/absent"
        return 1
    fi

    if [ "${SftpType}" = "push" ]; then
        if [ -z "${DestDir}" ] || [ "${DestDir}" = ":" ]; then
            log_error "SFTP_PARAMETERS" "Mandatory field (DestDir) in the configuration file is blank/absent"
            return 1
        fi
    fi

    if [ "${SftpType}" = "pull" ]; then
        if [ -z "${PullSrcDir}" ] || [ "${PullSrcDir}" = ":" ]; then
            log_error "SFTP_PARAMETERS" "Mandatory field (PullSrcDir) in the configuration file is blank/absent"
            return 1
        fi
    fi

    return 0
}

# ---------- Run SFTP Transfer (with retries) ----------

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

action_on_success() {
    local file_path="$1"

    [ ! -f "${file_path}" ] && return 0

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
            ;;
        .*)
            local new_name="${file_path}${ActionOnSuccess}"
            log_msg "Renaming source file: ${file_path} -> ${new_name}"
            mv "${file_path}" "${new_name}"
            ;;
    esac
}

# ---------- Push SFTP ----------

push_sftp() {
    log_msg "Starting PUSH operation from ${SrcDir}"

    local found_files=0

    while IFS= read -r -d '' src_file; do
        found_files=1
        local filename
        filename="$(basename "${src_file}")"

        local batch_file="${WORK_DIR}/sftp_push_$$.batch"
        {
            echo "binary"

            if [ -n "${DestDir}" ] && [ "${DestDir}" != "DEFAULT" ]; then
                echo "cd \"${DestDir}\""
            fi

            echo "put \"${src_file}\" \"${filename}.SFTP_TMP\""
            echo "chmod 775 \"${filename}.SFTP_TMP\""

            # Rename to final name
            local remote_name="${filename}"
            if [ -n "${DestFilePattern}" ]; then
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
    done < <(find "${SrcDir}" -maxdepth 1 -name "${DestFileName}" -type f -print0 2>/dev/null)

    if [ "${found_files}" -eq 0 ]; then
        log_msg "No files matching '${DestFileName}' found in ${SrcDir}"
    fi
}

# ---------- Pull SFTP ----------

pull_sftp() {
    log_msg "Starting PULL operation to ${PullDestDir}"

    local pull_temp="${WORK_DIR}/pull_tmp"
    mkdir -p "${pull_temp}"

    # Clean previous temp files
    find "${pull_temp}" -maxdepth 1 -name "${PullFilePattern}" -delete 2>/dev/null

    local batch_file="${WORK_DIR}/sftp_pull_$$.batch"
    {
        echo "binary"
        if [ -n "${PullSrcDir}" ] && [ "${PullSrcDir}" != "DEFAULT" ]; then
            echo "cd \"${PullSrcDir}\""
        fi
        echo "lcd \"${pull_temp}\""
        echo "get ${PullFilePattern}"
        echo "exit"
    } > "${batch_file}"

    if ! run_sftp_transfer "${batch_file}"; then
        log_error "PULL_SFTP" "Failed to pull files from remote server"
        return 1
    fi

    local pull_count
    pull_count=$(find "${pull_temp}" -maxdepth 1 -name "${PullFilePattern}" 2>/dev/null | wc -l)
    if [ "${pull_count}" -eq 0 ]; then
        log_msg "The files for pull are not present in the remote server"
        return 0
    fi

    log_msg "Copying ${pull_count} pulled file(s) to ${PullDestDir}"
    if ! cp "${pull_temp}"/${PullFilePattern} "${PullDestDir}/" 2>>"${LOG_FILE}"; then
        log_error "PULL_SFTP" "Error copying pulled files to target directory"
        return 1
    fi

    # Handle remote-side action
    if [ "${ActionOnSuccess}" = "DELETE" ]; then
        local del_batch="${WORK_DIR}/sftp_pull_del_$$.batch"
        {
            if [ -n "${PullSrcDir}" ] && [ "${PullSrcDir}" != "DEFAULT" ]; then
                echo "cd \"${PullSrcDir}\""
            fi
            echo "rm ${PullFilePattern}"
            echo "exit"
        } > "${del_batch}"

        run_sftp_transfer "${del_batch}" || \
            log_error "PULL_SFTP" "Failed to delete remote files after pull"
    fi

    # Clean temp
    find "${pull_temp}" -maxdepth 1 -name "${PullFilePattern}" -delete 2>/dev/null
}

# ---------- Housekeeping ----------

housekeep() {
    find "${SFTP_CFG_DIR}" -maxdepth 1 -iname '*.sftp' -mtime +2 -delete 2>/dev/null

    if [ -n "${SFTP_LOG_DIR}" ] && [ -d "${SFTP_LOG_DIR}" ]; then
        find "${SFTP_LOG_DIR}" -maxdepth 1 -iname 'GENERIC_SFTP*' -mtime +"${SFTP_PURGE_DAYS}" -delete 2>/dev/null
    fi

    rm -rf "${WORK_DIR}" 2>/dev/null
}

clean_finish() {
    [ "${_CLEANUP_DONE}" -eq 1 ] && return 0
    _CLEANUP_DONE=1
    housekeep
    log_msg "${PROCNAME} has completed successfully"
}

reg_error() {
    local phase="$1"
    local detail="$2"
    [ "${_CLEANUP_DONE}" -eq 1 ] && return
    _CLEANUP_DONE=1
    housekeep
    log_error "${phase}" "${detail}"
    exit 1
}

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
    SftpType="$2"
    ActionOnSuccess="${6:-NOCHANGE}"

    # Assign parameters based on SftpType
    local sftp_lower
    sftp_lower="$(echo "${SftpType}" | tr '[:upper:]' '[:lower:]')"
    SftpType="${sftp_lower}"

    if [ "${SftpType}" = "push" ]; then
        SrcDir="$3"
        DestFileName="$4"
        DestFilePattern="$5"
        PullDestDir=""
        PullFilePattern=""
    else
        SrcDir=""
        DestFileName=""
        DestFilePattern=""
        PullDestDir="$3"
        PullFilePattern="$4"
    fi

    mkdir -p "${WORK_DIR}"

    trap cleanup_and_exit EXIT SIGTERM SIGINT

    log_msg "${PROCNAME} has started"

    validate_environment || exit 1
    validate_params || exit 1
    check_singleton || exit 1
    parse_config_file || exit 1

    if [ "${SftpType}" = "push" ]; then
        push_sftp
    elif [ "${SftpType}" = "pull" ]; then
        pull_sftp
    fi

    clean_finish
}

# Entry-point guard
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
