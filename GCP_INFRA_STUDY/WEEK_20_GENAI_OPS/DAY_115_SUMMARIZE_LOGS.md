# Week 20, Day 115 (Mon) — Summarise Logs with GenAI

## Today's Objective

Learn to use Gemini and generative AI to summarise verbose Cloud Logging output, extract actionable insights from log floods, and build prompt templates for common log analysis scenarios.

**Source:** [Gemini in Cloud Logging](https://cloud.google.com/logging/docs/gemini) | [Vertex AI Gemini](https://cloud.google.com/vertex-ai/generative-ai/docs/overview)

**Deliverable:** A set of tested prompt templates for log summarisation covering errors, security events, and deployment logs

---

## Part 1: Concept (30 minutes)

### 1.1 Why AI for Logs?

```
Linux analogy:

tail -f /var/log/messages | grep ERROR    ──►    Traditional: grep + regex + dashboards
  - Works for known patterns                      - Finds what you already know to look for
  - Misses unexpected correlations                - Misses cross-service patterns

"Hey, summarise what went wrong today"    ──►    GenAI: "Here's what happened"
  - Natural language question                     - Natural language answer
  - Finds unexpected patterns                     - Correlates across services
  - Explains in context                           - Suggests next steps
```

### 1.2 AI Log Analysis Flow

```
┌──────────────────┐     gcloud logging     ┌──────────────────┐
│                  │     read + filter       │                  │
│  Cloud Logging   │ ──────────────────────► │  Raw Log Entries │
│  (millions/day)  │                         │  (filtered set)  │
│                  │                         │                  │
└──────────────────┘                         └────────┬─────────┘
                                                      │
                                              Format + Prompt
                                                      │
                                                      ▼
                                             ┌──────────────────┐
                                             │                  │
                                             │  Gemini / LLM    │
                                             │                  │
                                             │  "Summarise      │
                                             │   these logs"    │
                                             │                  │
                                             └────────┬─────────┘
                                                      │
                                                      ▼
                                             ┌──────────────────┐
                                             │  Human-readable  │
                                             │  Summary with    │
                                             │  • Root cause    │
                                             │  • Timeline      │
                                             │  • Next steps    │
                                             └──────────────────┘
```

### 1.3 Prompt Engineering for Logs

| Element | Purpose | Example |
|---|---|---|
| **Role** | Set context for the AI | "You are an SRE analysing production logs" |
| **Task** | What to do | "Summarise these error logs into a timeline" |
| **Format** | How to present output | "Use bullet points with timestamps" |
| **Constraints** | Boundaries | "Only include errors above WARNING level" |
| **Context** | Background info | "This is a GKE cluster running microservices" |

### 1.4 Good vs Bad Prompts

```
BAD:  "What do these logs say?"
  → Too vague; AI will summarise everything without focus

GOOD: "You are an SRE. Analyse these Cloud Logging entries from
       the last hour. Identify:
       1. The root cause of any errors
       2. A timeline of events
       3. Which services are affected
       4. Recommended next steps
       Format as a numbered list with timestamps."
  → Specific role, task, format, and structure
```

### 1.5 When to Use AI vs Traditional Tools

| Scenario | Best Tool |
|---|---|
| Find all 500 errors in the last hour | `gcloud logging read` + filter |
| Understand WHY errors spiked at 14:00 | AI summarisation |
| Count errors per service | Log-based metrics |
| Explain an unfamiliar error pattern | AI analysis |
| Alert on error rate exceeding threshold | Monitoring alert policy |
| Post-incident timeline reconstruction | AI + audit logs |

### 1.6 Data Safety

```
⚠️  IMPORTANT: Before sending logs to AI:

1. STRIP PII  ──► Remove emails, IPs, usernames
2. STRIP SECRETS ──► Remove tokens, keys, passwords
3. CHECK POLICY ──► Does your org allow external AI analysis?
4. USE VERTEX AI ──► Google's AI, data stays in GCP
5. REDACT ──► Replace sensitive values with [REDACTED]

Never paste production logs into public AI tools.
Use Vertex AI Gemini (data stays within your project).
```

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Gather Sample Logs (10 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)

# Query recent logs (adjust filter based on your project)
echo "=== Gathering sample logs ==="
gcloud logging read "
  severity>=WARNING
" --limit=30 --format=json --freshness=24h > sample_logs.json

# Count what we got
echo "Log entries gathered: $(cat sample_logs.json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"

# Also get some structured summary info
gcloud logging read "severity>=ERROR" --limit=10 --format="table(
  timestamp,
  severity,
  resource.type,
  protoPayload.methodName,
  textPayload
)" --freshness=24h
```

### Step 2: Build Log Summarisation Prompt Templates (15 min)

```bash
mkdir -p genai-ops-lab && cd genai-ops-lab

cat > prompt_log_summary.md <<'EOF'
# Prompt Template: Log Summary

## System Prompt
You are a senior SRE analysing Google Cloud Platform logs. Your audience is an
on-call engineer who needs a quick, actionable summary.

## User Prompt Template
Analyse the following Cloud Logging entries from project `{PROJECT_ID}` covering
the last `{TIME_RANGE}`.

**Instructions:**
1. Provide a 2-3 sentence executive summary
2. Create a timeline of significant events (with timestamps)
3. Group errors by service/resource
4. Identify the root cause (if determinable)
5. List recommended immediate actions
6. Rate the severity: LOW / MEDIUM / HIGH / CRITICAL

**Format:** Use markdown with clear headings.

**Logs:**
```json
{PASTE_LOGS_HERE}
```

---

## Example Output

### Executive Summary
Between 14:00-14:30 UTC, the Compute Engine service experienced 12 permission
denied errors from `app-sa@project.iam`, likely due to a missing IAM binding
after yesterday's Terraform apply. No data loss occurred.

### Timeline
- **14:00:12** — First `PERMISSION_DENIED` error from `app-sa` on `storage.objects.get`
- **14:02:45** — Error rate increased to 5/min
- **14:15:00** — Monitoring alert triggered
- **14:28:00** — Last error before fix applied

### Affected Services
| Service | Errors | Severity |
|---|---|---|
| Cloud Storage | 12 | HIGH |
| Compute Engine | 3 | MEDIUM |

### Root Cause
The service account `app-sa` lost `roles/storage.objectViewer` during a
Terraform apply that used `google_project_iam_binding` (authoritative),
which replaced all members for that role.

### Recommended Actions
1. Re-grant `roles/storage.objectViewer` to `app-sa`
2. Switch from `iam_binding` to `iam_member` in Terraform
3. Add a CI check to prevent authoritative IAM resource usage

### Severity: HIGH
EOF

echo "Created: prompt_log_summary.md"
```

### Step 3: Build Error Analysis Prompt (10 min)

```bash
cat > prompt_error_analysis.md <<'EOF'
# Prompt Template: Error Analysis

## System Prompt
You are a GCP infrastructure expert. Analyse error logs to identify patterns,
root causes, and fixes. Include gcloud commands for remediation.

## User Prompt Template
I have `{ERROR_COUNT}` errors from the last `{TIME_RANGE}` in project
`{PROJECT_ID}`. The errors are from `{SERVICE}`.

**Analyse these errors:**
1. Categorise by error type (auth, quota, config, network, etc.)
2. For each category, explain the likely root cause
3. Provide the exact gcloud commands to diagnose further
4. Provide the exact gcloud commands to fix
5. Suggest preventive measures

**Errors:**
```
{PASTE_ERRORS_HERE}
```

---

## Example Input (paste into Gemini/ChatGPT with Vertex AI)

I have 15 errors from the last 2 hours in project my-project-123.
The errors are from Cloud Storage.

Analyse these errors:
```
ERROR 2026-04-08T14:00:12Z storage.objects.get PERMISSION_DENIED on gs://data-bucket/file1.csv by app-sa@project.iam
ERROR 2026-04-08T14:00:15Z storage.objects.get PERMISSION_DENIED on gs://data-bucket/file2.csv by app-sa@project.iam
ERROR 2026-04-08T14:02:45Z storage.objects.list PERMISSION_DENIED on gs://data-bucket by app-sa@project.iam
WARNING 2026-04-08T14:10:00Z storage.buckets.get NOT_FOUND gs://wrong-bucket-name
ERROR 2026-04-08T14:15:00Z storage.objects.create FORBIDDEN on gs://data-bucket/output.csv by batch-sa@project.iam
```
EOF

echo "Created: prompt_error_analysis.md"
```

### Step 4: Build Security Event Prompt (10 min)

```bash
cat > prompt_security_audit.md <<'EOF'
# Prompt Template: Security Event Analysis

## System Prompt
You are a cloud security analyst. Analyse audit logs for potential security
incidents, unauthorized access, and policy violations. Be thorough but avoid
false positives.

## User Prompt Template
Review these Cloud Audit Log entries for security concerns in project
`{PROJECT_ID}`.

**Focus on:**
1. Unusual access patterns (off-hours, new IPs, new principals)
2. Privilege escalation attempts (IAM changes, role grants)
3. Data exfiltration indicators (large reads, bulk downloads)
4. Suspicious service account activity (key creation, impersonation)
5. Policy changes (firewall rules, org policies, VPC changes)

**For each finding:**
- Severity: INFO / LOW / MEDIUM / HIGH / CRITICAL
- What happened (1 sentence)
- Why it's concerning (1 sentence)
- Recommended action

**Audit entries:**
```json
{PASTE_AUDIT_LOGS_HERE}
```
EOF

echo "Created: prompt_security_audit.md"
```

### Step 5: Test with Vertex AI CLI (10 min)

```bash
# Format logs for AI consumption
echo "=== Formatting logs for AI ==="

# Get recent warnings/errors as concise text
gcloud logging read "severity>=WARNING" --limit=20 --format="table(
  timestamp,
  severity,
  resource.type,
  protoPayload.methodName,
  textPayload
)" --freshness=24h > formatted_logs.txt

echo ""
echo "Formatted logs saved to formatted_logs.txt"
echo "Entries: $(wc -l < formatted_logs.txt)"
echo ""
echo "=== To use with Gemini ==="
echo "Option 1: Paste into Gemini in Cloud Console"
echo "Option 2: Use Vertex AI API:"
echo ""
cat <<'EXAMPLE'
# Using gcloud with Vertex AI Gemini
gcloud ai models predict gemini-2.0-flash \
  --region=europe-west2 \
  --json-request='{
    "instances": [{
      "content": "You are an SRE. Summarise these logs:\n...(paste logs)..."
    }]
  }'

# Using Python SDK
from vertexai.generative_models import GenerativeModel
model = GenerativeModel("gemini-2.0-flash")
response = model.generate_content(f"""
You are an SRE analysing GCP logs. Summarise these entries:
{logs_text}

Provide: timeline, root cause, affected services, next steps.
""")
print(response.text)
EXAMPLE
```

### Step 6: Clean Up (5 min)

```bash
cd ~
rm -rf genai-ops-lab sample_logs.json
```

---

## Part 3: Revision (15 minutes)

- **AI log analysis** — use for understanding patterns, not replacing traditional monitoring
- **Prompt structure** — role + task + format + constraints + context = quality output
- **Data safety** — strip PII/secrets before AI processing; use Vertex AI for GCP data
- **Prompt templates** — reusable patterns for log summary, error analysis, security audit
- **Limitations** — AI can hallucinate causes, always verify findings with actual data
- **Best for** — post-incident timeline, unfamiliar error patterns, cross-service correlation

### Key Prompt Elements
```
1. Role: "You are a senior SRE..."
2. Task: "Analyse these logs and identify..."
3. Format: "Use markdown with timestamps..."
4. Constraints: "Only errors above WARNING..."
5. Context: "Project runs GKE microservices..."
```

---

## Part 4: Quiz (15 minutes)

**Q1:** Why should you use Vertex AI Gemini instead of a public AI service for log analysis?
<details><summary>Answer</summary>Production logs contain <b>sensitive data</b> — IP addresses, usernames, service account emails, internal resource names, and potentially PII. Vertex AI keeps data <b>within your GCP project</b> and is covered by your org's data processing agreement. Public AI services (ChatGPT, public Gemini) may log inputs for training. Also, Vertex AI has lower latency to your GCP data and can be integrated into automated pipelines with IAM-controlled access.</details>

**Q2:** What makes a good log analysis prompt vs a bad one?
<details><summary>Answer</summary><b>Good prompt:</b> Specifies a role (SRE), task (identify root cause), format (timeline with timestamps), constraints (WARNING+), and context (GKE cluster, last hour). Produces structured, actionable output. <b>Bad prompt:</b> "What do these logs say?" — too vague, no format guidance, AI will summarise without focus. Like asking "what's wrong?" vs "check if the NFS mount on /data failed in the last hour and show me the mount errors."</details>

**Q3:** What must you do before sending production logs to any AI tool?
<details><summary>Answer</summary>
1. <b>Strip PII</b> — remove/redact emails, usernames, IP addresses<br>
2. <b>Strip secrets</b> — remove API keys, tokens, passwords (even if they look redacted)<br>
3. <b>Check org policy</b> — confirm your organisation allows AI analysis of operational data<br>
4. <b>Use Vertex AI</b> — keep data within GCP if possible<br>
5. <b>Limit scope</b> — only send the relevant time window and services, not all logs
</details>

**Q4:** When should you NOT use AI for log analysis?
<details><summary>Answer</summary>
1. <b>Real-time alerting</b> — use Cloud Monitoring alerts, not AI (too slow, unreliable)<br>
2. <b>Simple pattern matching</b> — <code>grep ERROR</code> or log-based metrics are faster<br>
3. <b>Metrics counting</b> — use Cloud Monitoring dashboards, not AI<br>
4. <b>Compliance evidence</b> — AI summaries are not auditable evidence; use raw logs<br>
5. <b>When speed matters</b> — during a live incident, don't wait for AI; use known runbooks first<br>
AI is best for post-incident analysis and understanding unfamiliar patterns.
</details>
