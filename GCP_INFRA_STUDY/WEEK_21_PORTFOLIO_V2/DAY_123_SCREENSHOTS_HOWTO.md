# Day 123 — Add Screenshots + How-to-Run Instructions

> **Week 21 · Portfolio v2** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Capture meaningful screenshots that prove your projects work, annotate them for clarity, and write reproducible setup instructions that anyone can follow.

---

## Part 1 — Concept: Visual Proof & Reproducibility (30 min)

### Why Screenshots Matter for a Portfolio

Screenshots serve as **proof of work**. A recruiter or hiring manager who sees a working GCP Console dashboard, a successful `terraform apply` output, or a triggered alert knows your project actually runs — not just that you wrote some config files.

### What to Screenshot

| Category | What to Capture | Why It Matters |
|---|---|---|
| **GCP Console** | Resource dashboard, VM instances list, VPC network map | Proves resources were created in real GCP |
| **Terminal Output** | `terraform apply` success, script execution, test results | Shows the project runs end-to-end |
| **Monitoring** | Dashboards, alert firing, uptime checks | Proves observability is configured |
| **Architecture** | Network topology in Console, IAM policy viewer | Visual confirmation of design |
| **Before/After** | State before your change and after | Demonstrates the impact of your work |

### Screenshot Best Practices

| Do | Don't |
|---|---|
| Capture the **full relevant context** (panel + sidebar) | Don't screenshot a tiny cropped area with no context |
| **Redact** project IDs, emails, billing info | Don't expose sensitive information |
| Use **consistent resolution** (1920x1080 or retina) | Don't mix blurry and sharp images |
| **Timestamp** or show date in the screenshot | Don't use undated screenshots |
| Show **success states** (green ticks, "applied") | Don't only show configuration screens |
| Name files descriptively: `01-vpc-created.png` | Don't use `Screenshot 2026-04-08.png` |

### Screenshot Annotation Guide

Annotations draw attention to the key parts of a screenshot. Use them sparingly — 2-3 annotations per image maximum.

| Annotation Type | When to Use | Tool |
|---|---|---|
| **Red rectangle/circle** | Highlight a specific UI element | Any image editor, Snagit, ShareX |
| **Arrow + label** | Point to a value or status | Paint, Preview, or screenshot tool |
| **Numbered callouts** | Walk through steps in order | Snagit, Greenshot |
| **Blur/redact** | Hide sensitive data | Any image editor |

### Organising Screenshots in Your Repository

```
project-root/
├── README.md
├── docs/
│   └── images/
│       ├── 01-architecture-overview.png
│       ├── 02-terraform-apply-success.png
│       ├── 03-vpc-console-view.png
│       ├── 04-monitoring-dashboard.png
│       └── 05-alert-firing.png
├── terraform/
└── scripts/
```

**Reference in README:**
```markdown
## Results

### VPC Created Successfully
![VPC Network in GCP Console](docs/images/03-vpc-console-view.png)

### Monitoring Dashboard
![Custom monitoring dashboard showing VM metrics](docs/images/04-monitoring-dashboard.png)
```

### Writing Reproducible Setup Instructions

The gold standard: **someone with the listed prerequisites can go from clone to working in under 15 minutes.**

### Prerequisites Section Template

```markdown
## Prerequisites

| Requirement | Version | Check Command |
|---|---|---|
| GCP Account | Free tier OK | `gcloud auth list` |
| gcloud CLI | >= 450.0.0 | `gcloud version` |
| Terraform | >= 1.5.0 | `terraform version` |
| Git | >= 2.30 | `git --version` |

### GCP Setup
- A GCP project with billing enabled
- APIs enabled: Compute Engine, Cloud Monitoring, Cloud IAM
- Sufficient quota in `europe-west2` for: 2 VMs (e2-medium)

### Environment Variables
```bash
export PROJECT_ID="your-project-id"
export REGION="europe-west2"
export ZONE="europe-west2-a"
```
```

### How-to-Run Template

```markdown
## Quick Start

### 1. Clone and Navigate
```bash
git clone https://github.com/yourusername/project-name.git
cd project-name
```

### 2. Configure Variables
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values:
# project_id = "your-project-id"
# region     = "europe-west2"
```

### 3. Initialise and Deploy
```bash
terraform init
terraform plan    # Review changes
terraform apply   # Type 'yes' to confirm
```

### 4. Verify
```bash
# Check VMs are running
gcloud compute instances list --project=$PROJECT_ID

# Check monitoring dashboard
echo "Open: https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
```

### 5. Clean Up
```bash
terraform destroy  # Type 'yes' to confirm
```
```

### Environment Variables Documentation

| Pattern | When to Use |
|---|---|
| `.tfvars.example` file | Terraform projects — user copies and fills in |
| `.env.example` file | Script/application projects |
| Inline `export` commands | Quick setup, few variables |
| Table of variables | Documentation reference |

**Environment Variables Table Template:**

| Variable | Required | Default | Description |
|---|---|---|---|
| `PROJECT_ID` | Yes | — | Your GCP project ID |
| `REGION` | No | `europe-west2` | GCP region for resources |
| `ZONE` | No | `europe-west2-a` | GCP zone for zonal resources |
| `MACHINE_TYPE` | No | `e2-medium` | VM machine type |
| `ALERT_EMAIL` | Yes | — | Email for monitoring alerts |

---

## Part 2 — Hands-On Activity: Screenshot & Document (60 min)

### Exercise 1 — Capture Screenshots for Each Project (25 min)

For each of your top 3 projects, capture the following screenshots:

**Minimum set per project:**

- [ ] **Architecture/resource view** — Console showing created resources
- [ ] **Successful deployment** — Terminal showing `terraform apply` or script completing
- [ ] **Working result** — The project actually doing what it claims (dashboard, firewall rule in action, etc.)

**Steps:**
1. Open each project in GCP Console
2. Navigate to the relevant resource page
3. Capture with Windows Snipping Tool (`Win + Shift + S`) or ShareX
4. Save to `docs/images/` in each project with descriptive filenames
5. Redact any sensitive data (project ID is OK to show, billing details are not)

**Naming convention:** `NN-description.png`
- `01-terraform-apply-success.png`
- `02-vpc-console-network-map.png`
- `03-monitoring-dashboard-live.png`

### Exercise 2 — Annotate Key Screenshots (10 min)

Pick the 1-2 most important screenshots per project and add annotations:

1. Open in Paint, Paint 3D, or your preferred tool
2. Add a red rectangle around the key element (e.g., "Running" status, metric graph)
3. Add a brief text label if needed
4. Save as a new file: `03-monitoring-dashboard-annotated.png`

### Exercise 3 — Write Setup Instructions (25 min)

For each project, write complete setup instructions using the template from Part 1.

**Test your instructions mentally:**
1. Read each step as if you've never seen the project
2. Is every command included? No "obvious" steps skipped?
3. Are all required variables documented?
4. Is there a verification step after deployment?
5. Is there a clean-up step?

**Create the `.tfvars.example` or `.env.example` file:**

```hcl
# terraform.tfvars.example
# Copy this file to terraform.tfvars and fill in your values

project_id   = "your-gcp-project-id"
region       = "europe-west2"
zone         = "europe-west2-a"
alert_email  = "your-email@example.com"
```

**Add a prerequisites check script (optional but impressive):**

```bash
#!/bin/bash
# check-prereqs.sh — Verify all prerequisites are met

echo "Checking prerequisites..."

command -v gcloud >/dev/null 2>&1 || { echo "❌ gcloud CLI not found"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform not found"; exit 1; }

echo "✅ gcloud CLI: $(gcloud version 2>/dev/null | head -1)"
echo "✅ Terraform:  $(terraform version 2>/dev/null | head -1)"

if [ -z "$PROJECT_ID" ]; then
  echo "⚠️  PROJECT_ID not set. Run: export PROJECT_ID=your-project-id"
else
  echo "✅ PROJECT_ID: $PROJECT_ID"
fi

echo "Prerequisites check complete."
```

---

## Part 3 — Revision: Key Takeaways (15 min)

- **Screenshots are proof of work** — they show your project actually runs on real GCP infrastructure
- **Capture 3 types minimum:** resource view (Console), deployment success (terminal), working result
- **Redact sensitive data** — billing info, personal emails, service account keys
- **Name screenshots descriptively:** `01-vpc-created.png` not `Screenshot_123.png`
- **Store in `docs/images/`** folder, referenced from README with relative paths
- **Annotate sparingly** — 2-3 highlights per image maximum, use red rectangles
- **Reproducible instructions = someone can clone and deploy in <15 minutes**
- **Always include:** prerequisites table, environment variables, step-by-step commands, verification, and clean-up
- **Use `.tfvars.example` or `.env.example`** — never commit real credentials
- **A prerequisites check script** (`check-prereqs.sh`) is a small touch that signals production thinking

---

## Part 4 — Quiz (15 min)

**Q1.** What three types of screenshots should every portfolio project include at minimum?

<details><summary>Answer</summary>

1. **Resource/architecture view** — GCP Console showing created resources (VMs, VPC, firewall rules) proving the infrastructure exists
2. **Successful deployment** — Terminal output showing `terraform apply` completing successfully or scripts running without errors
3. **Working result** — The project doing what it claims: a monitoring dashboard displaying metrics, an alert firing, a load balancer distributing traffic

These three together prove the project was **built, deployed, and functions** — not just written.
</details>

**Q2.** Your project requires 5 environment variables. Should you put them in the README as `export` commands, a `.env.example` file, or a `terraform.tfvars.example` file?

<details><summary>Answer</summary>

It depends on the project type:
- **Terraform projects:** Use `terraform.tfvars.example` — this is the Terraform convention and keeps variables in one place that `terraform apply` reads automatically.
- **Script/application projects:** Use `.env.example` — a standard convention that many tools support.
- **In all cases,** also document the variables in a README table for quick reference (name, required/optional, default, description).

Never use only inline `export` commands in the README — they're easy to miss and hard to maintain. The `.example` file pattern clearly shows users what needs to be configured and prevents committing real values to Git.
</details>

**Q3.** You want to include a screenshot of your monitoring dashboard, but it shows your GCP project ID and email address. What should you do?

<details><summary>Answer</summary>

**GCP project ID is generally safe** to show in a portfolio screenshot — it's not sensitive and helps prove the project is real. **Email addresses should be redacted** using blur or a black rectangle in an image editor. Other things to redact: billing account IDs, service account key contents, API keys, OAuth secrets, and any PII. When in doubt, redact. You can add a note: "Project ID and email redacted for privacy" if needed.
</details>

**Q4.** Why should setup instructions include a "Clean Up" or "Destroy" step?

<details><summary>Answer</summary>

A clean-up step shows **production awareness**: (1) It prevents the reviewer from accidentally running up GCP costs if they test your project, (2) it demonstrates you think about **resource lifecycle management**, not just creation, (3) it signals understanding of **cloud cost management** — a real concern for employers, and (4) it makes the project easier to test and re-deploy. For Terraform projects, this is simply `terraform destroy`. For gcloud-based projects, include explicit delete commands for each resource created.
</details>
