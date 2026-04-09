# Day 31 — Cloud Storage Basics & Security

> **Week 6 — Storage & Backup** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### What Is Cloud Storage?

Google Cloud Storage (GCS) is an **object store** — not a filesystem, not a block device. Think of it as an infinite, flat key-value store where the key is the object path and the value is the file blob.

**Linux Analogy:**

| Linux Concept | GCS Equivalent |
|---|---|
| `/mnt/nfs/share/` | Bucket |
| File on NFS | Object |
| `chmod` / POSIX ACLs | IAM / ACLs |
| `du -sh` | `gsutil du` |
| `rsync -avz` | `gsutil rsync` |
| Symlinks (loosely) | Object metadata / pointers |

### Core Concepts

```
┌─────────────────────────────────────────────────┐
│                 GCS Architecture                │
│                                                 │
│  ┌──────────────────────────────────────────┐   │
│  │          Bucket: tap-data-prod            │   │
│  │          Location: europe-west2           │   │
│  │          Class: STANDARD                  │   │
│  │                                           │   │
│  │  ┌────────────┐  ┌────────────┐          │   │
│  │  │ logs/      │  │ backups/   │          │   │
│  │  │  app.log   │  │  db.tar.gz │          │   │
│  │  │  err.log   │  │  vm.snap   │          │   │
│  │  └────────────┘  └────────────┘          │   │
│  │                                           │   │
│  │  ┌────────────┐                          │   │
│  │  │ config/    │                          │   │
│  │  │  app.yaml  │                          │   │
│  │  └────────────┘                          │   │
│  └──────────────────────────────────────────┘   │
│                                                 │
│  Note: "folders" are virtual — just prefixes    │
└─────────────────────────────────────────────────┘
```

### Storage Classes

| Class | Min Duration | Use Case | Cost (GB/mo) |
|---|---|---|---|
| **STANDARD** | None | Frequently accessed | $$$ |
| **NEARLINE** | 30 days | Once/month access | $$ |
| **COLDLINE** | 90 days | Once/quarter access | $ |
| **ARCHIVE** | 365 days | Yearly / compliance | ¢ |

> **Linux analogy:** Think of storage classes like tape tiers in a tape library — hot data on fast disk, cold data on tape. Retrieval from ARCHIVE is cheap to store but expensive to read, like restoring from tape.

### IAM vs ACLs

```
┌───────────────────────────────────────────────────────┐
│                  Access Control Models                 │
│                                                       │
│  ┌─────────────────────┐  ┌────────────────────────┐  │
│  │       IAM            │  │       ACLs              │  │
│  │  (Recommended)       │  │  (Legacy)               │  │
│  │                      │  │                         │  │
│  │  • Bucket-level      │  │  • Per-object           │  │
│  │  • Role-based        │  │  • User/group grants    │  │
│  │  • Inherited from    │  │  • Fine-grained but     │  │
│  │    project/org       │  │    hard to manage        │  │
│  │  • Audit-friendly    │  │  • No inheritance       │  │
│  └─────────────────────┘  └────────────────────────┘  │
│                                                       │
│  Uniform Bucket-Level Access = DISABLE ACLs           │
│  (Best practice — use IAM only)                       │
└───────────────────────────────────────────────────────┘
```

**Linux analogy:** IAM is like LDAP/RBAC on a Linux server — roles assigned centrally. ACLs are like POSIX ACLs (`setfacl`) — per-file, messy at scale.

### Uniform Bucket-Level Access

When enabled:
- **All** access controlled via IAM only
- ACLs become **inactive**
- Simplifies auditing (Cloud Audit Logs show IAM checks)
- **90-day lock-in** — after 90 days, cannot revert to fine-grained

### Encryption at Rest

| Type | Key Management | Who Holds Key | Default |
|---|---|---|---|
| **Google-managed** | Automatic | Google | ✅ Yes |
| **CMEK** (Customer-Managed) | Cloud KMS | You (in KMS) | No |
| **CSEK** (Customer-Supplied) | You supply per-request | You (external) | No |

```
┌──────────────────────────────────────────────────┐
│              Encryption Decision Tree             │
│                                                   │
│  Need compliance / key control?                   │
│       │                                           │
│       ├── No  → Google-managed (default)          │
│       │                                           │
│       └── Yes                                     │
│            │                                      │
│            ├── Keep keys in GCP KMS? → CMEK       │
│            │                                      │
│            └── Keep keys outside GCP? → CSEK      │
│                (You send key with every request)   │
└──────────────────────────────────────────────────┘
```

**Linux analogy:** Google-managed = LUKS with auto-generated key. CMEK = LUKS where you store the key in a vault (KMS). CSEK = LUKS where you carry the USB key with you.

### Signed URLs

Signed URLs grant **time-limited** access to a specific object **without** requiring the requester to have a Google account.

```
  Client (no GCP account)
      │
      │  GET https://storage.googleapis.com/bucket/obj?
      │       X-Goog-SignedHeaders=host&
      │       X-Goog-Expires=3600&
      │       X-Goog-Signature=abc123...
      │
      ▼
  ┌──────────┐    Validates     ┌──────────┐
  │   GCS    │ ◄──signature──── │  IAM     │
  │  Bucket  │    against SA    │  Check   │
  └──────────┘                  └──────────┘
```

**Linux analogy:** Like a pre-authenticated HTTPS link — similar to a one-time `scp` token or a presigned S3 URL if you've used AWS.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites

```bash
# Set variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export BUCKET_STD="${PROJECT_ID}-std-lab31"
export BUCKET_COLD="${PROJECT_ID}-cold-lab31"
export SA_NAME="gcs-signer-lab31"
```

### Step 1 — Create Buckets with Different Classes

```bash
# Standard bucket in europe-west2
gsutil mb -p ${PROJECT_ID} \
  -c STANDARD \
  -l ${REGION} \
  -b on \
  gs://${BUCKET_STD}

# Coldline bucket
gsutil mb -p ${PROJECT_ID} \
  -c COLDLINE \
  -l ${REGION} \
  -b on \
  gs://${BUCKET_COLD}

# Verify
gsutil ls -L -b gs://${BUCKET_STD} | grep -E "Location|Storage class|Bucket Policy"
gsutil ls -L -b gs://${BUCKET_COLD} | grep -E "Location|Storage class|Bucket Policy"
```

> **Note:** `-b on` enables **Uniform Bucket-Level Access** at creation time.

### Step 2 — Upload Objects & Test Access

```bash
# Create test files
echo "This is application data" > /tmp/app-data.txt
echo "This is a log entry" > /tmp/app-log.txt

# Upload to standard bucket
gsutil cp /tmp/app-data.txt gs://${BUCKET_STD}/data/
gsutil cp /tmp/app-log.txt gs://${BUCKET_STD}/logs/

# List objects (note the "folder" prefixes)
gsutil ls -r gs://${BUCKET_STD}/

# Check object metadata
gsutil stat gs://${BUCKET_STD}/data/app-data.txt
```

### Step 3 — Set IAM on Bucket

```bash
# View current IAM
gsutil iam get gs://${BUCKET_STD}

# Grant a specific user read-only (use your own email for testing)
# gsutil iam ch user:someone@example.com:objectViewer gs://${BUCKET_STD}

# Grant allUsers read (PUBLIC — only for testing, remove after!)
# gsutil iam ch allUsers:objectViewer gs://${BUCKET_STD}

# Better: use a service account
gcloud iam service-accounts create ${SA_NAME} \
  --display-name="GCS Signer Lab31"

export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant the SA objectViewer on the bucket
gsutil iam ch serviceAccount:${SA_EMAIL}:objectViewer gs://${BUCKET_STD}

# Verify
gsutil iam get gs://${BUCKET_STD}
```

### Step 4 — Generate a Signed URL

```bash
# Create a key for the service account (needed for signing)
gcloud iam service-accounts keys create /tmp/sa-key.json \
  --iam-account=${SA_EMAIL}

# Grant the SA the needed role for signing
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectViewer"

# Generate a signed URL (valid 1 hour)
gsutil signurl -d 1h /tmp/sa-key.json gs://${BUCKET_STD}/data/app-data.txt

# The output contains a URL — test it in your browser or with curl
# curl "<SIGNED_URL>"
```

### Step 5 — Verify Encryption Settings

```bash
# Default encryption is Google-managed — check:
gsutil stat gs://${BUCKET_STD}/data/app-data.txt | grep -i encrypt

# To use CMEK, you would:
# 1. Create a KMS keyring and key
# 2. Set the bucket default encryption:
#    gsutil kms encryption -k projects/PROJECT/locations/REGION/keyRings/RING/cryptoKeys/KEY gs://BUCKET
```

### Step 6 — Terraform Version (Optional)

```hcl
# main.tf
resource "google_storage_bucket" "standard" {
  name                        = "${var.project_id}-std-tf-lab31"
  location                    = "europe-west2"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true

  encryption {
    # Omit for Google-managed, or specify KMS key for CMEK:
    # default_kms_key_name = google_kms_crypto_key.key.id
  }

  labels = {
    env     = "lab"
    week    = "6"
    day     = "31"
    purpose = "storage-security"
  }
}

resource "google_storage_bucket" "coldline" {
  name                        = "${var.project_id}-cold-tf-lab31"
  location                    = "europe-west2"
  storage_class               = "COLDLINE"
  uniform_bucket_level_access = true

  labels = {
    env     = "lab"
    week    = "6"
    day     = "31"
    purpose = "cold-storage"
  }
}

resource "google_storage_bucket_iam_member" "viewer" {
  bucket = google_storage_bucket.standard.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.sa_email}"
}

variable "project_id" {
  type = string
}

variable "sa_email" {
  type = string
}
```

### Cleanup

```bash
# Delete objects and buckets
gsutil rm -r gs://${BUCKET_STD}
gsutil rm -r gs://${BUCKET_COLD}

# Delete service account key
rm -f /tmp/sa-key.json

# Delete service account
gcloud iam service-accounts delete ${SA_EMAIL} --quiet

# If using Terraform:
# terraform destroy -auto-approve
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- GCS is an **object store** — flat namespace, not a filesystem
- **Buckets** are globally unique; **objects** are identified by bucket + key
- Four storage classes: Standard > Nearline > Coldline > Archive (cost vs access)
- **Uniform bucket-level access** = IAM only, no ACLs — best practice
- Three encryption options: Google-managed (default), CMEK (KMS), CSEK (you supply)
- **Signed URLs** = time-limited access without GCP credentials

### Essential Commands

```bash
# Bucket operations
gsutil mb -c CLASS -l LOCATION -b on gs://BUCKET         # Create bucket
gsutil ls -L -b gs://BUCKET                               # Bucket details
gsutil rm -r gs://BUCKET                                   # Delete bucket + contents

# Object operations
gsutil cp FILE gs://BUCKET/PREFIX/                         # Upload
gsutil ls -r gs://BUCKET/                                  # List recursively
gsutil stat gs://BUCKET/OBJECT                             # Object metadata

# IAM
gsutil iam get gs://BUCKET                                 # View IAM
gsutil iam ch MEMBER:ROLE gs://BUCKET                      # Grant access

# Signed URL
gsutil signurl -d DURATION KEY.json gs://BUCKET/OBJECT     # Generate signed URL

# Encryption
gsutil kms encryption -k KEY_RESOURCE gs://BUCKET          # Set CMEK
```

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: What is Uniform Bucket-Level Access, and why should you enable it?</strong></summary>

**Answer:** Uniform Bucket-Level Access disables object-level ACLs and enforces that **all** access to the bucket and its objects is controlled exclusively through IAM. You should enable it because:

1. **Simplified access management** — one system (IAM) instead of two (IAM + ACLs)
2. **Better auditability** — Cloud Audit Logs capture all IAM checks
3. **Reduced risk** — no accidental per-object ACL grants (e.g., `allUsers`)
4. **Best practice** — recommended by Google and required by many compliance frameworks

After 90 days, the setting becomes **permanent** and cannot be reverted.
</details>

<details>
<summary><strong>Q2: A colleague stores database backups in a STANDARD bucket but reads them only during quarterly DR tests. What would you recommend?</strong></summary>

**Answer:** Move the backups to **COLDLINE** storage class:

- **COLDLINE** has a 90-day minimum storage duration — quarterly access (every ~90 days) fits perfectly
- Storage cost drops significantly (~$0.004/GB/mo vs ~$0.020/GB/mo for STANDARD in europe-west2)
- Retrieval cost is higher but acceptable for quarterly reads
- Alternatively, use a **lifecycle policy** to automatically transition objects from STANDARD to COLDLINE after 30 days

If backups are kept for compliance (rarely accessed), **ARCHIVE** would be even cheaper.
</details>

<details>
<summary><strong>Q3: Explain the difference between CMEK and CSEK. When would you use each?</strong></summary>

**Answer:**

| Aspect | CMEK | CSEK |
|---|---|---|
| **Key storage** | Cloud KMS (GCP-managed HSMs) | External (you supply with each API call) |
| **Key lifecycle** | Managed via KMS (rotation, disable, destroy) | Entirely your responsibility |
| **Ease of use** | Set once on bucket, transparent thereafter | Must include key in every read/write request |
| **If key lost** | Recoverable (KMS has key versions) | **Data permanently inaccessible** |
| **Compliance** | Good for most regulations (SOC2, ISO) | Required when regulation mandates external key custody |

**Use CMEK** when you need key control + rotation but want GCP to handle the crypto operations. **Use CSEK** when regulations explicitly require that encryption keys never reside in the cloud provider's infrastructure.
</details>

<details>
<summary><strong>Q4: Your application needs to let unauthenticated users download a report PDF from a private GCS bucket. The link should expire after 2 hours. How do you implement this?</strong></summary>

**Answer:** Use a **Signed URL:**

1. Create a service account with `roles/storage.objectViewer` on the bucket
2. Generate a signed URL with a 2-hour expiry:
   ```bash
   gsutil signurl -d 2h /path/to/sa-key.json gs://bucket/reports/report.pdf
   ```
3. Share the resulting URL with the users — it works without authentication
4. After 2 hours, the URL stops working automatically

**Security considerations:**
- The SA key used for signing should be stored securely (e.g., Secret Manager)
- Use HTTPS (default) to prevent URL interception
- For programmatic generation, use the Cloud Storage client libraries' `generate_signed_url()` method
- Consider V4 signing (default in newer `gsutil`) for better security
</details>
