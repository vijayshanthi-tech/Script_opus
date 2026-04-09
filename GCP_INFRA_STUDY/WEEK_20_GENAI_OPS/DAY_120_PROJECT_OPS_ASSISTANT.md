# Week 20, Day 120 (Sat) — PROJECT: Ops Automation Assistant

## Today's Objective

Bring together everything from Week 20 into a practical project: build an "Ops Automation Assistant" — a structured set of scripts, prompt templates, and workflows that use GenAI to accelerate day-to-day GCP operations tasks.

**Source:** [Vertex AI Gemini](https://cloud.google.com/vertex-ai/generative-ai/docs/overview) | [SRE Workbook](https://sre.google/workbook/table-of-contents/)

**Deliverable:** A complete ops-assistant toolkit with data gatherers, prompt templates, and a usage workflow

---

## Part 1: Concept (30 minutes)

### 1.1 The Ops Assistant Architecture

```
┌────────────────────────────────────────────────────────────┐
│                  OPS AUTOMATION ASSISTANT                     │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ Data Gather  │  │   Prompt     │  │   AI Engine      │  │
│  │              │  │   Library    │  │                  │  │
│  │ gcloud logs  │──►│ Templates   │──►│ Vertex AI       │  │
│  │ gcloud iam   │  │ Variables    │  │ Gemini          │  │
│  │ billing data │  │ Examples     │  │                  │  │
│  └──────────────┘  └──────────────┘  └───────┬──────────┘  │
│                                               │              │
│                                               ▼              │
│                                      ┌──────────────────┐   │
│                                      │  Human Review    │   │
│                                      │                  │   │
│                                      │ Verify → Edit    │   │
│                                      │ → Approve → Use  │   │
│                                      └──────────────────┘   │
└────────────────────────────────────────────────────────────┘
```

### 1.2 Toolkit Components

```
ops-assistant/
├── README.md                      ← Toolkit overview and usage guide
├── gather/                        ← Data collection scripts
│   ├── gather_logs.sh             ← Collect logs for analysis
│   ├── gather_incident_data.sh    ← Collect all data for RCA
│   ├── gather_iam_policy.sh       ← Export IAM policy
│   └── gather_billing.sh          ← Export billing data
│
├── prompts/                       ← Prompt templates (from DAY_119)
│   ├── monitoring/
│   ├── incident-response/
│   ├── infrastructure/
│   ├── security/
│   └── cost/
│
├── templates/                     ← Output templates
│   ├── rca_template.md
│   ├── runbook_template.md
│   └── review_template.md
│
└── workflows/                     ← End-to-end workflows
    ├── incident_workflow.md
    ├── weekly_review_workflow.md
    └── terraform_review_workflow.md
```

### 1.3 Workflow Map

| Scenario | Gather Script | Prompt | Output |
|---|---|---|---|
| Alert triage | `gather_logs.sh` | `monitoring/alert-analysis.md` | Triage assessment |
| Post-incident RCA | `gather_incident_data.sh` | `incident-response/rca-summariser.md` | RCA document |
| New runbook | Past incidents | `incident-response/runbook-builder.md` | Runbook draft |
| TF code review | PR diff | `infrastructure/terraform-review.md` | Review comments |
| Quarterly IAM audit | `gather_iam_policy.sh` | `security/iam-audit.md` | Audit findings |
| Monthly cost review | `gather_billing.sh` | `cost/cost-analysis.md` | Cost report |

### 1.4 Safety Guardrails

```
BEFORE AI:
  ┌─────────────────────────────┐
  │  1. Strip PII               │
  │  2. Strip secrets           │
  │  3. Verify org policy allows│
  │  4. Use Vertex AI only      │
  └─────────────────────────────┘

AFTER AI:
  ┌─────────────────────────────┐
  │  1. Verify facts            │
  │  2. Check commands work     │
  │  3. Add institutional info  │
  │  4. Get peer review         │
  └─────────────────────────────┘
```

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create the Ops Assistant Toolkit (15 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)

mkdir -p ops-assistant/{gather,prompts/{monitoring,incident-response,infrastructure,security,cost},templates,workflows}
cd ops-assistant

cat > README.md <<'EOF'
# Ops Automation Assistant

AI-powered toolkit for accelerating GCP operations tasks.

## Quick Start

### 1. Gather Data
```bash
# For log analysis
./gather/gather_logs.sh PROJECT_ID 1h

# For incident RCA
./gather/gather_incident_data.sh PROJECT_ID START_TIME END_TIME

# For IAM audit
./gather/gather_iam_policy.sh PROJECT_ID
```

### 2. Choose the Right Prompt
| I need to... | Use this prompt |
|---|---|
| Understand why alerts fired | `prompts/monitoring/log-summary.md` |
| Write a post-mortem | `prompts/incident-response/rca-summariser.md` |
| Create a new runbook | `prompts/incident-response/runbook-builder.md` |
| Review Terraform changes | `prompts/infrastructure/terraform-review.md` |
| Audit IAM permissions | `prompts/security/iam-audit.md` |
| Analyse cloud costs | `prompts/cost/cost-analysis.md` |

### 3. Use the Data + Prompt
1. Open the prompt template
2. Fill in the `{variables}` with your gathered data
3. Use with Vertex AI Gemini (data stays in GCP)
4. **Always review AI output before acting on it**

### 4. Safety Rules
- ⚠️ Strip PII and secrets before sending to AI
- ⚠️ Use only Vertex AI (approved internal AI tools)
- ⚠️ Verify all commands before running in production
- ⚠️ Add team-specific context that AI can't know
EOF
```

### Step 2: Create Data Gathering Scripts (15 min)

```bash
cat > gather/gather_logs.sh <<'SCRIPT'
#!/bin/bash
# Gather Cloud Logging entries for AI analysis
# Usage: ./gather_logs.sh <PROJECT_ID> <FRESHNESS> [SEVERITY]
set -euo pipefail

PROJECT_ID="${1:?Usage: $0 <PROJECT_ID> <FRESHNESS> [SEVERITY=WARNING]}"
FRESHNESS="${2:?Provide freshness, e.g., 1h, 24h, 7d}"
SEVERITY="${3:-WARNING}"

OUTPUT="logs_$(date +%Y%m%d_%H%M%S).txt"

echo "Gathering logs: project=${PROJECT_ID}, freshness=${FRESHNESS}, severity>=${SEVERITY}"

gcloud logging read "severity>=${SEVERITY}" \
  --project="${PROJECT_ID}" \
  --freshness="${FRESHNESS}" \
  --limit=100 \
  --format="table(
    timestamp,
    severity,
    resource.type,
    resource.labels.instance_id,
    protoPayload.methodName,
    textPayload
  )" > "${OUTPUT}"

LINES=$(wc -l < "${OUTPUT}")
echo "Saved ${LINES} lines to ${OUTPUT}"
echo ""
echo "Next: Use with prompts/monitoring/log-summary.md"
SCRIPT
chmod +x gather/gather_logs.sh

cat > gather/gather_iam_policy.sh <<'SCRIPT'
#!/bin/bash
# Gather IAM policy for security audit
# Usage: ./gather_iam_policy.sh <PROJECT_ID>
set -euo pipefail

PROJECT_ID="${1:?Usage: $0 <PROJECT_ID>}"
OUTPUT_DIR="iam_audit_$(date +%Y%m%d)"
mkdir -p "${OUTPUT_DIR}"

echo "=== Gathering IAM data for ${PROJECT_ID} ==="

# Full IAM policy
echo "Exporting IAM policy..."
gcloud projects get-iam-policy "${PROJECT_ID}" \
  --format=json > "${OUTPUT_DIR}/policy.json"

# Members with broad roles
echo "Finding broad roles..."
for ROLE in roles/owner roles/editor; do
  echo "=== ${ROLE} ===" >> "${OUTPUT_DIR}/broad_roles.txt"
  gcloud projects get-iam-policy "${PROJECT_ID}" \
    --flatten="bindings[].members" \
    --filter="bindings.role:${ROLE}" \
    --format="value(bindings.members)" >> "${OUTPUT_DIR}/broad_roles.txt" 2>&1
  echo "" >> "${OUTPUT_DIR}/broad_roles.txt"
done

# Service accounts
echo "Listing service accounts..."
gcloud iam service-accounts list \
  --project="${PROJECT_ID}" \
  --format="table(email, displayName, disabled)" > "${OUTPUT_DIR}/service_accounts.txt"

# SA keys
echo "Checking for user-managed keys..."
> "${OUTPUT_DIR}/sa_keys.txt"
for SA in $(gcloud iam service-accounts list --project="${PROJECT_ID}" --format="value(email)" 2>/dev/null); do
  KEYS=$(gcloud iam service-accounts keys list \
    --iam-account="${SA}" \
    --filter="keyType=USER_MANAGED" \
    --format="value(name)" 2>/dev/null | wc -l)
  if [ "${KEYS}" -gt "0" ]; then
    echo "WARNING: ${SA} has ${KEYS} user-managed key(s)" >> "${OUTPUT_DIR}/sa_keys.txt"
  fi
done

echo ""
echo "=== Output: ${OUTPUT_DIR}/ ==="
ls -la "${OUTPUT_DIR}/"
echo ""
echo "Next: Use with prompts/security/iam-audit.md"
SCRIPT
chmod +x gather/gather_iam_policy.sh

cat > gather/gather_incident_data.sh <<'SCRIPT'
#!/bin/bash
# Gather all relevant data for incident RCA
# Usage: ./gather_incident_data.sh <PROJECT_ID> <START_TIME> <END_TIME>
set -euo pipefail

PROJECT_ID="${1:?Usage: $0 <PROJECT_ID> <START_TIME> <END_TIME>}"
START_TIME="${2:?e.g., 2026-04-08T14:00:00Z}"
END_TIME="${3:?e.g., 2026-04-08T15:00:00Z}"

OUTPUT_DIR="incident_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUTPUT_DIR}"

echo "=== Incident Data Gathering ==="
echo "Project: ${PROJECT_ID}"
echo "Window: ${START_TIME} to ${END_TIME}"

# Error logs
echo "1/4 Gathering error logs..."
gcloud logging read "
  severity>=ERROR AND
  timestamp>=\"${START_TIME}\" AND
  timestamp<=\"${END_TIME}\"
" --project="${PROJECT_ID}" \
  --format="table(timestamp, severity, resource.type, protoPayload.methodName, textPayload)" \
  --limit=200 > "${OUTPUT_DIR}/errors.txt" 2>&1

# Admin activity
echo "2/4 Gathering admin activity..."
gcloud logging read "
  logName=~\"activity\" AND
  timestamp>=\"${START_TIME}\" AND
  timestamp<=\"${END_TIME}\"
" --project="${PROJECT_ID}" \
  --format="table(timestamp, protoPayload.authenticationInfo.principalEmail, protoPayload.methodName)" \
  --limit=100 > "${OUTPUT_DIR}/admin_activity.txt" 2>&1

# Permission denied
echo "3/4 Gathering permission denied events..."
gcloud logging read "
  protoPayload.status.code=7 AND
  timestamp>=\"${START_TIME}\" AND
  timestamp<=\"${END_TIME}\"
" --project="${PROJECT_ID}" \
  --format="table(timestamp, protoPayload.authenticationInfo.principalEmail, protoPayload.methodName, protoPayload.status.message)" \
  --limit=100 > "${OUTPUT_DIR}/permission_denied.txt" 2>&1

# All activity (for timeline)
echo "4/4 Gathering full timeline..."
gcloud logging read "
  timestamp>=\"${START_TIME}\" AND
  timestamp<=\"${END_TIME}\"
" --project="${PROJECT_ID}" \
  --format="table(timestamp, severity, resource.type, protoPayload.methodName)" \
  --limit=500 > "${OUTPUT_DIR}/full_timeline.txt" 2>&1

echo ""
echo "=== Output: ${OUTPUT_DIR}/ ==="
ls -la "${OUTPUT_DIR}/"
echo ""
echo "REMEMBER: Review for PII/secrets before using with AI"
echo "Next: Use with prompts/incident-response/rca-summariser.md"
SCRIPT
chmod +x gather/gather_incident_data.sh
```

### Step 3: Create Output Templates (10 min)

```bash
cat > templates/rca_template.md <<'EOF'
# RCA-{YEAR}-{NUMBER}: {TITLE}

**Incident ID:** {INC_ID}
**Date:** {DATE}
**Duration:** {DURATION}
**Severity:** {SEV_LEVEL}
**Status:** Resolved

---

## 1. Executive Summary
{AI: 3-4 sentences, then human review}

## 2. Impact Assessment
| Metric | Value |
|---|---|
| Duration | |
| Users affected | |
| Data loss | |
| SLO budget consumed | |

## 3. Timeline
| Time (UTC) | Event | Source |
|---|---|---|
| | | |

## 4. Root Cause Analysis
**Five Whys:**
1. Why? →
2. Why? →
3. Why? →
4. Why? →
5. Why? →

**Root Cause:** {one sentence}

## 5. Contributing Factors
- {factor 1}
- {factor 2}

## 6. Resolution
```bash
# Commands used to fix
```

## 7. Detection
- Detected by:
- Time to detect:
- Improvement:

## 8. Action Items
| Priority | Action | Owner | Deadline |
|---|---|---|---|
| P0 | | [TODO] | |
| P1 | | [TODO] | |
| P2 | | [TODO] | |

## 9. Lessons Learned
**Went well:** {what worked}
**Improve:** {what to improve}
EOF

cat > templates/runbook_template.md <<'EOF'
# Runbook: {TITLE}

**Last Updated:** {DATE} | **Owner:** {TEAM} | **Review:** Quarterly

## Overview
{2-3 sentences}

## Trigger
- Alert: {alert name and condition}

## Prerequisites
- [ ] {role/access needed}
- [ ] {tools needed}

## Quick Assessment (2 min)
```bash
export PROJECT_ID="YOUR_PROJECT"
# First commands to understand the situation
```

## Diagnosis (10 min)
```bash
# Systematic investigation
```

## Remediation
### Option A: {Quick fix}
```bash
# ⚠️ WARNING if destructive
```

### Option B: {Permanent fix}
```bash
```

## Verification (5 min)
```bash
# Confirm the fix worked
```

## Escalation
- [TODO: Primary contact]
- [TODO: Secondary contact]

## Prevention
1. {Long-term fix 1}
2. {Long-term fix 2}
EOF
```

### Step 4: Create Workflow Documents (10 min)

```bash
cat > workflows/incident_workflow.md <<'EOF'
# Incident Response Workflow with AI

## During the Incident

| Step | Action | Tool |
|---|---|---|
| 1. Acknowledge | Acknowledge the alert | PagerDuty / Monitoring |
| 2. Assess | Run quick assessment from runbook | Existing runbook |
| 3. Gather logs | `./gather/gather_logs.sh PROJECT 1h` | Gather script |
| 4. AI triage | Feed logs into `prompts/monitoring/alert-analysis.md` | Vertex AI |
| 5. Fix | Apply remediation from runbook or AI suggestion | gcloud CLI |
| 6. Verify | Confirm fix with monitoring | Cloud Console |

## After the Incident (within 48h)

| Step | Action | Tool |
|---|---|---|
| 1. Gather data | `./gather/gather_incident_data.sh PROJECT START END` | Gather script |
| 2. Redact | Remove PII/secrets from gathered data | Manual review |
| 3. AI draft RCA | Feed data into `prompts/incident-response/rca-summariser.md` | Vertex AI |
| 4. Review | Verify timeline, root cause, action items | Human review |
| 5. Add context | Fill in escalation, team contacts, institutional knowledge | Human |
| 6. Publish | Share with team, file in incident tracker | Wiki / Jira |

## If No Runbook Exists

| Step | Action | Tool |
|---|---|---|
| 1. | After resolving, gather incident notes | Post-mortem |
| 2. | Feed into `prompts/incident-response/runbook-builder.md` | Vertex AI |
| 3. | Review generated runbook, add team-specific info | Human |
| 4. | Submit PR to runbook repo | Git |
EOF

cat > workflows/weekly_review_workflow.md <<'EOF'
# Weekly Operations Review Workflow

## Monday Review (30 min)

### 1. Gather Data (10 min)
```bash
# Last week's errors
./gather/gather_logs.sh PROJECT_ID 7d ERROR
# IAM changes (if quarterly review)
./gather/gather_iam_policy.sh PROJECT_ID
```

### 2. AI Summary (10 min)
- Feed 7-day logs into `prompts/monitoring/log-summary.md`
- Ask AI to identify trends and recurring issues

### 3. Team Discussion (10 min)
- Review AI summary as a starting point
- Discuss any incidents from last week
- Prioritise action items for this week

## Quarterly IAM Review (60 min)

### 1. Gather IAM Data
```bash
./gather/gather_iam_policy.sh PROJECT_ID
```

### 2. AI Audit
- Feed policy.json into `prompts/security/iam-audit.md`

### 3. Review Findings
- Verify AI findings
- Create tickets for remediation
- Update access documentation
EOF
```

### Step 5: Verify the Toolkit (5 min)

```bash
echo "=== Ops Assistant Toolkit ==="
echo ""
find . -type f | sort | head -30
echo ""
echo "=== Gather scripts ==="
ls -la gather/
echo ""
echo "=== Prompt templates ==="
find prompts/ -name "*.md" | sort
echo ""
echo "=== Templates ==="
ls templates/
echo ""
echo "=== Workflows ==="
ls workflows/
```

### Step 6: Clean Up (5 min)

```bash
cd ~
# To keep the toolkit:
# mv ops-assistant ~/my-project/
# cd ops-assistant && git init && git add . && git commit -m "Initial ops assistant toolkit"

# To clean up:
rm -rf ops-assistant
echo "Toolkit cleaned up. Recreate from the lab steps when ready to use."
```

---

## Part 3: Revision (15 minutes)

- **Ops Assistant** — data gatherers + prompt library + output templates + workflows
- **Workflow pattern** — gather → redact → prompt → AI output → human review → publish
- **Safety** — strip PII/secrets, use Vertex AI only, always verify AI output
- **Data gatherers** — `gather_logs.sh`, `gather_incident_data.sh`, `gather_iam_policy.sh`
- **Output templates** — standardised RCA, runbook, and review formats
- **Team sharing** — version-controlled repo, weekly reviews, quarterly audits

### Toolkit Summary
```
gather/          → Collect data from GCP APIs
prompts/         → Categorised prompt templates
templates/       → Standard output document formats
workflows/       → Step-by-step usage procedures
```

---

## Part 4: Quiz (15 minutes)

**Q1:** What's the most important step between "AI generates output" and "team uses output"?
<details><summary>Answer</summary><b>Human review.</b> AI-generated content must be verified before use because: 1) AI can hallucinate facts (wrong timestamps, non-existent commands), 2) AI lacks institutional knowledge (team contacts, escalation paths, internal tools), 3) AI may miss business context (this service is critical for compliance, that team is on leave). The review should check: factual accuracy, command correctness, appropriate severity assessment, and complete action items. Like code review — don't merge without review.</details>

**Q2:** You're building this toolkit for a team of 10 engineers. How do you drive adoption?
<details><summary>Answer</summary>
1. <b>Start small</b> — introduce one workflow (e.g., post-incident RCA) and prove it saves time<br>
2. <b>Show the time savings</b> — "RCA took 2h manually, 30min with the toolkit"<br>
3. <b>Make it easy</b> — copy-paste scripts, clear README, worked examples<br>
4. <b>Integrate into existing process</b> — add to incident response checklist, not a separate tool<br>
5. <b>Iterate based on feedback</b> — ask "what was wrong with the AI output?" and improve prompts<br>
6. <b>Champion</b> — have one enthusiastic team member demo it regularly
</details>

**Q3:** The `gather_incident_data.sh` script collects sensitive production logs. What safeguards are needed?
<details><summary>Answer</summary>
1. <b>Access control</b> — only on-call/incident responders can run the script (IAM roles)<br>
2. <b>Output security</b> — files are written locally; don't commit to git or share publicly<br>
3. <b>Redaction step</b> — review output for PII/secrets before feeding to AI<br>
4. <b>Auto-cleanup</b> — add a cleanup step or TTL to delete gathered data after RCA is complete<br>
5. <b>Audit trail</b> — the gcloud commands generate audit logs showing who queried what<br>
6. <b>Approved AI only</b> — only use gathered data with Vertex AI (not public AI tools)
</details>

**Q4:** Looking back at Weeks 17-20, what are the three most impactful practices for a GCP infrastructure engineer?
<details><summary>Answer</summary>
1. <b>Infrastructure as Code with best practices</b> (Week 17) — version-controlled, modular, linted Terraform with remote state and least-privilege IAM. This prevents a whole class of incidents.<br>
2. <b>SRE Monitoring with SLOs</b> (Week 18) — SLI/SLO-based monitoring with error budgets provides objective signals for when to prioritise reliability vs features. Golden signals dashboards catch issues early.<br>
3. <b>Systematic IAM troubleshooting</b> (Week 19) — understanding the 403 evaluation flow, impersonation over keys, and audit logging. IAM is the #1 source of "it doesn't work" in GCP. Having a diagnostic framework saves hours of guesswork.
</details>

---

## 🎉 Congratulations!

You've completed the GCP Infrastructure Study Plan — 120 days of hands-on learning covering compute, networking, monitoring, Terraform, security, IAM, and AI-assisted operations. Keep practising and building!
