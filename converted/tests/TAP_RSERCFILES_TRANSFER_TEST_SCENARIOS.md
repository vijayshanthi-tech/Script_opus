# TAP_RSERCFILES_TRANSFER — Test Scenarios

## Purpose

This document lists the test scenarios required to validate that the converted
`tap_rsercfiles_transfer.sh` script behaves identically to the original VMS
`TAP_RSERCFILES_TRANSFER.COM`.

---

## Prerequisites

| Item | Detail |
|------|--------|
| Test framework | [Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System) |
| SFTP mock | Mock `sftp` binary to avoid real network calls |
| Dummy files | See `tests/dummy_inputs/` directory |
| SSH keys | Not needed — SFTP is mocked during tests |

---

## Test Scenario Matrix

### 1. Environment Validation

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 1.1 | All required directories exist and SFTP config is present | `validate_environment` succeeds (exit 0) | Logical checks |
| 1.2 | `TAP_CFG_DIR` is unset or missing | Script exits with error | `F$TRNLNM("TAP_CFG_DIR")` |
| 1.3 | `XI_DAT` directory does not exist | Script exits with error | `F$TRNLNM("XI_DAT")` |
| 1.4 | `FCS_RSERC_DIR` directory does not exist | Script exits with error | `F$TRNLNM("FCS_RSERC_DIR")` |
| 1.5 | `SFTP_TMP_DIR` directory does not exist | Script exits with error | `F$TRNLNM("SFTP_TMP_DIR")` |
| 1.6 | `RSERC_SFTP.CFG` file is missing | Script exits with error | `F$SEARCH("TAP_CFG_DIR:RSERC_SFTP.CFG")` |
| 1.7 | `RSERC_SFTP.CFG` file exists but is empty | `read_sftp_config` exits with error | `EXTRACT_SFTP` |

### 2. Single-Instance Enforcement

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 2.1 | No other instance running | Lock acquired, script proceeds | `SET PROCESS /NAME=` |
| 2.2 | Another instance already holds the lock | Script exits immediately with code 0 | `CHECK_INSTANCES` |

### 3. Housekeeping

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 3.1 | Log files older than 7 days exist | Old log files are deleted | `HOUSE_KEEP` |
| 3.2 | No old log files | Housekeeping completes without error | `HOUSE_KEEP` |

### 4. SFTP Config Parsing

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 4.1 | Valid config with username on line 1, hostname on line 2 | `DEST_USERNAME` and `DEST_HOSTNAME` set correctly | `EXTRACT_SFTP` |
| 4.2 | Config file has only one line (missing hostname) | Script exits with error | `EXTRACT_SFTP` |
| 4.3 | Config file is empty | Script exits with error | `EXTRACT_SFTP` |

### 5. RSERC File Collection

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 5.1 | 3 RSERC files in `FCS_RSERC_DIR` | All 3 staged in `SFTP_TMP_DIR` with `.sftp_tmp_rs` extension; `put`, `rename`, `delete` commands written | `RSERC_FILE_COUNT` |
| 5.2 | 0 RSERC files | `RSERC_COUNT` = 0, no batch commands written | `RSERC_FILE_COUNT` |
| 5.3 | 60 RSERC files (exceeds MAX_BATCH_SIZE=50) | Only 50 files processed in one batch | `.GT. 50` check |
| 5.4 | Exactly 50 RSERC files | All 50 processed | Boundary condition |
| 5.5 | File naming: `RSERC000001.DAT` through `RSERC999999.DAT` | Pattern `RSERC??????.DAT` matches; 6-char wildcard | `RSERC%%%%%%.DAT` |
| 5.6 | Files not matching the pattern (e.g. `RSERC1.DAT`, `OTHER000001.DAT`) | Ignored by collection | Pattern filter |
| 5.7 | Staged file content matches original | Byte-for-byte copy verified | `COPY/LOG` |

### 6. MRLOG File Collection

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 6.1 | 4 MRLOG files in `XI_DAT` | All 4 staged and batch commands written | `MRLOG_FILE_COUNT` |
| 6.2 | 0 MRLOG files | `MRLOG_COUNT` = 0 | `MRLOG_FILE_COUNT` |
| 6.3 | 60 MRLOG files | Only 50 processed | `.GT. 50` check |
| 6.4 | File naming: `MRLOG000001.DAT` format | Pattern `MRLOG??????.DAT` matches | `MRLOG%%%%%%.DAT` |

### 7. Batch File Generation

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 7.1 | SFTP batch starts with `binary`, `lcd SFTP_TMP_DIR`, `cd xi_dat` | Header matches VMS original | `SFTP_CTRL_FILE` |
| 7.2 | Each staged file has a `put` command | One `put <name>.sftp_tmp_rs` per file | `WRITE SFTP_CTRL_FILE` |
| 7.3 | Rename batch has `cd xi_dat` header and one `rename` per file | Maps `.sftp_tmp_rs` -> `.DAT` | `RENAME_TMP_FILE` |
| 7.4 | Delete script has one `rm -f` command per source file | Matches the original full path | `DELETE_TMP_FILE` |
| 7.5 | Batch ends with `exit` command | SFTP session terminates cleanly | `WRITE "exit"` |

### 8. SFTP Transfer Process

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 8.1 | SFTP upload succeeds | Batch file removed, proceeds to rename step | `SFTP_PROCESS` |
| 8.2 | SFTP upload fails | Script exits with error (code 4) | `ERROR` handler |
| 8.3 | SFTP rename succeeds | Rename batch removed, proceeds to delete step | `SFTP_PROCESS` |
| 8.4 | SFTP rename fails | Script exits with error (code 4) | `ERROR` handler |
| 8.5 | Local delete script runs successfully | Delete script removed, flag file removed | `DELETE_SFTPD_FILES` |
| 8.6 | Local delete script fails | Script exits with error (code 4) | `ERROR` handler |
| 8.7 | `SFTP_ABS_IN_PROGRESS.FLAG` created before upload | Flag present during transfer | `create FLAG` |
| 8.8 | Flag removed after successful completion | Flag file no longer exists | `DELETE FLAG` |

### 9. Self-Recovery

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 9.1 | No flag file exists | Recovery skipped, logs "No recovery needed" | `SELF_RECOVERY` |
| 9.2 | Flag + `SFTP_CTRL_FILE.DAT` exist (upload was in-progress) | SFTP `rm *.sftp_tmp_rs` on remote, cleanup local files | `RECOVERY_1` |
| 9.3 | Flag + `RENAME_SFTPD_FILES_TMP.sh` exists (rename was in-progress) | Script exits with error (recovery disabled, as per VMS) | `RECOVERY_2` (commented out in VMS) |
| 9.4 | Flag + `DELETE_SFTPD_FILES_TMP.sh` exists (delete was in-progress) | Delete script executed, files cleaned up | `RECOVERY_3` |
| 9.5 | `SFTP_TMP_DIR` contains leftover files from previous run | All temp files cleaned before proceeding | Initial cleanup |
| 9.6 | Recovery SFTP call fails | Script exits with error | `RECOVERY_1` error path |

### 10. Shutdown Control — TAP_CLOSEDOWN_ALL = N

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 10.1 | `TAP_CLOSEDOWN_ALL="N"` and `RSERC_TRANS_SHUTDOWN="N"` | Script continues looping (no time-based shutdown) | `FINAL_CHECK` |
| 10.2 | `TAP_CLOSEDOWN_ALL="N"` and `RSERC_TRANS_SHUTDOWN="Y"` | Script shuts down via flag only | `FINAL_CHECK` |
| 10.3 | `TAP_CLOSEDOWN_ALL="N"` and `RSERC_TRANS_SHUTDOWN.FLAG` file exists | Script shuts down via flag file | `FINAL_CHECK` |
| 10.4 | `TAP_CLOSEDOWN_ALL="18:00"` and current time is 19:00 | Script shuts down (time exceeded) | `FINAL_CHECK` |
| 10.5 | `TAP_CLOSEDOWN_ALL="23:59"` and current time is 10:00 | Script continues looping | `FINAL_CHECK` |
| 10.6 | `TAP_CLOSEDOWN_ALL="00:00"` — edge: midnight | Any non-midnight time causes shutdown | Boundary |

### 11. Sleep / Wait Cycle

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 11.1 | No files to transfer (0 RSERC, 0 MRLOG) | Script sleeps 10 minutes (600s), then checks shutdown | `WAIT 00:10:00` |
| 11.2 | Files found and transferred | No sleep, loops immediately | `MAIN_LOOP` |

### 12. Mixed Batch (RSERC + MRLOG)

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 12.1 | 5 RSERC + 5 MRLOG files | All 10 transferred in one batch | `MAIN_LOOP` |
| 12.2 | 50 RSERC + 50 MRLOG files | 100 total (50 each) in one batch | `MAIN_LOOP` |
| 12.3 | 60 RSERC + 0 MRLOG | 50 RSERC transferred; 10 remain for next cycle | Batch cap |
| 12.4 | 0 RSERC + 3 MRLOG | Only MRLOG files transferred | `MAIN_LOOP` |

### 13. Logging

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 13.1 | Script startup | Log line: `<script> has started at DD-Mon-YYYY HH:MM:SS` | `TAPLOG_MESS` |
| 13.2 | File staged | Log line: `Staged RSERC file: <filename>` or `Staged MRLOG file: <filename>` | `COPY/LOG` |
| 13.3 | Transfer started | Log line with "SFTP PROCESS ... STARTED" | `SFTP_PROCESS` |
| 13.4 | Transfer completed | Log line with "SFTP PROCESS ... COMPLETED" | `SFTP_PROCESS` |
| 13.5 | Error | Log line: `ERROR: *** <scriptname> - <phase>, <text>` | `ERROR` |
| 13.6 | Shutdown | Log line with shutdown reason | `FINAL_CHECK` |
| 13.7 | Timestamp format | `DD-Mon-YYYY HH:MM:SS` (e.g. `25-Mar-2026 14:30:00`) | `F$TIME()` |

### 14. Signal Handling

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 14.1 | SIGTERM received | `error_exit` called, cleanup runs, exit code 4 | `ON ERROR THEN GOTO ERROR` |
| 14.2 | SIGINT received | Same as SIGTERM | `SET CONTROL=(T,Y)` |
| 14.3 | Normal exit | `cleanup_and_exit` called via EXIT trap, lock released | `EXIT` |
| 14.4 | Double cleanup guard | `_CLEANUP_DONE` flag prevents re-entry | Exit guard |

### 15. Temporary File Extension

| # | Scenario | Expected Outcome | VMS Section |
|---|----------|-------------------|-------------|
| 15.1 | Staged RSERC file | Extension changes from `.DAT` to `.sftp_tmp_rs` | `FILE_TMP = name+".SFTP_TMP_RS"` |
| 15.2 | Remote rename | `.sftp_tmp_rs` renamed back to `.DAT` on ABS server | `RENAME_TMP_FILE` |
| 15.3 | Prevents partial pickup | ABS should never see `.sftp_tmp_rs` files (only `.DAT`) | Design intent |

---

## End-to-End Integration Test (Manual)

This test should be performed in a staging environment with real SFTP connectivity.

1. **Setup**: Place 5 RSERC and 3 MRLOG dummy files in the source directories.
2. **Run**: Execute `tap_rsercfiles_transfer.sh` with `RSERC_TRANS_SHUTDOWN=Y` (so it runs one cycle and exits).
3. **Verify**:
   - All 8 files appear on the ABS server in `xi_dat/` with `.DAT` extension.
   - No `.sftp_tmp_rs` files remain on the ABS server.
   - Source files deleted from `FCS_RSERC_DIR` and `XI_DAT`.
   - `SFTP_TMP_DIR` is clean.
   - `SFTP_ABS_IN_PROGRESS.FLAG` is removed.
   - Log file contains expected start/complete messages.

---

## Recovery Integration Test (Manual)

1. **Simulate failure**: Start a transfer, then kill the script mid-upload.
2. **Verify**: `SFTP_ABS_IN_PROGRESS.FLAG` and `SFTP_CTRL_FILE.DAT` remain.
3. **Restart**: Run the script again.
4. **Verify**: Self-recovery cleans up remote `.sftp_tmp_rs` files, removes stale control files, and resumes normal operation.

---

## Dummy Input Files

Pre-built dummy files for testing are in `tests/dummy_inputs/`:

| File | Location | Content |
|------|----------|---------|
| `RSERC000001.DAT` – `RSERC000005.DAT` | `dummy_inputs/FCS_RSERC/` | Simulated RSERC records |
| `MRLOG000001.DAT` – `MRLOG000003.DAT` | `dummy_inputs/XI_DAT/` | Simulated MRLOG records |
| `RSERC_SFTP.CFG` | `dummy_inputs/CFG/` | username + hostname (2 lines) |

Copy these into the appropriate directories before running manual tests.
