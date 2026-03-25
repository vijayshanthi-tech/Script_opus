# TAP_JOB_STARTUP — Complete Migration & Technical Document

> **VMS Source:** `TAP_JOB_STARTUP.COM` — Case ID `TAPOP0190` / Spec ID `TAPSO190.DOC`  
> **Linux Target:** `tap_job_startup.sh`  
> **Author (VMS):** S.R.Campbell (1998)  
> **System:** VMO2 TAP (Transferred Account Procedure) — GSMA Telecom Roaming/Billing

---

## Table of Contents

1. [PART 1 — Understanding the VMS Script](#part-1--understanding-the-vms-script)
2. [PART 2 — Dependency Analysis](#part-2--dependency-analysis)
3. [PART 3 — Conversion to Linux](#part-3--conversion-to-linux)
4. [PART 4 — Gap Analysis](#part-4--gap-analysis)
5. [PART 5 — Testing Guide](#part-5--testing-guide)
6. [PART 6 — Run Guide](#part-6--run-guide)

---

# PART 1 — Understanding the VMS Script

## 1. Overall Purpose

### What the Script Does

`TAP_JOB_STARTUP.COM` is a **generic wrapper** that launches any TAP executable program as a named VMS process. Think of it as a "run this program safely" template.  It:

1. **Accepts three parameters** — a process type (e.g., `GAPS`), an instance number (e.g., `01`), and a program name (e.g., `GAPS_PROC`)
2. **Registers itself** with a unique VMS process name (`TAP_<type>_<instance>`) — this prevents accidental duplicates
3. **Finds and runs** the executable from `TAP_EXE_DIR`
4. **Cleans up** its own "closedown" logical so the system knows it finished
5. **Reports errors** to operators if anything goes wrong

### What System It Belongs To

This script is part of the **VMO2 TAP (Transferred Account Procedure)** system — a telecom billing platform that handles inter-operator roaming charges under the GSMA standard. The TAP system processes call data records (CDRs) flowing between mobile operators.

### Why It Exists

On VMS, batch jobs are submitted to queues. Rather than writing startup/cleanup/error-handling code in every individual job, this single wrapper provides a **standardised harness**. It is called by `TAP_MONITOR.COM` via the VMS `SUBMIT` command to start background jobs like GAPS and GSDM.

---

## 2. End-to-End Workflow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    TAP_JOB_STARTUP.COM Flow                        │
└─────────────────────────────────────────────────────────────────────┘

  START
    │
    ▼
  ┌──────────────────────────────────────────┐
  │  PHASE: STARTING                         │
  │  • Set ON WARNING THEN GOTO ERROR        │
  │  • Define global VMS symbols             │
  │    (bell, crlf, csi, esc, tab, etc.)     │
  └────────────────────┬─────────────────────┘
                       │
                       ▼
  ┌──────────────────────────────────────────┐
  │  PHASE: SAVE_ENVIRONMENT                 │
  │  • Save current procedure name & path    │
  │  • If interactive: save terminal state   │
  │  • If batch: enable verification         │
  │  • Validate P1, P2, P3 are non-empty     │
  │    └─ If missing → ERROR                 │
  │  • SET PROCESS/NAME="TAP_<P1>_<P2>"      │
  │    └─ If fails → ERROR                   │
  └────────────────────┬─────────────────────┘
                       │
                       ▼
  ┌──────────────────────────────────────────┐
  │  PHASE: MAIN                             │
  │  • Search for TAP_EXE_DIR:<P3>.EXE       │
  │    └─ If not found → ERROR               │
  │  • RUN the executable                    │
  │  • Clean up closedown logical:           │
  │    DEASSIGN/GROUP <procname>_CLOSEDOWN    │
  │  • If run failed → ERROR                 │
  └────────────────────┬─────────────────────┘
                       │
              ┌────────┴────────┐
              ▼                 ▼
      ┌─────────────┐   ┌─────────────────┐
      │  SUCCESS     │   │  ERROR           │
      │  → goto exit │   │  • Log error     │
      │              │   │  • Notify oper8  │
      │              │   │  • Call TAPLOG_  │
      │              │   │    MESS          │
      └──────┬───── ┘   └────────┬────────┘
             │                    │
             ▼                    ▼
      ┌──────────────────────────────────────┐
      │  PHASE: EXIT                          │
      │  • If interactive: restore terminal   │
      │    settings (broadcast, messages,     │
      │    default directory, control codes)  │
      │  • EXIT                               │
      └──────────────────────────────────────┘
```

### Loop Behaviour

**None** — this script runs once, executes the program, and exits. It is NOT a daemon or loop-based script, unlike `TAP_MONITOR.COM` or `TAP_RSERCFILES_TRANSFER.COM`.

### Exit Conditions

| Condition | VMS Path | Exit Code |
|-----------|----------|-----------|
| All three parameters provided, program found, run succeeds | `goto exit` | Success |
| Missing parameter P1, P2, or P3 | `goto error` | Error |
| Cannot set process name (duplicate already running) | `goto error` | Error |
| Executable not found in `TAP_EXE_DIR` | `goto error` | Error |
| Program returns error status | `goto error` | Error |

### External Interactions

| Interaction | Details |
|-------------|---------|
| **Program execution** | Runs any executable from `TAP_EXE_DIR` (e.g., GAPS_PROC.EXE) |
| **VMS batch queue** | Receives parameters via SUBMIT /PARAM from TAP_MONITOR |
| **Operator console** | `REQUEST/TO=operator` sends error messages to OPER8 terminal |
| **Logging** | `@TAP_COM_DIR:TAPLOG_MESS` writes to system log |
| **Closedown logicals** | Reads and deletes `<procname>_CLOSEDOWN` group logical |

---

## 3. All Sections / Labels

### 3.1 Global Symbol Definitions (Lines 30–61)

**Purpose:** Define VMS terminal control sequences and shorthand commands used across all TAP scripts.

| Symbol | Purpose |
|--------|---------|
| `bell`, `crlf`, `csi`, `esc`, `tab` | Terminal control characters |
| `big1`, `big2`, `blink`, `bold`, `rev`, `under`, `wide` | Text formatting sequences |
| `cls`, `cll`, `top`, `l23`, `norm`, `off` | Screen control |
| `wo` | Shorthand for `WRITE SYS$OUTPUT` (print to screen) |
| `wof` | Shorthand for `WRITE OUTFILE` (write to file) |
| `operator` | Set to `"oper8"` — the operator terminal |
| `status` | Global status variable, initialised to `""` |
| `input` | System input program reference |

**Linux equivalent:** Not needed. Terminal formatting is handled by ANSI codes or not used in batch scripts. `wo` becomes `echo`, `operator` becomes email address.

---

### 3.2 SAVE_ENVIRONMENT (Lines 67–108)

**Purpose:** Save current DCL environment state, validate parameters, and set the process identity.

**Inputs:**
- `P1` — Process type (e.g., `GAPS`, `GSDM`)
- `P2` — Instance number (e.g., `01`)
- `P3` — Program name (e.g., `GAPS_PROC`)

**Actions:**

1. **Get procedure info:**
   - `proc = f$environment("PROCEDURE")` — full path to this .COM file
   - `procname = f$getjpi("","PRCNAM")` — current process name

2. **Interactive vs Batch handling:**
   - **Interactive** (`f$mode() .EQS. "INTERACTIVE"`):
     - Save terminal settings (broadcast, control codes, messages, default dir)
     - Suppress messages, disable verify
   - **Batch** (non-interactive):
     - Enable full messages and verification

3. **Parameter validation:**
   - If P1, P2, or P3 is empty → set status to "Parameter must be provided" → `goto error`

4. **Process naming (singleton enforcement):**
   - `SET PROCESS/NAME="TAP_<P1>_<P2>"` — rename the current process
   - If this fails (name already taken by another process) → "Process name cannot be set" → `goto error`
   - On VMS, process names must be unique within a node, so this acts as a natural singleton guard

**Outputs:** `procname` global symbol set to `TAP_<P1>_<P2>`

**Dependencies:** None (VMS built-in functions)

---

### 3.3 MAIN (Lines 114–143)

**Purpose:** Locate the executable, run it, clean up.

**Actions:**

1. **Search for executable:**
   - `f$search("tap_exe_dir:''p3'.exe")` — check if the program exists
   - If not found → "unavailable" → `goto error`

2. **Run the program:**
   - `RUN TAP_EXE_DIR:<P3>` — execute the program
   - Capture `$STATUS` (VMS system status)

3. **Cleanup closedown logical:**
   - Build logical name: `<process_name>_CLOSEDOWN`
   - If it exists → `DEASSIGN/GROUP` (remove it)
   - This allows the process to signal that it has finished, so other scripts (like TAP_MONITOR) know the job completed

4. **Check run status:**
   - If status indicates failure → "Error returned from program" → `goto error`
   - Otherwise → `goto exit` (success)

**Dependencies:**
- `TAP_EXE_DIR` — VMS logical name pointing to the executables directory
- The program file `<P3>.EXE` must exist in that directory

---

### 3.4 ERROR (Lines 153–185)

**Purpose:** Central error handler. Logs, notifies, and terminates.

**Actions:**

1. **Determine error text:**
   - If `status` is empty → use VMS system error message: `f$message($status)`
   - If `status` has a string → use that string directly

2. **Interactive display (if applicable):**
   - Clear screen, show error at line 20
   - Prompt user to press ENTER

3. **Log the error:**
   - `@TAP_COM_DIR:TAPLOG_MESS " ***" "<procname> - <phase>, <error_text>" " "`
   - This calls the TAP logging subroutine to write a timestamped entry

4. **Operator notification:**
   - `REQUEST/TO=operator` — sends message to the operator terminal (`oper8`)

**Outputs:** Error logged, operator notified

---

### 3.5 EXIT (Lines 195–209)

**Purpose:** Restore the DCL environment after the script completes (success or error).

**Actions (interactive only):**
- Clear status symbol
- Clear screen
- Re-enable terminal broadcasts
- Restore verify flag
- Restore message settings
- Restore default directory
- Restore control-key handling

**Batch mode:** Simply exits — no restoration needed.

---

# PART 2 — Dependency Analysis

## 1. External Scripts

| Script | Called How | Purpose | Status |
|--------|-----------|---------|--------|
| `TAP_COM_DIR:TAPLOG_MESS` | `@tap_com_dir:taplog_mess` | TAP system logging utility — writes timestamped messages to a shared log file | ❌ **Missing** (recreated as inline `log_msg()` function, consistent with all other converted scripts) |
| Called program (`P3`) | `RUN TAP_EXE_DIR:<P3>` | The actual TAP job executable (e.g., GAPS_PROC, GSDM_PROC) | ❌ **External** — compiled binaries, not part of this conversion scope. Must exist in `TAP_EXE_DIR`. |

## 2. Logical Names (VMS Environment Variables)

| Logical Name | Purpose | Required | Default | Linux Equivalent |
|---|---|---|---|---|
| `TAP_EXE_DIR` | Directory containing TAP executables | **Yes** | None (must be defined) | `TAP_EXE_DIR=/data/call_data/tap/exe` |
| `TAP_COM_DIR` | Directory containing TAP command procedures | Yes (for TAPLOG_MESS) | None | `TAP_COM_DIR=/data/call_data/tap/com` |
| `TAP_LOG_DIR` | Directory for log files | Recommended | None | `TAP_LOG_DIR=/data/call_data/tap/log` |
| `<procname>_CLOSEDOWN` | Per-process closedown signal (VMS group logical) | Optional | Not defined | Flag file in `TAP_CLOSEDOWN_DIR` |
| `operator` / `oper8` | Operator terminal for alerts | Yes | `oper8` | `OPERATOR_EMAIL` or `logger -t` |

### How VMS Logicals Work (for beginners)

VMS "logical names" are like Linux environment variables, but they can be scoped to different levels (process, group, system). The key ones here:

- **`TAP_EXE_DIR`**: A system-level logical pointing to a disk/directory where compiled programs (`.EXE` files) live. On Linux, this becomes a simple path variable.
- **`<procname>_CLOSEDOWN`**: A group-level logical. When someone wants to tell a TAP process to shut down, they `DEFINE/GROUP TAP_GAPS_01_CLOSEDOWN "Y"`. The process checks for it and shuts down gracefully. The startup script cleans this up after the program exits.

## 3. File Systems

| VMS Path | Linux Equivalent | Contents | Access |
|----------|-----------------|----------|--------|
| `TAP_EXE_DIR:*.EXE` | `/data/call_data/tap/exe/*` | Compiled TAP programs | Read + Execute |
| `TAP_COM_DIR:*.COM` | `/data/call_data/tap/com/*.sh` | Command procedures (scripts) | Read + Execute |
| `TAP_LOG_DIR:*.LOG` | `/data/call_data/tap/log/*.log` | Log files | Write + Append |
| (Group logicals) | `/data/call_data/tap/closedown/` | Closedown flag files | Read + Write + Delete |
| `/tmp/TAP_<P1>_<P2>.lock` | Lock file for singleton | flock lock file | Write |

## 4. Database Usage

**None.** This script does not interact with any database. It only launches other programs which may use databases.

## 5. VMS-Specific Functions and Linux Equivalents

| VMS Function / Command | What It Does | Linux Equivalent |
|---|---|---|
| `f$verify(0)` / `f$verify(1)` | Enable/disable command echo (like `set -x`) | `set +x` / `set -x` |
| `f$environment("PROCEDURE")` | Get full path of running script | `"$(readlink -f "$0")"` or `BASH_SOURCE` |
| `f$getjpi("","PRCNAM")` | Get current process name | `$$` (PID) or custom `PROCNAME` variable |
| `f$mode()` | Check if INTERACTIVE or BATCH | `[ -t 0 ]` (terminal attached?) |
| `SET PROCESS/NAME="name"` | Rename current process (singleton) | `flock` on a lock file |
| `f$search("dir:file")` | Search for a file | `[ -f "path" ]` or `find` |
| `RUN program` | Execute compiled program | `./program` or `"${path}/program"` |
| `$STATUS` | Exit status of last command | `$?` |
| `f$process()` | Current process name | `${PROCNAME}` variable |
| `f$trnlnm("name")` | Translate logical name | `${VAR_NAME}` or `printenv VAR_NAME` |
| `DEASSIGN/GROUP logical` | Remove group logical | `rm -f flag_file` |
| `SET NOON` | Don't exit on error | `set +e` (or no `set -e`) |
| `SET ON` | Exit on error | `set -e` |
| `ON WARNING THEN GOTO ERROR` | Global error trap | `trap 'error_exit ...' ERR` |
| `REQUEST/TO=operator "msg"` | Send message to operator terminal | `logger -t TAG "msg"` + `mailx` |
| `@script` | Execute a command procedure | `source script.sh` or `./script.sh` |
| `SET TERM/NOBROAD` | Disable broadcast messages to terminal | Not applicable (no VMS terminal broadcasts) |
| `SET MESSAGE/NOTEXT/...` | Suppress DCL error messages | Redirect stderr: `2>/dev/null` |
| `bell[0,32] == %D7` | Define character code into symbol | Not needed — no terminal bell usage |
| `SUBMIT/QUEUE=.../PARAM=(...)` | Submit batch job with parameters | `nohup ./script.sh args &` or `at` / `cron` |
| `f$message($status)` | Convert status code to text | `strerror()` — not directly available; use exit code |

---

# PART 3 — Conversion to Linux

## 1. Main Bash Script: `tap_job_startup.sh`

The converted script is located at: `converted/tap_job_startup.sh`

### Architecture

```
tap_job_startup.sh
    │
    ├── log_msg()          ─── Replaces @TAP_COM_DIR:TAPLOG_MESS
    ├── send_alert()       ─── Replaces REQUEST/TO=operator
    ├── error_exit()       ─── Replaces ERROR label
    ├── cleanup_closedown()─── Replaces DEASSIGN/GROUP closedown logical
    │
    ├── Parameter validation ─── P1, P2, P3 checks
    ├── Singleton check    ─── flock (replaces SET PROCESS/NAME)
    ├── Program execution  ─── Direct execution (replaces RUN TAP_EXE_DIR:)
    └── Cleanup & exit     ─── Replaces EXIT label
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| `flock` for singleton | VMS `SET PROCESS/NAME` ensures uniqueness; `flock` is the Linux best practice |
| Flag files for closedown | VMS group logicals don't exist on Linux; flag files in a dedicated directory provide the same signal mechanism |
| Look for `P3` then `P3.sh` | VMS looks for `.EXE`; on Linux, programs may be scripts (`.sh`) or compiled binaries (no extension) |
| `log_msg()` inline | Consistent with all other converted scripts — replaces `TAPLOG_MESS` |
| No terminal handling | VMS interactive mode saved/restored terminal state; on Linux, background jobs don't need this |

## 2. Supporting Scripts

| Script | Status | Notes |
|--------|--------|-------|
| `TAPLOG_MESS` | ✅ **Replaced** | Inline `log_msg()` function in every converted script |
| Target programs (GAPS_PROC, GSDM_PROC, etc.) | ❌ **External** | Compiled VMS executables — outside scope of shell script conversion. Must be ported separately or replaced with equivalent Linux binaries/scripts. |

## 3. Complete VMS → Linux Mapping Table

| # | VMS Feature | VMS Code | Bash Equivalent | Notes |
|---|---|---|---|---|
| 1 | Error trap | `ON WARNING THEN GOTO ERROR` | `error_exit()` function called at each check point | Bash `trap ERR` is an option but explicit checks give clearer control |
| 2 | Global symbols | `bell[0,32] == %D7` etc. | Not needed | VMS terminal control codes — irrelevant in Linux batch jobs |
| 3 | Status variable | `status == ""` | `RUN_STATUS=$?` | `$?` is Bash's exit status |
| 4 | Save environment | `proc = f$environment("PROCEDURE")` | `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` | Not needed in this script since we don't restore env |
| 5 | Get process name | `procname = f$getjpi("","PRCNAM")` | `PROCNAME="TAP_${P1}_${P2}"` | Constructed from params |
| 6 | Interactive check | `f$mode() .eqs. "INTERACTIVE"` | Not implemented | Script always runs as background job |
| 7 | Save terminal state | `contcodes = f$environment("control")` etc. | Not needed | No terminal interaction in Linux batch |
| 8 | Parameter check | `p1 .eqs. "" .or. p2 .eqs. ""...` | `[ -z "${P1}" ] \|\| [ -z "${P2}" ] \|\| [ -z "${P3}" ]` | Same logic |
| 9 | Set process name | `SET PROCESS/NAME="TAP_''p1'_''p2'"` | `flock -n 200` on `/tmp/${PROCNAME}.lock` | Prevents duplicate instances |
| 10 | Check name success | `.NOT. $STATUS` check | `if ! flock -n 200` | flock returns non-zero if lock held |
| 11 | Search for EXE | `f$search("tap_exe_dir:''p3'.exe")` | `[ -x "${TAP_EXE_DIR}/${P3}" ]` | Also checks for `.sh` extension |
| 12 | Run program | `RUN TAP_EXE_DIR:'p3'` | `"${PROGRAM}"` | Direct execution |
| 13 | Capture run status | `status == $status` | `RUN_STATUS=$?` | Exit code |
| 14 | Build closedown name | `mylog = f$process() + "_CLOSEDOWN"` | `flag_file="${TAP_CLOSEDOWN_DIR}/TAP_${P1}_${P2}_CLOSEDOWN"` | Path-based flag |
| 15 | Check closedown exists | `f$trnlnm(mylog) .nes. ""` | `[ -f "${flag_file}" ]` | File existence check |
| 16 | Remove closedown | `DEASSIGN/GROUP &mylog` | `rm -f "${flag_file}"` | Delete flag file |
| 17 | Check run failure | `.NOT. STATUS` | `[ ${RUN_STATUS} -ne 0 ]` | Non-zero = error |
| 18 | Log error | `@tap_com_dir:taplog_mess " ***" ...` | `log_msg " *** ${procname} - ${phase}, ${error_text}"` | Inline logging |
| 19 | Operator alert | `REQUEST/TO=operator "message"` | `logger -t TAG "msg"` | syslog + optional email |
| 20 | Interactive error display | `wo "...20;1H..."` + `read/prompt=` | Not implemented | No terminal in batch mode |
| 21 | Restore terminal | `SET TERM/BROAD`, restore messages, dir | Not needed | No terminal state to restore |

---

# PART 4 — Gap Analysis

## Missing Information

| Item | Description | Impact | Mitigation |
|------|-------------|--------|------------|
| `TAPLOG_MESS` source code | The external logging script is not provided | Low | Replaced with inline `log_msg()` — same approach as all other converted scripts |
| Target executables (GAPS_PROC, GSDM_PROC, etc.) | The actual VMS .EXE programs are compiled binaries | **High** | These must be ported to Linux separately (C/Fortran recompilation or reimplementation). `tap_job_startup.sh` will look for them as executables or `.sh` scripts in `TAP_EXE_DIR`. |
| `TAP_EXE_DIR` directory structure | Exact list of executables available | Medium | Script handles missing executables gracefully with error message |
| Closedown mechanism details | How exactly closedown logicals are set by other processes | Low | Implemented as flag files — any process can `touch` a closedown flag |
| Operator terminal (`oper8`) configuration | VMS-specific operator terminal setup | Low | Replaced with `logger` (syslog) + optional `mailx` |

## Assumptions Made

| # | Assumption | Reasoning |
|---|-----------|-----------|
| 1 | The script will only run in batch (non-interactive) mode on Linux | VMS interactive mode was for development/debugging. Production TAP jobs are submitted as batch |
| 2 | Target programs will be available as Linux executables or shell scripts | VMS `.EXE` files cannot run on Linux — they must be recompiled/rewritten |
| 3 | `flock` is an acceptable replacement for VMS process naming | flock is the standard Linux approach for singleton processes |
| 4 | Flag files in `TAP_CLOSEDOWN_DIR` replace VMS group logicals | Group logicals don't exist on Linux; file-based signalling is the closest equivalent |
| 5 | `TAP_EXE_DIR` defaults to `/data/call_data/tap/exe` | Consistent with other converted scripts' directory conventions |
| 6 | Logging format matches existing `log_msg()` pattern | All other converted scripts use `DD-Mon-YYYY HH:MM:SS - message` format |
| 7 | Programs with `.sh` extension are also valid | On VMS, all executables have `.exe`. On Linux, scripts typically have `.sh` |

## Risks

| # | Risk | Severity | Description |
|---|------|----------|-------------|
| 1 | **Program compatibility** | 🔴 High | VMS compiled programs (`.EXE`) will NOT work on Linux. Each target program called via TAP_JOB_STARTUP must be separately ported. |
| 2 | **Singleton behaviour difference** | 🟡 Medium | VMS `SET PROCESS/NAME` gives a system-unique process name. Linux `flock` only works if all instances try the same lock file. If someone runs the program directly (not through `tap_job_startup.sh`), the lock won't prevent duplicates. |
| 3 | **Closedown signal timing** | 🟡 Medium | VMS group logical deassignment is atomic. Linux `rm -f` on a flag file has a tiny race window (another process could create the flag between our check and delete). In practice, this is negligible for TAP's polling-based design. |
| 4 | **Exit status semantics** | 🟢 Low | VMS uses odd=success, even=failure for `$STATUS`. Linux uses 0=success, non-zero=failure. The converted script correctly uses Linux conventions. |
| 5 | **Operator notification** | 🟢 Low | VMS `REQUEST/REPLY/TO=operator` is a synchronous terminal message. Linux `logger` + `mailx` is asynchronous. Operators must monitor syslog or email instead of a VMS terminal. |

---

# PART 5 — Testing Guide

## 1. Pre-requisites

### Environment Setup

```bash
# Create all required directories
sudo mkdir -p /data/call_data/tap/{exe,com,log,closedown}

# Or for testing, use temporary paths:
export TAP_EXE_DIR="/tmp/tap_test/exe"
export TAP_COM_DIR="/tmp/tap_test/com"
export TAP_LOG_DIR="/tmp/tap_test/log"
export TAP_CLOSEDOWN_DIR="/tmp/tap_test/closedown"
mkdir -p "${TAP_EXE_DIR}" "${TAP_COM_DIR}" "${TAP_LOG_DIR}" "${TAP_CLOSEDOWN_DIR}"
```

### Required Tools

| Tool | Purpose | Check Command |
|------|---------|---------------|
| Bash 4+ | Shell interpreter | `bash --version` |
| flock | File locking for singleton | `which flock` (part of `util-linux`) |
| logger | Syslog logging | `which logger` (part of `util-linux`) |
| mailx (optional) | Email alerts | `which mailx` |

### Create a Dummy Test Program

```bash
# Create a simple test program that succeeds
cat > "${TAP_EXE_DIR}/TEST_PROG" << 'EOF'
#!/bin/bash
echo "TEST_PROG running at $(date)"
sleep 2
echo "TEST_PROG completed"
exit 0
EOF
chmod +x "${TAP_EXE_DIR}/TEST_PROG"

# Create a test program that fails
cat > "${TAP_EXE_DIR}/FAIL_PROG" << 'EOF'
#!/bin/bash
echo "FAIL_PROG running — about to fail"
exit 1
EOF
chmod +x "${TAP_EXE_DIR}/FAIL_PROG"

# Create a script with .sh extension
cat > "${TAP_EXE_DIR}/SCRIPT_PROG.sh" << 'EOF'
#!/bin/bash
echo "SCRIPT_PROG.sh running"
exit 0
EOF
chmod +x "${TAP_EXE_DIR}/SCRIPT_PROG.sh"
```

---

## 2. Test Cases

### TC-01: Successful execution with all parameters

**Purpose:** Verify the golden path — all parameters provided, program exists, runs successfully.

```bash
./tap_job_startup.sh TEST 01 TEST_PROG
echo "Exit code: $?"
# Expected: 0
# Log should show: TAP_TEST_01 started, executing, completed successfully
cat "${TAP_LOG_DIR}/tap_job_startup.log"
```

**Expected output:**
```
<timestamp> - TAP_TEST_01 started (PID <pid>)
<timestamp> - TAP_TEST_01 executing: /tmp/tap_test/exe/TEST_PROG
<timestamp> - TAP_TEST_01 completed successfully
```

---

### TC-02: Missing parameter P1

```bash
./tap_job_startup.sh "" 01 TEST_PROG
echo "Exit code: $?"
# Expected: 1
# Log should show error about missing parameter
```

---

### TC-03: Missing parameter P2

```bash
./tap_job_startup.sh TEST "" TEST_PROG
echo "Exit code: $?"
# Expected: 1
```

---

### TC-04: Missing parameter P3

```bash
./tap_job_startup.sh TEST 01 ""
echo "Exit code: $?"
# Expected: 1
```

---

### TC-05: No parameters at all

```bash
./tap_job_startup.sh
echo "Exit code: $?"
# Expected: 1
# Error: "Parameter must be provided"
```

---

### TC-06: Program not found in TAP_EXE_DIR

```bash
./tap_job_startup.sh TEST 01 NONEXISTENT_PROG
echo "Exit code: $?"
# Expected: 1
# Error: "NONEXISTENT_PROG unavailable in <path>"
```

---

### TC-07: Program fails (non-zero exit)

```bash
./tap_job_startup.sh TEST 01 FAIL_PROG
echo "Exit code: $?"
# Expected: 1
# Error: "Error returned from program FAIL_PROG (exit code 1)"
```

---

### TC-08: Singleton enforcement (duplicate prevention)

```bash
# Terminal 1: Start a long-running program
cat > "${TAP_EXE_DIR}/LONG_PROG" << 'EOF'
#!/bin/bash
echo "LONG_PROG started — sleeping 60 seconds"
sleep 60
EOF
chmod +x "${TAP_EXE_DIR}/LONG_PROG"

# Run first instance in background
./tap_job_startup.sh TEST 01 LONG_PROG &
PID1=$!
sleep 1

# Terminal 2: Try to start same process type + instance
./tap_job_startup.sh TEST 01 LONG_PROG
echo "Exit code: $?"
# Expected: 1
# Error: "Process name cannot be set — TAP_TEST_01 is already running"

# Clean up
kill $PID1 2>/dev/null
```

---

### TC-09: Different instances can run simultaneously

```bash
./tap_job_startup.sh TEST 01 TEST_PROG &
./tap_job_startup.sh TEST 02 TEST_PROG &
wait
echo "Both completed"
# Expected: Both succeed — different lock files (TAP_TEST_01.lock vs TAP_TEST_02.lock)
```

---

### TC-10: Closedown flag cleanup

```bash
# Create a closedown flag before running
touch "${TAP_CLOSEDOWN_DIR}/TAP_TEST_01_CLOSEDOWN"
ls "${TAP_CLOSEDOWN_DIR}"
# Should show: TAP_TEST_01_CLOSEDOWN

./tap_job_startup.sh TEST 01 TEST_PROG
ls "${TAP_CLOSEDOWN_DIR}"
# Should be empty — flag was cleaned up
```

---

### TC-11: Program found with .sh extension

```bash
./tap_job_startup.sh TEST 01 SCRIPT_PROG
echo "Exit code: $?"
# Expected: 0
# Script should find SCRIPT_PROG.sh
```

---

### TC-12: TAP_EXE_DIR not set (uses default)

```bash
unset TAP_EXE_DIR
./tap_job_startup.sh TEST 01 TEST_PROG
echo "Exit code: $?"
# Expected: 1 (unless default /data/call_data/tap/exe exists with the program)
```

---

### TC-13: Lock file cleanup after normal exit

```bash
./tap_job_startup.sh TEST 01 TEST_PROG
ls /tmp/TAP_TEST_01.lock 2>/dev/null
# Lock file may exist but lock is released
# Verify a new instance can start immediately
./tap_job_startup.sh TEST 01 TEST_PROG
echo "Exit code: $?"
# Expected: 0
```

---

### TC-14: GAPS-style invocation (as called by TAP_MONITOR)

```bash
# Simulate how TAP_MONITOR calls this script
cat > "${TAP_EXE_DIR}/GAPS_PROC" << 'EOF'
#!/bin/bash
echo "GAPS processing started at $(date)"
sleep 3
echo "GAPS processing completed at $(date)"
exit 0
EOF
chmod +x "${TAP_EXE_DIR}/GAPS_PROC"

nohup ./tap_job_startup.sh GAPS 01 GAPS_PROC >> "${TAP_LOG_DIR}/tap_gaps_01.log" 2>&1 &
wait $!
echo "GAPS job exit code: $?"
cat "${TAP_LOG_DIR}/tap_gaps_01.log"
```

---

### TC-15: GSDM-style invocation

```bash
cat > "${TAP_EXE_DIR}/GSDM_PROC" << 'EOF'
#!/bin/bash
echo "GSDM processing started at $(date)"
sleep 2
echo "GSDM processing completed at $(date)"
exit 0
EOF
chmod +x "${TAP_EXE_DIR}/GSDM_PROC"

nohup ./tap_job_startup.sh GSDM 01 GSDM_PROC >> "${TAP_LOG_DIR}/tap_gsdm_01.log" 2>&1 &
wait $!
echo "GSDM job exit code: $?"
```

---

## 3. Expected Outputs

### Log Format

All log entries follow the standard TAP format:
```
DD-Mon-YYYY HH:MM:SS - <message>
```

### Success Log Example
```
25-Mar-2026 10:30:00 - TAP_GAPS_01 started (PID 12345)
25-Mar-2026 10:30:00 - TAP_GAPS_01 executing: /data/call_data/tap/exe/GAPS_PROC
25-Mar-2026 10:30:05 - TAP_GAPS_01 completed successfully
```

### Error Log Example
```
25-Mar-2026 10:30:00 - TAP_TEST_01 started (PID 12345)
25-Mar-2026 10:30:00 -  *** TAP_TEST_01 - MAIN, NONEXISTENT unavailable in /data/call_data/tap/exe
25-Mar-2026 10:30:00 - ALERT: TAP_TEST_01 - MAIN, NONEXISTENT unavailable in /data/call_data/tap/exe
```

### Syslog Entry (via logger)
```
Mar 25 10:30:00 hostname TAP_TEST_01: ALERT: TAP_TEST_01 - MAIN, ...
```

---

# PART 6 — Run Guide

## How to Run the Script

### Direct Execution

```bash
# Make executable
chmod +x tap_job_startup.sh

# Run with three mandatory parameters
./tap_job_startup.sh <PROCESS_TYPE> <INSTANCE> <PROGRAM>
```

### As a Background Job (how TAP_MONITOR calls it)

```bash
nohup /data/call_data/tap/com/tap_job_startup.sh GAPS 01 GAPS_PROC \
    >> /data/call_data/tap/log/tap_gaps_01.log 2>&1 &
```

### Parameters

| Parameter | Position | Required | Description | Example Values |
|-----------|----------|----------|-------------|----------------|
| PROCESS_TYPE | $1 | **Yes** | Type of TAP process | `GAPS`, `GSDM`, `TEST` |
| INSTANCE | $2 | **Yes** | Instance number | `01`, `02` |
| PROGRAM | $3 | **Yes** | Name of executable to run | `GAPS_PROC`, `GSDM_PROC` |

The process identity becomes `TAP_<PROCESS_TYPE>_<INSTANCE>` (e.g., `TAP_GAPS_01`).

## Required Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TAP_EXE_DIR` | **Yes** | `/data/call_data/tap/exe` | Directory containing executables |
| `TAP_LOG_DIR` | Recommended | `/data/call_data/tap/log` | Directory for log files |
| `TAP_COM_DIR` | Optional | `/data/call_data/tap/com` | Directory for scripts |
| `TAP_CLOSEDOWN_DIR` | Optional | `/data/call_data/tap/closedown` | Directory for closedown flag files |

### Setting Up Environment

```bash
# Add to /etc/profile.d/tap_env.sh or ~/.bashrc
export TAP_EXE_DIR="/data/call_data/tap/exe"
export TAP_COM_DIR="/data/call_data/tap/com"
export TAP_LOG_DIR="/data/call_data/tap/log"
export TAP_CLOSEDOWN_DIR="/data/call_data/tap/closedown"
```

## Example Execution

### Example 1: Run GAPS job

```bash
export TAP_EXE_DIR="/data/call_data/tap/exe"
export TAP_LOG_DIR="/data/call_data/tap/log"
export TAP_CLOSEDOWN_DIR="/data/call_data/tap/closedown"

./tap_job_startup.sh GAPS 01 GAPS_PROC
```

### Example 2: Run from TAP_MONITOR (automated)

The script is designed to be called by `tap_monitor.sh`:

```bash
# Inside tap_monitor.sh — check_gaps() function:
nohup "${TAP_COM_DIR}/tap_job_startup.sh" "GAPS" "01" "${GAPN}" \
    >> "${TAP_LOG_DIR}/tap_gaps_01.log" 2>&1 &
```

## How to Stop It Safely

### Option 1: Create a closedown flag (graceful)

This doesn't stop `tap_job_startup.sh` itself (it's short-lived), but signals the running program if it checks for closedown:

```bash
touch /data/call_data/tap/closedown/TAP_GAPS_01_CLOSEDOWN
```

The target program should check for this file. When `tap_job_startup.sh` finishes running the program, it automatically removes this flag.

### Option 2: Kill the process

```bash
# Find the process
ps aux | grep "tap_job_startup.sh GAPS 01"

# Kill it
kill <PID>
```

### Option 3: Remove the lock file (after process terminated abnormally)

If the process died without cleaning up:

```bash
rm -f /tmp/TAP_GAPS_01.lock
```

---

# Appendix A — VMS Script Annotated Walkthrough

For readers who want to understand what each VMS line does, here is a line-by-line annotation:

```dcl
$! ---- STARTING PHASE ----
$  phase = "STARTING"              !! Track which section we're in (for error messages)
$  on warning then goto error      !! If ANY command produces a warning or error, jump to error handler

$! ---- GLOBAL SYMBOLS ----
$  verify = f$verify(0)            !! Turn off command echo, but save old state
$  bell[0,32] == %D7               !! Define ASCII BEL character (terminal beep)
$  wo == "write sys$output"        !! Shorthand: wo = print to screen
$  operator== "oper8"              !! Operator terminal name
$  status == ""                    !! Global status variable (empty = no error)

$! ---- SAVE ENVIRONMENT ----
$  proc = f$environment("PROCEDURE")  !! Get full path to this script
$  procname = f$getjpi("","PRCNAM")   !! Get current process name

$! Check if running interactively (from a terminal) or in batch (submitted job)
$  if f$mode() .eqs. "INTERACTIVE" then ...
$!   Save terminal settings so we can restore them later

$! ---- PARAMETER VALIDATION ----
$  if p1 .eqs. "" .or. p2 .eqs. "" .or. p3 .eqs. "" then goto error
$!   All three params are required: P1=type, P2=instance, P3=program

$! ---- SINGLETON: SET PROCESS NAME ----
$  set process/name="TAP_''p1'_''p2'"
$!   Rename this process. VMS enforces unique names per node.
$!   If another process already has this name → failure → error

$! ---- MAIN: FIND AND RUN PROGRAM ----
$  if f$search("tap_exe_dir:''p3'.exe") .eqs. "" then goto error
$!   Check if the executable exists in the TAP exe directory

$  run tap_exe_dir:'p3'
$!   Actually run the program. This BLOCKS until the program finishes.

$  mylog = f$process() + "_CLOSEDOWN"
$  if f$trnlnm(mylog) .nes. "" then deassign/group &mylog
$!   Clean up: if someone defined a closedown logical for us, remove it

$! ---- ERROR HANDLER ----
$  @tap_com_dir:taplog_mess " ***" "''procname' - ''phase', ''error_text'" " "
$!   Log the error to the TAP log file
$  request/to='operator' "''procname' - ''phase', ''error_text'"
$!   Send message to operator console

$! ---- EXIT: RESTORE ENVIRONMENT ----
$  if f$mode() .eqs. "INTERACTIVE" then ...
$!   Restore terminal settings (broadcast, messages, default directory)
$  exit
```

---

# Appendix B — File Listing

| File | Type | Description |
|------|------|-------------|
| `TAP_JOB_STARTUP.COM` | VMS DCL | Original VMS source |
| `converted/tap_job_startup.sh` | Bash | Linux conversion |
| `converted/TAP_JOB_STARTUP_MIGRATION_DOCUMENT.md` | Documentation | This document |
