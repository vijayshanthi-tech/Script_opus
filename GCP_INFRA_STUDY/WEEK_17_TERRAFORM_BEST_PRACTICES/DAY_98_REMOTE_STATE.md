# Week 17, Day 98 (Tue) — Terraform Remote State

## Today's Objective

Understand and configure remote state using GCS backend, implement state locking, secure state files with encryption, and use `terraform_remote_state` data source for cross-stack references.

**Source:** [Terraform: GCS Backend](https://developer.hashicorp.com/terraform/language/settings/backends/gcs) | [Google: Manage Terraform State in GCS](https://cloud.google.com/docs/terraform/resource-management/store-state)

**Deliverable:** Working GCS backend with state locking + cross-stack data source demo

---

## Part 1: Concept (30 minutes)

### 1.1 Why Remote State?

Local state is like keeping your `/etc/passwd` on a USB stick — it works for one person but breaks when a team needs access. Remote state solves:

```
LOCAL STATE PROBLEMS                    REMOTE STATE SOLUTIONS
┌─────────────────────────┐            ┌─────────────────────────┐
│ • Single user only      │            │ • Team collaboration    │
│ • No locking            │  ──────►   │ • State locking (GCS)   │
│ • Secrets in git risk   │            │ • Encrypted at rest     │
│ • No audit trail        │            │ • Versioned (GCS)       │
│ • Lost laptop = lost    │            │ • Centrally backed up   │
│   infrastructure state  │            │ • Access-controlled     │
└─────────────────────────┘            └─────────────────────────┘
```

### 1.2 GCS Backend Architecture

```
┌──────────────┐       terraform init        ┌───────────────────┐
│  Developer   │ ──────────────────────────►  │   GCS Bucket      │
│  Workstation │                              │   (Remote State)  │
│              │  ◄── read state ──────────── │                   │
│  terraform   │  ──► write state ──────────► │  ┌─────────────┐  │
│  plan/apply  │                              │  │ .tfstate     │  │
│              │  ◄── acquire lock ─────────► │  │ .tflock      │  │
└──────────────┘                              │  └─────────────┘  │
                                              │                   │
                                              │  Encryption: ✅   │
                                              │  Versioning: ✅   │
                                              │  IAM: ✅          │
                                              └───────────────────┘
```

### 1.3 State Locking with GCS

GCS backend uses **object-level locking** to prevent concurrent modifications.

| Event | What Happens |
|---|---|
| `terraform plan` | Acquires read lock on `.tflock` |
| `terraform apply` | Acquires write lock, blocks other writers |
| Lock held by another | Error: "state locked by <user>" |
| Force unlock | `terraform force-unlock LOCK_ID` (dangerous!) |

```
Linux analogy:

flock /var/lock/myapp.lock -c "run_critical_section"
                    ↕
terraform apply     →  GCS lock object prevents concurrent runs
```

### 1.4 State File Security

| Threat | Mitigation |
|---|---|
| State contains secrets (passwords, keys) | Encrypt bucket with CMEK |
| Unauthorised read | IAM: `roles/storage.objectViewer` only to CI/CD SA |
| Unauthorised write | IAM: `roles/storage.objectAdmin` only to CI/CD SA |
| Accidental deletion | Enable versioning on bucket |
| State corruption | Versioning allows rollback |

### 1.5 Partial Backend Configuration

Avoid hardcoding bucket names in code. Pass them at init time:

```hcl
# backend.tf — partial config
terraform {
  backend "gcs" {}
}
```

```bash
# At init time, supply the details
terraform init \
  -backend-config="bucket=myproj-tf-state-dev" \
  -backend-config="prefix=terraform/state"
```

| Approach | Pros | Cons |
|---|---|---|
| Hardcoded in `backend.tf` | Simple, self-documenting | Secrets in code, env-specific |
| Partial + `-backend-config` | Flexible, CI/CD friendly | Requires wrapper scripts |
| Partial + `.tfbackend` file | Best of both — file-based, git-ignored | Extra file to manage |

### 1.6 terraform_remote_state Data Source

```
┌─────────────────┐         ┌─────────────────┐
│  Network Stack  │         │  Compute Stack  │
│  (envs/network) │         │  (envs/compute) │
│                 │         │                 │
│  Outputs:       │  read   │  Data source:   │
│  - vpc_id ──────┼────────►│  terraform_     │
│  - subnet_id    │  via    │  remote_state   │
│                 │  GCS    │  → vpc_id       │
└─────────────────┘         └─────────────────┘
```

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create State Bucket (10 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)
export BUCKET_NAME="${PROJECT_ID}-tf-state-lab"

# Create bucket with versioning in europe-west2
gcloud storage buckets create gs://${BUCKET_NAME} \
  --location=europe-west2 \
  --uniform-bucket-level-access \
  --public-access-prevention

# Enable versioning (rollback protection)
gcloud storage buckets update gs://${BUCKET_NAME} --versioning

# Verify
gcloud storage buckets describe gs://${BUCKET_NAME} \
  --format="table(name,location,versioning.enabled)"
```

### Step 2: Create Network Stack with Remote State (15 min)

```bash
mkdir -p tf-remote-lab/network tf-remote-lab/compute
```

```hcl
# tf-remote-lab/network/main.tf
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    # Partial config — pass at init
  }
}

provider "google" {
  project = var.project_id
  region  = "europe-west2"
}

variable "project_id" {
  type = string
}

resource "google_compute_network" "lab_vpc" {
  name                    = "remote-state-lab-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "lab_subnet" {
  name          = "remote-state-lab-subnet"
  region        = "europe-west2"
  network       = google_compute_network.lab_vpc.id
  ip_cidr_range = "10.99.0.0/24"
}

output "vpc_id" {
  value = google_compute_network.lab_vpc.id
}

output "vpc_name" {
  value = google_compute_network.lab_vpc.name
}

output "subnet_id" {
  value = google_compute_subnetwork.lab_subnet.id
}
```

### Step 3: Init with Partial Backend Config (5 min)

```bash
cd tf-remote-lab/network

terraform init \
  -backend-config="bucket=${BUCKET_NAME}" \
  -backend-config="prefix=network/state"

# Create a tfvars file
echo "project_id = \"${PROJECT_ID}\"" > terraform.tfvars
```

### Step 4: Apply Network Stack (5 min)

```bash
terraform plan
terraform apply -auto-approve
```

### Step 5: Verify State in GCS (5 min)

```bash
# List state objects
gcloud storage ls gs://${BUCKET_NAME}/network/state/

# View state metadata (DO NOT print contents — secrets!)
gcloud storage objects describe \
  gs://${BUCKET_NAME}/network/state/default.tfstate \
  --format="table(name,size,updated,metadata)"
```

### Step 6: Create Compute Stack Using Remote State (15 min)

```hcl
# tf-remote-lab/compute/main.tf
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = "europe-west2"
}

variable "project_id" {
  type = string
}

# Read outputs from the network stack
data "terraform_remote_state" "network" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "network/state"
  }
}

variable "state_bucket" {
  description = "GCS bucket holding network state"
  type        = string
}

resource "google_compute_instance" "lab_vm" {
  name         = "remote-state-lab-vm"
  machine_type = "e2-micro"
  zone         = "europe-west2-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    subnetwork = data.terraform_remote_state.network.outputs.subnet_id
  }

  labels = {
    env  = "lab"
    week = "17"
  }
}

output "vm_name" {
  value = google_compute_instance.lab_vm.name
}

output "vm_internal_ip" {
  value = google_compute_instance.lab_vm.network_interface[0].network_ip
}
```

```bash
cd ../compute

terraform init \
  -backend-config="bucket=${BUCKET_NAME}" \
  -backend-config="prefix=compute/state"

cat > terraform.tfvars <<EOF
project_id   = "${PROJECT_ID}"
state_bucket = "${BUCKET_NAME}"
EOF

terraform plan
terraform apply -auto-approve
```

### Step 7: Clean Up (5 min)

```bash
# Destroy compute first (depends on network)
cd ../compute
terraform destroy -auto-approve

# Then destroy network
cd ../network
terraform destroy -auto-approve

# Delete state bucket
gcloud storage rm -r gs://${BUCKET_NAME}

# Remove local directories
cd ~
rm -rf tf-remote-lab
```

---

## Part 3: Revision (15 minutes)

- **Remote state** in GCS enables team collaboration, locking, versioning, and encryption
- **State locking** — GCS automatically locks during `apply`; prevents concurrent modifications
- **Partial backend config** — keep bucket names out of code; pass via `-backend-config` or `.tfbackend` files
- **terraform_remote_state** data source — reads outputs from another stack's state file
- **NEVER** print state contents — they contain secrets; use `terraform output` instead
- **Enable versioning** on state buckets — allows rollback from corruption
- **IAM on state bucket** — only CI/CD service account should have write access

### Key Commands
```bash
terraform init -backend-config="bucket=BUCKET"
terraform state list                    # List resources in state
terraform state show RESOURCE           # Show resource details
terraform force-unlock LOCK_ID          # Emergency unlock (dangerous!)
gcloud storage buckets update gs://B --versioning  # Enable versioning
```

---

## Part 4: Quiz (15 minutes)

**Q1:** What happens if two engineers run `terraform apply` simultaneously without state locking?
<details><summary>Answer</summary>Both read the same current state, both generate plans independently, and both try to write changes. This leads to <b>state corruption</b> — one apply overwrites the other's changes. Resources may be created twice or left in an inconsistent state. State locking prevents this by allowing only one writer at a time, like <code>flock</code> in Linux.</details>

**Q2:** Why use partial backend configuration instead of hardcoding the bucket in `backend.tf`?
<details><summary>Answer</summary>Hardcoding means environment-specific values in code (different buckets per env). Partial config lets you pass the bucket at <code>terraform init</code> time, making the same code reusable across environments. It also keeps bucket names (which may be sensitive) out of version control. Similar to using environment variables instead of hardcoding paths in shell scripts.</details>

**Q3:** How does `terraform_remote_state` data source work, and when would you use it?
<details><summary>Answer</summary>It reads the <b>outputs</b> of another Terraform state file stored in a remote backend. Use it for cross-stack references — e.g., the compute stack reads the VPC ID from the network stack's state. It requires the reader to have read access to the state bucket. It only exposes values declared as <code>output</code> in the source stack.</details>

**Q4:** A colleague accidentally deleted the state file from GCS. How do you recover?
<details><summary>Answer</summary>If <b>versioning is enabled</b> on the bucket, list previous versions with <code>gcloud storage ls --all-versions gs://BUCKET/prefix/</code> and restore the previous version. If versioning was NOT enabled, you'd need to <code>terraform import</code> each resource manually — a painful process. This is why versioning on state buckets is mandatory.</details>
