# Day 20 — Variables & Outputs: Parameterising Terraform

> **Week 4 · Terraform Basics** | Region: `europe-west2` | Study time: 2 hours

---

## Part 1 — Concept (30 min)

### 1.1 Why Variables?

Hardcoding values in `main.tf` is like hardcoding paths in a bash script — it works once but breaks when anything changes. Variables make Terraform configs **reusable and environment-aware**.

| Linux Analogy | Terraform Equivalent |
|---|---|
| `$HOME`, `$USER` (env vars) | Input variables (`var.name`) |
| `echo $result` (print output) | Output values (`output "name"`) |
| `script.sh --zone=eu` (CLI args) | `terraform apply -var="zone=eu"` |
| `source config.env` (load env file) | `terraform.tfvars` (variable values file) |
| `readonly PORT=8080` (constants) | `locals { port = 8080 }` |

### 1.2 Variable Types

```
┌─────────────────────────────────────────────────────┐
│              TERRAFORM VARIABLE TYPES                 │
│                                                     │
│  ┌─────────┐  ┌─────────┐  ┌──────┐  ┌──────────┐  │
│  │ string  │  │ number  │  │ bool │  │ Special  │  │
│  │         │  │         │  │      │  │          │  │
│  │ "hello" │  │ 42      │  │ true │  │ any      │  │
│  │ "eu-w2" │  │ 3.14    │  │ false│  │ null     │  │
│  └─────────┘  └─────────┘  └──────┘  └──────────┘  │
│                                                     │
│  ┌──────────────────┐  ┌───────────────────────┐    │
│  │ list(type)       │  │ map(type)             │    │
│  │                  │  │                       │    │
│  │ ["a", "b", "c"]  │  │ { key1 = "val1"      │    │
│  │ [1, 2, 3]        │  │   key2 = "val2" }    │    │
│  └──────────────────┘  └───────────────────────┘    │
│                                                     │
│  ┌──────────────────┐  ┌───────────────────────┐    │
│  │ set(type)        │  │ object({...})         │    │
│  │                  │  │                       │    │
│  │ unique values    │  │ { name = string       │    │
│  │ no duplicates    │  │   size = number }     │    │
│  └──────────────────┘  └───────────────────────┘    │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │ tuple([type1, type2, ...])                   │   │
│  │ mixed types in order: ["hello", 42, true]    │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

| Type | Example | Use Case |
|---|---|---|
| `string` | `"europe-west2-b"` | Zone, name, image |
| `number` | `10` | Disk size, count |
| `bool` | `true` | Feature toggles (enable external IP?) |
| `list(string)` | `["tag1", "tag2"]` | Tags, CIDRs |
| `map(string)` | `{ env = "lab", team = "infra" }` | Labels |
| `object({...})` | `{ name = string, size = number }` | Complex config bundles |

### 1.3 Variable Declaration Syntax

```hcl
# variables.tf

variable "project_id" {
  description = "GCP project ID"
  type        = string
  # No default = REQUIRED (must be provided)
}

variable "zone" {
  description = "Compute zone"
  type        = string
  default     = "europe-west2-b"   # Optional default
}

variable "machine_type" {
  description = "VM machine type"
  type        = string
  default     = "e2-micro"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 10
}

variable "enable_external_ip" {
  description = "Whether to assign an external IP"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {
    env     = "lab"
    managed = "terraform"
  }
}

variable "tags" {
  description = "Network tags for the VM"
  type        = list(string)
  default     = ["tf-lab"]
}
```

### 1.4 How Variables Are Supplied — Precedence

```
┌──────────────────────────────────────────────────────────┐
│         VARIABLE VALUE PRECEDENCE (lowest → highest)     │
│                                                          │
│  1. default value in variable block         (lowest)     │
│  2. terraform.tfvars file                                │
│  3. *.auto.tfvars files (alphabetical)                   │
│  4. -var-file="custom.tfvars" flag                       │
│  5. -var="key=value" CLI flag                            │
│  6. TF_VAR_name environment variable        (highest)    │
└──────────────────────────────────────────────────────────┘
```

| Method | Example | Best For |
|---|---|---|
| `default` in variable block | `default = "e2-micro"` | Sensible defaults |
| `terraform.tfvars` | `zone = "europe-west2-b"` | Project-specific values |
| `*.auto.tfvars` | `prod.auto.tfvars` | Auto-loaded per environment |
| `-var-file` flag | `terraform apply -var-file=prod.tfvars` | Explicit env selection |
| `-var` flag | `terraform apply -var="zone=us-central1-a"` | Quick one-off overrides |
| `TF_VAR_*` env var | `export TF_VAR_zone="us-east1-b"` | CI/CD pipelines |

> **Linux analogy:** This is like how a shell resolves a variable — `~/.bashrc` < `~/.bash_profile` < `export VAR=val` < inline `VAR=val command`.

### 1.5 Variable Validation

You can add validation rules — like input checking in a bash script with `[[ -z "$1" ]]`:

```hcl
variable "machine_type" {
  description = "VM machine type"
  type        = string
  default     = "e2-micro"

  validation {
    condition     = contains(["e2-micro", "e2-small", "e2-medium"], var.machine_type)
    error_message = "machine_type must be one of: e2-micro, e2-small, e2-medium."
  }
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 10

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 500
    error_message = "disk_size_gb must be between 10 and 500."
  }
}
```

### 1.6 Sensitive Variables

Mark variables as `sensitive` to hide their values from plan/apply output:

```hcl
variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true   # Value hidden in plan/apply/state output
}
```

```
# Plan output with sensitive variable:
+ password = (sensitive value)
```

> **Security note:** The value is still stored in `terraform.tfstate` in plain text. Use a proper secrets manager (Secret Manager, Vault) for production.

### 1.7 Output Values

Outputs export values after `apply` — like printing results at the end of a script.

```hcl
# outputs.tf

output "vm_name" {
  description = "Name of the created VM"
  value       = google_compute_instance.vm.name
}

output "vm_ip" {
  description = "External IP address"
  value       = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}

output "connection_command" {
  description = "SSH command to connect"
  value       = "gcloud compute ssh ${google_compute_instance.vm.name} --zone=${var.zone}"
}
```

```bash
# After apply, query outputs:
terraform output                  # Show all outputs
terraform output vm_ip            # Show one specific output
terraform output -json            # JSON format (for scripts)
terraform output -raw vm_ip       # Raw value (no quotes, for piping)
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Goal

Refactor the Day 19 hardcoded VM config into a fully parameterised version with variables, validation, and outputs.

### Prerequisites

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-b
```

### Step 1 — Create Project Directory

```bash
mkdir -p ~/tf-day20 && cd ~/tf-day20
```

### Step 2 — Write providers.tf

```bash
cat > providers.tf << 'EOF'
terraform {
  required_version = ">= 1.5.0"

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
  zone    = var.zone
}
EOF
```

### Step 3 — Write variables.tf

```bash
cat > variables.tf << 'EOF'
# --- Project Settings ---

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west2"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "europe-west2-b"
}

# --- VM Settings ---

variable "vm_name" {
  description = "Name of the VM instance"
  type        = string
  default     = "tf-day20-vm"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.vm_name))
    error_message = "vm_name must start with a letter, contain only lowercase letters, numbers, hyphens, max 63 chars."
  }
}

variable "machine_type" {
  description = "Machine type for the VM"
  type        = string
  default     = "e2-micro"

  validation {
    condition     = contains(["e2-micro", "e2-small", "e2-medium"], var.machine_type)
    error_message = "machine_type must be one of: e2-micro, e2-small, e2-medium."
  }
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 10

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 100
    error_message = "disk_size_gb must be between 10 and 100."
  }
}

variable "image" {
  description = "Boot disk image"
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "enable_external_ip" {
  description = "Whether to assign an ephemeral external IP"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to the VM"
  type        = map(string)
  default = {
    env     = "lab"
    week    = "4"
    day     = "20"
    managed = "terraform"
  }
}

variable "tags" {
  description = "Network tags"
  type        = list(string)
  default     = ["tf-lab"]
}
EOF
```

### Step 4 — Write main.tf

```bash
cat > main.tf << 'EOF'
resource "google_compute_instance" "vm" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.disk_size_gb
    }
  }

  network_interface {
    network = "default"

    # Conditionally assign external IP
    dynamic "access_config" {
      for_each = var.enable_external_ip ? [1] : []
      content {}
    }
  }

  labels = var.labels
  tags   = var.tags

  metadata = {
    enable-oslogin = "TRUE"
  }
}
EOF
```

### Step 5 — Write outputs.tf

```bash
cat > outputs.tf << 'EOF'
output "vm_name" {
  description = "Name of the created VM"
  value       = google_compute_instance.vm.name
}

output "vm_zone" {
  description = "Zone where the VM was created"
  value       = google_compute_instance.vm.zone
}

output "vm_machine_type" {
  description = "Machine type of the VM"
  value       = google_compute_instance.vm.machine_type
}

output "vm_internal_ip" {
  description = "Internal IP address"
  value       = google_compute_instance.vm.network_interface[0].network_ip
}

output "vm_external_ip" {
  description = "External IP address (empty if external IP disabled)"
  value       = var.enable_external_ip ? google_compute_instance.vm.network_interface[0].access_config[0].nat_ip : "N/A"
}

output "vm_self_link" {
  description = "Self-link URL of the VM"
  value       = google_compute_instance.vm.self_link
}

output "ssh_command" {
  description = "gcloud SSH command"
  value       = "gcloud compute ssh ${google_compute_instance.vm.name} --zone=${google_compute_instance.vm.zone}"
}
EOF
```

### Step 6 — Write terraform.tfvars

```bash
cat > terraform.tfvars << 'EOF'
# Project-specific values
project_id = "YOUR_PROJECT_ID"

# VM configuration
vm_name      = "tf-day20-vm"
machine_type = "e2-micro"
zone         = "europe-west2-b"
disk_size_gb = 10

# Feature toggles
enable_external_ip = true

# Labels
labels = {
  env     = "lab"
  week    = "4"
  day     = "20"
  managed = "terraform"
}
EOF
```

### Step 7 — Init and Plan

```bash
terraform init

# Plan — it reads terraform.tfvars automatically
terraform plan
```

### Step 8 — Test Variable Override via CLI

```bash
# Override vm_name via -var flag (highest priority except env var)
terraform plan -var="vm_name=cli-override-vm"

# Override via environment variable
export TF_VAR_vm_name="env-override-vm"
terraform plan
unset TF_VAR_vm_name
```

### Step 9 — Test Validation

```bash
# This should FAIL — invalid machine_type
terraform plan -var="machine_type=n1-standard-96"
# Error: machine_type must be one of: e2-micro, e2-small, e2-medium.

# This should FAIL — disk too small
terraform plan -var="disk_size_gb=5"
# Error: disk_size_gb must be between 10 and 100.

# This should FAIL — invalid VM name
terraform plan -var="vm_name=UPPERCASE-BAD"
# Error: vm_name must start with a letter...
```

### Step 10 — Apply

```bash
terraform apply
```

### Step 11 — Query Outputs

```bash
# All outputs
terraform output

# Specific output
terraform output vm_external_ip

# Raw (no quotes — useful for piping)
terraform output -raw vm_external_ip

# JSON format
terraform output -json

# Use in a gcloud command
gcloud compute ssh $(terraform output -raw vm_name) \
    --zone=$(terraform output -raw vm_zone) \
    --command="hostname"
```

### Step 12 — Create an Alternative tfvars File

```bash
cat > small-vm.tfvars << 'EOF'
project_id         = "YOUR_PROJECT_ID"
vm_name            = "tf-small-test"
machine_type       = "e2-micro"
disk_size_gb       = 10
enable_external_ip = false
labels = {
  env = "test"
  managed = "terraform"
}
EOF

# Plan with the alternative file
terraform plan -var-file="small-vm.tfvars"
# Note: enable_external_ip=false means no access_config block
```

### Cleanup

```bash
# Destroy all resources
terraform destroy

# Verify
gcloud compute instances list --filter="name~tf-day20"

# Clean up
cd ~ && rm -rf ~/tf-day20
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Variables** make Terraform configs reusable — like parameters in a bash function
- Types: `string`, `number`, `bool`, `list(type)`, `map(type)`, `object({...})`, `set(type)`
- Variables without `default` are **required** — Terraform prompts or errors if missing
- **Precedence** (low→high): default < `terraform.tfvars` < `*.auto.tfvars` < `-var-file` < `-var` < `TF_VAR_*`
- **Validation blocks** enforce constraints at plan time — fail fast before API calls
- **Sensitive** variables are hidden from output but still stored in state (plain text!)
- **Outputs** export values after apply — query with `terraform output`
- `terraform.tfvars` is auto-loaded; custom `.tfvars` files need `-var-file` flag
- Use `dynamic` blocks for conditional resource arguments (e.g., optional external IP)
- Use `-raw` flag when piping output values to other commands

### Essential Commands

```bash
# Supply variables
terraform apply -var="key=value"                    # CLI flag
terraform apply -var-file="prod.tfvars"             # Custom tfvars file
export TF_VAR_project_id="my-project"               # Environment variable

# Query outputs
terraform output                                     # All outputs
terraform output vm_name                             # Specific output
terraform output -raw vm_ip                          # Raw (no quotes)
terraform output -json                               # JSON format

# Validate
terraform validate                                   # Check syntax + types
terraform plan -var="machine_type=invalid"           # Test validation rules
```

---

## Part 4 — Quiz (15 min)

**Question 1: You have `default = "e2-micro"` in your variable block, `machine_type = "e2-small"` in `terraform.tfvars`, and you run `terraform apply -var="machine_type=e2-medium"`. Which value is used?**

<details>
<summary>Show Answer</summary>

**`e2-medium`** — the `-var` CLI flag wins. The precedence order is:

1. `default` in variable block → `e2-micro` (lowest)
2. `terraform.tfvars` → `e2-small`
3. `-var` flag → `e2-medium` (highest of these three)

Only `TF_VAR_*` environment variables would override the `-var` flag. Think of it like shell variable precedence: `export VAR=env` < inline `VAR=val command`.

</details>

---

**Question 2: You declare a variable with `sensitive = true`. Is the actual value protected in the state file?**

<details>
<summary>Show Answer</summary>

**No.** The `sensitive` flag only redacts the value from **CLI output** (`plan`, `apply`, `output` display). The actual value is still stored in **plain text** in `terraform.tfstate`.

This means:
- Anyone with access to the state file can read the value
- State files must be protected with proper access controls
- For production secrets, use a dedicated secrets manager (GCP Secret Manager, HashiCorp Vault) and reference them via `data` sources instead of storing them as Terraform variables

</details>

---

**Question 3: You have a variable with no `default` value and no value in `terraform.tfvars`. What happens when you run `terraform apply`?**

<details>
<summary>Show Answer</summary>

Terraform will **interactively prompt** you for the value at the terminal:

```
var.project_id
  GCP project ID

  Enter a value: _
```

If running in a non-interactive context (CI/CD pipeline with `-input=false`), it will **error out**:

```
Error: No value for required variable
```

This is by design — variables without defaults are considered **required**. Like a bash script that checks `if [[ -z "$1" ]]; then echo "Usage: ..."; exit 1; fi`.

</details>

---

**Question 4: You want to conditionally NOT assign an external IP based on a boolean variable. How do you achieve this in HCL?**

<details>
<summary>Show Answer</summary>

Use a **`dynamic` block** with a conditional `for_each`:

```hcl
variable "enable_external_ip" {
  type    = bool
  default = true
}

resource "google_compute_instance" "vm" {
  # ...
  network_interface {
    network = "default"

    dynamic "access_config" {
      for_each = var.enable_external_ip ? [1] : []
      content {}
    }
  }
}
```

When `enable_external_ip = true`, `for_each = [1]` creates one `access_config` block (external IP assigned). When `false`, `for_each = []` creates zero blocks (no external IP).

This pattern is common for optional nested blocks. It replaces the `count` trick used for entire resources.

</details>

---

*End of Day 20 — Tomorrow: Creating VPC, subnets, and firewall rules with Terraform.*
