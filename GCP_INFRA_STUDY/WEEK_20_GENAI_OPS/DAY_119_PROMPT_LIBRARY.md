# Week 20, Day 119 (Fri) — Prompt Library for Ops

## Today's Objective

Build a curated, version-controlled prompt library for GCP operations: categorised templates for monitoring, incident response, infrastructure, security, and cost analysis. Establish a system for maintaining and sharing prompts across the team.

**Source:** [Prompt Engineering Best Practices](https://cloud.google.com/vertex-ai/generative-ai/docs/learn/prompts/introduction-prompt-design) | [Gemini for Cloud](https://cloud.google.com/gemini/docs/overview)

**Deliverable:** A structured prompt library with tested templates, a taxonomy system, and team sharing workflow

---

## Part 1: Concept (30 minutes)

### 1.1 Why a Prompt Library?

```
Linux analogy:

/usr/local/bin/scripts/            ──►    prompts/
  - backup.sh                             - log_summary.md
  - check_disk.sh                         - rca_template.md
  - rotate_keys.sh                        - terraform_gen.md
  - Documented, tested, shared            - Documented, tested, shared
  - Version controlled                    - Version controlled
  - New team members use them             - New team members use them
```

### 1.2 Prompt Library Structure

```
prompts/
├── README.md                       ← How to use the library
├── CONTRIBUTING.md                  ← How to add new prompts
│
├── monitoring/                     ← Category
│   ├── log-summary.md              ← Prompt template
│   ├── alert-analysis.md
│   └── dashboard-review.md
│
├── incident-response/
│   ├── rca-summariser.md
│   ├── timeline-builder.md
│   └── impact-assessment.md
│
├── infrastructure/
│   ├── terraform-generator.md
│   ├── architecture-review.md
│   └── migration-plan.md
│
├── security/
│   ├── iam-audit.md
│   ├── vulnerability-triage.md
│   └── access-review.md
│
└── cost/
    ├── cost-analysis.md
    ├── rightsizing-review.md
    └── budget-review.md
```

### 1.3 Prompt Template Standard

| Field | Required? | Purpose |
|---|---|---|
| **Name** | Yes | Searchable title |
| **Category** | Yes | Taxonomy for organisation |
| **Version** | Yes | Track changes |
| **Author** | Yes | Who created it |
| **Description** | Yes | When and why to use this prompt |
| **System prompt** | Yes | Role and constraints for the AI |
| **User prompt template** | Yes | The actual prompt with `{variables}` |
| **Variables** | Yes | List of inputs with descriptions |
| **Example input** | Recommended | A worked example |
| **Example output** | Recommended | Expected result quality |
| **Limitations** | Recommended | Known weaknesses |
| **Review date** | Yes | When to revisit |

### 1.4 Prompt Quality Tiers

```
TIER 1: TESTED (green)
  - Used in 3+ real incidents
  - Produces consistent results
  - Reviewed by team
  - Has example input/output
  
TIER 2: VALIDATED (yellow)
  - Used 1-2 times
  - Produces good results
  - Needs more testing
  
TIER 3: DRAFT (red)
  - New, untested
  - Theory-based
  - Needs real-world validation
```

### 1.5 Maintenance Cycle

```
┌──────────┐     Use in      ┌──────────┐     Evaluate     ┌──────────┐
│  Create  │ ───────────────► │  Real    │ ─────────────── ►│  Review  │
│  Prompt  │   incident/task  │  Usage   │   output quality │  Quality │
└──────────┘                  └──────────┘                  └────┬─────┘
     ▲                                                           │
     │                                                     Good? │
     │                                                     │     │
     │             ┌──────────┐                           Yes    No
     └─────────────│  Update  │◄──────────────────────────┘     │
                   │  Prompt  │                                  │
                   └──────────┘◄─────────────────────────────────┘
                                        Improve
```

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create Library Structure (10 min)

```bash
mkdir -p prompt-library/{monitoring,incident-response,infrastructure,security,cost}
cd prompt-library

cat > README.md <<'EOF'
# GCP Operations Prompt Library

A curated collection of AI prompt templates for GCP infrastructure operations.

## Quick Start

1. Browse categories below
2. Find the relevant prompt template
3. Fill in the `{variables}` with your data
4. Use with Vertex AI Gemini or approved internal AI tools

## Categories

| Category | Prompts | Description |
|---|---|---|
| [monitoring/](monitoring/) | Log summary, alert analysis, dashboard review | Day-to-day monitoring tasks |
| [incident-response/](incident-response/) | RCA, timeline, impact assessment | During and after incidents |
| [infrastructure/](infrastructure/) | Terraform gen, architecture review | Infrastructure changes |
| [security/](security/) | IAM audit, vulnerability triage | Security operations |
| [cost/](cost/) | Cost analysis, rightsizing | FinOps tasks |

## Quality Tiers

- 🟢 **Tested** — Used in 3+ real scenarios, consistent results
- 🟡 **Validated** — Used 1-2 times, good results
- 🔴 **Draft** — New, needs real-world testing

## Data Safety

⚠️ Before using any prompt with production data:
1. Strip PII (emails, usernames, IPs)
2. Strip secrets (keys, tokens, passwords)
3. Use Vertex AI (data stays in GCP)
4. Follow the [data handling policy](link-to-policy)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)
EOF
```

### Step 2: Create Monitoring Prompts (10 min)

```bash
cat > monitoring/log-summary.md <<'EOF'
# Log Summary

**Category:** Monitoring | **Version:** 1.2 | **Quality:** 🟢 Tested
**Author:** Platform Team | **Review:** Quarterly

## Description
Summarise Cloud Logging entries for a specific time window. Use after alerts fire
or during shift handovers.

## System Prompt
```
You are a senior SRE analysing Google Cloud Platform logs for project
{project_id}. Your audience is the on-call engineer. Be concise and actionable.
Use UK English.
```

## User Prompt Template
```
Analyse these Cloud Logging entries from {start_time} to {end_time}.

1. Executive summary (2-3 sentences)
2. Timeline of significant events (table with timestamps)
3. Error categorisation (group by type)
4. Affected services/resources
5. Recommended immediate actions
6. Severity rating: LOW / MEDIUM / HIGH / CRITICAL

Logs:
{paste_logs_here}
```

## Variables
| Variable | Description | Example |
|---|---|---|
| `{project_id}` | GCP project ID | `prod-data-123` |
| `{start_time}` | Start of analysis window | `2026-04-08T14:00:00Z` |
| `{end_time}` | End of analysis window | `2026-04-08T15:00:00Z` |
| `{paste_logs_here}` | Filtered log entries | Output from `gcloud logging read` |

## Data Gathering Command
```bash
gcloud logging read "severity>=WARNING" \
  --project=${PROJECT_ID} \
  --freshness=1h \
  --limit=50 \
  --format="table(timestamp, severity, resource.type, protoPayload.methodName, textPayload)"
```

## Limitations
- AI may miss subtle correlations in very large log sets
- Timestamp accuracy depends on log entry format
- Cannot access real-time metrics (only log entries provided)
EOF

cat > monitoring/alert-analysis.md <<'EOF'
# Alert Analysis

**Category:** Monitoring | **Version:** 1.0 | **Quality:** 🟡 Validated
**Author:** Platform Team | **Review:** Quarterly

## Description
Analyse a Cloud Monitoring alert to determine urgency, scope, and next steps.

## System Prompt
```
You are an SRE triaging monitoring alerts. Determine if this is a real incident
or noise. Be direct and specific. Provide gcloud commands for investigation.
```

## User Prompt Template
```
An alert fired:
- Alert name: {alert_name}
- Condition: {condition}
- Current value: {value}
- Threshold: {threshold}
- Resource: {resource}
- Duration: {duration}
- Time: {timestamp}

Questions:
1. Is this likely a real incident or transient noise? (explain reasoning)
2. What is the potential impact if left unresolved?
3. Provide 3 gcloud commands to investigate further
4. What immediate actions (if any) should the on-call take?
5. Should this alarm be tuned? If so, how?
```

## Variables
| Variable | Description |
|---|---|
| `{alert_name}` | Name of the alert policy |
| `{condition}` | What triggered the alert |
| `{value}` | Current metric value |
| `{threshold}` | Alert threshold |
| `{resource}` | Affected resource |
| `{duration}` | How long the condition has been true |
| `{timestamp}` | When the alert fired |
EOF
```

### Step 3: Create Incident Response Prompts (10 min)

```bash
cat > incident-response/rca-summariser.md <<'EOF'
# RCA Summariser

**Category:** Incident Response | **Version:** 2.0 | **Quality:** 🟢 Tested
**Author:** Platform Team | **Review:** Quarterly

## Description
Generate a blameless Root Cause Analysis document from incident data.
See DAY_118 for detailed usage.

## System Prompt
```
You are an SRE writing a blameless post-mortem. Use evidence from the provided
logs and timeline. Never blame individuals — identify systemic causes and
process gaps. Use UK English. Cite timestamps.
```

## User Prompt Template
```
Generate an RCA for:
- Incident: {incident_id}
- Date: {date}
- Duration: {duration}
- Severity: {severity}
- Service: {service}

Sections:
1. Executive Summary (4 sentences max)
2. Impact (table: duration, users, data loss, SLO budget)
3. Timeline (table: time, event, source)
4. Root Cause (Five Whys technique)
5. Contributing Factors (bullet list)
6. Resolution (commands used)
7. Detection (how found, could we find sooner?)
8. Action Items (table: priority, action, owner=[TODO], deadline)
9. Lessons Learned (went well / improve)

Data:
{paste_incident_data_here}
```

## Data Gathering
```bash
./gather_incident_data.sh PROJECT_ID START_TIME END_TIME
```
EOF

cat > incident-response/impact-assessment.md <<'EOF'
# Impact Assessment

**Category:** Incident Response | **Version:** 1.0 | **Quality:** 🟡 Validated
**Author:** Platform Team | **Review:** Quarterly

## Description
Quickly assess the business impact of an ongoing incident.

## System Prompt
```
You are an incident commander assessing the impact of a GCP incident.
Provide a structured impact assessment for stakeholder communication.
Be honest about unknowns. Use UK English.
```

## User Prompt Template
```
Assess the impact of this incident:
- What: {description}
- When started: {start_time}
- Services affected: {services}
- Error rate: {error_rate}
- Current status: {status}

Provide:
1. User impact (who is affected and how)
2. Business impact (revenue, operations, compliance)
3. Data impact (loss, corruption, exposure)
4. SLO impact (estimated budget consumption)
5. Communication needed (who needs to be informed)
6. Estimated time to resolution (if known)
```
EOF
```

### Step 4: Create Security and Cost Prompts (10 min)

```bash
cat > security/iam-audit.md <<'EOF'
# IAM Audit Review

**Category:** Security | **Version:** 1.0 | **Quality:** 🟡 Validated
**Author:** Security Team | **Review:** Quarterly

## Description
Review IAM policy for security issues: overly broad roles, stale access,
excessive service account keys.

## System Prompt
```
You are a cloud security analyst reviewing GCP IAM policies. Focus on
least privilege, access hygiene, and compliance. Flag specific findings
with severity ratings. Use UK English.
```

## User Prompt Template
```
Review this IAM policy for project {project_id}:

{paste_iam_policy_json}

Identify:
1. Overly broad roles (Editor, Owner — who has them and why?)
2. External members (non-organisation emails with access)
3. Service accounts with user-managed keys
4. Stale access (if activity logs provided)
5. Missing conditional bindings (temp access without expiry)
6. Recommendations (table: finding, severity, recommendation)
```

## Data Gathering
```bash
gcloud projects get-iam-policy PROJECT_ID --format=json > iam_policy.json
```
EOF

cat > cost/cost-analysis.md <<'EOF'
# Cost Analysis

**Category:** Cost | **Version:** 1.0 | **Quality:** 🔴 Draft
**Author:** FinOps Team | **Review:** Monthly

## Description
Analyse GCP billing data for cost optimisation opportunities.

## System Prompt
```
You are a FinOps analyst reviewing GCP costs. Identify optimisation
opportunities with estimated savings. Prioritise by savings potential.
Use UK English.
```

## User Prompt Template
```
Review this billing summary for project {project_id}:
Period: {billing_period}

{paste_billing_data}

Provide:
1. Cost breakdown by service (table)
2. Month-over-month trend (increasing/decreasing/stable)
3. Top 3 cost optimisation opportunities with estimated savings
4. Resources that appear over-provisioned
5. Recommendations for committed use discounts
6. Action items (table: action, estimated savings, effort)
```

## Data Gathering
```bash
# Export from Billing Console or BigQuery billing export
bq query --format=prettyjson "
  SELECT service.description, SUM(cost) as total_cost
  FROM \`project.billing_dataset.gcp_billing_export\`
  WHERE DATE(usage_start_time) >= '2026-03-01'
  GROUP BY 1 ORDER BY 2 DESC LIMIT 20
"
```
EOF
```

### Step 5: Create Contributing Guide (5 min)

```bash
cat > CONTRIBUTING.md <<'EOF'
# Contributing to the Prompt Library

## Adding a New Prompt

1. Choose the correct category directory
2. Use the template below
3. Submit a PR with the new prompt
4. Include at least one worked example
5. Set quality tier to 🔴 Draft for new prompts

## Template

```markdown
# Prompt Name

**Category:** X | **Version:** 1.0 | **Quality:** 🔴 Draft
**Author:** Your Team | **Review:** Quarterly

## Description
When and why to use this prompt.

## System Prompt
The AI's role and constraints.

## User Prompt Template
The actual prompt with {variables}.

## Variables
Table of inputs.

## Data Gathering Command
How to collect the input data.

## Example Input
A real-world example.

## Example Output
What good output looks like.

## Limitations
Known weaknesses.
```

## Quality Promotion

- 🔴 → 🟡: Used successfully in 1-2 real scenarios
- 🟡 → 🟢: Used successfully in 3+ scenarios with consistent quality

## Review Cycle

All prompts are reviewed quarterly. If a prompt hasn't been used in 6 months,
it's archived to `prompts/archive/`.
EOF
```

### Step 6: Clean Up (5 min)

```bash
cd ~
# Keep the library if you want to use it:
# rm -rf prompt-library
echo "Prompt library created at: $(pwd)/prompt-library"
echo "To keep: add to git and version control"
```

---

## Part 3: Revision (15 minutes)

- **Prompt libraries** — version-controlled, categorised, tested prompt templates
- **Standard fields** — name, category, version, system prompt, user template, variables, examples
- **Quality tiers** — Draft (untested), Validated (1-2 uses), Tested (3+ uses)
- **Categories** — monitoring, incident response, infrastructure, security, cost
- **Maintenance** — quarterly reviews, archive unused prompts, promote after real usage
- **Sharing** — Git repo, team wiki, or shared docs with search

### Library Categories
```
monitoring/         → log-summary, alert-analysis, dashboard-review
incident-response/ → rca-summariser, timeline-builder, impact-assessment
infrastructure/    → terraform-generator, architecture-review
security/          → iam-audit, vulnerability-triage
cost/              → cost-analysis, rightsizing-review
```

---

## Part 4: Quiz (15 minutes)

**Q1:** Why version control prompt templates instead of just keeping them in a shared doc?
<details><summary>Answer</summary>Version control provides: 1) <b>Change history</b> — see who changed a prompt and why, 2) <b>Review process</b> — PRs for new/changed prompts ensure quality, 3) <b>Rollback</b> — revert to a working version if an edit reduces quality, 4) <b>Branching</b> — experiment with prompt variations without affecting the main library, 5) <b>Integration</b> — scripts can pull prompts directly from the repo. Shared docs lack audit trail, review workflow, and programmatic access.</details>

**Q2:** A new team member asks which prompt to use during an incident. How does the library help?
<details><summary>Answer</summary>The library helps through: 1) <b>Categories</b> — browse "incident-response/" for relevant prompts, 2) <b>Descriptions</b> — each prompt says when to use it, 3) <b>Quality tiers</b> — 🟢 Tested prompts are reliable during high-pressure incidents, 4) <b>Examples</b> — worked examples show exactly what to paste and what to expect, 5) <b>Data gathering commands</b> — copy-paste <code>gcloud</code> commands to collect the input data. New engineers don't need to know prompt engineering — they follow the template.</details>

**Q3:** How do you decide when to promote a prompt from Draft to Tested?
<details><summary>Answer</summary>Track usage and quality: 🔴 <b>Draft → 🟡 Validated</b>: Used in 1-2 real scenarios where the output was useful with minimal editing. 🟡 <b>Validated → 🟢 Tested</b>: Used in 3+ real scenarios across different incidents/tasks, produces consistent quality, and at least one team member other than the author has used it successfully. Document each usage in the PR that promotes the quality tier.</details>

**Q4:** The cost-analysis prompt is marked 🔴 Draft. What should happen before it's used for a real FinOps review?
<details><summary>Answer</summary>
1. <b>Test with synthetic data</b> — use sample billing data to verify the output is sensible<br>
2. <b>Test with real data</b> — run on a non-critical project's billing data<br>
3. <b>Review by FinOps team</b> — verify the recommendations the AI makes are relevant and accurate<br>
4. <b>Add an example</b> — include a worked example with real input/output<br>
5. <b>Document limitations</b> — note what the AI gets wrong (e.g., it can't access real-time pricing)<br>
Only after at least one successful real-world use should it be promoted to 🟡 Validated.
</details>
