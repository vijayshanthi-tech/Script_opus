# Day 19 — Terraform Lifecycle: init, plan, apply, destroy

> **Week 4 · Terraform Basics** | Region: `europe-west2` | Study time: 2 hours

---

## Part 1 — Concept (30 min)

### 1.1 What Is Terraform?

Terraform is HashiCorp's **Infrastructure as Code (IaC)** tool — think of it as writing a **Makefile for your entire infrastructure**. Instead of running dozens of `gcloud` commands, you declare what you want in `.tf` files and Terraform figures out how to build it.

| Linux Analogy | Terraform Equivalent |
|---|---|
| `Makefile` | `.tf` configuration files |
| `make build` | `terraform apply` |
| `make clean` | `terraform destroy` |
| `make -n` (dry run) | `terraform plan` |
| `apt install` (package manager) | `terraform init` (plugin manager) |
| State of installed packages (`dpkg -l`) | `terraform.tfstate` |
| `diff` between desired and actual | `terraform plan` output |

### 1.2 The Terraform Lifecycle

```
┌─────────────────────────────────────────────────────────┐
│              TERRAFORM LIFECYCLE                         │
│                                                         │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐            │
│  │  WRITE   │──>│   INIT   │──>│   PLAN   │            │
│  │  .tf     │   │          │   │          │            │
│  │  files   │   │ Download │   │ Dry run  │            │
│  │          │   │ provider │   │ show     │            │
│  │          │   │ plugins  │   │ changes  │            │
│  └──────────┘   └──────────┘   └────┬─────┘            │
│                                      │                  │
│                                      ▼                  │
│                                ┌──────────┐             │
│                                │  APPLY   │             │
│                                │          │             │
│                                │ Execute  │             │
│                                │ changes  │             │
│                                │ Update   │             │
│                                │ state    │             │
│                                └────┬─────┘             │
│                                      │                  │
│                                      ▼                  │
│                                ┌──────────┐             │
│                                │ DESTROY  │             │
│                                │          │             │
│                                │ Tear     │             │
│                                │ down all │             │
│                                │ infra    │             │
│                                └──────────┘             │
└─────────────────────────────────────────────────────────┘
```

| Command | Purpose | When to Use |
|---|---|---|
| `terraform init` | Download provider plugins, initialise backend | First time, or after adding a new provider/module |
| `terraform plan` | Preview changes without applying | Always before `apply` — review the diff |
| `terraform apply` | Create/modify real infrastructure | When you're happy with the plan |
| `terraform destroy` | Delete all resources managed by this config | Cleanup/teardown |
| `terraform fmt` | Format `.tf` files consistently | Before committing code |
| `terraform validate` | Check syntax without accessing APIs | Quick syntax check |

### 1.3 HCL Syntax Basics

HCL (HashiCorp Configuration Language) is a declarative language — you describe **what** you want, not **how** to build it.

```hcl
# Block type    "Label 1"      "Label 2"
resource      "google_compute_instance" "my_vm" {
  # Arguments
  name         = "my-vm"
  machine_type = "e2-micro"
  zone         = "europe-west2-b"

  # Nested block
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  # Another nested block
  network_interface {
    network = "default"
    access_config {}   # empty block = assign external IP
  }
}
```

| HCL Element | Description | Linux Analogy |
|---|---|---|
| `resource` | A piece of infrastructure to manage | A target in a Makefile |
| `provider` | Plugin that talks to an API (GCP, AWS, etc.) | A package repository |
| `variable` | Input parameter | Environment variable |
| `output` | Exported value after apply | Command output to stdout |
| `data` | Read-only lookup of existing resources | `dpkg -l` (query, don't install) |
| `locals` | Computed intermediate values | Shell variable set inside script |

### 1.4 Providers

A provider is a plugin that maps Terraform resources to real API calls — like a **device driver for infrastructure**.

```
┌─────────────────────────────────────────────────────┐
│                TERRAFORM CORE                        │
│                                                     │
│   .tf files ──> Plan ──> Apply                      │
│                   │                                 │
│                   ▼                                 │
│   ┌──────────────────────────────────────────┐      │
│   │            PROVIDER PLUGINS              │      │
│   │                                          │      │
│   │  ┌──────────┐ ┌──────┐ ┌────────────┐   │      │
│   │  │  google   │ │ aws  │ │ azurerm    │   │      │
│   │  │ (GCP)    │ │      │ │ (Azure)    │   │      │
│   │  └────┬─────┘ └──┬───┘ └─────┬──────┘   │      │
│   │       │          │            │          │      │
│   └───────┼──────────┼────────────┼──────────┘      │
│           ▼          ▼            ▼                  │
│        GCP API    AWS API     Azure API              │
└─────────────────────────────────────────────────────┘
```

### 1.5 .tf File Structure

A typical Terraform project has this layout:

```
my-project/
├── main.tf           # Resource definitions (the "what")
├── variables.tf      # Input variable declarations
├── outputs.tf        # Output value declarations
├── providers.tf      # Provider configuration
├── terraform.tfvars  # Variable values (not committed if secrets)
├── .terraform/       # Downloaded provider plugins (auto-generated)
├── terraform.tfstate # Current state of infrastructure (auto-generated)
└── .terraform.lock.hcl  # Provider version lock file (commit this)
```

| File | Purpose | Commit to Git? |
|---|---|---|
| `main.tf` | Core resource definitions | Yes |
| `variables.tf` | Variable declarations | Yes |
| `outputs.tf` | Output definitions | Yes |
| `providers.tf` | Provider config + version constraints | Yes |
| `terraform.tfvars` | Variable values | Only if no secrets |
| `.terraform/` | Plugin cache directory | No (`.gitignore`) |
| `terraform.tfstate` | State file (current infra snapshot) | No (use remote state) |
| `.terraform.lock.hcl` | Provider version lock | Yes |

### 1.6 The State File — terraform.tfstate

The state file is Terraform's **memory** — it maps your `.tf` config to real infrastructure. Think of it as Terraform's version of `dpkg --status` — it knows what's installed and where.

```
┌─────────────────────────────┐       ┌─────────────────────────┐
│  .tf files (desired state)  │       │  terraform.tfstate      │
│                             │       │  (last known state)     │
│  resource "vm" "web" {      │       │  {                      │
│    name = "web-vm"          │  ──>  │    "vm.web": {          │
│    machine_type = "e2-micro"│ PLAN  │      id: "123456",     │
│  }                          │ DIFF  │      name: "web-vm",   │
│                             │       │      type: "e2-micro"   │
└─────────────────────────────┘       │    }                    │
                                      │  }                      │
                                      └─────────────────────────┘
```

> **Critical rule:** Never hand-edit `terraform.tfstate`. It's auto-managed. Corrupting it is like deleting `/var/lib/dpkg/status` — Terraform won't know what exists.

---

## Part 2 — Hands-On Lab (60 min)

### Lab Goal

Install Terraform, write a `main.tf` to create a GCE VM, and walk through the full lifecycle: `init` → `plan` → `apply` → `destroy`.

### Prerequisites

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-b
```

### Step 1 — Install Terraform (10 min)

**Option A — Linux / Cloud Shell:**

```bash
# Download the latest Terraform binary
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common

wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update && sudo apt-get install terraform

# Verify
terraform version
```

**Option B — Already in Cloud Shell:**

```bash
# Terraform is pre-installed in Google Cloud Shell
terraform version
```

### Step 2 — Create the Project Directory

```bash
mkdir -p ~/tf-day19 && cd ~/tf-day19
```

### Step 3 — Write providers.tf

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
  project = "YOUR_PROJECT_ID"
  region  = "europe-west2"
  zone    = "europe-west2-b"
}
EOF
```

### Step 4 — Write main.tf

```bash
cat > main.tf << 'EOF'
# Create a Compute Engine VM
resource "google_compute_instance" "day19_vm" {
  name         = "tf-day19-vm"
  machine_type = "e2-micro"
  zone         = "europe-west2-b"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10   # GB
    }
  }

  network_interface {
    network = "default"

    # Assign an ephemeral external IP
    access_config {}
  }

  labels = {
    env     = "lab"
    week    = "4"
    day     = "19"
    managed = "terraform"
  }

  tags = ["tf-lab"]

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
  description = "Name of the VM"
  value       = google_compute_instance.day19_vm.name
}

output "vm_external_ip" {
  description = "External IP of the VM"
  value       = google_compute_instance.day19_vm.network_interface[0].access_config[0].nat_ip
}

output "vm_internal_ip" {
  description = "Internal IP of the VM"
  value       = google_compute_instance.day19_vm.network_interface[0].network_ip
}

output "vm_self_link" {
  description = "Self-link of the VM"
  value       = google_compute_instance.day19_vm.self_link
}
EOF
```

### Step 6 — terraform init

```bash
terraform init
```

**Expected output:**

```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/google versions matching "~> 5.0"...
- Installing hashicorp/google v5.x.x...
- Installed hashicorp/google v5.x.x (signed by HashiCorp)

Terraform has been successfully initialized!
```

**What happened:**
- Terraform read `providers.tf` and downloaded the `google` provider plugin
- Created `.terraform/` directory with the plugin binary
- Created `.terraform.lock.hcl` to lock the exact provider version

```bash
# Verify — see the downloaded provider
ls -la .terraform/providers/registry.terraform.io/hashicorp/google/

# See the lock file
cat .terraform.lock.hcl
```

### Step 7 — terraform plan

```bash
terraform plan
```

**Expected output (abbreviated):**

```
Terraform will perform the following actions:

  # google_compute_instance.day19_vm will be created
  + resource "google_compute_instance" "day19_vm" {
      + name         = "tf-day19-vm"
      + machine_type = "e2-micro"
      + zone         = "europe-west2-b"
      + ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

**Read the plan like a diff:**
- `+` = will be created (like `>>` in a script — adding)
- `-` = will be destroyed
- `~` = will be modified in-place
- `-/+` = must destroy and recreate (replace)

### Step 8 — terraform apply

```bash
terraform apply
```

Terraform shows the plan again and asks for confirmation:

```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
```

**After apply:**

```
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

vm_name        = "tf-day19-vm"
vm_external_ip = "34.x.x.x"
vm_internal_ip = "10.x.x.x"
vm_self_link   = "projects/YOUR_PROJECT_ID/zones/europe-west2-b/instances/tf-day19-vm"
```

### Step 9 — Verify with gcloud

```bash
# Confirm the VM exists
gcloud compute instances list --filter="name=tf-day19-vm"

# SSH into it
gcloud compute ssh tf-day19-vm --zone=europe-west2-b --command="hostname && uname -a"
```

### Step 10 — Inspect the State File

```bash
# Show what Terraform is tracking
terraform show

# List all resources in state
terraform state list

# Get details of a specific resource
terraform state show google_compute_instance.day19_vm

# Look at the raw state file (JSON)
cat terraform.tfstate | head -50
```

### Step 11 — terraform fmt and validate

```bash
# Auto-format all .tf files (like gofmt or black)
terraform fmt

# Validate syntax without contacting APIs
terraform validate
```

### Step 12 — terraform destroy (Cleanup)

```bash
terraform destroy
```

```
Plan: 0 to add, 0 to change, 1 to destroy.

Do you really want to destroy all resources?
  Enter a value: yes

Destroy complete! Resources: 1 destroyed.
```

```bash
# Verify it's gone
gcloud compute instances list --filter="name=tf-day19-vm"

# The state file is now empty (no resources)
terraform state list
```

### Cleanup Verification

```bash
# Confirm no resources left
gcloud compute instances list --filter="labels.day=19"

# Optionally remove the working directory
cd ~ && rm -rf ~/tf-day19
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- Terraform = **declarative IaC** — you describe desired state, it figures out the actions
- **Lifecycle**: `init` (download plugins) → `plan` (dry run diff) → `apply` (execute) → `destroy` (teardown)
- **Provider** = API plugin (e.g., `hashicorp/google` for GCP); downloaded by `init`
- **Resource block** = one piece of infrastructure: `resource "TYPE" "NAME" { ... }`
- **HCL** = HashiCorp Configuration Language; declarative, supports blocks, maps, lists
- **State file** (`terraform.tfstate`) = Terraform's memory of what it created + real IDs. Never edit manually.
- `.terraform/` = local plugin cache. Don't commit. Regenerated by `init`.
- `.terraform.lock.hcl` = exact provider versions. DO commit.
- Plan symbols: `+` create, `-` destroy, `~` update, `-/+` replace
- `terraform fmt` = auto-format; `terraform validate` = syntax check
- Always run `plan` before `apply` — treat it like `make -n` dry run

### Essential Commands

```bash
# Full lifecycle
terraform init                  # Download providers/modules
terraform plan                  # Preview changes
terraform apply                 # Execute changes (creates/modifies infra)
terraform destroy               # Tear down all managed resources

# Inspection
terraform show                  # Show current state in human-readable form
terraform state list            # List all tracked resources
terraform state show RESOURCE   # Detailed info on one resource

# Housekeeping
terraform fmt                   # Auto-format .tf files
terraform validate              # Syntax + basic validation check
terraform version               # Show Terraform + provider versions

# Apply without interactive prompt (CI/CD)
terraform apply -auto-approve
terraform destroy -auto-approve
```

---

## Part 4 — Quiz (15 min)

**Question 1: You write a new `main.tf` and run `terraform plan` immediately. It fails. What did you forget?**

<details>
<summary>Show Answer</summary>

You forgot to run **`terraform init`** first. Before Terraform can plan or apply anything, it needs to download provider plugins. `init` reads the `required_providers` block, fetches the plugins, and sets up the `.terraform/` directory. This is like forgetting to run `apt update` before `apt install`.

</details>

---

**Question 2: You run `terraform plan` and see `Plan: 0 to add, 1 to change, 0 to destroy.` with a `~` next to a resource. What does the `~` symbol mean, and what will happen when you apply?**

<details>
<summary>Show Answer</summary>

The `~` symbol means the resource will be **modified in-place** — Terraform will update the existing resource without destroying and recreating it. This happens for attributes that can be changed via API (like labels or machine type on a stopped VM).

If the change required destroying first, you'd see `-/+` (destroy and replace). The `~` means an in-place API update — less disruptive, no downtime.

</details>

---

**Question 3: A colleague accidentally deletes the `terraform.tfstate` file. The VM it tracks is still running in GCP. What happens if you run `terraform apply` now?**

<details>
<summary>Show Answer</summary>

Terraform will attempt to **create a duplicate** VM because it has no memory of the existing one. The state file is Terraform's record of what it manages. Without it, Terraform thinks nothing exists and tries to create everything from scratch.

To recover: use **`terraform import`** to re-attach the existing resource to Terraform's state before running apply. Example:

```bash
terraform import google_compute_instance.day19_vm \
    projects/YOUR_PROJECT_ID/zones/europe-west2-b/instances/tf-day19-vm
```

This is why state files should be stored in a **remote backend** (GCS bucket) — never rely solely on local state.

</details>

---

**Question 4: What is the difference between `terraform validate` and `terraform plan`? When would each fail?**

<details>
<summary>Show Answer</summary>

| | `terraform validate` | `terraform plan` |
|---|---|---|
| **What it checks** | HCL syntax, type correctness, required args | Everything `validate` does PLUS actual API connectivity |
| **Contacts APIs?** | No | Yes — checks current state against desired |
| **Speed** | Instant | Slower (API round-trips) |
| **Fails when** | Missing arguments, wrong types, syntax errors | API errors, quota limits, permissions, naming conflicts |

Example: a typo in a block name (`machin_type` instead of `machine_type`) would fail in `validate`. But a duplicate resource name in GCP would only fail during `plan` or `apply` because `validate` doesn't talk to GCP.

Think of `validate` as `bash -n script.sh` (syntax check) vs `plan` as `make -n` (dry-run that checks real dependencies).

</details>

---

*End of Day 19 — Tomorrow: Variables and outputs to make your Terraform configs reusable.*
