#!/usr/bin/env bats
###############################################################################
# Tests for tap_rsercfiles_transfer.sh
#
# Requires: bats-core (https://github.com/bats-core/bats-core)
# Run:      bats converted/tests/tap_rsercfiles_transfer.bats
###############################################################################

# ---------- Resolve path to the script under test ----------
SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
SCRIPT_UNDER_TEST="${SCRIPT_DIR}/tap_rsercfiles_transfer.sh"

# ---------- Per-test temp directory ----------
setup() {
    TEST_TEMP_DIR="$(mktemp -d)"

    # Directory structure matching the script's env vars
    export TAP_CFG_DIR="${TEST_TEMP_DIR}/CFG"
    export TAP_DAT_DIR="${TEST_TEMP_DIR}/DAT"
    export TAP_LOG_DIR="${TEST_TEMP_DIR}/LOG"
    export TAP_COM_DIR="${TEST_TEMP_DIR}/COM"
    export FCS_RSERC_DIR="${TEST_TEMP_DIR}/FCS_RSERC"
    export XI_DAT="${TEST_TEMP_DIR}/XI_DAT"
    export SFTP_TMP_DIR="${TEST_TEMP_DIR}/SFTP_TMP"
    export LOG_FILE="${TAP_LOG_DIR}/tap_rsercfiles_transfer.log"
    export LOCK_FILE="${TEST_TEMP_DIR}/tap_rsercfiles_transfer.lock"

    # Shutdown controls
    export RSERC_TRANS_SHUTDOWN="N"
    export TAP_CLOSEDOWN_ALL="N"

    mkdir -p "${TAP_CFG_DIR}" "${TAP_DAT_DIR}" "${TAP_LOG_DIR}" \
             "${TAP_COM_DIR}" "${FCS_RSERC_DIR}" "${XI_DAT}" "${SFTP_TMP_DIR}"

    # Create SFTP config file (line 1 = user, line 2 = host)
    printf 'testuser\ntesthost.example.com\n' > "${TAP_CFG_DIR}/RSERC_SFTP.CFG"

    # --- Mock command directory ---
    MOCK_BIN="${TEST_TEMP_DIR}/mock_bin"
    mkdir -p "${MOCK_BIN}"
    export PATH="${MOCK_BIN}:${PATH}"

    # Default mocks
    create_mock_sftp
    create_mock_logger

    # Source the script (guard prevents main() execution)
    export _CLEANUP_DONE=0
    source "${SCRIPT_UNDER_TEST}"
}

teardown() {
    rm -rf "${TEST_TEMP_DIR}" 2>/dev/null || true
}

# ========================== MOCK GENERATORS ==========================

create_mock_sftp() {
    cat > "${MOCK_BIN}/sftp" <<'MOCK'
#!/bin/bash
# Mock sftp — log calls, succeed by default
echo "SFTP_CALL: $*" >> "${TAP_DAT_DIR}/sftp_calls.log"
exit 0
MOCK
    chmod +x "${MOCK_BIN}/sftp"
}

create_mock_sftp_fail() {
    cat > "${MOCK_BIN}/sftp" <<'MOCK'
#!/bin/bash
echo "SFTP_CALL_FAIL: $*" >> "${TAP_DAT_DIR}/sftp_calls.log"
exit 1
MOCK
    chmod +x "${MOCK_BIN}/sftp"
}

create_mock_logger() {
    cat > "${MOCK_BIN}/logger" <<'MOCK'
#!/bin/bash
echo "LOGGER: $*" >> "${TAP_DAT_DIR}/logger.log"
MOCK
    chmod +x "${MOCK_BIN}/logger"
}

# ========================== HELPER FUNCTIONS ==========================

# Create dummy RSERC files in FCS_RSERC_DIR
create_rserc_files() {
    local count="${1:-5}"
    for i in $(seq 1 "${count}"); do
        local num
        num=$(printf "%06d" "${i}")
        echo "RSERC_DATA_${i}" > "${FCS_RSERC_DIR}/RSERC${num}.DAT"
    done
}

# Create dummy MRLOG files in XI_DAT
create_mrlog_files() {
    local count="${1:-5}"
    for i in $(seq 1 "${count}"); do
        local num
        num=$(printf "%06d" "${i}")
        echo "MRLOG_DATA_${i}" > "${XI_DAT}/MRLOG${num}.DAT"
    done
}

# ========================== TESTS ==========================

# --- validate_environment tests ---

@test "validate_environment succeeds when all dirs and config exist" {
    run validate_environment
    [ "$status" -eq 0 ]
}

@test "validate_environment fails when FCS_RSERC_DIR is missing" {
    rmdir "${FCS_RSERC_DIR}"
    run validate_environment
    [ "$status" -ne 0 ]
}

@test "validate_environment fails when SFTP config file is missing" {
    rm -f "${TAP_CFG_DIR}/RSERC_SFTP.CFG"
    run validate_environment
    [ "$status" -ne 0 ]
}

# --- read_sftp_config tests ---

@test "read_sftp_config reads username and hostname from config" {
    read_sftp_config
    [ "${DEST_USERNAME}" = "testuser" ]
    [ "${DEST_HOSTNAME}" = "testhost.example.com" ]
}

@test "read_sftp_config fails on empty config file" {
    > "${TAP_CFG_DIR}/RSERC_SFTP.CFG"
    run read_sftp_config
    [ "$status" -ne 0 ]
}

# --- housekeeping tests ---

@test "housekeeping runs without error" {
    run housekeeping
    [ "$status" -eq 0 ]
}

# --- collect_rserc_files tests ---

@test "collect_rserc_files finds RSERC files and stages them" {
    create_rserc_files 3

    local sftp_batch="${TAP_DAT_DIR}/test_sftp.dat"
    local rename_batch="${TAP_DAT_DIR}/test_rename.sh"
    local delete_script="${TAP_DAT_DIR}/test_delete.sh"
    > "${sftp_batch}"
    > "${rename_batch}"
    > "${delete_script}"

    collect_rserc_files "${sftp_batch}" "${rename_batch}" "${delete_script}"

    [ "${RSERC_COUNT}" -eq 3 ]

    # Check that put commands were written
    local put_count
    put_count=$(grep -c "^put " "${sftp_batch}")
    [ "${put_count}" -eq 3 ]

    # Check that rename commands were written
    local rename_count
    rename_count=$(grep -c "^rename " "${rename_batch}")
    [ "${rename_count}" -eq 3 ]

    # Check staging directory has files
    local staged_count
    staged_count=$(find "${SFTP_TMP_DIR}" -name '*.sftp_tmp_rs' | wc -l)
    [ "${staged_count}" -eq 3 ]
}

@test "collect_rserc_files caps at MAX_BATCH_SIZE" {
    MAX_BATCH_SIZE=5
    create_rserc_files 10

    local sftp_batch="${TAP_DAT_DIR}/test_sftp.dat"
    local rename_batch="${TAP_DAT_DIR}/test_rename.sh"
    local delete_script="${TAP_DAT_DIR}/test_delete.sh"
    > "${sftp_batch}"
    > "${rename_batch}"
    > "${delete_script}"

    collect_rserc_files "${sftp_batch}" "${rename_batch}" "${delete_script}"

    [ "${RSERC_COUNT}" -eq 5 ]
}

@test "collect_rserc_files handles zero files" {
    local sftp_batch="${TAP_DAT_DIR}/test_sftp.dat"
    local rename_batch="${TAP_DAT_DIR}/test_rename.sh"
    local delete_script="${TAP_DAT_DIR}/test_delete.sh"
    > "${sftp_batch}"
    > "${rename_batch}"
    > "${delete_script}"

    collect_rserc_files "${sftp_batch}" "${rename_batch}" "${delete_script}"

    [ "${RSERC_COUNT}" -eq 0 ]
}

# --- collect_mrlog_files tests ---

@test "collect_mrlog_files finds MRLOG files and stages them" {
    create_mrlog_files 4

    local sftp_batch="${TAP_DAT_DIR}/test_sftp.dat"
    local rename_batch="${TAP_DAT_DIR}/test_rename.sh"
    local delete_script="${TAP_DAT_DIR}/test_delete.sh"
    > "${sftp_batch}"
    > "${rename_batch}"
    > "${delete_script}"

    collect_mrlog_files "${sftp_batch}" "${rename_batch}" "${delete_script}"

    [ "${MRLOG_COUNT}" -eq 4 ]
}

# --- should_shutdown tests ---

@test "should_shutdown returns false when TAP_CLOSEDOWN_ALL is N" {
    RSERC_TRANS_SHUTDOWN="N"
    TAP_CLOSEDOWN_ALL="N"
    run should_shutdown
    [ "$status" -ne 0 ]
}

@test "should_shutdown returns false when closedown time not yet reached" {
    RSERC_TRANS_SHUTDOWN="N"
    TAP_CLOSEDOWN_ALL="23:59"
    run should_shutdown
    [ "$status" -ne 0 ]
}

@test "should_shutdown returns true when RSERC_TRANS_SHUTDOWN is Y" {
    RSERC_TRANS_SHUTDOWN="Y"
    run should_shutdown
    [ "$status" -eq 0 ]
}

@test "should_shutdown returns true when closedown time has passed" {
    RSERC_TRANS_SHUTDOWN="N"
    TAP_CLOSEDOWN_ALL="00:00"
    run should_shutdown
    [ "$status" -eq 0 ]
}

@test "should_shutdown returns true when flag file exists" {
    RSERC_TRANS_SHUTDOWN="N"
    TAP_CLOSEDOWN_ALL="N"
    touch "${TAP_DAT_DIR}/RSERC_TRANS_SHUTDOWN.FLAG"
    run should_shutdown
    [ "$status" -eq 0 ]
}

# --- self_recovery tests ---

@test "self_recovery does nothing when no flag file exists" {
    read_sftp_config
    run self_recovery
    [ "$status" -eq 0 ]
    [[ "${output}" == *"No recovery needed"* ]]
}

@test "self_recovery stage 1: cleans up when ctrl file exists" {
    read_sftp_config
    touch "${FLAG_FILE}"
    echo "test" > "${TAP_DAT_DIR}/SFTP_CTRL_FILE.DAT"

    run self_recovery
    [ "$status" -eq 0 ]

    # Flag and ctrl files should be removed
    [ ! -f "${FLAG_FILE}" ]
    [ ! -f "${TAP_DAT_DIR}/SFTP_CTRL_FILE.DAT" ]

    # SFTP should have been called for cleanup
    grep -q "SFTP_CALL" "${TAP_DAT_DIR}/sftp_calls.log"
}

@test "self_recovery stage 3: runs delete script" {
    read_sftp_config
    touch "${FLAG_FILE}"
    # No ctrl file, no rename file, just a delete script
    echo '#!/bin/bash' > "${TAP_DAT_DIR}/delete_sftpd_files_tmp.sh"
    echo 'echo "DELETE_RAN" > "${TAP_DAT_DIR}/delete_ran.flag"' >> "${TAP_DAT_DIR}/delete_sftpd_files_tmp.sh"
    chmod +x "${TAP_DAT_DIR}/delete_sftpd_files_tmp.sh"

    run self_recovery
    [ "$status" -eq 0 ]
    [ ! -f "${FLAG_FILE}" ]
}

# --- sftp_transfer tests ---

@test "sftp_transfer succeeds and cleans up flag and batch files" {
    read_sftp_config
    create_rserc_files 2

    # Prepare batch files
    local sftp_batch="${TAP_DAT_DIR}/sftp_ctrl.dat"
    local rename_batch="${TAP_DAT_DIR}/rename.sh"
    local delete_script="${TAP_DAT_DIR}/delete.sh"

    echo "binary" > "${sftp_batch}"
    echo "exit" >> "${sftp_batch}"
    echo "exit" > "${rename_batch}"
    echo '#!/bin/bash' > "${delete_script}"

    run sftp_transfer "${sftp_batch}" "${rename_batch}" "${delete_script}"
    [ "$status" -eq 0 ]

    # Flag file should not exist after successful transfer
    [ ! -f "${FLAG_FILE}" ]

    # Batch files should be cleaned up
    [ ! -f "${sftp_batch}" ]
    [ ! -f "${rename_batch}" ]
    [ ! -f "${delete_script}" ]
}

@test "sftp_transfer fails and calls error_exit when sftp fails" {
    read_sftp_config
    create_mock_sftp_fail

    local sftp_batch="${TAP_DAT_DIR}/sftp_ctrl.dat"
    local rename_batch="${TAP_DAT_DIR}/rename.sh"
    local delete_script="${TAP_DAT_DIR}/delete.sh"
    echo "exit" > "${sftp_batch}"
    echo "exit" > "${rename_batch}"
    echo "true" > "${delete_script}"

    run sftp_transfer "${sftp_batch}" "${rename_batch}" "${delete_script}"
    [ "$status" -ne 0 ]
}

# --- File extension / staging tests ---

@test "staged files use .sftp_tmp_rs extension" {
    create_rserc_files 1

    local sftp_batch="${TAP_DAT_DIR}/test_sftp.dat"
    local rename_batch="${TAP_DAT_DIR}/test_rename.sh"
    local delete_script="${TAP_DAT_DIR}/test_delete.sh"
    > "${sftp_batch}"
    > "${rename_batch}"
    > "${delete_script}"

    collect_rserc_files "${sftp_batch}" "${rename_batch}" "${delete_script}"

    # Verify .sftp_tmp_rs files exist in staging
    local staged_file
    staged_file=$(find "${SFTP_TMP_DIR}" -name '*.sftp_tmp_rs' -print -quit)
    [ -n "${staged_file}" ]
}

@test "rename batch maps .sftp_tmp_rs back to .DAT" {
    create_rserc_files 1

    local sftp_batch="${TAP_DAT_DIR}/test_sftp.dat"
    local rename_batch="${TAP_DAT_DIR}/test_rename.sh"
    local delete_script="${TAP_DAT_DIR}/test_delete.sh"
    > "${sftp_batch}"
    > "${rename_batch}"
    > "${delete_script}"

    collect_rserc_files "${sftp_batch}" "${rename_batch}" "${delete_script}"

    # Rename batch should have "rename XXX.sftp_tmp_rs RSERC000001.DAT"
    grep -q "rename.*\.sftp_tmp_rs.*\.DAT" "${rename_batch}"
}

# --- log_msg test ---

@test "log_msg writes timestamped message to log file" {
    log_msg "Test log message"
    grep -q "Test log message" "${LOG_FILE}"
}
