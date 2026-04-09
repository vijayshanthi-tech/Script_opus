# Week 20, Day 116 (Tue) — Draft Runbooks with GenAI

## Today's Objective

Use generative AI to rapidly draft operational runbooks from incident notes, existing procedures, and infrastructure knowledge. Learn prompt patterns for generating structured runbooks that follow SRE best practices.

**Source:** [Google SRE Workbook — Runbooks](https://sre.google/workbook/on-call/) | [Vertex AI Gemini](https://cloud.google.com/vertex-ai/generative-ai/docs/overview)

**Deliverable:** A GenAI-assisted workflow for creating runbooks from incident post-mortems and operational knowledge

---

## Part 1: Concept (30 minutes)

### 1.1 The Runbook Problem

```
Linux analogy:

man sshd_config                    ──►    Runbook: "How to restart service X"
  - Always available                      - Must exist BEFORE the incident
  - Consistently formatted                - Consistent format = faster response
  - Written once, used many times         - Draft quickly, refine with experience

vs. "I think you run... let me check..." ──► No runbook: figure it out under pressure
```

### 1.2 Traditional vs AI-Assisted Runbook Creation

```
TRADITIONAL (hours per runbook):
  Meeting → Draft → Review → Edit → Review → Publish → Goes stale
  └── 4-8 hours per runbook ──┘

AI-ASSISTED (minutes per runbook):
  Prompt + Context → AI Draft → Human Review → Edit → Publish
  └── 30-60 min per runbook ──┘
  
Key: AI writes 80% of the boilerplate, humans add 20% institutional knowledge
```

### 1.3 Runbook Structure (Standard Template)

| Section | Purpose | AI Can Generate? |
|---|---|---|
| **Title + Metadata** | What, who, when | ✅ From service name |
| **Overview** | What this runbook covers | ✅ From service description |
| **Prerequisites** | Required access + tools | ✅ From infrastructure docs |
| **Symptoms/Triggers** | When to use this | ✅ From alert definitions |
| **Diagnosis Steps** | How to investigate | ✅ From gcloud commands |
| **Remediation Steps** | How to fix | ✅ From operational experience |
| **Verification** | How to confirm the fix | ✅ From success criteria |
| **Escalation** | Who to call if it fails | ❌ Requires institutional knowledge |
| **Post-Incident** | Cleanup + follow-up | ✅ Generic steps |

### 1.4 Prompt Architecture

```
┌─────────────────────────────────────────────┐
│  INPUT TO AI                                 │
│                                              │
│  ┌──────────────┐  ┌─────────────────────┐  │
│  │ Service Info  │  │ Past Incidents      │  │
│  │ - Name        │  │ - Post-mortems      │  │
│  │ - Architecture│  │ - What went wrong   │  │
│  │ - Dependencies│  │ - How we fixed it   │  │
│  └──────────────┘  └─────────────────────┘  │
│                                              │
│  ┌──────────────┐  ┌─────────────────────┐  │
│  │ Alert Defs   │  │ Template            │  │
│  │ - Conditions  │  │ - Standard format   │  │
│  │ - Thresholds  │  │ - Required sections │  │
│  │ - Severity    │  │ - Style guide       │  │
│  └──────────────┘  └─────────────────────┘  │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
              ┌──────────────┐
              │  GenAI Draft │
              │  (80% done)  │
              └──────┬───────┘
                     │
                     ▼
              ┌──────────────┐
              │ Human Review │
              │ + Edit (20%) │
              │ - Escalation │
              │ - Context    │
              │ - Edge cases │
              └──────────────┘
```

### 1.5 What AI Is Good and Bad At

| Good At | Bad At |
|---|---|
| Structuring from unstructured notes | Knowing your team's on-call schedule |
| Generating gcloud/kubectl commands | Knowing which Slack channel to use |
| Creating step-by-step procedures | Institutional knowledge (who owns what) |
| Formatting consistently | Understanding political/organizational context |
| Covering edge cases (if prompted) | Knowing which shortcuts your team uses |

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create the Runbook Generator Prompt (15 min)

```bash
mkdir -p genai-runbook-lab && cd genai-runbook-lab

cat > prompt_runbook_generator.md <<'PROMPT'
# Runbook Generator Prompt Template

## System Prompt

You are a senior SRE who writes operational runbooks for Google Cloud Platform
infrastructure. Your runbooks are used by on-call engineers during incidents.

Style rules:
- Every command must be copy-pasteable (use variables with clear substitution markers)
- Include verification after every fix step
- Use WARNING boxes for destructive actions
- Include estimated time for each major step
- Use UK English spelling

## User Prompt Template

Generate a complete operational runbook for the following scenario:

**Service:** {SERVICE_NAME}
**Platform:** Google Cloud Platform
**Region:** europe-west2
**Alert trigger:** {ALERT_DESCRIPTION}
**Severity:** {SEVERITY}
**Past incident notes:** {INCIDENT_NOTES}

### Required Sections

1. **Title** — Clear, searchable name
2. **Metadata** — Last updated, owner team, review date
3. **Overview** — 2-3 sentences on what this covers
4. **Trigger** — What alert/symptom leads you here
5. **Prerequisites** — Required IAM roles, tools, access
6. **Quick Assessment** (2 min) — First commands to understand the situation
7. **Diagnosis** (10 min) — Systematic investigation steps
8. **Remediation** (varies) — Step-by-step fix with verification
9. **Verification** (5 min) — Confirm the fix is complete
10. **Escalation** — When and who to escalate to (leave as [TODO])
11. **Cleanup** — Any post-fix cleanup needed
12. **Prevention** — Long-term fixes to prevent recurrence

### Command Requirements
- Use `gcloud` commands (not Console UI steps)
- Include `--project`, `--region`, or `--zone` flags explicitly
- Use shell variables at the top: `export PROJECT_ID=...`
- Include expected output or success criteria after each command

PROMPT

echo "Created: prompt_runbook_generator.md"
```

### Step 2: Generate a VM Disk Full Runbook (15 min)

```bash
cat > example_vm_disk_full.md <<'EOF'
# Example: Input to the AI

**Service:** Compute Engine VM
**Platform:** Google Cloud Platform
**Region:** europe-west2
**Alert trigger:** "Disk utilisation > 90% on instance app-server-01"
**Severity:** HIGH
**Past incident notes:**
- Last time this happened, /var/log filled up due to debug logging left on
- We had to SSH in and truncate the log files
- The root disk was only 10GB, we resized to 20GB after
- Application writes temp files to /tmp that aren't cleaned up

---

# AI-Generated Runbook (example of expected output)

# Runbook: VM Disk Full — Compute Engine

**Last Updated:** 2026-04-08 | **Owner:** Platform Team | **Review:** Quarterly

## Overview
This runbook addresses disk utilisation alerts (>90%) on Compute Engine VMs.
The most common causes are log accumulation, temp file buildup, and undersized disks.

## Trigger
- Alert: "Disk utilisation > 90% on instance {INSTANCE_NAME}"
- Monitoring: Cloud Monitoring → Compute Engine → Disk utilisation metric

## Prerequisites
- [ ] `roles/compute.instanceAdmin.v1` on the project
- [ ] SSH access to the VM (via IAP or external IP)
- [ ] `gcloud` CLI authenticated

## Quick Assessment (2 min)

```bash
export PROJECT_ID="YOUR_PROJECT"
export INSTANCE="app-server-01"
export ZONE="europe-west2-a"

# Check current disk usage from monitoring
gcloud compute instances describe ${INSTANCE} \
  --zone=${ZONE} \
  --project=${PROJECT_ID} \
  --format="table(disks[].source, disks[].diskSizeGb)"

# SSH and check disk usage
gcloud compute ssh ${INSTANCE} \
  --zone=${ZONE} \
  --project=${PROJECT_ID} \
  --command="df -h && echo '---' && du -sh /var/log /tmp /home 2>/dev/null | sort -rh | head -10"
```

## Diagnosis (10 min)

```bash
# Find largest files
gcloud compute ssh ${INSTANCE} --zone=${ZONE} --project=${PROJECT_ID} --command="
  echo '=== Top 10 largest files ==='
  sudo find / -xdev -type f -size +100M -exec ls -lh {} \; 2>/dev/null | sort -k5 -rh | head -10
  
  echo ''
  echo '=== Top 10 largest directories ==='
  sudo du -sh /* 2>/dev/null | sort -rh | head -10
  
  echo ''
  echo '=== /var/log usage ==='
  sudo du -sh /var/log/* 2>/dev/null | sort -rh | head -10
"
```

## Remediation

### Option A: Clear log files (immediate, 5 min)

```bash
# ⚠️  WARNING: This truncates log files. Content cannot be recovered.
gcloud compute ssh ${INSTANCE} --zone=${ZONE} --project=${PROJECT_ID} --command="
  # Truncate (not delete) large log files
  sudo truncate -s 0 /var/log/syslog.1
  sudo truncate -s 0 /var/log/kern.log.1
  
  # Clean old logs
  sudo journalctl --vacuum-size=100M
  
  # Clean temp files older than 7 days
  sudo find /tmp -type f -mtime +7 -delete
  
  echo 'After cleanup:'
  df -h /
"
```

### Option B: Resize disk (permanent, 15 min)

```bash
# Step 1: Resize disk (online, no downtime)
gcloud compute disks resize ${INSTANCE} \
  --zone=${ZONE} \
  --project=${PROJECT_ID} \
  --size=50GB

# Step 2: Grow filesystem inside the VM
gcloud compute ssh ${INSTANCE} --zone=${ZONE} --project=${PROJECT_ID} --command="
  sudo growpart /dev/sda 1
  sudo resize2fs /dev/sda1    # ext4
  # OR: sudo xfs_growfs /     # xfs
  
  echo 'After resize:'
  df -h /
"
```

## Verification (5 min)

```bash
gcloud compute ssh ${INSTANCE} --zone=${ZONE} --project=${PROJECT_ID} --command="
  echo '=== Disk usage after fix ==='
  df -h /
  echo ''
  echo 'Expected: Usage < 80%'
"

# Check monitoring to confirm alert clears
echo "Wait 5 minutes, then check:"
echo "https://console.cloud.google.com/monitoring?project=${PROJECT_ID}"
```

## Escalation
- [TODO: Team Slack channel]
- [TODO: On-call escalation path]
- [TODO: Service owner contact]

## Prevention
1. Set up log rotation: `logrotate` config with maxsize 100M, rotate 4
2. Automated temp cleanup: systemd timer to clean /tmp daily
3. Right-size disks: Minimum 30GB for application VMs
4. Add disk usage alert at 80% (warning) and 90% (critical)
EOF

echo "Created: example_vm_disk_full.md"
```

### Step 3: Create Post-Mortem to Runbook Converter (15 min)

```bash
cat > prompt_postmortem_to_runbook.md <<'EOF'
# Prompt Template: Post-Mortem → Runbook Converter

## System Prompt
You are an SRE converting incident post-mortems into preventive runbooks.
Extract the diagnosis steps, remediation actions, and lessons learned into
a structured, reusable runbook.

## User Prompt Template

Convert this post-mortem into a runbook:

**Post-Mortem:**
```
{PASTE_POST_MORTEM_HERE}
```

**Generate a runbook that:**
1. Starts from the alert/symptom that triggered the incident
2. Lists the diagnosis steps the responders used (in order)
3. Documents the fix that worked
4. Includes the fix that DIDN'T work (with explanation why)
5. Adds prevention steps from the action items
6. Includes verification commands to confirm the fix

**Important:**
- Convert "we did X" into "do X" (imperative instructions)
- Add gcloud commands where the post-mortem describes Console actions
- Include time estimates based on the post-mortem timeline
- Flag any TODO items for team-specific information

---

## Example Input

Post-mortem: "On April 3rd, Cloud SQL instance prod-db went down at 14:00.
We first checked if the instance was running (it was). Then we checked
connections — it was at max (100). We found a stuck migration job creating
hundreds of connections. We killed the job, but connections didn't drop.
We had to restart the Cloud SQL instance at 14:45. Service restored at 14:50.
Root cause: migration job had no connection limit or timeout."

→ AI generates runbook for "Cloud SQL Connection Exhaustion"
EOF

echo "Created: prompt_postmortem_to_runbook.md"
```

### Step 4: Create Quick Runbook Builder Script (10 min)

```bash
cat > build_runbook.sh <<'SCRIPT'
#!/bin/bash
# Quick Runbook Builder — Generates the prompt to paste into Gemini/Vertex AI

echo "=== Runbook Generator ==="
echo ""

read -p "Service name: " SERVICE
read -p "Alert description: " ALERT
read -p "Severity (LOW/MEDIUM/HIGH/CRITICAL): " SEVERITY
read -p "Any past incident notes (or 'none'): " NOTES
read -p "GCP region [europe-west2]: " REGION
REGION=${REGION:-europe-west2}

cat <<PROMPT

============================================================
COPY THIS PROMPT INTO GEMINI / VERTEX AI
============================================================

You are a senior SRE. Generate a complete operational runbook.

**Service:** ${SERVICE}
**Platform:** Google Cloud Platform
**Region:** ${REGION}
**Alert:** ${ALERT}
**Severity:** ${SEVERITY}
**Past notes:** ${NOTES}

Required sections:
1. Title and metadata
2. Overview (2-3 sentences)
3. Trigger (what alert brings you here)
4. Prerequisites (IAM roles, tools)
5. Quick Assessment (2 min — first commands)
6. Diagnosis (10 min — systematic investigation)
7. Remediation (step-by-step with verification)
8. Verification (5 min — confirm fix)
9. Escalation (leave as [TODO])
10. Cleanup
11. Prevention (long-term fixes)

Command rules:
- All gcloud commands with explicit --project, --region, --zone
- Shell variables at the top (export PROJECT_ID=...)
- Include expected output after each command
- Use copy-pasteable bash code blocks
- UK English spelling

============================================================
PROMPT

SCRIPT
chmod +x build_runbook.sh
echo "Created: build_runbook.sh"
```

### Step 5: Clean Up (5 min)

```bash
cd ~
rm -rf genai-runbook-lab
```

---

## Part 3: Revision (15 minutes)

- **AI creates 80%** of runbook boilerplate; humans add 20% institutional knowledge
- **Prompt quality drives output quality** — include role, task, format, constraints, context
- **Runbook sections** — overview, trigger, prerequisites, assessment, diagnosis, remediation, verification, escalation
- **Post-mortems as input** — convert incident lessons into preventive runbooks
- **Always review AI output** — verify commands actually work, check for hallucinated flags
- **Escalation paths and team contacts** must ALWAYS be filled in by humans

### Key Prompt Pattern
```
System: "You are a senior SRE..."
Input: Service name + alert + past incidents + region
Format: Standard runbook sections with gcloud commands
Constraints: Copy-pasteable, verified, UK English
```

---

## Part 4: Quiz (15 minutes)

**Q1:** What parts of a runbook can AI reliably generate, and what must humans always add?
<details><summary>Answer</summary><b>AI can generate:</b> Structured templates, gcloud diagnostic commands, common remediation steps, verification procedures, generic prevention recommendations. <b>Humans must add:</b> Escalation paths (who to call), team-specific Slack channels, institutional shortcuts, political context (which teams own what), environment-specific variables (project IDs, SA emails), and validation that commands actually work. AI provides the skeleton; humans provide the institutional knowledge.</details>

**Q2:** You have a post-mortem from last week's incident. How do you convert it to a runbook?
<details><summary>Answer</summary>Feed the post-mortem text to AI with the prompt: "Convert this post-mortem into a preventive runbook." The AI will: 1) Extract the symptom/trigger, 2) Convert "we checked X" into "check X" (imperative), 3) Document what worked AND what didn't, 4) Include gcloud commands for each step. Then you review: add team contacts, verify commands, add time estimates from the actual incident timeline, and flag any organisation-specific context the AI couldn't know.</details>

**Q3:** Why is the "Quick Assessment (2 min)" section critical in a runbook?
<details><summary>Answer</summary>During an incident, the on-call engineer needs to <b>rapidly triage</b> before committing to a full diagnosis. The quick assessment (2 min) answers: Is the service up or down? What's the scope of impact? Is this a known pattern? This prevents wasting 10 minutes diagnosing the wrong service. Like checking <code>systemctl status sshd</code> before diving into SSH config files. The 2-minute constraint forces you to include only the most diagnostic commands.</details>

**Q4:** An AI-generated runbook includes `gcloud compute instances reset` as a fix. What should you verify?
<details><summary>Answer</summary>
1. <b>Is the command correct?</b> — <code>reset</code> is a hard reset (like pulling the power). Is that really necessary, or would <code>stop</code> + <code>start</code> be safer?<br>
2. <b>Are the flags complete?</b> — Does it include <code>--zone</code> and <code>--project</code>?<br>
3. <b>Is there a warning?</b> — A hard reset can cause data loss. The runbook should have a ⚠️ WARNING<br>
4. <b>Is there a verification step?</b> — After the reset, how do we confirm the VM is healthy?<br>
5. <b>Are there side effects?</b> — Will resetting this VM cause cascading failures?<br>
Always <b>test AI-generated commands in a non-production environment</b> before publishing.
</details>
