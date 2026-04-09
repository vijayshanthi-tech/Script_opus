# Day 62 — IAM Introduction

> **Week 11 · Security Posture**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 61 completed

---

## Part 1 — Concept (30 min)

### IAM Core Model

```
┌────────────────────────────────────────────────────────────┐
│                    IAM POLICY                               │
│                                                             │
│  "WHO can do WHAT on WHICH resource"                        │
│                                                             │
│  ┌──────────┐    ┌──────────┐    ┌─────────────────┐      │
│  │ Principal │ +  │   Role   │ =  │   IAM Binding   │      │
│  │  (WHO)    │    │  (WHAT)  │    │                 │      │
│  └──────────┘    └──────────┘    └─────────────────┘      │
│                                                             │
│  Principal:        Role:           Binding:                 │
│  - user:a@b.com    - roles/viewer  - a@b.com → viewer      │
│  - group:dev@b.com - roles/editor  - dev@b.com → editor    │
│  - SA:my-sa@...    - roles/owner   - my-sa → compute.admin │
│                                                             │
│  Policy = Collection of Bindings                            │
│  Attached to: Project, Folder, or Organization              │
└────────────────────────────────────────────────────────────┘
```

### Linux Analogy

```
Linux File Permissions              GCP IAM
──────────────────────────────────────────────────
User:   alice                  →   user:alice@company.com
Group:  developers             →   group:developers@company.com
File:   /data/app.conf         →   projects/my-project
Permission: rwx (read/write/exec) → roles/editor (read/write/manage)

chmod 750 /data/app.conf       →   gcloud projects add-iam-policy-binding
  owner=rwx, group=r-x, other=--- →   role=editor, member=group:dev@...

/etc/sudoers                   →   roles/owner (superuser)
/etc/group                     →   Google Groups / Cloud Identity
```

### Principal Types

| Principal Type      | Format                                        | Description                       |
|---------------------|-----------------------------------------------|-----------------------------------|
| Google Account      | `user:alice@example.com`                      | Individual user                   |
| Google Group        | `group:devs@example.com`                      | Group of users                    |
| Service Account     | `serviceAccount:my-sa@project.iam.gserviceaccount.com` | Non-human identity       |
| Domain              | `domain:example.com`                          | All users in the domain           |
| allAuthenticatedUsers | `allAuthenticatedUsers`                     | Any Google account (dangerous!)   |
| allUsers            | `allUsers`                                    | Anyone, even unauthenticated      |

### Role Hierarchy

```
┌──────────────────────────────────────────────────┐
│              ROLE TYPES                           │
│                                                   │
│  Basic Roles (coarse — avoid in production):      │
│  ┌─────────────────────────────────────────┐     │
│  │ roles/viewer    → Read-only everything  │     │
│  │ roles/editor    → Read + write almost   │     │
│  │                   everything            │     │
│  │ roles/owner     → Full control + IAM    │     │
│  └─────────────────────────────────────────┘     │
│                                                   │
│  Predefined Roles (granular — recommended):       │
│  ┌─────────────────────────────────────────┐     │
│  │ roles/compute.instanceAdmin.v1          │     │
│  │ roles/compute.networkAdmin              │     │
│  │ roles/storage.objectViewer              │     │
│  │ roles/logging.viewer                    │     │
│  │ roles/monitoring.editor                 │     │
│  └─────────────────────────────────────────┘     │
│                                                   │
│  Custom Roles (build your own):                   │
│  ┌─────────────────────────────────────────┐     │
│  │ projects/my-project/roles/vmOperator    │     │
│  │   → compute.instances.get              │     │
│  │   → compute.instances.start             │     │
│  │   → compute.instances.stop              │     │
│  │   → compute.instances.list              │     │
│  └─────────────────────────────────────────┘     │
└──────────────────────────────────────────────────┘
```

### IAM Policy Inheritance

```
Organization: example.com
  │ Policy: group:admins@example.com → roles/owner
  │
  ├── Folder: Production
  │   │ Policy: group:sre@example.com → roles/editor
  │   │
  │   ├── Project: prod-web
  │   │   │ Policy: sa:web-app@... → roles/compute.instanceAdmin
  │   │   │
  │   │   └── Effective: admins=owner, sre=editor, web-app=instanceAdmin
  │   │
  │   └── Project: prod-db
  │       └── Effective: admins=owner, sre=editor
  │
  └── Folder: Development
      │ Policy: group:devs@example.com → roles/editor
      │
      └── Project: dev-sandbox
          └── Effective: admins=owner, devs=editor
```

### Service Accounts

```
┌─────────────────────────────────────────────────────────┐
│             SERVICE ACCOUNTS                             │
│                                                          │
│  What: Non-human identity for apps/VMs/services          │
│  Like: Linux service users (www-data, nobody, postgres)  │
│                                                          │
│  Types:                                                  │
│  ├── Default SA (auto-created, too permissive)          │
│  │   PROJECT_NUMBER-compute@developer.gserviceaccount.com│
│  │   ← Has roles/editor by default! BAD for production  │
│  │                                                       │
│  ├── User-created SA (recommended)                       │
│  │   my-app@PROJECT_ID.iam.gserviceaccount.com          │
│  │   ← Grant only needed permissions                    │
│  │                                                       │
│  └── Google-managed SA (internal GCP services)           │
│      ← Used by GCP services, don't modify               │
└─────────────────────────────────────────────────────────┘
```

### IAM Conditions

```
Binding with Condition:
  member: user:alice@example.com
  role: roles/compute.instanceAdmin
  condition:
    title: "Weekday only"
    expression: |
      request.time.getHours("Europe/London") >= 9 &&
      request.time.getHours("Europe/London") <= 17 &&
      request.time.getDayOfWeek("Europe/London") >= 1 &&
      request.time.getDayOfWeek("Europe/London") <= 5
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Practice granting, revoking, and testing IAM roles. Create a service account with minimal permissions.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
```

### Step 2 — View Current IAM Policy

```bash
# Full IAM policy
gcloud projects get-iam-policy $PROJECT_ID

# Formatted view
gcloud projects get-iam-policy $PROJECT_ID \
    --format="table(bindings.role, bindings.members)"

# Find all principals with Owner role
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.role:roles/owner" \
    --format="value(bindings.members)"
```

### Step 3 — Create a Service Account

```bash
# Create SA for a web application
gcloud iam service-accounts create web-app-sa \
    --display-name="Web Application Service Account" \
    --description="Minimal-permission SA for web VMs"

# Verify
gcloud iam service-accounts list --filter="email:web-app-sa"
```

### Step 4 — Grant Minimal Roles to the SA

```bash
SA_EMAIL="web-app-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant only what the app needs: read logs + write monitoring
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/monitoring.metricWriter"
```

### Step 5 — Verify Bindings

```bash
# Check what roles the SA has
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:$SA_EMAIL" \
    --format="table(bindings.role)"
```

### Step 6 — Test SA Permissions (IAM Policy Simulator)

```bash
# Test if the SA can create a VM (should be DENIED)
gcloud iam list-testable-permissions \
    //cloudresourcemanager.googleapis.com/projects/$PROJECT_ID \
    --filter="name:compute.instances.create" \
    --format="table(name, stage)"

# Test permissions directly
gcloud projects test-iam-permissions $PROJECT_ID \
    --permissions="compute.instances.create,logging.logEntries.create,monitoring.timeSeries.create"
```

### Step 7 — Create a VM Using the SA

```bash
gcloud compute instances create test-sa-vm \
    --zone=europe-west2-a \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --service-account=$SA_EMAIL \
    --scopes=cloud-platform \
    --no-address

# SSH and test permissions from inside the VM
gcloud compute ssh test-sa-vm --zone=europe-west2-a --tunnel-through-iap -- \
    "gcloud compute instances list 2>&1 | head -5"
# Expected: Permission denied (SA doesn't have compute.instances.list)
```

### Step 8 — Revoke a Role

```bash
# Remove the monitoring role
gcloud projects remove-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/monitoring.metricWriter"

# Verify removal
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:$SA_EMAIL" \
    --format="table(bindings.role)"
```

### Step 9 — List Available Predefined Roles

```bash
# List all Compute Engine predefined roles
gcloud iam roles list --filter="name:roles/compute" \
    --format="table(name, title)" \
    --limit=20

# Describe a specific role to see its permissions
gcloud iam roles describe roles/compute.instanceAdmin.v1
```

### Cleanup

```bash
gcloud compute instances delete test-sa-vm --zone=europe-west2-a --quiet
gcloud projects remove-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" --role="roles/logging.logWriter"
gcloud iam service-accounts delete $SA_EMAIL --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- IAM = **WHO** (principal) can do **WHAT** (role) on **WHICH** (resource)
- **Principals**: user, group, service account, domain, allUsers
- **Basic roles** (viewer/editor/owner): too broad — avoid in production
- **Predefined roles**: granular, per-service (recommended)
- **Custom roles**: pick exact permissions you need
- **Service accounts**: non-human identity for VMs/apps; create custom SAs, avoid default SA
- **Inheritance**: policies at org/folder level flow down to projects
- **Conditions**: time-based, resource-based restrictions on bindings
- **Default SA** has `roles/editor` — overly permissive, always replace

### Essential Commands

```bash
# View IAM policy
gcloud projects get-iam-policy PROJECT

# Grant role
gcloud projects add-iam-policy-binding PROJECT \
    --member="TYPE:EMAIL" --role="ROLE"

# Revoke role
gcloud projects remove-iam-policy-binding PROJECT \
    --member="TYPE:EMAIL" --role="ROLE"

# Service accounts
gcloud iam service-accounts create NAME --display-name="DESC"
gcloud iam service-accounts list
gcloud iam service-accounts delete EMAIL

# List roles
gcloud iam roles list --filter="name:roles/compute"
gcloud iam roles describe ROLE
```

---

## Part 4 — Quiz (15 min)

**Question 1: Why should you avoid using `roles/editor` on service accounts in production?**

<details>
<summary>Show Answer</summary>

`roles/editor` grants **write access to almost every GCP service** in the project — Compute, Storage, BigQuery, Pub/Sub, etc. If the VM is compromised, an attacker with `roles/editor` can:

- Delete or modify any resource in the project
- Read all data in Cloud Storage and BigQuery
- Create new VMs (crypto-mining)
- Modify firewall rules

**Best practice**: Create a custom service account with only the specific roles needed. A web server typically needs only `roles/logging.logWriter` and `roles/monitoring.metricWriter`.

</details>

**Question 2: A developer at org level has `roles/viewer`. At the project level, they're granted `roles/compute.instanceAdmin`. What can they do in that project?**

<details>
<summary>Show Answer</summary>

IAM policies are **additive** — permissions are the **union** of all inherited and directly granted roles. The developer can:

- **View** everything in the project (from org-level `roles/viewer`)
- **Manage Compute Engine instances** (from project-level `roles/compute.instanceAdmin`): create, delete, start, stop, SSH

They **cannot** modify networking, IAM policies, storage, or other services beyond what these two roles provide. There is no way to **deny** in IAM — policies only grant access.

</details>

**Question 3: What's the difference between a service account and a Google Group for IAM purposes?**

<details>
<summary>Show Answer</summary>

| Aspect           | Service Account                           | Google Group                     |
|------------------|-------------------------------------------|----------------------------------|
| Identity type    | Non-human (application/VM)               | Collection of human users        |
| Authentication   | Keys, metadata token, workload identity  | Google login (password, 2FA)     |
| Use case         | VM identity, CI/CD, automation           | Team access management           |
| Can SSH?         | No (it's a machine identity)             | Yes (via member accounts)        |
| Best practice    | One SA per application/service           | Group roles, not individual users|

Use **service accounts** for machines; use **Google Groups** to manage human access (add/remove members from the group instead of individual IAM bindings).

</details>

**Question 4: You need to allow a contractor to start/stop VMs but not create or delete them. How do you accomplish this?**

<details>
<summary>Show Answer</summary>

Create a **custom role** with only the needed permissions:

```bash
gcloud iam roles create vmOperator \
    --project=$PROJECT_ID \
    --title="VM Operator" \
    --permissions="compute.instances.get,compute.instances.list,compute.instances.start,compute.instances.stop,compute.instances.reset"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="user:contractor@example.com" \
    --role="projects/$PROJECT_ID/roles/vmOperator"
```

This excludes `compute.instances.create` and `compute.instances.delete`. Predefined roles like `compute.instanceAdmin.v1` would grant too many permissions.

</details>

---

*Next: [Day 63 — Least Privilege Exercise](DAY_63_LEAST_PRIVILEGE.md)*
