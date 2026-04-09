# Day 32 — GCS Lifecycle Policies & Object Versioning

> **Week 6 — Storage & Backup** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### Why Lifecycle Management?

In Linux, you write cron jobs to clean `/var/log` or move old archives. In GCS, **lifecycle policies** do this automatically — no cron, no scripts, no forgotten cleanup.

### Lifecycle Rules

```
┌──────────────────────────────────────────────────────┐
│                Lifecycle Rule Engine                  │
│                                                      │
│  Rule = CONDITION  +  ACTION                         │
│                                                      │
│  Conditions:              Actions:                   │
│  ┌────────────────┐       ┌─────────────────────┐    │
│  │ age > N days   │       │ Delete               │    │
│  │ createdBefore  │  ───► │ SetStorageClass      │    │
│  │ numNewerVer >N │       │ AbortIncompleteMulti │    │
│  │ isLive=true/   │       │   partUpload         │    │
│  │   false        │       └─────────────────────┘    │
│  │ matchesClass   │                                  │
│  │ matchesPrefix  │                                  │
│  │ matchesSuffix  │                                  │
│  └────────────────┘                                  │
│                                                      │
│  GCS evaluates rules once per day (not real-time)    │
└──────────────────────────────────────────────────────┘
```

### Common Lifecycle Patterns

| Pattern | Condition | Action |
|---|---|---|
| Auto-archive logs | `age > 30` + class=STANDARD | SetStorageClass → NEARLINE |
| Deep archive | `age > 90` + class=NEARLINE | SetStorageClass → COLDLINE |
| Delete old backups | `age > 365` | Delete |
| Clean up versions | `numNewerVersions > 3` + `isLive=false` | Delete |
| Abort stale uploads | `age > 7` + incomplete multipart | AbortIncompleteMultipartUpload |

**Linux analogy:**

| Linux | GCS Lifecycle |
|---|---|
| `logrotate` rotate after 30 days | `age > 30` → SetStorageClass |
| `find /backups -mtime +365 -delete` | `age > 365` → Delete |
| `tmpwatch` on /tmp | `age > 7` → Delete (for temp prefix) |

### Class Transition Rules

Not all transitions are allowed. Objects can only move **downward**:

```
  STANDARD
      │
      ▼
  NEARLINE  (min 30 days)
      │
      ▼
  COLDLINE  (min 90 days)
      │
      ▼
  ARCHIVE   (min 365 days)

  ✗ Cannot go ARCHIVE → STANDARD via lifecycle
    (You must rewrite the object manually)
```

### Object Versioning

When versioning is **enabled**, every overwrite/delete creates a **noncurrent version** instead of destroying data.

```
┌─────────────────────────────────────────────────┐
│        Versioning Timeline for config.yaml      │
│                                                 │
│  Time ──────────────────────────────────►        │
│                                                 │
│  v1 (upload)    v2 (overwrite)   v3 (overwrite) │
│  ┌─────────┐   ┌─────────┐     ┌─────────┐     │
│  │ gen=101 │   │ gen=102 │     │ gen=103 │     │
│  │ LIVE    │──►│ LIVE    │──►  │ LIVE    │     │
│  │         │   │         │     │ (current)│     │
│  └────┬────┘   └────┬────┘     └─────────┘     │
│       │             │                           │
│       ▼             ▼                           │
│   noncurrent    noncurrent                      │
│   (gen=101)     (gen=102)                       │
│                                                 │
│  "Delete" v3 ──► v3 becomes noncurrent          │
│                  (nothing truly deleted)         │
└─────────────────────────────────────────────────┘
```

**Linux analogy:** Like having `cp --backup=numbered` on every file operation, or like ZFS snapshots — you can always roll back.

### Retention Policies & Holds

| Feature | Purpose | Scope |
|---|---|---|
| **Retention policy** | Objects cannot be deleted/overwritten before retention period | Bucket-level |
| **Retention policy lock** | Makes the retention policy **permanent** (cannot shorten) | Bucket-level |
| **Event-based hold** | Hold object until an event clears it | Per-object |
| **Temporary hold** | Admin hold — can be removed anytime | Per-object |

```
┌────────────────────────────────────────────────┐
│           Retention & Holds                    │
│                                                │
│  Bucket: retention_period = 365 days           │
│  ┌──────────────────────────────────────────┐  │
│  │ Object: invoice-2024.pdf                 │  │
│  │   Created: 2024-01-15                    │  │
│  │   Deletable after: 2025-01-15            │  │
│  │   Event-based hold: NO                   │  │
│  │   Temporary hold: NO                     │  │
│  │                                          │  │
│  │   DELETE request before 2025-01-15?      │  │
│  │   ──► 403 FORBIDDEN                      │  │
│  └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export BUCKET="${PROJECT_ID}-lifecycle-lab32"
```

### Step 1 — Create a Bucket with Versioning

```bash
# Create bucket
gsutil mb -p ${PROJECT_ID} \
  -c STANDARD \
  -l ${REGION} \
  -b on \
  gs://${BUCKET}

# Enable versioning
gsutil versioning set on gs://${BUCKET}

# Verify
gsutil versioning get gs://${BUCKET}
# Expected: gs://BUCKET: Enabled
```

### Step 2 — Test Versioning

```bash
# Upload v1
echo "version 1 content" > /tmp/config.yaml
gsutil cp /tmp/config.yaml gs://${BUCKET}/config.yaml

# Overwrite with v2
echo "version 2 content - updated" > /tmp/config.yaml
gsutil cp /tmp/config.yaml gs://${BUCKET}/config.yaml

# Overwrite with v3
echo "version 3 content - final" > /tmp/config.yaml
gsutil cp /tmp/config.yaml gs://${BUCKET}/config.yaml

# List all versions
gsutil ls -a gs://${BUCKET}/config.yaml
# Shows: gs://BUCKET/config.yaml#1234567890123456 (multiple entries)

# Read the current (live) version
gsutil cat gs://${BUCKET}/config.yaml

# Read a specific old version (use a generation number from ls -a output)
# gsutil cat gs://${BUCKET}/config.yaml#GENERATION_NUMBER
```

### Step 3 — Restore an Old Version

```bash
# List versions to find the generation number
gsutil ls -a gs://${BUCKET}/config.yaml

# Copy the old version back as the live version
# Replace GENERATION with actual number from ls -a output
# gsutil cp gs://${BUCKET}/config.yaml#GENERATION gs://${BUCKET}/config.yaml

# Verify restoration
gsutil cat gs://${BUCKET}/config.yaml
```

### Step 4 — Configure Lifecycle Rules (JSON)

```bash
# Create lifecycle config
cat > /tmp/lifecycle.json << 'EOF'
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30, "matchesStorageClass": ["STANDARD"]}
    },
    {
      "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
      "condition": {"age": 90, "matchesStorageClass": ["NEARLINE"]}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"age": 365}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"numNewerVersions": 3, "isLive": false}
    },
    {
      "action": {"type": "AbortIncompleteMultipartUpload"},
      "condition": {"age": 7}
    }
  ]
}
EOF

# Apply lifecycle rules
gsutil lifecycle set /tmp/lifecycle.json gs://${BUCKET}

# Verify
gsutil lifecycle get gs://${BUCKET}
```

### Step 5 — Test Lifecycle (Noncurrent Version Cleanup)

```bash
# Create 5 versions of a test file
for i in 1 2 3 4 5; do
  echo "test version $i" > /tmp/test.txt
  gsutil cp /tmp/test.txt gs://${BUCKET}/test.txt
done

# List all versions
gsutil ls -a gs://${BUCKET}/test.txt
# You'll see 5 versions — lifecycle will eventually delete the oldest 2
# (keeping 3 noncurrent + 1 live)
# Note: lifecycle runs async, ~once/day — won't happen instantly in lab
```

### Step 6 — Retention Policy (Optional)

```bash
# Create a separate bucket for retention testing
export BUCKET_RET="${PROJECT_ID}-retention-lab32"
gsutil mb -p ${PROJECT_ID} -l ${REGION} -b on gs://${BUCKET_RET}

# Set a 60-second retention period (short for testing)
gsutil retention set 60s gs://${BUCKET_RET}

# Upload a file
echo "important data" > /tmp/important.txt
gsutil cp /tmp/important.txt gs://${BUCKET_RET}/important.txt

# Try to delete immediately — should fail
gsutil rm gs://${BUCKET_RET}/important.txt
# ERROR: 403 Object is under active retention policy

# Wait 60+ seconds, then delete succeeds
# gsutil rm gs://${BUCKET_RET}/important.txt

# View retention policy
gsutil retention get gs://${BUCKET_RET}
```

### Step 7 — Terraform Version

```hcl
# main.tf
resource "google_storage_bucket" "versioned" {
  name                        = "${var.project_id}-lifecycle-tf-lab32"
  location                    = "europe-west2"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age                = 30
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age                = 90
      matches_storage_class = ["NEARLINE"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    env  = "lab"
    week = "6"
    day  = "32"
  }
}

variable "project_id" {
  type = string
}
```

### Cleanup

```bash
# Delete all object versions first (required for versioned buckets)
gsutil rm -a gs://${BUCKET}/**
gsutil rb gs://${BUCKET}

# Retention bucket — wait until retention period expires, then:
gsutil rm -a gs://${BUCKET_RET}/**
gsutil rb gs://${BUCKET_RET}

rm -f /tmp/lifecycle.json /tmp/config.yaml /tmp/test.txt /tmp/important.txt

# Terraform:
# terraform destroy -auto-approve
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Lifecycle rules** = automated object management (transition class, delete, abort uploads)
- Rules are evaluated **once per day** — not real-time
- Class transitions are one-way: STANDARD → NEARLINE → COLDLINE → ARCHIVE
- **Versioning** keeps noncurrent versions on overwrite/delete — nothing is truly lost
- Use `numNewerVersions` to auto-clean old versions and prevent runaway storage costs
- **Retention policy** prevents deletion before a minimum period — compliance use case
- **Retention policy lock** is irreversible — test carefully before locking

### Essential Commands

```bash
# Versioning
gsutil versioning set on gs://BUCKET              # Enable
gsutil versioning get gs://BUCKET                  # Check status
gsutil ls -a gs://BUCKET/OBJECT                    # List all versions
gsutil cp gs://BUCKET/OBJECT#GEN gs://BUCKET/OBJ   # Restore old version
gsutil rm -a gs://BUCKET/**                        # Delete ALL versions

# Lifecycle
gsutil lifecycle set CONFIG.json gs://BUCKET       # Apply rules
gsutil lifecycle get gs://BUCKET                   # View rules

# Retention
gsutil retention set DURATION gs://BUCKET          # Set retention
gsutil retention get gs://BUCKET                   # View retention
gsutil retention lock gs://BUCKET                  # PERMANENT lock
```

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: You have a bucket with STANDARD objects. You want them moved to NEARLINE after 30 days and deleted after 1 year. Write the lifecycle rules (conceptually).</strong></summary>

**Answer:** Two rules:

1. **Rule 1 — Transition:** Condition: `age > 30` AND `matchesStorageClass = STANDARD` → Action: `SetStorageClass → NEARLINE`
2. **Rule 2 — Deletion:** Condition: `age > 365` → Action: `Delete`

**Important notes:**
- Rules are evaluated independently — GCS checks all rules daily
- Rule 2 will fire at 365 days regardless of current class
- If you also want NEARLINE → COLDLINE, add a third rule with `age > 90`
- Objects already past the age threshold when rules are applied will be affected on the next daily evaluation
</details>

<details>
<summary><strong>Q2: With versioning enabled, a user deletes `report.csv`. Is the data gone? How do you recover it?</strong></summary>

**Answer:** **No, the data is NOT gone.** When versioning is enabled, a "delete" operation does not destroy the object. Instead:

1. The live object becomes a **noncurrent version** (gets a delete marker)
2. The object is no longer visible with `gsutil ls` (normal listing)
3. The object IS visible with `gsutil ls -a` (all versions)

**To recover:**
```bash
# List all versions including noncurrent
gsutil ls -a gs://bucket/report.csv
# Output: gs://bucket/report.csv#1234567890123456

# Copy the noncurrent version back as the live version
gsutil cp gs://bucket/report.csv#1234567890123456 gs://bucket/report.csv
```

This is similar to restoring from a ZFS snapshot or an LVM snapshot on Linux.
</details>

<details>
<summary><strong>Q3: What's the difference between a retention policy and a temporary hold?</strong></summary>

**Answer:**

| Aspect | Retention Policy | Temporary Hold |
|---|---|---|
| **Scope** | Bucket-level (applies to all objects) | Per-object |
| **Duration** | Fixed period from object creation | Indefinite (until removed) |
| **Removal** | Can shorten if not locked; can remove if not locked | Admin removes it anytime |
| **Lock** | Can be permanently locked | No lock concept |
| **Use case** | Compliance (e.g., "keep 7 years") | Ad-hoc legal hold on specific files |

**Key point:** A locked retention policy is **irreversible** — you cannot delete the bucket or shorten the period. Test with short periods before locking production buckets.
</details>

<details>
<summary><strong>Q4: You notice your versioned bucket's storage cost is growing rapidly. What lifecycle rule would you add to control it?</strong></summary>

**Answer:** Add a rule to limit noncurrent versions:

```json
{
  "action": {"type": "Delete"},
  "condition": {
    "numNewerVersions": 3,
    "isLive": false
  }
}
```

This keeps at most **3 noncurrent versions** per object. When a 4th noncurrent version appears, the oldest is deleted.

**Additional measures:**
- Add a maximum age for noncurrent versions: `"age": 90, "isLive": false` → Delete
- Transition noncurrent versions to cheaper classes first: `"age": 30, "isLive": false` → SetStorageClass COLDLINE
- Monitor with `gsutil du -s gs://bucket` or Cloud Monitoring storage metrics
</details>
