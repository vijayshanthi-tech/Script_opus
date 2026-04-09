# Day 22 — Terraform State & Drift Detection

> **Week 4 · Terraform Basics** | Region: `europe-west2` | Study time: 2 hours

---

## Part 1 — Concept (30 min)

### 1.1 What Is Terraform State?

Terraform state is a **JSON file that maps your `.tf` config to real infrastructure**. It's Terraform's memory — without it, Terraform doesn't know what it's managing.

| Linux Analogy | Terraform Equivalent |
|---|---|
| `/var/lib/dpkg/status` (installed packages) | `terraform.tfstate` (managed resources) |
| `rpm -qa` (list installed) | `terraform state list` |
| `dpkg -s nginx` (package details) | `terraform state show google_compute_instance.vm` |
| `diff desired.conf actual.conf` | `terraform plan` (state vs config diff) |

### 1.2 State File Anatomy

```json
{
  "version": 4,
  "terraform_version": "1.7.0",
  "serial": 5,
  "lineage": "abc123-def456-...",
  "outputs": {
    "vm_name": {
      "value": "tf-day22-vm",
      "type": "string"
    }
  },
  "resources": [
    {
      "mode": "managed",
      "type": "google_compute_instance",
      "name": "vm",
      "provider": "provider[\"registry.terraform.io/hashicorp/google\"]",
      "instances": [
        {
          "attributes": {
            "id": "projects/my-proj/zones/europe-west2-b/instances/tf-day22-vm",
            "name": "tf-day22-vm",
            "machine_type": "e2-micro",
            "zone": "europe-west2-b",
            "labels": { "env": "lab" },
            "network_interface": [...]
          }
        }
      ]
    }
  ]
}
```

| Field | Purpose |
|---|---|
| `version` | State format version (currently 4) |
| `serial` | Increments on every state write (like a version counter) |
| `lineage` | Unique ID for this state — prevents mixing states from different configs |
| `outputs` | Last-known output values |
| `resources` | Array of all managed resources with their real attributes |
| `instances[].attributes.id` | The real GCP resource ID — links `.tf` to reality |

### 1.3 Local State vs Remote State

```
┌─────────────────────────────────────────────────────────────┐
│           LOCAL STATE (default)                              │
│                                                             │
│  ~/my-project/                                              │
│  ├── main.tf                                                │
│  ├── terraform.tfstate      ◄── on your local disk          │
│  └── terraform.tfstate.backup                               │
│                                                             │
│  Problems:                                                  │
│  • Lost if disk fails                                       │
│  • No team collaboration                                    │
│  • No locking (two people apply = corruption)               │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│           REMOTE STATE (production)                          │
│                                                             │
│  terraform {                                                │
│    backend "gcs" {                                          │
│      bucket = "my-project-tf-state"                         │
│      prefix = "env/prod"                                    │
│    }                                                        │
│  }                                                          │
│                                                             │
│  ┌──────────────┐         ┌──────────────────────┐          │
│  │  Developer A │──lock──>│  GCS Bucket          │          │
│  │  terraform   │         │  terraform.tfstate   │          │
│  │  apply       │         │  (shared, locked)    │          │
│  └──────────────┘         └──────────────────────┘          │
│                                 ▲                           │
│  ┌──────────────┐               │                           │
│  │  Developer B │──wait─────────┘                           │
│  │  (locked out │                                           │
│  │   until A    │                                           │
│  │   finishes)  │                                           │
│  └──────────────┘                                           │
│                                                             │
│  Benefits:                                                  │
│  • Shared across team                                       │
│  • Automatic locking (prevents concurrent apply)            │
│  • Versioned (GCS object versioning for rollback)           │
│  • Encrypted at rest                                        │
└─────────────────────────────────────────────────────────────┘
```

| Feature | Local State | Remote State (GCS) |
|---|---|---|
| Storage | Local filesystem | GCS bucket |
| Team collaboration | Not possible | Yes — shared state |
| Locking | None | Automatic (prevents concurrent changes) |
| Backup | Manual | GCS object versioning |
| Encryption | None (plain JSON) | GCS server-side encryption |
| Setup | Default (nothing to configure) | Requires `backend "gcs"` block |

### 1.4 What Is Drift?

**Drift** occurs when real infrastructure diverges from what Terraform state records. This happens when someone makes a change **outside Terraform** (Console, gcloud, API).

```
┌────────────────────┐      ┌─────────────────────┐
│  .tf config         │      │  terraform.tfstate   │
│  machine_type =     │      │  machine_type =      │
│  "e2-micro"         │      │  "e2-micro"          │
└────────┬───────────┘      └──────────┬──────────┘
         │                              │
         │  Both say e2-micro           │
         │  but someone changed         │
         │  it in Console to...         │
         │                              │
         │      ┌─────────────────┐     │
         │      │  REAL GCP       │     │
         │      │  machine_type = │     │
         └─────>│  "e2-small"     │<────┘
                │  (DRIFT!)       │
                └─────────────────┘
```

| Drift Scenario | How It Happens | Risk |
|---|---|---|
| Someone changes a label in Console | Manual change | Next `apply` reverts it |
| Someone resizes disk via `gcloud` | CLI change outside TF | State mismatch |
| Someone deletes a firewall rule | Console deletion | TF tries to use deleted resource |
| Network auto-scaling adds resources | GCP auto-scaling | TF doesn't know about new resources |

### 1.5 Key State Commands

| Command | Purpose | Linux Analogy |
|---|---|---|
| `terraform show` | Display current state (human-readable) | `dpkg -l` |
| `terraform state list` | List all tracked resource addresses | `rpm -qa` |
| `terraform state show ADDR` | Details of one resource | `dpkg -s package` |
| `terraform plan` | Detect drift (compares state to real infra) | `diff desired actual` |
| `terraform refresh` | Update state from real infra (without changing infra) | Re-scan installed packages |
| `terraform import ADDR ID` | Import existing resource into state | `dpkg --force-depends -i` |
| `terraform state rm ADDR` | Remove resource from state (doesn't delete infra) | `dpkg --remove --force-remove-reinstreq` |
| `terraform state mv` | Rename/move resource in state | `mv old new` |

### 1.6 terraform import

Import brings an existing resource (created outside Terraform) into state:

```bash
# Syntax:
terraform import <RESOURCE_ADDRESS> <GCP_RESOURCE_ID>

# Example: import an existing VM
terraform import google_compute_instance.vm \
    projects/my-project/zones/europe-west2-b/instances/legacy-vm
```

After import, you must also write the matching `.tf` resource block — `import` only adds to state, it doesn't generate config.

---

## Part 2 — Hands-On Lab (60 min)

### Lab Goal

Create a VM with Terraform, manually drift it in the Console, detect drift with `terraform plan`, fix it, and practice `terraform import`.

### Prerequisites

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-b
```

### Step 1 — Create Project Directory

```bash
mkdir -p ~/tf-day22 && cd ~/tf-day22
```

### Step 2 — Write the Config Files

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

cat > variables.tf << 'EOF'
variable "project_id" {
  description = "GCP project ID"
  type        = string
}
EOF

cat > terraform.tfvars << 'EOF'
project_id = "YOUR_PROJECT_ID"
EOF

cat > main.tf << 'EOF'
resource "google_compute_instance" "vm" {
  name         = "tf-day22-vm"
  machine_type = "e2-micro"
  zone         = "europe-west2-b"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  labels = {
    env     = "lab"
    week    = "4"
    day     = "22"
    managed = "terraform"
  }

  tags = ["tf-lab"]

  metadata = {
    enable-oslogin = "TRUE"
  }
}
EOF

cat > outputs.tf << 'EOF'
output "vm_name" {
  value = google_compute_instance.vm.name
}

output "vm_machine_type" {
  value = google_compute_instance.vm.machine_type
}

output "vm_external_ip" {
  value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}

output "vm_labels" {
  value = google_compute_instance.vm.labels
}
EOF
```

### Step 3 — Init and Apply

```bash
terraform init
terraform apply
```

### Step 4 — Verify Initial State

```bash
# Check what Terraform knows
terraform state list
terraform state show google_compute_instance.vm

# Confirm labels
terraform output vm_labels

# Confirm with gcloud
gcloud compute instances describe tf-day22-vm \
    --zone=europe-west2-b \
    --format="table(name,machineType.basename(),labels)"
```

### Step 5 — Introduce Drift (Manual Change)

Now simulate someone making a change **outside Terraform**:

```bash
# Drift 1: Add a label via gcloud (not in .tf files)
gcloud compute instances update tf-day22-vm \
    --zone=europe-west2-b \
    --update-labels=team=rogue-change,modified-by=console

# Drift 2: Stop the VM and change machine type
gcloud compute instances stop tf-day22-vm --zone=europe-west2-b --quiet

gcloud compute instances set-machine-type tf-day22-vm \
    --zone=europe-west2-b \
    --machine-type=e2-small

gcloud compute instances start tf-day22-vm --zone=europe-west2-b

# Verify the drift exists in GCP
gcloud compute instances describe tf-day22-vm \
    --zone=europe-west2-b \
    --format="yaml(name,machineType,labels)"
```

### Step 6 — Detect Drift with terraform plan

```bash
terraform plan
```

**Expected output showing drift:**

```
  # google_compute_instance.vm will be updated in-place
  ~ resource "google_compute_instance" "vm" {
      ~ labels       = {
          + "modified-by" = "console"    # Will be REMOVED by Terraform
          + "team"        = "rogue-change"  # Will be REMOVED
            # (other labels unchanged)
        }
      ~ machine_type = "e2-small" -> "e2-micro"  # Will be REVERTED
        # ...
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

**Key insight:** Terraform plan compares `.tf` config (desired) against real GCP state and shows what it will change to **enforce your config**. It will:
- Remove the manually-added labels (`team`, `modified-by`)
- Revert `machine_type` from `e2-small` back to `e2-micro`

### Step 7 — Fix the Drift

**Option A — Revert to Terraform's config (most common):**

```bash
# Apply to enforce the .tf config — removes drift
terraform apply
```

**Option B — Accept the drift by updating .tf files:**

If the console change was intentional, update `main.tf` to match:

```hcl
# In main.tf, update machine_type and labels:
  machine_type = "e2-small"   # Accept the new size
  labels = {
    env         = "lab"
    week        = "4"
    day         = "22"
    managed     = "terraform"
    team        = "rogue-change"    # Accept the new label
    modified-by = "console"
  }
```

Then `terraform plan` shows no changes (desired = actual).

**For this lab, use Option A:**

```bash
terraform apply
# Confirm: yes

# Verify drift is fixed
gcloud compute instances describe tf-day22-vm \
    --zone=europe-west2-b \
    --format="yaml(name,machineType,labels)"
```

### Step 8 — Practice terraform refresh

```bash
# Add another drift
gcloud compute instances update tf-day22-vm \
    --zone=europe-west2-b \
    --update-labels=sneaky=yes

# Refresh state — updates state file from real GCP WITHOUT changing infra
terraform refresh

# Now the state file knows about the sneaky label
terraform state show google_compute_instance.vm | grep sneaky
# labels.sneaky = "yes"

# But plan still shows it will remove it (config doesn't have it)
terraform plan
# ~ labels = { - "sneaky" = "yes" -> null }
```

> **Note:** In Terraform 1.5+, `terraform refresh` runs automatically as part of `terraform plan`. The explicit `refresh` command is rarely needed.

### Step 9 — Practice terraform import

Create a resource outside Terraform, then import it:

```bash
# Create a firewall rule with gcloud (not managed by Terraform)
gcloud compute firewall-rules create legacy-ssh-rule \
    --network=default \
    --allow=tcp:22 \
    --source-ranges=10.0.0.0/8 \
    --target-tags=legacy-ssh \
    --description="Legacy SSH rule created outside Terraform"

# Verify it exists
gcloud compute firewall-rules describe legacy-ssh-rule
```

Now write a matching resource block in Terraform:

```bash
cat >> main.tf << 'EOF'

# Imported resource — was created manually with gcloud
resource "google_compute_firewall" "legacy_ssh" {
  name    = "legacy-ssh-rule"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["10.0.0.0/8"]
  target_tags   = ["legacy-ssh"]
  description   = "Legacy SSH rule created outside Terraform"
}
EOF
```

Import the existing resource into state:

```bash
# Import syntax: terraform import <resource_address> <gcp_resource_id>
terraform import google_compute_firewall.legacy_ssh \
    projects/YOUR_PROJECT_ID/global/firewalls/legacy-ssh-rule
```

**Expected output:**

```
Import successful!

The resources that were imported are shown above. These resources are now in
your Terraform state and will henceforth be managed by Terraform.
```

Verify:

```bash
# Resource is now in state
terraform state list
# google_compute_firewall.legacy_ssh  ← newly imported

# Plan should show no changes (config matches real infra)
terraform plan
# No changes. Your infrastructure matches the configuration.
```

### Step 10 — Practice terraform state rm

Remove a resource from state **without destroying it**:

```bash
# Remove the firewall rule from Terraform management
terraform state rm google_compute_firewall.legacy_ssh

# It's removed from state
terraform state list
# google_compute_firewall.legacy_ssh is gone

# But the rule still exists in GCP!
gcloud compute firewall-rules describe legacy-ssh-rule
# It's still there — just unmanaged now
```

> **Use case:** When you want Terraform to "forget" a resource without deleting it — useful when migrating resources between Terraform configs.

### Cleanup

```bash
# Destroy Terraform-managed resources
terraform destroy

# Manually delete the unmanaged firewall rule (we state-rm'd it)
gcloud compute firewall-rules delete legacy-ssh-rule --quiet

# Verify everything is gone
gcloud compute instances list --filter="name=tf-day22-vm"
gcloud compute firewall-rules list --filter="name=legacy-ssh-rule"

# Clean up
cd ~ && rm -rf ~/tf-day22
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **State file** = Terraform's memory mapping `.tf` config → real resource IDs. JSON format.
- **Local state** = default, stored on disk. No locking, no team collaboration.
- **Remote state** = stored in GCS/S3 with locking. Use `backend "gcs"` block. Required for teams.
- **Drift** = real infra differs from state. Caused by manual changes in Console/gcloud.
- `terraform plan` detects drift by comparing config vs real infra via API.
- `terraform apply` **enforces** your `.tf` config — reverts any drift.
- `terraform refresh` updates state from real infra without changing anything.
- `terraform import ADDR ID` adds an existing resource to state (requires matching `.tf` block).
- `terraform state rm ADDR` removes resource from state without destroying it.
- `terraform state mv` renames a resource in state.
- Never hand-edit `terraform.tfstate` — use `terraform state` commands.
- State contains **sensitive data** (IPs, passwords) — secure it.

### Essential Commands

```bash
# State inspection
terraform show                                  # Human-readable state
terraform state list                            # List all resources
terraform state show RESOURCE_ADDRESS           # Details of one resource

# Drift management
terraform plan                                  # Detect drift
terraform apply                                 # Fix drift (enforce config)
terraform refresh                               # Update state from real infra

# Import and removal
terraform import RESOURCE_ADDRESS GCP_ID        # Import existing resource
terraform state rm RESOURCE_ADDRESS             # Remove from state (keep infra)
terraform state mv OLD_ADDR NEW_ADDR            # Rename in state

# Remote state setup (in providers.tf)
terraform {
  backend "gcs" {
    bucket = "my-tf-state-bucket"
    prefix = "env/lab"
  }
}
```

---

## Part 4 — Quiz (15 min)

**Question 1: Someone deletes the `terraform.tfstate` file but doesn't touch the real GCP infrastructure. What happens if you run `terraform plan`?**

<details>
<summary>Show Answer</summary>

Terraform will plan to **create all resources from scratch** because it has no memory of what exists. It doesn't query GCP to check — it compares `.tf` config against the state file, and an empty/missing state means "nothing exists."

This would lead to **duplicate resources** or errors (name conflicts).

**Recovery steps:**
1. If you have `terraform.tfstate.backup`, rename it to `terraform.tfstate`
2. If no backup, use `terraform import` to re-import each resource
3. For teams — this is why **remote state** in a GCS bucket with versioning is critical

This is exactly like deleting `/var/lib/dpkg/status` — the package manager loses track of what's installed.

</details>

---

**Question 2: You have a VM managed by Terraform. A colleague stops the VM and changes the machine type from `e2-micro` to `e2-medium` in the Console. You run `terraform plan`. What does it show?**

<details>
<summary>Show Answer</summary>

`terraform plan` will show:

```
  ~ machine_type = "e2-medium" -> "e2-micro"
```

Terraform will plan to **revert the machine type back to `e2-micro`** because that's what your `.tf` config declares. Terraform enforces the `.tf` config as the source of truth.

To **accept** the colleague's change instead:
1. Update `main.tf` to `machine_type = "e2-medium"`
2. Run `terraform plan` — it will show no changes

This is the core principle: `.tf` files are the desired state. Anything different in reality is drift to be corrected.

</details>

---

**Question 3: What is the difference between `terraform state rm` and `terraform destroy` for a single resource?**

<details>
<summary>Show Answer</summary>

| | `terraform state rm` | `terraform destroy` (or removing from `.tf`) |
|---|---|---|
| **State** | Removes resource from state | Removes resource from state |
| **Real infrastructure** | **NOT touched** — resource continues to exist | **DELETED** — resource is destroyed |
| **Use case** | "Stop managing this, but leave it running" | "Delete this resource entirely" |

Example:
- `terraform state rm google_compute_instance.vm` → VM keeps running, Terraform forgets about it
- Removing the resource block from `.tf` then running `terraform apply` → VM is deleted from GCP

`state rm` is useful when migrating resources between Terraform configs or when you want to manually manage something going forward.

</details>

---

**Question 4: You want to store Terraform state in a GCS bucket for team collaboration. Write the backend config block and explain what `prefix` does.**

<details>
<summary>Show Answer</summary>

```hcl
terraform {
  backend "gcs" {
    bucket = "my-project-tf-state"
    prefix = "infra/prod"
  }
}
```

| Argument | Purpose |
|---|---|
| `bucket` | GCS bucket name where state is stored |
| `prefix` | Path prefix inside the bucket — like a directory. The state file is stored at `gs://bucket/prefix/default.tfstate` |

With the above config, the state file path is:
```
gs://my-project-tf-state/infra/prod/default.tfstate
```

**Why prefix matters:** It lets you store multiple Terraform configs' states in one bucket:
- `infra/prod/default.tfstate` — production infrastructure
- `infra/staging/default.tfstate` — staging infrastructure
- `network/prod/default.tfstate` — networking config

After adding the backend block, run `terraform init` to migrate from local to remote state. GCS backends support **automatic locking** to prevent concurrent applies.

</details>

---

*End of Day 22 — Tomorrow: Terraform modules for reusable infrastructure.*
