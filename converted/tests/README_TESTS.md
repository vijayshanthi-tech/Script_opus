# RSERC_CHK — Bats Unit Test Suite

## Overview

This test suite validates the `rserc_chk.sh` shell script (converted from VMS `RSERC_CHK.COM`) using [Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

**Total tests:** 55+ covering 12 categories

---

## Prerequisites

### 1. Install Bats

```bash
# Option A: OS package manager
sudo apt-get install bats          # Debian/Ubuntu
sudo yum install bats              # RHEL/CentOS (EPEL)

# Option B: From source
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

### 2. Verify installation

```bash
bats --version
# Expected: Bats 1.x.x
```

### 3. No additional Bats libraries required

The test suite is self-contained — `bats-assert` and `bats-support` are **not** required. All assertions use native Bats/Bash constructs.

---

## Running Tests

### Run entire suite

```bash
cd converted/tests
bats rserc_chk.bats
```

### Run with TAP output (for CI/CD)

```bash
bats --tap rserc_chk.bats
```

### Run a single test by name

```bash
bats -f "archive alert" rserc_chk.bats
```

### Run with verbose output

```bash
bats --verbose-run rserc_chk.bats
```

---

## Test Categories

| # | Category | Tests | Description |
|---|----------|-------|-------------|
| 1 | `log_msg` | 3 | Timestamp format, append behaviour |
| 2 | `send_alert` | 2 | mailx invocation, subject logging |
| 3 | `send_report` | 2 | Multi-recipient file email, missing file |
| 4 | `schedule_next_run` | 2 | `at` command invocation, failure warning |
| 5 | `generate_spid_list` | 2 | Oracle SPID list creation |
| 6 | `check_tap_directories` | 12 | Archive, collect, pricing, split checks |
| 7 | `generate_hourly_reports` | 8 | Oracle reports, zero-RSERC alert, SPOOL path |
| 8 | `check_rserc_failures` | 9 | .don/.tmp detection, recovery, dist skip |
| 9 | `cleanup_and_exit` | 5 | Temp cleanup, old log deletion, guard |
| 10 | Edge cases | 10 | Boundary thresholds, case-insensitive match |
| 11 | Golden master | 9 | Exact text format verification |
| 12 | Integration | 3 | Multi-function flow tests |

---

## Mock Infrastructure

All external dependencies are mocked via the `test_helper.bash` file:

| Mocked Command | What It Does |
|----------------|-------------|
| `sqlplus` | Reads heredoc, honours SPOOL directives, writes mock files |
| `mailx` | Logs calls to `${WORK_DIR}/mailx.log` for assertion |
| `at` | Logs scheduling calls to `${WORK_DIR}/at.log` |
| `ps` | (optional override) Returns configurable process list |

### Mock Variants

| Helper Function | Purpose |
|----------------|---------|
| `create_mock_sqlplus` | Default — reads SQL, processes SPOOL |
| `create_mock_sqlplus_with_filecount N` | Injects `FILE_COUNT=N` into `files_created1.lis` |
| `create_mock_sqlplus_spid 10 20 30` | Returns SP_ID values to stdout |
| `create_mock_mailx` | Logs all mailx calls |
| `create_mock_at` | Logs all at calls |

### File Helpers

| Helper Function | Purpose |
|----------------|---------|
| `populate_dir DIR PREFIX SUFFIX COUNT` | Creates N dummy files |
| `populate_recent_files DIR PREFIX SUFFIX COUNT` | Creates N files with current mtime |
| `populate_old_files DIR PREFIX SUFFIX COUNT` | Creates N files with mtime 5 hours ago |
| `create_spid_list SP1 SP2 ...` | Creates a SPID list file with given IDs |

---

## Test Architecture

```
converted/
├── rserc_chk.sh              # Script under test
└── tests/
    ├── rserc_chk.bats         # Main test file (55+ tests)
    ├── test_helper.bash       # Setup/teardown, mocks, file helpers
    ├── golden/
    │   ├── expected_log_output.txt       # Reference log format
    │   └── expected_email_subjects.txt   # Reference email subjects
    └── README_TESTS.md        # This file
```

### How Sourcing Works

The `rserc_chk.sh` script uses a `BASH_SOURCE` guard:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap cleanup_and_exit EXIT SIGTERM SIGINT
    main "$@"
fi
```

When Bats sources the script via `test_helper.bash`, only functions are defined — `main()` does not execute. This allows individual function testing.

### Isolation

Each test gets:
- A fresh temp directory (`${TEST_TEMP_DIR}`)
- Independent `WORK_DIR`, log file, and mock binaries
- Clean `PATH` with mock commands prepended
- All directories pre-created (empty)

Teardown removes everything after each test.

---

## Threshold Reference

From the script configuration (can be overridden per-test):

| Variable | Default | Triggers When |
|----------|---------|---------------|
| `MAX` | 400 | File count > 400 in collect/pricing/priced dirs |
| `SPLIT_MAX` | 600 | File count > 600 in per-SPID split dir |

Boundary tests cover: exactly at threshold (no alert), threshold+1 (alert).

---

## Known Limitations

1. **SP_ID extraction position**: The `awk 'substr($0, 35, 3)'` position is inherited from VMS and may need adjustment for actual Linux filenames. The test uses padded filenames to verify the extraction mechanism, not the exact position.

2. **Oracle connectivity**: All Oracle calls are mocked. Integration testing against a real database requires a separate test environment.

3. **Timing-dependent tests**: The `main()` loop (hour checks, 10-min sleep) is not directly tested because it would block. Individual functions called by `main()` are tested instead.

4. **Platform**: Tests require GNU `find` with `-printf`, `-delete`, and `-mmin` support (standard on Linux, not macOS).

---

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Install Bats
  run: sudo apt-get install -y bats

- name: Run RSERC_CHK tests
  run: |
    cd converted/tests
    bats --tap rserc_chk.bats
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests passed |
| 1 | One or more tests failed |

---

## Adding New Tests

1. Add test to `rserc_chk.bats` with a descriptive `@test` name
2. Use the existing mock helpers or add new ones to `test_helper.bash`
3. Follow the naming convention: `"CATEGORY: description"`
4. Run `bats rserc_chk.bats` to verify
