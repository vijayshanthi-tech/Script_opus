#!/bin/bash
###############################################################################
# test_helper.bash — Shared setup/teardown & mock helpers for rserc_chk tests
###############################################################################

# ---------- Resolve path to the script under test ----------
SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
SCRIPT_UNDER_TEST="${SCRIPT_DIR}/rserc_chk.sh"

# ---------- Per-test temp directory ----------
setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export WORK_DIR="${TEST_TEMP_DIR}/work"
    mkdir -p "${WORK_DIR}"

    # Default directories used by the script
    export TAP_ARCHIVE_DIR="${TEST_TEMP_DIR}/ARCHIVE"
    export TAP_COLLECT_DIR="${TEST_TEMP_DIR}/COLLECT"
    export TAP_READY_FOR_PRICING="${TEST_TEMP_DIR}/TO_PRICE"
    export TAP_OB_PRICED="${TEST_TEMP_DIR}/PRICED"
    export TAP_OB_SPLIT="${TEST_TEMP_DIR}/SPLIT"
    export TAP_OUTGOING_SP="${TEST_TEMP_DIR}/OG_SP"
    export TAP_PERIOD_DIR="${TEST_TEMP_DIR}/PERIOD"
    export TAP_LOG_DIR="${TEST_TEMP_DIR}/LOG"
    export LOG_FILE="${TAP_LOG_DIR}/rserc_chk.log"
    export RERUN_RSERC_SQL="${TEST_TEMP_DIR}/rerun_rserc.sql"
    export MAX=400
    export SPLIT_MAX=600

    mkdir -p "${TAP_ARCHIVE_DIR}" "${TAP_COLLECT_DIR}" "${TAP_READY_FOR_PRICING}" \
             "${TAP_OB_PRICED}" "${TAP_OB_SPLIT}" "${TAP_OUTGOING_SP}" \
             "${TAP_PERIOD_DIR}" "${TAP_LOG_DIR}"

    # --- Mock command directory (prepended to PATH) ---
    MOCK_BIN="${TEST_TEMP_DIR}/mock_bin"
    mkdir -p "${MOCK_BIN}"
    export PATH="${MOCK_BIN}:${PATH}"

    # --- Create default mocks ---
    create_mock_sqlplus
    create_mock_mailx
    create_mock_at

    # --- Source the script (guard prevents execution) ---
    # Re-initialise script-level globals that would normally be set at source time
    export _CLEANUP_DONE=0
    source "${SCRIPT_UNDER_TEST}"
}

teardown() {
    rm -rf "${TEST_TEMP_DIR}" 2>/dev/null || true
}

# ========================== MOCK GENERATORS ==========================

# Mock sqlplus — writes predictable output based on arguments
create_mock_sqlplus() {
    cat > "${MOCK_BIN}/sqlplus" <<'MOCK'
#!/bin/bash
# Mock sqlplus — reads stdin (the heredoc) and writes deterministic output.
# If invoked with "@rerun_rserc.sql" it records the SP_ID to a log.
if [[ "$*" == *"@"* ]]; then
    echo "RERUN:$*" >> "${WORK_DIR}/sqlplus_rerun.log"
    exit 0
fi
# Consume stdin (the heredoc/SQL); honour SPOOL directives by writing files.
spool_file=""
while IFS= read -r line; do
    # Detect SPOOL directives
    if [[ "${line}" =~ ^[[:space:]]*SPOOL[[:space:]]+OFF ]]; then
        spool_file=""
        continue
    fi
    if [[ "${line}" =~ ^[[:space:]]*SPOOL[[:space:]]+(.+) ]]; then
        spool_file="${BASH_REMATCH[1]}"
        spool_file="${spool_file%%[[:space:]]*}"
        # Create the file so the script can find it
        > "${spool_file}"
        continue
    fi
    # Write to spool file if active
    if [ -n "${spool_file}" ]; then
        echo "${line}" >> "${spool_file}"
    fi
done
exit 0
MOCK
    chmod +x "${MOCK_BIN}/sqlplus"
}

# Mock sqlplus that produces files_created1.lis with a configurable FILE_COUNT
create_mock_sqlplus_with_filecount() {
    local count="${1:-42}"
    cat > "${MOCK_BIN}/sqlplus" <<MOCK
#!/bin/bash
if [[ "\$*" == *"@"* ]]; then
    echo "RERUN:\$*" >> "\${WORK_DIR}/sqlplus_rerun.log"
    exit 0
fi
spool_file=""
while IFS= read -r line; do
    if [[ "\${line}" =~ ^[[:space:]]*SPOOL[[:space:]]+OFF ]]; then
        spool_file=""
        continue
    fi
    if [[ "\${line}" =~ ^[[:space:]]*SPOOL[[:space:]]+(.+) ]]; then
        spool_file="\${BASH_REMATCH[1]}"
        spool_file="\${spool_file%%[[:space:]]*}"
        > "\${spool_file}"
        # If this is files_created1, inject FILE_COUNT
        if [[ "\${spool_file}" == *files_created1* ]]; then
            echo "FILE_COUNT=   ${count}" >> "\${spool_file}"
        fi
        continue
    fi
    if [ -n "\${spool_file}" ]; then
        echo "\${line}" >> "\${spool_file}"
    fi
done
exit 0
MOCK
    chmod +x "${MOCK_BIN}/sqlplus"
}

# Mock sqlplus that returns SPID list
create_mock_sqlplus_spid() {
    local spids=("$@")
    {
        echo '#!/bin/bash'
        echo '# Outputs SPID values to stdout'
        for sp in "${spids[@]}"; do
            echo "echo \"${sp}\""
        done
        echo 'cat > /dev/null'  # Consume stdin
    } > "${MOCK_BIN}/sqlplus"
    chmod +x "${MOCK_BIN}/sqlplus"
}

create_mock_mailx() {
    cat > "${MOCK_BIN}/mailx" <<'MOCK'
#!/bin/bash
# Mock mailx — log calls for assertion
echo "MAILX_CALL: subject=[$2] recipients=[${@:3}]" >> "${WORK_DIR}/mailx.log"
cat > /dev/null  # Consume stdin
MOCK
    chmod +x "${MOCK_BIN}/mailx"
}

create_mock_at() {
    cat > "${MOCK_BIN}/at" <<'MOCK'
#!/bin/bash
# Mock at — log scheduling calls
echo "AT_CALL: $*" >> "${WORK_DIR}/at.log"
cat > /dev/null  # Consume stdin
MOCK
    chmod +x "${MOCK_BIN}/at"
}

# ========================== FILE HELPERS ==========================

# Create N dummy files matching a glob pattern in a directory
# Usage: populate_dir <dir> <prefix> <suffix> <count>
populate_dir() {
    local dir="$1" prefix="$2" suffix="$3" count="$4"
    mkdir -p "${dir}"
    for i in $(seq 1 "${count}"); do
        touch "${dir}/${prefix}$(printf '%05d' $i)${suffix}"
    done
}

# Create files with recent mtime (within last 4 hours = 240 minutes)
populate_recent_files() {
    local dir="$1" prefix="$2" suffix="$3" count="$4"
    populate_dir "$@"
    # Ensure files have recent mtime (touch defaults to now, which is fine)
}

# Create files with OLD mtime (older than 4 hours)
populate_old_files() {
    local dir="$1" prefix="$2" suffix="$3" count="$4"
    populate_dir "$@"
    # Set mtime to 5 hours ago
    find "${dir}" -name "${prefix}*${suffix}" -exec touch -d '5 hours ago' {} + 2>/dev/null
}

# Create a mock SPID list file
create_spid_list() {
    local dest="${WORK_DIR}/spid_list.lis"
    for sp in "$@"; do
        echo "${sp}" >> "${dest}"
    done
    export SPID_LIST="${dest}"
}
