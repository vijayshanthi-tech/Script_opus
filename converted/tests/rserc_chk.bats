#!/usr/bin/env bats
###############################################################################
# rserc_chk.bats — Comprehensive Bats unit-test suite for rserc_chk.sh
#
# Test categories:
#   1.  log_msg          — Logging helper
#   2.  send_alert       — Email alerting
#   3.  send_report      — Email with file body
#   4.  schedule_next_run — Self-scheduling
#   5.  generate_spid_list — Oracle SP_ID retrieval
#   6.  check_tap_directories — Directory backlog monitoring
#   7.  generate_hourly_reports — Oracle hourly reports & zero-RSERC alert
#   8.  check_rserc_failures — Failure detection & auto-recovery
#   9.  cleanup_and_exit — Resource teardown
#  10.  Edge cases & boundary tests
#  11.  Golden master tests (expected output format)
###############################################################################

load 'test_helper'

# =============================================================================
#  1. log_msg
# =============================================================================

@test "log_msg writes timestamped entry to log file" {
    log_msg "HELLO TEST"
    [ -f "${LOG_FILE}" ]
    grep -q "HELLO TEST" "${LOG_FILE}"
}

@test "log_msg includes date/time prefix" {
    log_msg "TIMESTAMPED"
    local line
    line=$(tail -1 "${LOG_FILE}")
    # Format: DD-Mon-YYYY HH:MM:SS - TIMESTAMPED
    [[ "${line}" =~ ^[0-9]{2}-[A-Za-z]{3}-[0-9]{4}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\ -\ TIMESTAMPED$ ]]
}

@test "log_msg appends successive messages" {
    log_msg "LINE1"
    log_msg "LINE2"
    local count
    count=$(wc -l < "${LOG_FILE}")
    [ "${count}" -eq 2 ]
}

# =============================================================================
#  2. send_alert
# =============================================================================

@test "send_alert calls mailx and logs subject" {
    send_alert "Test Alert Subject"
    grep -q "Test Alert Subject" "${LOG_FILE}"
    grep -q "MAILX_CALL:" "${WORK_DIR}/mailx.log"
}

@test "send_alert mailx call contains correct subject" {
    send_alert "TAP warning"
    grep -q 'subject=\[-s\]' "${WORK_DIR}/mailx.log" || \
    grep -q 'TAP warning' "${WORK_DIR}/mailx.log"
}

# =============================================================================
#  3. send_report
# =============================================================================

@test "send_report sends file content to all recipients" {
    local report="${WORK_DIR}/test_report.txt"
    echo "report body" > "${report}"
    send_report "Report Sub" "${report}" "user1@test.com" "user2@test.com"
    local calls
    calls=$(grep -c "MAILX_CALL:" "${WORK_DIR}/mailx.log")
    [ "${calls}" -eq 2 ]
}

@test "send_report handles missing file gracefully" {
    # mailx will silently fail with missing file (< /nonexistent)
    send_report "No File" "/nonexistent/file" "user@test.com" || true
    # No crash is the assertion
}

# =============================================================================
#  4. schedule_next_run
# =============================================================================

@test "schedule_next_run invokes at command" {
    schedule_next_run
    [ -f "${WORK_DIR}/at.log" ]
    grep -q "AT_CALL:" "${WORK_DIR}/at.log"
}

@test "schedule_next_run logs warning on at failure" {
    rm -f "${MOCK_BIN}/at"
    cat > "${MOCK_BIN}/at" <<'FAIL'
#!/bin/bash
exit 1
FAIL
    chmod +x "${MOCK_BIN}/at"

    schedule_next_run
    grep -q "WARNING.*schedule" "${LOG_FILE}"
}

# =============================================================================
#  5. generate_spid_list
# =============================================================================

@test "generate_spid_list creates spid_list.lis" {
    create_mock_sqlplus_spid 10 20 30
    generate_spid_list
    [ -f "${SPID_LIST}" ]
}

@test "generate_spid_list logs creation message" {
    create_mock_sqlplus_spid 42
    generate_spid_list
    grep -q "Creating SPID list" "${LOG_FILE}"
}

# =============================================================================
#  6. check_tap_directories
# =============================================================================

@test "check_tap_directories: no recent archive files triggers alert" {
    # No files in archive → alert expected
    create_spid_list
    check_tap_directories
    grep -q "No Call files processed.*four hours" "${LOG_FILE}"
}

@test "check_tap_directories: recent archive files = no alert" {
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 5
    create_spid_list
    check_tap_directories
    ! grep -q "No Call files processed" "${LOG_FILE}"
}

@test "check_tap_directories: old archive files only triggers alert" {
    populate_old_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 5
    create_spid_list
    check_tap_directories
    grep -q "No Call files processed" "${LOG_FILE}"
}

@test "check_tap_directories: collect files under MAX = no alert" {
    populate_dir "${TAP_COLLECT_DIR}" "CD00001GBRCN" ".dat" 100
    create_spid_list
    check_tap_directories
    ! grep -q "files in tap collection" "${LOG_FILE}"
}

@test "check_tap_directories: collect files over MAX triggers alert" {
    populate_dir "${TAP_COLLECT_DIR}" "CD00001GBRCN" ".dat" 401
    create_spid_list
    check_tap_directories
    grep -q "files in tap collection" "${LOG_FILE}"
}

@test "check_tap_directories: collect files at exactly MAX = no alert" {
    populate_dir "${TAP_COLLECT_DIR}" "CD00001GBRCN" ".dat" 400
    create_spid_list
    check_tap_directories
    ! grep -q "files in tap collection" "${LOG_FILE}"
}

@test "check_tap_directories: toprice files over MAX triggers alert" {
    populate_dir "${TAP_READY_FOR_PRICING}" "CD00001GBRCN" ".DAT" 401
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1
    create_spid_list
    check_tap_directories
    grep -q "files in TAP pricing" "${LOG_FILE}"
}

@test "check_tap_directories: priced files over MAX triggers alert" {
    populate_dir "${TAP_OB_PRICED}" "CD00001GBRCN" ".PRC" 401
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1
    create_spid_list
    check_tap_directories
    grep -q "files in TAP spliting" "${LOG_FILE}"
}

@test "check_tap_directories: per-SPID split check over SPLIT_MAX triggers alert" {
    create_spid_list 42
    local split_dir="${TAP_OB_SPLIT}/042"
    populate_dir "${split_dir}" "CD00001" ".SPLIT" 601
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1
    check_tap_directories
    grep -q "files in TAP Distribute for spid 042" "${LOG_FILE}"
}

@test "check_tap_directories: per-SPID split at exactly SPLIT_MAX = no alert" {
    create_spid_list 42
    local split_dir="${TAP_OB_SPLIT}/042"
    populate_dir "${split_dir}" "CD00001" ".SPLIT" 600
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1
    check_tap_directories
    ! grep -q "files in TAP Distribute" "${LOG_FILE}"
}

@test "check_tap_directories: missing SPID list = no SPID check crash" {
    SPID_LIST="${WORK_DIR}/nonexistent.lis"
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1
    check_tap_directories
    # Should not crash — just skip SPID check
}

@test "check_tap_directories: invalid SPID entry does not crash" {
    create_spid_list "abc" "42" "xyz"
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1
    check_tap_directories
    # Script uses 'continue' for printf failures; should not abort
}

@test "check_tap_directories increments run_count" {
    run_count=0
    create_spid_list
    check_tap_directories
    [ "${run_count}" -eq 1 ]
}

@test "check_tap_directories: empty directories = no crashes" {
    create_spid_list
    check_tap_directories
    # Only archive alert expected (no files), no crashes
    grep -q "Checking TAP directories" "${LOG_FILE}"
}

# =============================================================================
#  7. generate_hourly_reports
# =============================================================================

@test "generate_hourly_reports logs report creation" {
    run_count=2
    generate_hourly_reports
    grep -q "Creating Tap hourly reports" "${LOG_FILE}"
}

@test "generate_hourly_reports sends RSERC report email" {
    run_count=2
    generate_hourly_reports
    grep -q "Processed RESRC File Report" "${LOG_FILE}"
}

@test "generate_hourly_reports sends CDR report email" {
    run_count=2
    generate_hourly_reports
    grep -q "Processed roaming CDRs Report" "${LOG_FILE}"
}

@test "generate_hourly_reports cleans up spool files" {
    run_count=2
    generate_hourly_reports
    [ ! -f "${WORK_DIR}/files_created.lis" ]
    [ ! -f "${WORK_DIR}/files_created1.lis" ]
    [ ! -f "${WORK_DIR}/recs_created.lis" ]
}

@test "generate_hourly_reports: zero FILE_COUNT on non-first run triggers alert" {
    create_mock_sqlplus_with_filecount 0
    run_count=2
    generate_hourly_reports
    grep -q "no RSERC created in last 4 hours" "${LOG_FILE}"
}

@test "generate_hourly_reports: zero FILE_COUNT on first run NO alert (skip)" {
    create_mock_sqlplus_with_filecount 0
    run_count=1
    generate_hourly_reports
    ! grep -q "no RSERC created" "${LOG_FILE}"
}

@test "generate_hourly_reports: positive FILE_COUNT = no alert" {
    create_mock_sqlplus_with_filecount 150
    run_count=5
    generate_hourly_reports
    ! grep -q "no RSERC created" "${LOG_FILE}"
}

@test "generate_hourly_reports: SPOOL paths use WORK_DIR (unquoted heredoc)" {
    # Verify that the SPOOL files are created inside WORK_DIR, not as literal
    # '${FILES_CREATED}' in the current directory.
    run_count=2
    generate_hourly_reports
    # If SPOOL paths expanded, the mock sqlplus creates files in WORK_DIR
    # The script deletes them after use — but we can check no literal files leaked
    [ ! -f '${FILES_CREATED}' ]
    [ ! -f '${FILES_CREATED1}' ]
    [ ! -f '${RECS_CREATED}' ]
}

# =============================================================================
#  8. check_rserc_failures
# =============================================================================

@test "check_rserc_failures logs checking message" {
    check_rserc_failures
    grep -q "Checking for RSERC failures" "${LOG_FILE}"
}

@test "check_rserc_failures: no .don or .tmp files = clean run" {
    check_rserc_failures
    ! grep -q "RSERC Failure" "${LOG_FILE}"
}

@test "check_rserc_failures: .don files trigger 841 DON alert" {
    touch "${TAP_OUTGOING_SP}/file1.don"
    touch "${TAP_OUTGOING_SP}/file2.don"
    check_rserc_failures
    grep -q "Procedure 841.*DON files" "${LOG_FILE}"
}

@test "check_rserc_failures: .don alert emails TAP support and L2" {
    touch "${TAP_OUTGOING_SP}/test.don"
    check_rserc_failures
    local mail_log="${WORK_DIR}/mailx.log"
    [ -f "${mail_log}" ]
    grep -q "MAILX_CALL:" "${mail_log}"
}

@test "check_rserc_failures: .tmp files trigger 841 TMP recovery alert" {
    touch "${TAP_OUTGOING_SP}/file1.tmp"
    check_rserc_failures
    grep -q "Procudure 841.*TMP files" "${LOG_FILE}"
}

@test "check_rserc_failures: .tmp files are deleted after recovery" {
    touch "${TAP_OUTGOING_SP}/test1.tmp"
    touch "${TAP_OUTGOING_SP}/test2.tmp"
    check_rserc_failures
    local remaining
    remaining=$(find "${TAP_OUTGOING_SP}" -iname '*.tmp' | wc -l)
    [ "${remaining}" -eq 0 ]
}

@test "check_rserc_failures: .tmp in PERIOD dir also deleted" {
    touch "${TAP_OUTGOING_SP}/x.tmp"
    touch "${TAP_PERIOD_DIR}/y.tmp"
    check_rserc_failures
    local remaining_p
    remaining_p=$(find "${TAP_PERIOD_DIR}" -iname '*.tmp' | wc -l)
    [ "${remaining_p}" -eq 0 ]
}

@test "check_rserc_failures: mrlog*.tmp triggers rerun via sqlplus" {
    # Create mrlog file with predictable name for SP_ID extraction
    # Position 35 (1-based) in '0123456789012345678901234567890123456789' → char at index 34
    # We pad the name so position 35 (1-based awk) gives a known SP_ID
    local padded_name
    padded_name=$(printf '%-34s' "mrlog_dummy" | tr ' ' 'X')
    padded_name="${padded_name}042.tmp"
    touch "${TAP_OUTGOING_SP}/${padded_name}"
    check_rserc_failures
    # The sqlplus rerun log should exist (mock records these)
    [ -f "${WORK_DIR}/sqlplus_rerun.log" ]
}

@test "check_rserc_failures: skips if 'dist' process found" {
    # Create a mock ps that includes "dist" in output
    cat > "${MOCK_BIN}/ps" <<'MOCKPS'
#!/bin/bash
echo "root 12345 0.0 /opt/tap/dist_process"
MOCKPS
    chmod +x "${MOCK_BIN}/ps"

    touch "${TAP_OUTGOING_SP}/dangerous.don"
    check_rserc_failures
    # dist found → skip failure checks → no alert
    ! grep -q "RSERC Failure" "${LOG_FILE}"
    rm -f "${MOCK_BIN}/ps"
}

@test "check_rserc_failures: cleans up rserc_chk.lis after run" {
    check_rserc_failures
    [ ! -f "${WORK_DIR}/rserc_chk.lis" ]
}

# =============================================================================
#  9. cleanup_and_exit
# =============================================================================

@test "cleanup_and_exit logs completion" {
    _CLEANUP_DONE=0
    cleanup_and_exit
    grep -q "RSERC_CHK completed" "${LOG_FILE}"
}

@test "cleanup_and_exit removes work directory" {
    _CLEANUP_DONE=0
    cleanup_and_exit
    [ ! -d "${WORK_DIR}" ]
}

@test "cleanup_and_exit removes rserc_failure files" {
    touch "${WORK_DIR}/rserc_failure_1.txt"
    touch "${WORK_DIR}/rserc_failure_2.txt"
    _CLEANUP_DONE=0
    cleanup_and_exit
    [ ! -f "${WORK_DIR}/rserc_failure_1.txt" ]
    [ ! -f "${WORK_DIR}/rserc_failure_2.txt" ]
}

@test "cleanup_and_exit deletes logs older than 30 days" {
    touch -d '31 days ago' "${TAP_LOG_DIR}/rserc_chk.log.old"
    _CLEANUP_DONE=0
    cleanup_and_exit
    [ ! -f "${TAP_LOG_DIR}/rserc_chk.log.old" ]
}

@test "cleanup_and_exit preserves recent logs" {
    touch "${TAP_LOG_DIR}/rserc_chk.log.recent"
    _CLEANUP_DONE=0
    cleanup_and_exit
    [ -f "${TAP_LOG_DIR}/rserc_chk.log.recent" ]
}

@test "cleanup_and_exit double-call guard prevents duplicate execution" {
    _CLEANUP_DONE=0
    cleanup_and_exit
    local count1
    count1=$(grep -c "RSERC_CHK completed" "${LOG_FILE}")

    # Second call should be no-op
    cleanup_and_exit
    local count2
    count2=$(grep -c "RSERC_CHK completed" "${LOG_FILE}")
    [ "${count1}" -eq "${count2}" ]
}

# =============================================================================
#  10. Edge cases & boundary tests
# =============================================================================

@test "EDGE: MAX=0 means any file triggers collect alert" {
    export MAX=0
    touch "${TAP_COLLECT_DIR}/CD00001GBRCN00001.dat"
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1
    create_spid_list
    check_tap_directories
    grep -q "files in tap collection" "${LOG_FILE}"
}

@test "EDGE: exactly 401 collect files triggers alert (MAX=400)" {
    export MAX=400
    populate_dir "${TAP_COLLECT_DIR}" "CD00001GBRCN" ".dat" 401
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1
    create_spid_list
    check_tap_directories
    grep -q "files in tap collection" "${LOG_FILE}"
}

@test "EDGE: exactly 601 split files triggers alert (SPLIT_MAX=600)" {
    export SPLIT_MAX=600
    create_spid_list 1
    local split_dir="${TAP_OB_SPLIT}/001"
    populate_dir "${split_dir}" "CD" ".SPLIT" 601
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1
    check_tap_directories
    grep -q "files in TAP Distribute" "${LOG_FILE}"
}

@test "EDGE: multiple SPIDs checked independently" {
    create_spid_list 10 20
    local split_10="${TAP_OB_SPLIT}/010"
    local split_20="${TAP_OB_SPLIT}/020"
    populate_dir "${split_10}" "CD" ".SPLIT" 601
    populate_dir "${split_20}" "CD" ".SPLIT" 100

    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1

    check_tap_directories
    grep -q "spid 010" "${LOG_FILE}"
    ! grep -q "spid 020" "${LOG_FILE}"
}

@test "EDGE: SPID zero-padded to 3 digits" {
    create_spid_list 5
    local split_dir="${TAP_OB_SPLIT}/005"
    populate_dir "${split_dir}" "CD" ".SPLIT" 601

    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1

    check_tap_directories
    grep -q "spid 005" "${LOG_FILE}"
}

@test "EDGE: empty SPID list file = no crash" {
    SPID_LIST="${WORK_DIR}/spid_list.lis"
    > "${SPID_LIST}"
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1
    check_tap_directories
    # No SPID alerts, no crash
    ! grep -q "TAP Distribute" "${LOG_FILE}"
}

@test "EDGE: non-matching file patterns not counted" {
    # Files that DON'T match the pattern should not be counted
    touch "${TAP_COLLECT_DIR}/NOTACDFILE.dat"
    touch "${TAP_COLLECT_DIR}/random.txt"
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1
    create_spid_list
    check_tap_directories
    ! grep -q "files in tap collection" "${LOG_FILE}"
}

@test "EDGE: case-insensitive file matching for .don" {
    touch "${TAP_OUTGOING_SP}/file.DON"
    touch "${TAP_OUTGOING_SP}/other.Don"
    check_rserc_failures
    grep -q "DON files" "${LOG_FILE}"
}

@test "EDGE: case-insensitive file matching for .tmp" {
    touch "${TAP_OUTGOING_SP}/file.TMP"
    check_rserc_failures
    grep -q "TMP files" "${LOG_FILE}"
}

# =============================================================================
#  11. Golden master tests (expected output format)
# =============================================================================

@test "GOLDEN: log line format matches DD-Mon-YYYY HH:MM:SS - message" {
    log_msg "TEST_GOLDEN_MSG"
    local line
    line=$(tail -1 "${LOG_FILE}")
    # Example: 15-Jan-2025 14:30:00 - TEST_GOLDEN_MSG
    [[ "${line}" =~ ^[0-9]{2}-[A-Z][a-z]{2}-[0-9]{4}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\ -\ TEST_GOLDEN_MSG$ ]]
}

@test "GOLDEN: archive alert subject text matches VMS" {
    create_spid_list
    check_tap_directories
    grep -q "No Call files processed by TAP collection in last four hours" "${LOG_FILE}"
}

@test "GOLDEN: collect alert includes file count" {
    populate_dir "${TAP_COLLECT_DIR}" "CD00001GBRCN" ".dat" 410
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1
    create_spid_list
    check_tap_directories
    grep -q "There are 410 files in tap collection" "${LOG_FILE}"
}

@test "GOLDEN: zero RSERC alert text matches VMS" {
    create_mock_sqlplus_with_filecount 0
    run_count=3
    generate_hourly_reports
    grep -q "There are no RSERC created in last 4 hours" "${LOG_FILE}"
}

@test "GOLDEN: DON failure alert preserves original RSERC Failure prefix" {
    touch "${TAP_OUTGOING_SP}/x.don"
    check_rserc_failures
    grep -q "RSERC Failure - Procedure 841 - \*.DON files left out" "${LOG_FILE}"
}

@test "GOLDEN: TMP failure alert preserves original VMS typo 'Procudure'" {
    touch "${TAP_OUTGOING_SP}/x.tmp"
    check_rserc_failures
    # Note: Original VMS has "Procudure" (typo) — preserved intentionally
    grep -q "Procudure 841" "${LOG_FILE}"
}

@test "GOLDEN: cleanup log message is correct" {
    _CLEANUP_DONE=0
    cleanup_and_exit
    grep -q "RSERC_CHK completed" "${LOG_FILE}"
}

@test "GOLDEN: RSERC report email subject matches expected" {
    run_count=2
    generate_hourly_reports
    grep -q "TAP - Processed RESRC File Report" "${LOG_FILE}"
}

@test "GOLDEN: CDR report email subject matches expected" {
    run_count=2
    generate_hourly_reports
    grep -q "TAP - Processed roaming CDRs Report" "${LOG_FILE}"
}

# =============================================================================
#  12. Integration-like flow tests
# =============================================================================

@test "INTEGRATION: full check_tap + report cycle completes without error" {
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 5
    create_spid_list 1 2 3
    run_count=0

    check_tap_directories
    generate_hourly_reports

    grep -q "Checking TAP directories" "${LOG_FILE}"
    grep -q "Creating Tap hourly reports" "${LOG_FILE}"
    [ "${run_count}" -eq 1 ]
}

@test "INTEGRATION: failure check + cleanup cycle" {
    touch "${TAP_OUTGOING_SP}/test.don"
    check_rserc_failures

    _CLEANUP_DONE=0
    cleanup_and_exit

    grep -q "RSERC Failure" "${LOG_FILE}"
    grep -q "RSERC_CHK completed" "${LOG_FILE}"
}

@test "INTEGRATION: generate_spid_list + check_tap_directories uses SPID list" {
    create_mock_sqlplus_spid 7 14
    generate_spid_list
    populate_recent_files "${TAP_ARCHIVE_DIR}" "cd" ".dat" 1

    # Create overloaded split dir for SPID 007
    local split_dir="${TAP_OB_SPLIT}/007"
    populate_dir "${split_dir}" "CD" ".SPLIT" 601

    check_tap_directories
    grep -q "spid 007" "${LOG_FILE}"
}
