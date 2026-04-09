# Day 74 — Service Accounts: Types, Creation & Best Practices

> **Week 13 — IAM Deep Dive** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 What Is a Service Account?

A service account is a **non-human identity** used by applications, VMs, and services to authenticate to GCP APIs.

**Linux analogy:**
| Linux | GCP Service Account |
|-------|---------------------|
| System users (`nobody`, `www-data`) | Default & Google-managed SAs |
| Application-specific users (`postgres`, `nginx`) | User-managed SAs |
| `/etc/passwd` service entries | SA email address |
| SSH keys for automation | SA keys (but avoid them!) |
| `sudo -u www-data` | Impersonating a SA |
| RHDS `uid=ldapservice,ou=Services` | SA for directory operations |

### 1.2 Three Types of Service Accounts

```
┌──────────────────────────────────────────────────────────────┐
│                SERVICE ACCOUNT TYPES                          │
├──────────────────┬────────────────────┬──────────────────────┤
│  DEFAULT SA      │  USER-MANAGED SA   │  GOOGLE-MANAGED SA   │
├──────────────────┼────────────────────┼──────────────────────┤
│ Auto-created     │ You create it      │ GCP creates it       │
│ when API enabled │                    │ for internal use      │
│                  │                    │                       │
│ Format:          │ Format:            │ Format:               │
│ PROJECT_NUM-     │ NAME@PROJECT_ID.   │ service-PROJECT_NUM@  │
│ compute@dev..    │ iam.gserviceaccount│ ...gserviceaccount..  │
│                  │ .com               │                       │
│                  │                    │                       │
│ Has Editor role  │ No roles by default│ Has specific roles    │
│ (TOO BROAD!)     │ (you decide)       │ (don't modify)        │
│                  │                    │                       │
│ Avoid in prod    │ ★ RECOMMENDED ★    │ Leave alone           │
└──────────────────┴────────────────────┴──────────────────────┘
```

### 1.3 Service Account Workflow

```
  ┌──────────────┐         ┌──────────────────┐
  │  Developer   │         │  VM / App / Job   │
  │  creates SA  │────────▶│  runs with SA     │
  └──────┬───────┘         └────────┬──────────┘
         │                          │
  ┌──────▼───────┐         ┌────────▼──────────┐
  │ Grant roles  │         │ SA authenticates   │
  │ TO the SA    │         │ via metadata server│
  │              │         │ (no keys needed!)  │
  └──────────────┘         └────────┬──────────┘
                                    │
                           ┌────────▼──────────┐
                           │ GCP API checks     │
                           │ SA's IAM roles     │
                           │ → Allow or Deny    │
                           └───────────────────┘
```

### 1.4 SA Keys — Why to Avoid

```
 SA KEY LIFECYCLE (BAD PRACTICE)
 ─────────────────────────────────
  Create key  ──▶  Download JSON  ──▶  Store somewhere  ──▶  ???
       │                │                    │
       │           ┌────▼────┐          ┌────▼────┐
       │           │ Risk:   │          │ Risk:   │
       │           │ Leaked  │          │ Lost    │
       │           │ in git  │          │ track   │
       │           └─────────┘          │ of who  │
       │                                │ has it  │
       │                                └─────────┘
  BETTER ALTERNATIVES:
  ┌─────────────────────────────────────────────┐
  │ 1. Attached SA + metadata server (on GCP)   │
  │ 2. Workload Identity Federation (off GCP)   │
  │ 3. SA impersonation (user → SA)             │
  └─────────────────────────────────────────────┘
```

> **RHDS parallel:** In RHDS, you'd create a `uid=ldapbind,ou=Services` entry with a password stored in a config file. SA keys are similar — a secret stored externally. The risk is the same: credential sprawl. GCP's metadata server approach is like Kerberos keytab-based auth — the machine proves its identity without a stored password.

### 1.5 Workload Identity

```
  ┌─────────────────────────────────────────────────┐
  │            WORKLOAD IDENTITY                     │
  ├─────────────────────────────────────────────────┤
  │                                                  │
  │  GKE Pod ──────▶ K8s Service Account             │
  │                        │                         │
  │                   (annotated with)                │
  │                        │                         │
  │                        ▼                         │
  │              GCP Service Account                  │
  │              (has IAM roles)                      │
  │                        │                         │
  │                        ▼                         │
  │              GCP API Access                       │
  │              (no keys needed!)                    │
  │                                                  │
  │  External ────▶ Workload Identity Federation     │
  │  (AWS, Azure,         │                          │
  │   on-prem)      Token exchange                   │
  │                        │                         │
  │                        ▼                         │
  │              Short-lived GCP token                │
  └─────────────────────────────────────────────────┘
```

### 1.6 Granting Roles TO vs ON Service Accounts

```
  TWO DISTINCT CONCEPTS:
  ════════════════════════════════════════════

  1. Grant role TO a SA (SA acts as principal)
     "Let this SA read storage buckets"
     gcloud projects add-iam-policy-binding PROJECT \
       --member="serviceAccount:SA_EMAIL" \
       --role="roles/storage.objectViewer"

  2. Grant role ON a SA (SA is the resource)
     "Let this user impersonate this SA"
     gcloud iam service-accounts add-iam-policy-binding SA_EMAIL \
       --member="user:USER_EMAIL" \
       --role="roles/iam.serviceAccountUser"
```

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Inspect Default Service Account

```bash
# List all service accounts
gcloud iam service-accounts list --project=$PROJECT_ID

# Find the default compute SA (has -compute@ in the name)
export DEFAULT_SA=$(gcloud iam service-accounts list \
  --filter="email ~ compute@developer" \
  --format="value(email)")
echo "Default SA: $DEFAULT_SA"

# Check what roles the default SA has
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$DEFAULT_SA" \
  --format="table(bindings.role)"
```

### Lab 2.2 — Create a Custom Service Account

```bash
# Create a SA for a web application
gcloud iam service-accounts create web-app-sa \
  --display-name="Web App Service Account" \
  --description="SA for web application - storage read only" \
  --project=$PROJECT_ID

export CUSTOM_SA=web-app-sa@${PROJECT_ID}.iam.gserviceaccount.com

# Grant specific roles TO the SA
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CUSTOM_SA" \
  --role="roles/storage.objectViewer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CUSTOM_SA" \
  --role="roles/logging.logWriter"

# Verify roles
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$CUSTOM_SA" \
  --format="table(bindings.role)"
```

### Lab 2.3 — Create VM with Custom SA vs Default SA

```bash
# VM with default SA (bad practice)
gcloud compute instances create vm-default-sa \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --no-address \
  --scopes=cloud-platform

# VM with custom SA (good practice)
gcloud compute instances create vm-custom-sa \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --no-address \
  --service-account=$CUSTOM_SA \
  --scopes=cloud-platform

# Compare the SAs attached to each VM
gcloud compute instances describe vm-default-sa \
  --zone=$ZONE --format="value(serviceAccounts.email)"

gcloud compute instances describe vm-custom-sa \
  --zone=$ZONE --format="value(serviceAccounts.email)"
```

### Lab 2.4 — Test API Access from VM

```bash
# SSH into the custom SA VM and test access
gcloud compute ssh vm-custom-sa --zone=$ZONE --tunnel-through-iap --command="
  echo '--- Service account on this VM ---'
  curl -s -H 'Metadata-Flavor: Google' \
    http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email
  echo ''
  echo '--- Test: list storage buckets (should work - objectViewer) ---'
  gsutil ls 2>&1 | head -5
  echo '--- Test: create instance (should fail - no compute role) ---'
  gcloud compute instances list --limit=1 2>&1 | head -3
"
```

### Lab 2.5 — SA Impersonation (No Keys Needed)

```bash
# Grant yourself permission to impersonate the SA
gcloud iam service-accounts add-iam-policy-binding $CUSTOM_SA \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/iam.serviceAccountTokenCreator"

# Use impersonation to run a command AS the SA
gcloud storage ls \
  --impersonate-service-account=$CUSTOM_SA 2>&1 | head -5

# Generate a short-lived token (no key download needed!)
gcloud auth print-access-token \
  --impersonate-service-account=$CUSTOM_SA 2>/dev/null | head -c 40
echo "... (truncated)"
```

### 🧹 Cleanup

```bash
# Delete VMs
gcloud compute instances delete vm-default-sa --zone=$ZONE --quiet
gcloud compute instances delete vm-custom-sa --zone=$ZONE --quiet

# Remove IAM bindings
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CUSTOM_SA" \
  --role="roles/storage.objectViewer"

gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CUSTOM_SA" \
  --role="roles/logging.logWriter"

gcloud iam service-accounts remove-iam-policy-binding $CUSTOM_SA \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/iam.serviceAccountTokenCreator"

# Delete the service account
gcloud iam service-accounts delete $CUSTOM_SA --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **3 SA types:** default (avoid), user-managed (recommended), Google-managed (don't touch)
- Default SA has **Editor** role — far too broad for production
- Always create a **dedicated SA** per application/workload
- Grant **minimum required roles** to each SA
- **Avoid SA keys** — use metadata server, impersonation, or workload identity
- **Granting TO vs ON** a SA are different operations with different effects
- Metadata server provides tokens automatically to VMs with attached SAs
- **Workload Identity** maps K8s SAs → GCP SAs (no keys for GKE pods)
- SA impersonation uses short-lived tokens — no persistent credentials

### Essential Commands
```bash
# Create service account
gcloud iam service-accounts create NAME --display-name="DISPLAY"

# List service accounts
gcloud iam service-accounts list

# Grant role TO a SA
gcloud projects add-iam-policy-binding PROJECT \
  --member="serviceAccount:SA_EMAIL" --role="ROLE"

# Grant role ON a SA (impersonation)
gcloud iam service-accounts add-iam-policy-binding SA_EMAIL \
  --member="user:USER_EMAIL" --role="roles/iam.serviceAccountUser"

# Create VM with specific SA
gcloud compute instances create NAME --service-account=SA_EMAIL

# Impersonate a SA
gcloud COMMAND --impersonate-service-account=SA_EMAIL

# Delete service account
gcloud iam service-accounts delete SA_EMAIL
```

---

## Part 4 — Quiz (15 min)

**Q1.** A VM is created without specifying `--service-account`. What SA does it use and why is this a concern?

<details><summary>Answer</summary>

It uses the **default Compute Engine service account** (`PROJECT_NUMBER-compute@developer.gserviceaccount.com`). This SA typically has the **Editor** role on the project, which grants read/write access to almost all resources. Any application on that VM inherits these broad permissions — a violation of least privilege and a significant blast radius if compromised.

</details>

**Q2.** Your application running on a GCE VM needs to read from Cloud Storage. What is the recommended approach — SA key or attached SA?

<details><summary>Answer</summary>

**Attached SA** is the recommended approach. Create a user-managed SA, grant it only `roles/storage.objectViewer`, and attach it to the VM with `--service-account`. The VM gets tokens automatically from the metadata server — no key files to manage, rotate, or risk leaking. SA keys should only be used when running outside GCP with no other federation option.

</details>

**Q3.** What is the difference between `roles/iam.serviceAccountUser` and `roles/iam.serviceAccountTokenCreator`?

<details><summary>Answer</summary>

- `roles/iam.serviceAccountUser` — allows a principal to **attach** the SA to resources (VMs, Cloud Functions) or run operations as the SA. It's about deploying workloads that use the SA.
- `roles/iam.serviceAccountTokenCreator` — allows a principal to **generate tokens** (access tokens, ID tokens, sign blobs) for the SA. It's about impersonation — acting as the SA directly.

Both are powerful and should be granted carefully.

</details>

**Q4.** In your RHDS experience, you created bind DN accounts for LDAP operations. How does this map to GCP service accounts?

<details><summary>Answer</summary>

An RHDS bind DN (`uid=appbind,ou=Services,dc=example,dc=com`) is analogous to a GCP user-managed SA. Both are non-human identities for application authentication. The LDAP bind password stored in a config file parallels a SA key file — both are secrets that can leak. The GCP improvement is the **metadata server** — like having an LDAP proxy that handles authentication transparently, so the application never sees credentials. Workload Identity Federation extends this further, like SASL/GSSAPI in LDAP where Kerberos handles auth without passwords.

</details>
