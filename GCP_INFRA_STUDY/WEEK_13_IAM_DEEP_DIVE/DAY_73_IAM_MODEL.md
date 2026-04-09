# Day 73 — IAM Model: Members, Roles, Policies & Hierarchy

> **Week 13 — IAM Deep Dive** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 What Is IAM?

IAM = **Identity and Access Management** — the system that answers:
- **Who** (member/principal) can do **what** (role/permissions) on **which resource**.

**Linux analogy:**
| Linux | GCP IAM |
|-------|---------|
| `/etc/passwd` users | Members (principals) |
| `chmod`, ACLs | Roles (bundles of permissions) |
| File ownership | Resource-level policy |
| Group membership (`/etc/group`) | Google Groups |
| `sudoers` | Basic Editor/Owner roles |
| SELinux policies | Organization policies + deny rules |

### 1.2 Members (Principals)

```
+------------------------------------------------------------------+
| WHO CAN ACCESS ?                                                  |
+------------------------------------------------------------------+
| Type                  | Format                    | Example       |
|-----------------------|---------------------------|---------------|
| Google Account        | user:email                | user:a@g.com  |
| Service Account       | serviceAccount:email      | sa:x@p.iam..  |
| Google Group          | group:email               | group:t@g.com |
| Google Workspace dom  | domain:example.com        | domain:co.uk  |
| allUsers              | allUsers (PUBLIC!)        | anyone        |
| allAuthenticatedUsers | allAuthenticatedUsers     | any Google ac |
+------------------------------------------------------------------+
```

> **RHDS parallel:** In LDAP you have `uid=john,ou=People,dc=example,dc=com`. In GCP you have `user:john@example.com`. The identity store moved from LDAP directory to Google Cloud Identity.

### 1.3 Roles

```
+-----------------------------------------------------------------+
|                       ROLE TYPES                                 |
+-----------------------------------------------------------------+
| Type        | Scope      | Example                | Granularity |
|-------------|------------|------------------------|-------------|
| Basic       | Project    | roles/owner            | Very broad  |
|             |            | roles/editor           |             |
|             |            | roles/viewer           |             |
| Predefined  | Service    | roles/compute.admin    | Medium      |
|             |            | roles/storage.objectViewer |          |
| Custom      | Org/Proj   | roles/myCustomRole     | Narrow      |
+-----------------------------------------------------------------+

PERMISSIONS live inside roles:
  roles/compute.instanceAdmin.v1
    ├── compute.instances.get
    ├── compute.instances.list
    ├── compute.instances.start
    ├── compute.instances.stop
    ├── compute.instances.delete
    └── ... (dozens more)
```

**Linux analogy:** Basic roles ≈ `sudo ALL`, predefined roles ≈ `sudo /sbin/service httpd restart`, custom roles ≈ specific `sudoers` command lists.

### 1.4 Policies (Bindings)

A **policy** is attached to a resource and contains **bindings**:

```
POLICY on project "my-project"
├── Binding 1
│   ├── Role: roles/compute.viewer
│   └── Members:
│       ├── user:alice@example.com
│       └── group:devs@example.com
├── Binding 2
│   ├── Role: roles/storage.admin
│   └── Members:
│       └── serviceAccount:backup@my-project.iam.gserviceaccount.com
└── Binding 3 (conditional)
    ├── Role: roles/compute.instanceAdmin.v1
    ├── Members:
    │   └── user:bob@example.com
    └── Condition:
        └── request.time < "2026-06-01T00:00:00Z"
```

**Linux analogy:** This is like an ACL on a directory — multiple entries, each granting specific access to specific users/groups.

### 1.5 Resource Hierarchy & Policy Inheritance

```
                    ┌─────────────┐
                    │ Organization │  (domain.com)
                    │  Policy: A   │
                    └──────┬──────┘
                           │ INHERITS DOWN
               ┌───────────┴───────────┐
               │                       │
        ┌──────┴──────┐        ┌───────┴─────┐
        │  Folder:    │        │   Folder:   │
        │  "Prod"     │        │   "Dev"     │
        │  Policy: B  │        │  Policy: C  │
        └──────┬──────┘        └──────┬──────┘
               │                      │
        ┌──────┴──────┐        ┌──────┴──────┐
        │  Project    │        │  Project    │
        │  "prod-web" │        │  "dev-web"  │
        │  Policy: D  │        │  Policy: E  │
        └──────┬──────┘        └─────────────┘
               │
        ┌──────┴──────┐
        │  Resource   │
        │  (VM, GCS)  │
        │  Policy: F  │
        └─────────────┘

EFFECTIVE POLICY = UNION of all policies from Org → Folder → Project → Resource
- Policies are ADDITIVE (grant at org = grant everywhere below)
- You CANNOT remove an inherited grant at a lower level (use Deny policies)
```

> **Key rule:** IAM is **additive only**. A permission granted at the org level cannot be revoked at the project level — unless you use a **Deny policy**.

### 1.6 Deny Policies

Deny policies override allow policies:

```
EVALUATION ORDER:
  1. Check DENY policies → if denied, STOP → 403
  2. Check ALLOW policies → if allowed, PERMIT
  3. Default → DENY (implicit deny)

       ┌──────────────────┐
       │  Incoming Request │
       └────────┬─────────┘
                │
       ┌────────▼─────────┐
       │  Deny policy      │──── DENIED ──→ 403 Forbidden
       │  matches?         │
       └────────┬─────────┘
                │ NO
       ┌────────▼─────────┐
       │  Allow policy     │──── ALLOWED ──→ ✅ Access
       │  matches?         │
       └────────┬─────────┘
                │ NO
       ┌────────▼─────────┐
       │  Implicit deny    │──→ 403 Forbidden
       └──────────────────┘
```

**Linux analogy:** Deny policies are like `DenyUsers` in `sshd_config` — they override any allow rules.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
# Set variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Examine Current IAM Policy

```bash
# View the full IAM policy for your project
gcloud projects get-iam-policy $PROJECT_ID --format=yaml

# List just the bindings
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="table(bindings.role, bindings.members)"

# Check what roles YOU have
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$(gcloud config get-value account)" \
  --format="table(bindings.role)"
```

### Lab 2.2 — Add IAM Bindings at Project Level

```bash
# Create a test service account (acts as our "test user")
gcloud iam service-accounts create lab-viewer \
  --display-name="Lab Viewer SA" \
  --project=$PROJECT_ID

export SA_VIEWER=lab-viewer@${PROJECT_ID}.iam.gserviceaccount.com

# Grant Compute Viewer at project level
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_VIEWER" \
  --role="roles/compute.viewer"

# Verify binding was added
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$SA_VIEWER" \
  --format="table(bindings.role)"
```

### Lab 2.3 — Test Policy Inheritance with Resources

```bash
# Create a VM
gcloud compute instances create iam-test-vm \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --no-address

# Grant Storage Viewer at project level
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_VIEWER" \
  --role="roles/storage.objectViewer"

# Test what permissions the SA has using testIamPermissions
gcloud asset analyze-iam-policy \
  --project=$PROJECT_ID \
  --identity="serviceAccount:$SA_VIEWER" \
  --full-resource-name="//compute.googleapis.com/projects/$PROJECT_ID/zones/$ZONE/instances/iam-test-vm" 2>/dev/null || echo "Asset API may need enabling"
```

### Lab 2.4 — Add Conditional Binding

```bash
# Add a time-limited binding (expires in 30 days)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_VIEWER" \
  --role="roles/compute.instanceAdmin.v1" \
  --condition="expression=request.time < timestamp('2026-05-08T00:00:00Z'),title=temp-admin-30d,description=Temporary admin for 30 days"

# Verify conditional binding
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$SA_VIEWER" \
  --format="yaml(bindings.role, bindings.condition)"
```

### Lab 2.5 — Remove a Binding

```bash
# Remove the compute viewer role
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_VIEWER" \
  --role="roles/compute.viewer"

# Confirm removal
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$SA_VIEWER" \
  --format="table(bindings.role)"
```

### 🧹 Cleanup

```bash
# Remove all bindings for the SA
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_VIEWER" \
  --role="roles/storage.objectViewer"

gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_VIEWER" \
  --role="roles/compute.instanceAdmin.v1" \
  --condition="expression=request.time < timestamp('2026-05-08T00:00:00Z'),title=temp-admin-30d,description=Temporary admin for 30 days"

# Delete the service account
gcloud iam service-accounts delete $SA_VIEWER --quiet

# Delete the test VM
gcloud compute instances delete iam-test-vm --zone=$ZONE --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- IAM answers: **WHO** can do **WHAT** on **WHICH** resource
- **6 member types:** Google account, service account, group, domain, allUsers, allAuthenticatedUsers
- **3 role types:** basic (broad), predefined (service-scoped), custom (fine-grained)
- A **policy** is a collection of **bindings** (role + members)
- Policies are **additive** — inherited down the resource hierarchy
- **Deny policies** override allow policies (evaluated first)
- Evaluation: Deny → Allow → Implicit Deny
- **Never** use `allUsers` or `allAuthenticatedUsers` unless you truly want public access
- Conditional bindings add **time, resource, IP** conditions to grants

### Essential Commands
```bash
# View project IAM policy
gcloud projects get-iam-policy PROJECT_ID

# Add a binding
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="TYPE:EMAIL" --role="ROLE"

# Remove a binding
gcloud projects remove-iam-policy-binding PROJECT_ID \
  --member="TYPE:EMAIL" --role="ROLE"

# List roles for a member
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:EMAIL" \
  --format="table(bindings.role)"

# List predefined roles
gcloud iam roles list --filter="name:roles/compute"

# Describe a role
gcloud iam roles describe roles/compute.viewer
```

---

## Part 4 — Quiz (15 min)

**Q1.** A user has `roles/viewer` at the Organisation level and `roles/compute.admin` at the project level. What compute permissions do they have at the project level?

<details><summary>Answer</summary>

They have the **union** of both: all permissions from `roles/viewer` (read-only across all services) plus all permissions from `roles/compute.admin` (full compute management). IAM policies are additive — permissions accumulate from higher to lower levels.

</details>

**Q2.** You granted `roles/storage.admin` to a user at the org level but want to block them from one specific project. How?

<details><summary>Answer</summary>

Use a **Deny policy** on that project. Standard IAM allow policies are additive and cannot revoke inherited permissions. A deny policy evaluated before allow policies will block the specific permissions on that project. Alternatively, restructure the hierarchy — but deny policies are the direct solution.

</details>

**Q3.** What is the difference between `allUsers` and `allAuthenticatedUsers`?

<details><summary>Answer</summary>

- `allUsers` = **anyone on the internet**, including unauthenticated users — fully public.
- `allAuthenticatedUsers` = **any Google account holder** — still very broad, includes personal Gmail accounts. Neither should be used for sensitive resources.

</details>

**Q4.** In Linux terms, how does a conditional IAM binding compare to `sudoers` configuration?

<details><summary>Answer</summary>

A conditional binding is like a `sudoers` rule with `timestamp_timeout` or host restrictions — it grants access only when specific conditions are met (time window, resource tags, IP range). In RHDS LDAP, this parallels **time-based access control** (`nsTimeLimit`) or **CoS (Class of Service)** templates that vary access by attribute values.

</details>
