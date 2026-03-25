#!/usr/bin/env bats
###############################################################################
# Test Suite   : tap_job_startup.bats
# Tests For    : tap_job_startup.sh
# Framework    : BATS (Bash Automated Testing System)
###############################################################################

# ---- helpers ----
setup() {
    export TEST_DIR="/tmp/tap_job_startup_test_$$"
    export TAP_EXE_DIR="${TEST_DIR}/exe"
    export TAP_COM_DIR="${TEST_DIR}/com"
    export TAP_LOG_DIR="${TEST_DIR}/log"
    export TAP_CLOSEDOWN_DIR="${TEST_DIR}/closedown"

    mkdir -p "${TAP_EXE_DIR}" "${TAP_COM_DIR}" "${TAP_LOG_DIR}" "${TAP_CLOSEDOWN_DIR}"

    # Path to the script under test
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    SUT="${SCRIPT_DIR}/tap_job_startup.sh"
    chmod +x "${SUT}" 2>/dev/null

    # Create a simple test program that succeeds
    cat > "${TAP_EXE_DIR}/TEST_PROG" << 'PROG'
#!/bin/bash
echo "TEST_PROG executed"
exit 0
PROG
    chmod +x "${TAP_EXE_DIR}/TEST_PROG"

    # Create a test program that fails
    cat > "${TAP_EXE_DIR}/FAIL_PROG" << 'PROG'
#!/bin/bash
echo "FAIL_PROG — exiting with error"
exit 1
PROG
    chmod +x "${TAP_EXE_DIR}/FAIL_PROG"

    # Create a test program with .sh extension only
    cat > "${TAP_EXE_DIR}/SCRIPT_PROG.sh" << 'PROG'
#!/bin/bash
echo "SCRIPT_PROG.sh executed"
exit 0
PROG
    chmod +x "${TAP_EXE_DIR}/SCRIPT_PROG.sh"
}

teardown() {
    # Remove any lock files created during tests
    rm -f /tmp/TAP_TEST_01.lock /tmp/TAP_TEST_02.lock \
          /tmp/TAP_GAPS_01.lock /tmp/TAP_GSDM_01.lock 2>/dev/null
    # Clean up test directory
    rm -rf "${TEST_DIR}" 2>/dev/null
}

# =========================================================================
#  Parameter Validation
# =========================================================================

@test "exits with error when no parameters provided" {
    run "${SUT}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Parameter must be provided"* ]]
}

@test "exits with error when P1 is empty" {
    run "${SUT}" "" "01" "TEST_PROG"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Parameter must be provided"* ]]
}

@test "exits with error when P2 is empty" {
    run "${SUT}" "TEST" "" "TEST_PROG"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Parameter must be provided"* ]]
}

@test "exits with error when P3 is empty" {
    run "${SUT}" "TEST" "01" ""
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Parameter must be provided"* ]]
}

# =========================================================================
#  Successful Execution
# =========================================================================

@test "runs successfully with valid parameters" {
    run "${SUT}" "TEST" "01" "TEST_PROG"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"TAP_TEST_01 started"* ]]
    [[ "${output}" == *"TAP_TEST_01 completed successfully"* ]]
}

@test "log file is created on successful run" {
    run "${SUT}" "TEST" "01" "TEST_PROG"
    [ "${status}" -eq 0 ]
    [ -f "${TAP_LOG_DIR}/tap_job_startup.log" ]
    grep -q "TAP_TEST_01 started" "${TAP_LOG_DIR}/tap_job_startup.log"
    grep -q "TAP_TEST_01 completed successfully" "${TAP_LOG_DIR}/tap_job_startup.log"
}

@test "log entries have correct timestamp format" {
    run "${SUT}" "TEST" "01" "TEST_PROG"
    [ "${status}" -eq 0 ]
    # Format: DD-Mon-YYYY HH:MM:SS - message
    grep -qE '^[0-9]{2}-[A-Z][a-z]{2}-[0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} - ' \
        "${TAP_LOG_DIR}/tap_job_startup.log"
}

# =========================================================================
#  Program Not Found
# =========================================================================

@test "exits with error when program does not exist" {
    run "${SUT}" "TEST" "01" "NONEXISTENT"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"NONEXISTENT unavailable"* ]]
}

# =========================================================================
#  Program Failure
# =========================================================================

@test "exits with error when program returns non-zero" {
    run "${SUT}" "TEST" "01" "FAIL_PROG"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Error returned from program FAIL_PROG"* ]]
}

@test "error log includes exit code of failed program" {
    run "${SUT}" "TEST" "01" "FAIL_PROG"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"exit code 1"* ]]
}

# =========================================================================
#  .sh Extension Fallback
# =========================================================================

@test "finds program with .sh extension when no exact match" {
    run "${SUT}" "TEST" "01" "SCRIPT_PROG"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"SCRIPT_PROG.sh"* ]]
}

# =========================================================================
#  Closedown Flag Cleanup
# =========================================================================

@test "removes closedown flag after successful run" {
    touch "${TAP_CLOSEDOWN_DIR}/TAP_TEST_01_CLOSEDOWN"
    [ -f "${TAP_CLOSEDOWN_DIR}/TAP_TEST_01_CLOSEDOWN" ]

    run "${SUT}" "TEST" "01" "TEST_PROG"
    [ "${status}" -eq 0 ]
    [ ! -f "${TAP_CLOSEDOWN_DIR}/TAP_TEST_01_CLOSEDOWN" ]
}

@test "removes closedown flag even when program fails" {
    touch "${TAP_CLOSEDOWN_DIR}/TAP_TEST_01_CLOSEDOWN"

    run "${SUT}" "TEST" "01" "FAIL_PROG"
    [ "${status}" -eq 1 ]
    [ ! -f "${TAP_CLOSEDOWN_DIR}/TAP_TEST_01_CLOSEDOWN" ]
}

@test "no error when closedown flag does not exist" {
    [ ! -f "${TAP_CLOSEDOWN_DIR}/TAP_TEST_01_CLOSEDOWN" ]

    run "${SUT}" "TEST" "01" "TEST_PROG"
    [ "${status}" -eq 0 ]
}

# =========================================================================
#  Singleton (flock) Enforcement
# =========================================================================

@test "different instances can run in parallel" {
    # Create a slow program
    cat > "${TAP_EXE_DIR}/SLOW_PROG" << 'PROG'
#!/bin/bash
sleep 2
exit 0
PROG
    chmod +x "${TAP_EXE_DIR}/SLOW_PROG"

    # Start instance 01 in background
    "${SUT}" "TEST" "01" "SLOW_PROG" &
    PID1=$!
    sleep 0.5

    # Instance 02 should succeed simultaneously
    run "${SUT}" "TEST" "02" "TEST_PROG"
    [ "${status}" -eq 0 ]

    wait "${PID1}" 2>/dev/null
}

# =========================================================================
#  GAPS / GSDM Integration Style
# =========================================================================

@test "GAPS-style invocation succeeds" {
    cat > "${TAP_EXE_DIR}/GAPS_PROC" << 'PROG'
#!/bin/bash
echo "GAPS processing"
exit 0
PROG
    chmod +x "${TAP_EXE_DIR}/GAPS_PROC"

    run "${SUT}" "GAPS" "01" "GAPS_PROC"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"TAP_GAPS_01 started"* ]]
    [[ "${output}" == *"TAP_GAPS_01 completed successfully"* ]]
}

@test "GSDM-style invocation succeeds" {
    cat > "${TAP_EXE_DIR}/GSDM_PROC" << 'PROG'
#!/bin/bash
echo "GSDM processing"
exit 0
PROG
    chmod +x "${TAP_EXE_DIR}/GSDM_PROC"

    run "${SUT}" "GSDM" "01" "GSDM_PROC"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"TAP_GSDM_01 started"* ]]
}

# =========================================================================
#  Process Name Construction
# =========================================================================

@test "process name is correctly formed as TAP_P1_P2" {
    run "${SUT}" "MYTYPE" "99" "TEST_PROG"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"TAP_MYTYPE_99 started"* ]]
}

@test "lock file uses process name" {
    cat > "${TAP_EXE_DIR}/SLOW2" << 'PROG'
#!/bin/bash
sleep 3
exit 0
PROG
    chmod +x "${TAP_EXE_DIR}/SLOW2"

    "${SUT}" "TEST" "01" "SLOW2" &
    PID1=$!
    sleep 0.5

    # Lock file should exist
    [ -f "/tmp/TAP_TEST_01.lock" ]

    wait "${PID1}" 2>/dev/null
}
