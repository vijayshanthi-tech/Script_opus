# Week 20, Day 118 (Thu) — RCA Summariser Prompt Template

## Today's Objective

Build a reusable AI prompt template for Root Cause Analysis (RCA) summarisation. Convert verbose incident data, logs, and timeline entries into structured, actionable RCA documents that follow SRE post-mortem standards.

**Source:** [Google SRE — Postmortem Culture](https://sre.google/sre-book/postmortem-culture/) | [Blameless Postmortems](https://sre.google/workbook/postmortem-culture/)

**Deliverable:** A complete RCA prompt template with examples, plus a script to gather incident data for AI analysis

---

## Part 1: Concept (30 minutes)

### 1.1 The RCA Challenge

```
Linux analogy:

Reading through /var/log/messages   ──►    Reading Cloud Logging entries
  + /var/log/auth.log                       + Monitoring alerts
  + /var/log/nginx/error.log                + Deployment logs
  + dmesg output                            + Terraform plan output
  + network captures                        + VPC flow logs
  = INFORMATION OVERLOAD                    = INFORMATION OVERLOAD

Senior admin writes incident report  ──►   AI drafts RCA from same data
  - 2 hours of writing                      - 10 minutes of review
  - Might miss correlations                 - Might hallucinate details
  - Deep institutional knowledge            - Consistent format every time
```

### 1.2 RCA Document Structure

```
┌──────────────────────────────────────────────────────┐
│                  RCA DOCUMENT                          │
│                                                       │
│  1. SUMMARY          ← What happened (2 sentences)    │
│  2. IMPACT           ← Who was affected, how badly    │
│  3. TIMELINE         ← Minute-by-minute events        │
│  4. ROOT CAUSE       ← The actual underlying cause    │
│  5. CONTRIBUTING     ← Factors that made it worse     │
│  6. RESOLUTION       ← What fixed it                  │
│  7. DETECTION        ← How was it discovered          │
│  8. ACTION ITEMS     ← What we'll do to prevent it    │
│  9. LESSONS LEARNED  ← What we learned                │
│  10. APPENDIX        ← Raw data, links, logs          │
└──────────────────────────────────────────────────────┘
```

### 1.3 Five Whys Technique

```
Problem: Production API returned 500 errors

Why 1: The API server couldn't connect to Cloud SQL
Why 2: Cloud SQL was out of connections (max 100)
Why 3: A migration job opened 200 connections without pooling
Why 4: The migration script had no connection limit parameter
Why 5: The migration script was not reviewed for production readiness

Root Cause: Missing production readiness review for migration scripts
Contributing: No connection pooling, no connection limit alert
```

### 1.4 AI's Role in RCA

| RCA Element | AI Strength | Human Required |
|---|---|---|
| **Timeline** | Excellent — extracts from logs | Verify accuracy |
| **Impact** | Good — counts errors, affected users | Business impact assessment |
| **Root cause** | Decent — suggests likely causes | Verify with evidence |
| **Contributing factors** | Good — identifies correlations | Judge relevance |
| **Action items** | Good — suggests generic fixes | Prioritise, assign owners |
| **Lessons learned** | Weak — too generic | Deep institutional insights |
| **Blame** | N/A — should be blameless | Ensure blameless culture |

### 1.5 Data Gathering for AI

```
INPUT DATA (gather before prompting):

1. Alert history    → Monitoring console export
2. Audit logs       → gcloud logging read (IAM + admin changes)
3. Error logs       → gcloud logging read (severity>=ERROR)
4. Deployment logs  → CI/CD pipeline history
5. Metrics          → Dashboard screenshots / data export
6. Slack/comms      → Incident channel timeline
7. Status page      → User-facing communications

The more context you feed the AI, the better the RCA.
But: strip PII and secrets first!
```

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create the RCA Prompt Template (15 min)

```bash
mkdir -p genai-rca-lab && cd genai-rca-lab

cat > prompt_rca_summariser.md <<'PROMPT'
# RCA Summariser Prompt Template

## System Prompt

You are an SRE writing a blameless post-mortem / Root Cause Analysis document.
Your writing should be:
- Factual and evidence-based (cite timestamps and log entries)
- Blameless (never name individuals; use roles like "the on-call engineer")
- Actionable (every finding should lead to an action item)
- Concise (busy engineers will read this)
- UK English spelling

## User Prompt Template

Generate a Root Cause Analysis document from the following incident data:

**Incident ID:** {INCIDENT_ID}
**Date:** {DATE}
**Duration:** {DURATION}
**Severity:** {SEVERITY}
**Service affected:** {SERVICE}

### Raw Data

**Alert history:**
```
{PASTE_ALERTS_HERE}
```

**Error logs (from Cloud Logging):**
```
{PASTE_ERROR_LOGS_HERE}
```

**Timeline from incident channel:**
```
{PASTE_TIMELINE_HERE}
```

**Changes deployed in the last 24 hours:**
```
{PASTE_DEPLOYMENT_LOGS_HERE}
```

### Generate the RCA with these sections:

1. **Executive Summary** (3-4 sentences max)
   - What happened, when, impact, current status

2. **Impact Assessment**
   - Users affected (number/percentage)
   - Duration of impact
   - Data loss (if any)
   - SLO budget consumed

3. **Timeline** (table format)
   | Time (UTC) | Event | Source |
   - Include: alert fired, investigation started, root cause identified, fix applied, verified

4. **Root Cause Analysis**
   - Use the Five Whys technique
   - Clearly state the root cause in one sentence
   - Distinguish root cause from contributing factors

5. **Contributing Factors**
   - List factors that made the incident worse or slower to resolve

6. **Resolution**
   - Exact steps taken to fix the issue
   - Include gcloud commands used (if applicable)

7. **Detection**
   - How was the incident detected? (alert, user report, etc.)
   - Could we have detected it sooner?

8. **Action Items** (table format)
   | Priority | Action | Owner | Deadline |
   - P0: Immediate (prevent recurrence)
   - P1: This sprint
   - P2: Next quarter

9. **Lessons Learned**
   - What went well during the response
   - What could be improved

10. **Appendix**
    - Links to dashboards, log queries, related documents
PROMPT

echo "Created: prompt_rca_summariser.md"
```

### Step 2: Build the Incident Data Gatherer (15 min)

```bash
cat > gather_incident_data.sh <<'SCRIPT'
#!/bin/bash
# Incident Data Gatherer — Collects logs for RCA AI analysis
# Usage: ./gather_incident_data.sh <PROJECT_ID> <START_TIME> <END_TIME>

set -euo pipefail

PROJECT_ID="${1:?Usage: $0 <PROJECT_ID> <START_TIME> <END_TIME>}"
START_TIME="${2:?Provide start time, e.g., 2026-04-08T14:00:00Z}"
END_TIME="${3:?Provide end time, e.g., 2026-04-08T15:00:00Z}"

OUTPUT_DIR="incident_data_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUTPUT_DIR}"

echo "=== Gathering incident data ==="
echo "Project: ${PROJECT_ID}"
echo "Window: ${START_TIME} to ${END_TIME}"
echo "Output: ${OUTPUT_DIR}/"
echo ""

# 1. Error logs
echo "Gathering error logs..."
gcloud logging read "
  severity>=ERROR AND
  timestamp>=\"${START_TIME}\" AND
  timestamp<=\"${END_TIME}\"
" --project="${PROJECT_ID}" \
  --format="table(timestamp, severity, resource.type, protoPayload.methodName, textPayload)" \
  --limit=200 \
  > "${OUTPUT_DIR}/error_logs.txt" 2>&1

# 2. IAM / Admin changes
echo "Gathering admin activity..."
gcloud logging read "
  logName=~\"activity\" AND
  timestamp>=\"${START_TIME}\" AND
  timestamp<=\"${END_TIME}\"
" --project="${PROJECT_ID}" \
  --format="table(timestamp, protoPayload.authenticationInfo.principalEmail, protoPayload.methodName, protoPayload.resourceName)" \
  --limit=100 \
  > "${OUTPUT_DIR}/admin_activity.txt" 2>&1

# 3. Permission denied events
echo "Gathering permission denied events..."
gcloud logging read "
  protoPayload.status.code=7 AND
  timestamp>=\"${START_TIME}\" AND
  timestamp<=\"${END_TIME}\"
" --project="${PROJECT_ID}" \
  --format="table(timestamp, protoPayload.authenticationInfo.principalEmail, protoPayload.methodName, protoPayload.status.message)" \
  --limit=100 \
  > "${OUTPUT_DIR}/permission_denied.txt" 2>&1

# 4. Alert incidents (if monitoring API available)
echo "Gathering alert incidents..."
gcloud alpha monitoring policies list \
  --project="${PROJECT_ID}" \
  --format="table(name, displayName, enabled)" \
  > "${OUTPUT_DIR}/alert_policies.txt" 2>&1 || echo "Monitoring API not available" > "${OUTPUT_DIR}/alert_policies.txt"

# 5. Summary
echo ""
echo "=== Data Collection Complete ==="
echo "Files:"
ls -la "${OUTPUT_DIR}/"
echo ""
echo "=== Next Steps ==="
echo "1. Review the files for PII/secrets"
echo "2. Redact any sensitive information"
echo "3. Feed into the RCA prompt template"
echo "4. Review AI-generated RCA and add institutional context"

SCRIPT
chmod +x gather_incident_data.sh
echo "Created: gather_incident_data.sh"
```

### Step 3: Create a Sample RCA (worked example) (15 min)

```bash
cat > example_rca.md <<'EOF'
# RCA-2026-042: Cloud Storage Permission Denied Incident

**Incident ID:** INC-2026-042
**Date:** 2026-04-08
**Duration:** 45 minutes (14:00 - 14:45 UTC)
**Severity:** SEV-2 (High)
**Status:** Resolved

---

## 1. Executive Summary

On 8 April 2026, the data-pipeline service in project `prod-data-123` began
receiving 403 (Permission Denied) errors when reading from Cloud Storage
bucket `gs://prod-data-input`. The issue started at 14:00 UTC following a
Terraform apply that inadvertently removed the service account's IAM binding.
The issue was resolved at 14:45 UTC by re-granting the role. No data was lost,
but 45 minutes of pipeline processing was delayed.

## 2. Impact Assessment

| Metric | Value |
|---|---|
| Duration | 45 minutes |
| Users affected | 0 (internal pipeline) |
| Records delayed | ~12,000 |
| Data loss | None |
| SLO budget consumed | 2.1% of monthly error budget |
| Revenue impact | None (batch processing) |

## 3. Timeline

| Time (UTC) | Event | Source |
|---|---|---|
| 13:45 | Terraform PR merged for IAM cleanup | GitLab CI |
| 13:50 | `terraform apply` executed in prod | CI pipeline log |
| 14:00 | First 403 error from pipeline-sa on gs://prod-data-input | Cloud Logging |
| 14:02 | Error rate monitoring alert fires (>5 errors/min) | Cloud Monitoring |
| 14:05 | On-call engineer acknowledges alert | PagerDuty |
| 14:10 | Engineer checks SA roles — objectViewer missing | gcloud CLI |
| 14:15 | Root cause identified: TF used `iam_binding` (authoritative) | Terraform state |
| 14:20 | Fix PR raised: switch to `iam_member` + re-add binding | GitLab |
| 14:30 | Emergency CLI fix: `gcloud storage buckets add-iam-policy-binding` | gcloud CLI |
| 14:32 | Error rate drops to 0 | Cloud Monitoring |
| 14:45 | Pipeline backlog cleared, incident resolved | Application logs |

## 4. Root Cause Analysis

**Five Whys:**
1. Why did the pipeline get 403 errors? → The SA lost `roles/storage.objectViewer`
2. Why was the role removed? → `terraform apply` replaced all role members
3. Why did it replace all members? → The config used `google_project_iam_binding` (authoritative)
4. Why was authoritative mode used? → The original author copied from a doc example
5. Why wasn't this caught in review? → No CI check for authoritative IAM resources

**Root Cause:** Terraform configuration used `google_project_iam_binding` (authoritative
per role) instead of `google_project_iam_member` (additive). When the TF state didn't
include the pipeline SA's binding (it was added manually), `terraform apply` deleted it.

## 5. Contributing Factors

- The pipeline SA binding was added via CLI, not tracked in Terraform state
- No CI/CD check to flag use of authoritative IAM resources
- The error rate alert threshold was 5/min, which allowed 2 minutes of errors before alerting
- No `terraform plan` review step in the CI pipeline for this repo

## 6. Resolution

```bash
# Emergency fix (CLI)
gcloud storage buckets add-iam-policy-binding gs://prod-data-input \
  --member="serviceAccount:pipeline-sa@prod-data-123.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

# Permanent fix (Terraform)
# Changed from google_project_iam_binding to google_project_iam_member
# Added the pipeline SA binding to Terraform state
```

## 7. Detection

- **Detected by:** Cloud Monitoring error rate alert (>5 errors/min)
- **Time to detect:** 2 minutes
- **Could we detect sooner?** Yes — alert on first 403 from this SA would save 2 min

## 8. Action Items

| Priority | Action | Owner | Deadline |
|---|---|---|---|
| P0 | Add all SA bindings to Terraform (no manual CLI) | Platform | 2026-04-12 |
| P0 | Switch all `iam_binding` to `iam_member` in prod TF | Platform | 2026-04-12 |
| P1 | Add checkov/tfsec check for authoritative IAM in CI | DevOps | 2026-04-19 |
| P1 | Add mandatory `terraform plan` review in CI | DevOps | 2026-04-19 |
| P2 | Lower error rate alert threshold to 1/min for critical SAs | SRE | 2026-04-30 |
| P2 | Document "safe IAM patterns" in team wiki | Platform | 2026-04-30 |

## 9. Lessons Learned

**What went well:**
- Alert fired within 2 minutes of the first error
- On-call engineer responded and diagnosed within 10 minutes
- Emergency fix was applied without escalation

**What could be improved:**
- All IAM bindings should be managed in Terraform (no manual CLI)
- CI should prevent authoritative IAM resources from being applied
- Plan review should be mandatory for IAM changes

## 10. Appendix

- [Cloud Logging query](https://console.cloud.google.com/logs?query=...)
- [Monitoring dashboard](https://console.cloud.google.com/monitoring/dashboards/...)
- [Terraform PR](https://gitlab.com/team/infra/merge_requests/...)
- [Incident channel](https://slack.com/archives/...)
EOF

echo "Created: example_rca.md"
```

### Step 4: Clean Up (5 min)

```bash
cd ~
rm -rf genai-rca-lab
```

---

## Part 3: Revision (15 minutes)

- **RCA structure** — summary, impact, timeline, root cause, contributing factors, resolution, detection, actions, lessons
- **Five Whys** — keep asking "why" until you reach the systemic cause (not a person)
- **Blameless** — use roles ("the on-call engineer"), never names
- **AI strength** — timeline extraction, correlation, consistent formatting
- **Human required** — verify findings, add institutional context, prioritise actions, assign owners
- **Data gathering script** — automate log collection to speed up AI input preparation

### Key Sections
```
1. Executive Summary (what happened)
2. Impact (who/what was affected)
3. Timeline (when events occurred)
4. Root Cause (Five Whys)
5. Action Items (P0/P1/P2 with owners)
```

---

## Part 4: Quiz (15 minutes)

**Q1:** You feed incident logs to AI and it suggests "the developer caused the outage." What's wrong with this RCA?
<details><summary>Answer</summary>This violates <b>blameless post-mortem culture</b>. RCAs should identify <b>systemic causes</b>, not blame individuals. Instead of "the developer caused it," the root cause should be "the CI pipeline lacked a plan review step for IAM changes" or "the Terraform module used an authoritative resource type." If a person made a mistake, ask: what system allowed that mistake to cause an outage? People make mistakes — systems should prevent them from becoming incidents.</details>

**Q2:** An AI-generated RCA lists "upgrade to the latest version" as an action item. Is this a good action item?
<details><summary>Answer</summary><b>No.</b> Good action items are <b>specific, measurable, assigned, and deadlined</b>. "Upgrade to the latest version" is vague and unactionable. Better: "Upgrade Terraform Google provider from 4.x to 5.x in the prod-infra repo to fix deprecated IAM resource behaviour. Owner: Platform team. Deadline: 2026-04-19. Verification: CI passes with new provider version." Always rewrite generic AI suggestions into SMART action items.</details>

**Q3:** Why should you gather data BEFORE prompting the AI for an RCA?
<details><summary>Answer</summary>AI quality depends on <b>input quality</b>. Without data, the AI will generate a generic, hallucinated RCA with plausible but fictional details. With real logs, alerts, and timeline data, the AI can: 1) Extract an accurate timeline, 2) Identify correlations between events, 3) Cite specific timestamps as evidence, 4) Suggest relevant fixes. Garbage in, garbage out. The <code>gather_incident_data.sh</code> script standardises data collection so you don't miss sources under incident pressure.</details>

**Q4:** What's the most important thing a human must verify in an AI-generated RCA?
<details><summary>Answer</summary>The <b>root cause</b>. AI tends to identify the most obvious or recent cause, not necessarily the systemic root cause. For example, AI might say "the role was removed" (immediate cause) instead of "there was no CI check preventing authoritative IAM changes" (root cause). Apply the Five Whys yourself to verify the AI went deep enough. Also verify: timeline accuracy (AI may misorder events), action item feasibility, and that the tone is blameless.</details>
