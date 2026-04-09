# Week 20, Day 117 (Wed) — Generate Terraform with GenAI

## Today's Objective

Use generative AI to scaffold Terraform configurations from natural-language descriptions, learn prompt patterns for producing correct HCL, validate AI-generated infrastructure code, and understand the limitations and risks.

**Source:** [Gemini Code Assist](https://cloud.google.com/gemini/docs/codeassist/overview) | [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

**Deliverable:** A workflow for generating, validating, and safely applying AI-generated Terraform code

---

## Part 1: Concept (30 minutes)

### 1.1 AI-Assisted IaC

```
Linux analogy:

man iptables                       ──►    Terraform docs (dense reference)
  - Read docs → write rules                - Read docs → write HCL
  - Time-consuming for complex setups      - Time-consuming for new resources

"Create a firewall rule allowing       ──►    "Create a VPC with private subnet,
 SSH from 10.0.0.0/24 to port 22"              Cloud NAT, and firewall rules"
  ↓ AI generates iptables command             ↓ AI generates Terraform config
  ↓ Human reviews + tests                     ↓ Human reviews + plan + tests
```

### 1.2 AI-Generated TF Workflow

```
┌──────────────────────┐
│ Natural Language      │
│ "I need a VPC with   │
│  private subnet and  │
│  Cloud NAT in        │
│  europe-west2"       │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ AI Generates HCL     │
│ - VPC resource       │
│ - Subnet resource    │
│ - Router resource    │
│ - NAT resource       │
│ - Firewall rules     │
└──────────┬───────────┘
           │
    ┌──────┴──────┐
    ▼             ▼
┌────────┐  ┌──────────┐
│Validate│  │ Security │
│ tf fmt │  │  Review  │
│ tf val │  │ checkov  │
│ tflint │  │ tfsec    │
└───┬────┘  └────┬─────┘
    │            │
    └─────┬──────┘
          ▼
   ┌────────────┐
   │ tf plan    │
   │ (review!)  │
   └─────┬──────┘
         ▼
   ┌────────────┐
   │ tf apply   │
   │ (approved) │
   └────────────┘
```

### 1.3 What AI Gets Right and Wrong

| Gets Right (usually) | Gets Wrong (often) |
|---|---|
| Resource structure and required args | API versions / provider versions |
| Naming conventions (if shown examples) | Region-specific constraints |
| Basic dependencies (subnet needs VPC) | Complex IAM implications |
| Variable patterns | State management configuration |
| Output definitions | Exact attribute names (hallucination) |
| Standard module structure | Org policy compatibility |

### 1.4 Prompt Pattern for Terraform

```
EFFECTIVE PROMPT STRUCTURE:

1. CONTEXT: "Using Terraform with the Google provider (hashicorp/google ~> 5.0)"
2. REQUIREMENTS: Specific resources and their configuration
3. CONSTRAINTS: Region, naming, tags, networking
4. STYLE: Module structure, variable usage, output patterns
5. SECURITY: "No public IPs, no default SA, no 0.0.0.0/0 rules"
6. REFERENCE: "Follow the pattern in this existing code: ..."

Example:
"Using Terraform with hashicorp/google ~> 5.0, create a module that deploys:
- A VPC with a /16 CIDR
- One private subnet (/24) in europe-west2
- Cloud NAT for outbound internet
- Firewall allowing IAP SSH (35.235.240.0/20)
- No public IPs on any resources
- Use variables for project_id, region, CIDR ranges
- Output the VPC ID and subnet self_link"
```

### 1.5 Validation Pipeline

| Step | Tool | What It Catches |
|---|---|---|
| 1. Format | `terraform fmt` | Inconsistent formatting |
| 2. Validate | `terraform validate` | Syntax errors, missing args |
| 3. Lint | `tflint` | Deprecated features, naming |
| 4. Security | `checkov` / `tfsec` | Security misconfigurations |
| 5. Plan | `terraform plan` | Actual resource changes |
| 6. Review | Human | Business logic, cost, scope |

### 1.6 Common AI Terraform Mistakes

```
MISTAKE 1: Hallucinated attributes
  resource "google_compute_instance" "vm" {
    enable_integrity_monitoring = true    ← Doesn't exist here
  }
  Fix: Check provider docs for actual attributes

MISTAKE 2: Wrong provider version
  required_providers { google = { version = "~> 3.0" } }
  Fix: Always specify ~> 5.0 for current provider

MISTAKE 3: Overly permissive
  source_ranges = ["0.0.0.0/0"]    ← Open to entire internet
  Fix: Specify exact CIDR ranges needed

MISTAKE 4: Missing dependencies
  NAT without router, subnet without VPC
  Fix: Check terraform plan for errors

MISTAKE 5: Default service account
  (not specifying service_account block)
  Fix: Always specify a dedicated SA
```

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create the AI Prompt Template for TF (10 min)

```bash
mkdir -p genai-terraform-lab && cd genai-terraform-lab

cat > prompt_terraform_generator.md <<'EOF'
# Terraform Generator Prompt Template

## System Prompt

You are a Terraform expert specialising in Google Cloud Platform. Generate
production-quality HCL code following these rules:

1. Provider: hashicorp/google ~> 5.0
2. Terraform version: >= 1.5
3. Region: europe-west2 (unless specified otherwise)
4. Always use variables for project_id, region, and environment
5. Never use default service accounts
6. Never allow 0.0.0.0/0 in firewall source_ranges
7. Always include labels: env, managed_by="terraform"
8. Use google_project_iam_member (additive), never iam_policy or iam_binding
9. Include outputs for key resource attributes
10. Include a locals block for computed values

## User Prompt Template

Generate a Terraform configuration for:

**Infrastructure:** {DESCRIPTION}
**Project:** {PROJECT_ID}
**Region:** europe-west2
**Environment:** {ENV}
**Network requirements:** {NETWORK_DETAILS}
**Security requirements:** {SECURITY_DETAILS}
**Naming convention:** {NAMING_PATTERN}

Generate:
1. `main.tf` — primary resources
2. `variables.tf` — all input variables with descriptions and defaults
3. `outputs.tf` — key outputs
4. `terraform.tfvars.example` — example values

Do NOT generate:
- Backend configuration (we'll add that separately)
- Provider credentials (we use impersonation)
EOF

echo "Created: prompt_terraform_generator.md"
```

### Step 2: Generate and Validate a VPC Module (20 min)

```bash
# This is what AI would generate — we'll write it as if generated
mkdir -p modules/vpc

cat > modules/vpc/variables.tf <<'EOF'
variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "europe-west2"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR range for the primary subnet"
  default     = "10.0.0.0/24"
}

variable "enable_cloud_nat" {
  type        = bool
  description = "Enable Cloud NAT for outbound internet"
  default     = true
}
EOF

cat > modules/vpc/main.tf <<'EOF'
locals {
  name_prefix = "${var.environment}-vpc"
  labels = {
    env        = var.environment
    managed_by = "terraform"
  }
}

resource "google_compute_network" "vpc" {
  name                    = local.name_prefix
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "private" {
  name                     = "${local.name_prefix}-private-${var.region}"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.vpc_cidr
  private_ip_google_access = true
}

# IAP SSH firewall rule (not 0.0.0.0/0)
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "${local.name_prefix}-allow-iap-ssh"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]  # IAP range only
  target_tags   = ["allow-ssh"]
}

# Internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "${local.name_prefix}-allow-internal"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.vpc_cidr]
}

# Cloud NAT (conditional)
resource "google_compute_router" "router" {
  count   = var.enable_cloud_nat ? 1 : 0
  name    = "${local.name_prefix}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  count                              = var.enable_cloud_nat ? 1 : 0
  name                               = "${local.name_prefix}-nat"
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.router[0].name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
EOF

cat > modules/vpc/outputs.tf <<'EOF'
output "vpc_id" {
  description = "VPC network ID"
  value       = google_compute_network.vpc.id
}

output "vpc_self_link" {
  description = "VPC self link"
  value       = google_compute_network.vpc.self_link
}

output "subnet_id" {
  description = "Private subnet ID"
  value       = google_compute_subnetwork.private.id
}

output "subnet_self_link" {
  description = "Private subnet self link"
  value       = google_compute_subnetwork.private.self_link
}
EOF
```

### Step 3: Validate the Generated Code (15 min)

```bash
# Create root config to test the module
export PROJECT_ID=$(gcloud config get-value project)

cat > main.tf <<'EOF'
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" { type = string }
variable "region" { type = string; default = "europe-west2" }

module "vpc" {
  source           = "./modules/vpc"
  project_id       = var.project_id
  region           = var.region
  environment      = "dev"
  vpc_cidr         = "10.10.0.0/24"
  enable_cloud_nat = true
}

output "vpc_id" { value = module.vpc.vpc_id }
output "subnet_id" { value = module.vpc.subnet_id }
EOF

echo "project_id = \"${PROJECT_ID}\"" > terraform.tfvars

# Step 1: Format check
echo "=== Step 1: terraform fmt ==="
terraform fmt -recursive -check && echo "PASS: Formatting OK" || echo "FAIL: Run terraform fmt"

# Step 2: Init and validate
echo ""
echo "=== Step 2: terraform validate ==="
terraform init
terraform validate && echo "PASS: Validation OK" || echo "FAIL: Fix validation errors"

# Step 3: Plan (review what would be created)
echo ""
echo "=== Step 3: terraform plan ==="
terraform plan -out=plan.tfplan

echo ""
echo "=== Review Checklist ==="
echo "[ ] No 0.0.0.0/0 in firewall rules?"
echo "[ ] Private IP Google Access enabled?"
echo "[ ] Cloud NAT configured?"
echo "[ ] Labels present on all resources?"
echo "[ ] No default service account references?"
```

### Step 4: Clean Up (5 min)

```bash
# Don't apply — this is a validation exercise
cd ~
rm -rf genai-terraform-lab
```

---

## Part 3: Revision (15 minutes)

- **AI generates 80%-correct Terraform** — always validate with fmt, validate, tflint, checkov
- **Prompt quality matters** — include provider version, region, security constraints, naming
- **Common AI mistakes** — hallucinated attributes, wrong provider versions, overly permissive rules
- **Validation pipeline** — fmt → validate → lint → security scan → plan → human review
- **Never `terraform apply` AI code without reviewing the plan** — AI errors can create insecure infra
- **Feed AI your existing code** — it produces better output when given your project's patterns

### Key Validation Commands
```bash
terraform fmt -recursive -check
terraform validate
terraform plan -out=plan.tfplan
terraform show plan.tfplan
# Plus: tflint, checkov -d ., tfsec .
```

---

## Part 4: Quiz (15 minutes)

**Q1:** You ask AI to generate Terraform for a GCE instance. It produces `enable_integrity_monitoring = true` at the resource top level. What's wrong?
<details><summary>Answer</summary>The attribute is <b>hallucinated</b> — it doesn't exist at the top level of <code>google_compute_instance</code>. Integrity monitoring is configured inside the <code>shielded_instance_config</code> block as <code>enable_integrity_monitoring = true</code>. AI often "knows" a feature exists but places it at the wrong nesting level. <b>Fix:</b> Always check the <a href="https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance">Terraform provider docs</a> for correct attribute placement. <code>terraform validate</code> would catch this.</details>

**Q2:** AI generates a firewall rule with `source_ranges = ["0.0.0.0/0"]`. Why is this dangerous and how do you fix it?
<details><summary>Answer</summary><code>0.0.0.0/0</code> means <b>the entire internet</b> can reach the target port. This is the #1 cloud security misconfiguration. <b>Fix:</b> Restrict to specific CIDR ranges: IAP (<code>35.235.240.0/20</code>), your VPN range, or internal subnet CIDRs. Include a security constraint in your prompt: "Never allow 0.0.0.0/0 in source_ranges." Use <code>checkov</code> or <code>tfsec</code> in CI to catch this automatically.</details>

**Q3:** What's the minimum validation you should do before applying AI-generated Terraform?
<details><summary>Answer</summary>
1. <b><code>terraform fmt</code></b> — fix formatting<br>
2. <b><code>terraform validate</code></b> — catch syntax and structural errors<br>
3. <b><code>terraform plan</code></b> — review exactly what will be created/changed/destroyed<br>
4. <b>Human review</b> of the plan — check for unexpected resources, overly broad permissions, cost implications<br>
Ideally also: <code>tflint</code> (deprecated features), <code>checkov</code> (security), and check the provider docs for any attributes you don't recognise.
</details>

**Q4:** How do you get AI to produce Terraform that matches your team's existing patterns?
<details><summary>Answer</summary>Include <b>existing code as context</b> in your prompt: "Follow the pattern in this module: [paste existing module]." This teaches the AI your naming conventions, variable patterns, label requirements, and module structure. Also specify explicit constraints: provider version, region, security rules, and output conventions. The more context you provide, the closer the output matches your standards. Like giving a new team member your style guide before they write code.</details>
