# Day 23 — Terraform Modules: Reusable Infrastructure

> **Week 4 · Terraform Basics** | Region: `europe-west2` | Study time: 2 hours

---

## Part 1 — Concept (30 min)

### 1.1 Why Modules?

Copying the same resource blocks across projects is like copying the same bash function into every script. **Modules** let you package and reuse infrastructure — write once, deploy many.

| Linux Analogy | Terraform Equivalent |
|---|---|
| Bash function in a sourced file | Module |
| `source /opt/lib/functions.sh` | `module "vm" { source = "./modules/vm" }` |
| Function parameters | Module input variables |
| Function return value | Module output values |
| `/usr/lib/` (shared library) | `modules/` directory |
| `apt install nginx` (pre-built) | Public registry module |

### 1.2 Root Module vs Child Module

```
┌───────────────────────────────────────────────────────────┐
│                    ROOT MODULE                             │
│                    (your main config)                      │
│                                                           │
│  ┌────────────────────────────────────────────────────┐   │
│  │  main.tf                                           │   │
│  │                                                    │   │
│  │  module "web_vm" {                                 │   │
│  │    source       = "./modules/vm"  ──────────────┐  │   │
│  │    vm_name      = "web-server"                  │  │   │
│  │    machine_type = "e2-small"                    │  │   │
│  │  }                                              │  │   │
│  │                                                 │  │   │
│  │  module "app_vm" {                              │  │   │
│  │    source       = "./modules/vm"  ──────────┐   │  │   │
│  │    vm_name      = "app-server"              │   │  │   │
│  │    machine_type = "e2-micro"                │   │  │   │
│  │  }                                          │   │  │   │
│  └─────────────────────────────────────────────┼───┼──┘   │
│                                                │   │      │
│       ┌────────────────────────────────────────┼───┘      │
│       │                                        │          │
│       ▼                                        ▼          │
│  ┌──────────────────────────────────────────────────┐     │
│  │          CHILD MODULE: modules/vm/               │     │
│  │                                                  │     │
│  │  variables.tf  ← receives vm_name, machine_type  │     │
│  │  main.tf       ← creates google_compute_instance │     │
│  │  outputs.tf    ← returns IP, name, self_link     │     │
│  └──────────────────────────────────────────────────┘     │
└───────────────────────────────────────────────────────────┘
```

| Term | Definition |
|---|---|
| **Root module** | The top-level `.tf` files where you run `terraform apply` |
| **Child module** | A reusable package called with `module "name" { ... }` |
| **Source** | Where the module lives (local path, Git repo, registry) |
| **Module inputs** | Variables declared in the child module's `variables.tf` |
| **Module outputs** | Outputs declared in the child module's `outputs.tf` |

### 1.3 Module Directory Structure

```
my-project/
├── main.tf              ← Root module: calls child modules
├── variables.tf         ← Root variables
├── outputs.tf           ← Root outputs (can reference module outputs)
├── providers.tf
├── terraform.tfvars
│
└── modules/
    └── vm/              ← Child module
        ├── main.tf      ← Resource definitions
        ├── variables.tf ← Input interface (what the caller provides)
        └── outputs.tf   ← Output interface (what the caller receives)
```

> **Rule of three:** If you copy-paste the same resource block three times, extract it into a module.

### 1.4 Module Source Types

```
┌──────────────────────────────────────────────────────┐
│               MODULE SOURCE TYPES                     │
│                                                      │
│  ┌──────────────┐  source = "./modules/vm"           │
│  │  Local Path  │  Filesystem path relative to root  │
│  └──────────────┘                                    │
│                                                      │
│  ┌──────────────┐  source = "git::https://..."       │
│  │  Git Repo    │  Any Git repo (GitHub, GitLab)     │
│  └──────────────┘                                    │
│                                                      │
│  ┌──────────────┐  source = "hashicorp/consul/aws"   │
│  │  TF Registry │  Public Terraform Registry         │
│  └──────────────┘                                    │
│                                                      │
│  ┌──────────────┐  source = "gs://bucket/module.zip" │
│  │  GCS Bucket  │  Module stored in Cloud Storage    │
│  └──────────────┘                                    │
└──────────────────────────────────────────────────────┘
```

| Source | Example | Use Case |
|---|---|---|
| Local path | `./modules/vm` | Same repo, quick iteration |
| Git URL | `git::https://github.com/org/modules.git//vm?ref=v1.0` | Versioned, cross-repo |
| Terraform Registry | `"GoogleCloudPlatform/lb-http/google"` | Community/official modules |
| GCS bucket | `gs://my-modules/vm/v1.0.0.zip` | Private module storage |

### 1.5 Module Inputs and Outputs

**Child module `variables.tf` (the interface):**

```hcl
# modules/vm/variables.tf

variable "vm_name" {
  description = "Name of the VM"
  type        = string
}

variable "machine_type" {
  description = "Machine type"
  type        = string
  default     = "e2-micro"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "europe-west2-b"
}
```

**Root module calling the child (passing inputs):**

```hcl
# main.tf (root)

module "web" {
  source       = "./modules/vm"
  vm_name      = "web-server"
  machine_type = "e2-small"
  zone         = "europe-west2-b"
}
```

**Child module `outputs.tf` (what root can read):**

```hcl
# modules/vm/outputs.tf

output "vm_ip" {
  value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}
```

**Root module using child output:**

```hcl
# outputs.tf (root)

output "web_server_ip" {
  value = module.web.vm_ip   # module.<MODULE_NAME>.<OUTPUT_NAME>
}
```

### 1.6 Module Best Practices

| Practice | Why |
|---|---|
| Keep modules small and focused | One module = one concern (VM, VPC, firewall) |
| Always declare `description` on variables | Self-documenting interface |
| Use `default` for optional parameters | Reduce required inputs for callers |
| Put `version` constraints on registry modules | Prevent breaking changes |
| Don't hardcode the provider in a child module | Let the root module configure it |
| Output everything the caller might need | IDs, names, IPs, self-links |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Goal

Create a reusable VM module in `modules/vm/`, call it from the root module to create two VMs with different configs.

### Prerequisites

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-b
```

### Step 1 — Create Directory Structure

```bash
mkdir -p ~/tf-day23/modules/vm
cd ~/tf-day23
```

### Step 2 — Write the VM Module (Child)

**modules/vm/variables.tf:**

```bash
cat > modules/vm/variables.tf << 'EOF'
variable "vm_name" {
  description = "Name of the VM instance"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.vm_name))
    error_message = "vm_name must be lowercase, start with a letter, max 63 chars."
  }
}

variable "machine_type" {
  description = "Machine type for the VM"
  type        = string
  default     = "e2-micro"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "europe-west2-b"
}

variable "image" {
  description = "Boot disk image"
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 10
}

variable "network" {
  description = "VPC network name or self-link"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Subnetwork name or self-link (optional, uses network's default if empty)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Network tags"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to the VM"
  type        = map(string)
  default     = {}
}

variable "enable_external_ip" {
  description = "Whether to assign an external IP"
  type        = bool
  default     = true
}

variable "startup_script" {
  description = "Startup script content"
  type        = string
  default     = ""
}
EOF
```

**modules/vm/main.tf:**

```bash
cat > modules/vm/main.tf << 'EOF'
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
    network    = var.subnetwork == "" ? var.network : null
    subnetwork = var.subnetwork != "" ? var.subnetwork : null

    dynamic "access_config" {
      for_each = var.enable_external_ip ? [1] : []
      content {}
    }
  }

  tags = var.tags

  labels = merge(
    {
      managed = "terraform"
    },
    var.labels
  )

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = var.startup_script != "" ? var.startup_script : null
}
EOF
```

**modules/vm/outputs.tf:**

```bash
cat > modules/vm/outputs.tf << 'EOF'
output "name" {
  description = "Name of the VM"
  value       = google_compute_instance.vm.name
}

output "self_link" {
  description = "Self-link of the VM"
  value       = google_compute_instance.vm.self_link
}

output "zone" {
  description = "Zone of the VM"
  value       = google_compute_instance.vm.zone
}

output "internal_ip" {
  description = "Internal IP address"
  value       = google_compute_instance.vm.network_interface[0].network_ip
}

output "external_ip" {
  description = "External IP address (empty if no external IP)"
  value       = var.enable_external_ip ? google_compute_instance.vm.network_interface[0].access_config[0].nat_ip : ""
}

output "instance_id" {
  description = "Instance ID"
  value       = google_compute_instance.vm.instance_id
}
EOF
```

### Step 3 — Write the Root Module

**providers.tf:**

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
  region  = "europe-west2"
  zone    = "europe-west2-b"
}
EOF
```

**variables.tf (root):**

```bash
cat > variables.tf << 'EOF'
variable "project_id" {
  description = "GCP project ID"
  type        = string
}
EOF
```

**terraform.tfvars:**

```bash
cat > terraform.tfvars << 'EOF'
project_id = "YOUR_PROJECT_ID"
EOF
```

**main.tf (root — calls the module twice):**

```bash
cat > main.tf << 'EOF'
# ──────────────────────────────────────────────
# Web Server VM (using our module)
# ──────────────────────────────────────────────

module "web_vm" {
  source = "./modules/vm"

  vm_name      = "tf-web-server"
  machine_type = "e2-small"
  zone         = "europe-west2-b"
  disk_size_gb = 10

  tags = ["http-server", "ssh-allowed"]

  labels = {
    env  = "lab"
    role = "web"
    day  = "23"
  }

  enable_external_ip = true

  startup_script = <<-SCRIPT
    #!/bin/bash
    apt-get update && apt-get install -y nginx
    echo "<h1>Web Server — $(hostname)</h1>" > /var/www/html/index.html
    systemctl enable nginx && systemctl start nginx
  SCRIPT
}

# ──────────────────────────────────────────────
# App Server VM (same module, different config)
# ──────────────────────────────────────────────

module "app_vm" {
  source = "./modules/vm"

  vm_name      = "tf-app-server"
  machine_type = "e2-micro"
  zone         = "europe-west2-b"
  disk_size_gb = 10

  tags = ["ssh-allowed"]

  labels = {
    env  = "lab"
    role = "app"
    day  = "23"
  }

  enable_external_ip = false  # Internal only
}
EOF
```

**outputs.tf (root — exposes module outputs):**

```bash
cat > outputs.tf << 'EOF'
# ── Web Server Outputs ──

output "web_vm_name" {
  description = "Web server VM name"
  value       = module.web_vm.name
}

output "web_vm_external_ip" {
  description = "Web server external IP"
  value       = module.web_vm.external_ip
}

output "web_vm_internal_ip" {
  description = "Web server internal IP"
  value       = module.web_vm.internal_ip
}

# ── App Server Outputs ──

output "app_vm_name" {
  description = "App server VM name"
  value       = module.app_vm.name
}

output "app_vm_internal_ip" {
  description = "App server internal IP"
  value       = module.app_vm.internal_ip
}

output "app_vm_external_ip" {
  description = "App server external IP (should be empty)"
  value       = module.app_vm.external_ip
}
EOF
```

### Step 4 — Verify the Structure

```bash
find ~/tf-day23 -name "*.tf" | sort
```

Expected:

```
/home/user/tf-day23/main.tf
/home/user/tf-day23/modules/vm/main.tf
/home/user/tf-day23/modules/vm/outputs.tf
/home/user/tf-day23/modules/vm/variables.tf
/home/user/tf-day23/outputs.tf
/home/user/tf-day23/providers.tf
/home/user/tf-day23/terraform.tfvars
/home/user/tf-day23/variables.tf
```

### Step 5 — Init (Installs Module)

```bash
terraform init
```

**Expected output:**

```
Initializing the backend...
Initializing modules...
- web_vm in modules/vm
- app_vm in modules/vm

Initializing provider plugins...
- Finding hashicorp/google versions matching "~> 5.0"...
- Installing hashicorp/google v5.x.x...

Terraform has been successfully initialized!
```

Notice: `init` discovers and loads both module calls.

### Step 6 — Plan and Apply

```bash
terraform plan
```

**Expected plan:**

```
Plan: 2 to add, 0 to change, 0 to destroy.

  # module.web_vm.google_compute_instance.vm will be created
  # module.app_vm.google_compute_instance.vm will be created
```

Notice the **module prefix** in resource addresses: `module.web_vm.google_compute_instance.vm`.

```bash
terraform apply
```

### Step 7 — Verify

```bash
# Check outputs
terraform output

# List resources — note the module prefix
terraform state list
# module.app_vm.google_compute_instance.vm
# module.web_vm.google_compute_instance.vm

# Show a module resource
terraform state show module.web_vm.google_compute_instance.vm

# Verify with gcloud
gcloud compute instances list --filter="labels.day=23" \
    --format="table(name,machineType.basename(),status,networkInterfaces[0].accessConfigs[0].natIP)"

# Test the web server
WEB_IP=$(terraform output -raw web_vm_external_ip)
curl -s "http://$WEB_IP"
```

### Step 8 — Deploy a Third VM with the Same Module

Add another module call to `main.tf`:

```bash
cat >> main.tf << 'EOF'

# ──────────────────────────────────────────────
# Database Server VM (same module, third call)
# ──────────────────────────────────────────────

module "db_vm" {
  source = "./modules/vm"

  vm_name      = "tf-db-server"
  machine_type = "e2-micro"
  zone         = "europe-west2-b"
  disk_size_gb = 20

  tags = ["ssh-allowed"]

  labels = {
    env  = "lab"
    role = "database"
    day  = "23"
  }

  enable_external_ip = false
}
EOF

cat >> outputs.tf << 'EOF'

# ── DB Server Outputs ──

output "db_vm_name" {
  value = module.db_vm.name
}

output "db_vm_internal_ip" {
  value = module.db_vm.internal_ip
}
EOF
```

```bash
# No need to re-init (same module, already loaded)
terraform plan
# Plan: 1 to add, 0 to change, 0 to destroy.

terraform apply
```

### Step 9 — Inspect Module in State

```bash
# All resources with module prefix
terraform state list

# Output:
# module.app_vm.google_compute_instance.vm
# module.db_vm.google_compute_instance.vm
# module.web_vm.google_compute_instance.vm

# Each module instance has its own state
terraform state show module.db_vm.google_compute_instance.vm
```

### Cleanup

```bash
# Destroy all three VMs
terraform destroy

# Verify
gcloud compute instances list --filter="labels.day=23"

# Clean up
cd ~ && rm -rf ~/tf-day23
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Module** = reusable package of `.tf` files. Like a bash function in a sourced library.
- **Root module** = top-level config where you run `terraform apply`
- **Child module** = called with `module "name" { source = "..." }`
- Module interface: **inputs** (`variables.tf`) and **outputs** (`outputs.tf`)
- Reference module outputs in root: `module.<MODULE_NAME>.<OUTPUT_NAME>`
- Resource addresses include module prefix: `module.web_vm.google_compute_instance.vm`
- Source types: local path (`./modules/vm`), Git, Terraform Registry, GCS
- `terraform init` discovers and loads modules
- Don't hardcode provider config in child modules — let root handle it
- `merge()` function combines maps (useful for default + user labels)
- `dynamic` blocks for conditional nested blocks
- Rule of three: if you copy a resource 3 times, extract to a module

### Essential Commands

```bash
# Module lifecycle
terraform init              # Discovers and installs modules
terraform plan              # Shows module.name.resource changes
terraform apply             # Creates all module resources
terraform destroy           # Destroys all module resources

# Inspect module state
terraform state list                              # Shows module-prefixed addresses
terraform state show module.web_vm.google_compute_instance.vm

# Query module outputs
terraform output web_vm_external_ip
terraform output -json

# Module call syntax in .tf
module "name" {
  source       = "./modules/vm"            # Required: where the module lives
  vm_name      = "my-server"               # Input variable values
  machine_type = "e2-small"
}
```

---

## Part 4 — Quiz (15 min)

**Question 1: You create a module at `./modules/vm/` and call it in your root `main.tf`. After writing the files, you run `terraform plan` and get an error: "Module not installed." What do you need to run first?**

<details>
<summary>Show Answer</summary>

Run **`terraform init`**. Whenever you add a new module (or change its `source`), you must re-run `init` so Terraform discovers and loads it. This applies to both local and remote modules.

```bash
terraform init
# Output: Initializing modules... - web_vm in modules/vm
```

Think of it like `source ./lib/functions.sh` — the shell needs to load the file before you can call functions from it. `terraform init` is Terraform's module loader.

</details>

---

**Question 2: Your root module calls `module "web" { source = "./modules/vm" }`. In the root `outputs.tf`, how do you reference the child module's output named `external_ip`?**

<details>
<summary>Show Answer</summary>

Use the syntax: **`module.<MODULE_NAME>.<OUTPUT_NAME>`**

```hcl
output "web_server_ip" {
  value = module.web.external_ip
}
```

The pattern is always `module.` + the label you gave in the module block (`"web"`) + `.` + the output name from the child module's `outputs.tf` (`external_ip`).

If the child module doesn't declare that output, you'll get an error: `module.web does not have an output named "external_ip"`.

</details>

---

**Question 3: You call the same module twice with different parameters. In `terraform state list`, what do the resource addresses look like?**

<details>
<summary>Show Answer</summary>

Each module call gets its own namespace in state:

```
module.web_vm.google_compute_instance.vm
module.app_vm.google_compute_instance.vm
```

The format is: `module.<CALL_NAME>.<RESOURCE_TYPE>.<RESOURCE_NAME>`

Even though both use the same module source (`./modules/vm`), they are completely independent instances. Changing one doesn't affect the other. It's like calling the same function twice with different arguments — each call has its own scope and return value.

</details>

---

**Question 4: You want your VM module to accept an optional startup script. If the caller doesn't provide one, no `metadata_startup_script` should be set. How do you handle this?**

<details>
<summary>Show Answer</summary>

Use a variable with an empty default and a conditional in the resource:

```hcl
# modules/vm/variables.tf
variable "startup_script" {
  description = "Startup script content (optional)"
  type        = string
  default     = ""
}

# modules/vm/main.tf
resource "google_compute_instance" "vm" {
  # ...
  metadata_startup_script = var.startup_script != "" ? var.startup_script : null
}
```

When `var.startup_script` is empty (`""`), the ternary returns `null`. In Terraform, setting an argument to `null` is equivalent to not setting it at all — the attribute is omitted from the API call.

This is a common pattern for optional arguments in modules. The caller can either pass a value or skip it entirely (uses the `""` default → evaluates to `null` → omitted).

</details>

---

*End of Day 23 — Tomorrow: PROJECT — Build a Terraform Landing Zone combining everything from Week 4.*
