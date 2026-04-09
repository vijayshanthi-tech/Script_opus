# Day 81 — Service Account Per Workload: Blast Radius & Naming

> **Week 14 — Secure Access** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 One SA Per Workload — Why?

```
  SHARED SA (BAD)                     ONE-SA-PER-WORKLOAD (GOOD)
  ═══════════════                     ════════════════════════════

  ┌──────────────┐                    ┌──────────────┐
  │  shared-sa   │                    │  web-app-sa  │──▶ GCS read
  │              │                    └──────────────┘
  │ Permissions: │                    ┌──────────────┐
  │ - GCS read   │                    │  batch-sa    │──▶ BQ write
  │ - BQ write   │                    └──────────────┘
  │ - PubSub pub │                    ┌──────────────┐
  │ - Compute    │                    │  worker-sa   │──▶ PubSub
  └──────┬───────┘                    └──────────────┘
         │
    Used by ALL apps                   Each app = minimal permissions
    
  BLAST RADIUS:                        BLAST RADIUS:
  If compromised:                      If web-app-sa compromised:
  → ALL permissions exposed            → Only GCS read exposed
  → ALL workloads affected             → Only web-app affected
  → Difficult audit trail              → Clear audit trail
```

**Linux analogy:**
| Shared SA | Per-Workload SA |
|-----------|-----------------|
| Running all apps as `root` | `www-data` for Apache, `postgres` for DB |
| One `uid=appuser` for everything | Separate UIDs per application |
| RHDS: one bind DN for all apps | RHDS: separate bind DN per app |

### 1.2 Blast Radius Principle

```
  BLAST RADIUS = Impact of a compromised identity
  ════════════════════════════════════════════════

  ┌─────────────────────────────────────────────────┐
  │  Scenario: SA key leaked or VM compromised       │
  │                                                  │
  │  Shared SA:                                      │
  │  ┌──────────────────────────────┐               │
  │  │  ████████████████████████████│ ← ENTIRE      │
  │  │  █ ALL SERVICES EXPOSED     █│   PROJECT     │
  │  │  ████████████████████████████│               │
  │  └──────────────────────────────┘               │
  │                                                  │
  │  Per-workload SA:                                │
  │  ┌──────────────────────────────┐               │
  │  │  ██░░░░░░░░░░░░░░░░░░░░░░░░│ ← ONLY ONE    │
  │  │   OK  OK  OK  OK  OK  OK   │   SERVICE     │
  │  │  ░░░░░░░░░░░░░░░░░░░░░░░░░░│               │
  │  └──────────────────────────────┘               │
  └─────────────────────────────────────────────────┘
```

### 1.3 SA Naming Conventions

```
  NAMING CONVENTION
  ═════════════════

  Pattern: {app}-{environment}-{function}
  
  Examples:
  ┌────────────────────────────────────────────────┐
  │ SA Name              │ Purpose                  │
  ├──────────────────────┼──────────────────────────┤
  │ web-prod-reader      │ Web app, prod, reads only│
  │ batch-dev-processor  │ Batch job, dev, processes│
  │ api-prod-writer      │ API server, prod, writes │
  │ monitor-prod-viewer  │ Monitoring, prod, views  │
  │ cicd-deploy-admin    │ CI/CD, deployment        │
  └────────────────────────────────────────────────┘

  Rules:
  - 6-30 characters
  - Lowercase letters, digits, hyphens
  - Must start with a letter
  - Display name: human-readable description
  - Description: detailed purpose + owner team
```

### 1.4 SA vs User for Automation

```
  WHO SHOULD RUN AUTOMATED TASKS?
  ════════════════════════════════

  ┌───────────────────────────────────────────────────┐
  │  Task Type          │ Use SA │ Use User │ Why     │
  ├─────────────────────┼────────┼──────────┼─────────┤
  │ CI/CD pipeline      │   ✅   │    ❌    │ No human│
  │ Cron job on VM      │   ✅   │    ❌    │ Unattend│
  │ Cloud Function      │   ✅   │    ❌    │ Service │
  │ Manual gcloud cmd   │   ❌   │    ✅    │ Human   │
  │ Console browsing    │   ❌   │    ✅    │ Human   │
  │ Terraform apply     │   ✅*  │    ✅*   │ Either  │
  │ On-call debugging   │   ❌   │    ✅    │ Human   │
  └───────────────────────────────────────────────────┘
  
  * Terraform: SA for CI/CD pipelines, user for local dev
  
  ⚠ NEVER: use a personal account for automated processes
  ⚠ NEVER: share a SA across unrelated applications
```

### 1.5 The Migration Path: Shared SA → Per-Workload

```
  MIGRATION STEPS
  ═══════════════

  BEFORE:
  shared-sa@project.iam... ──▶ roles/editor
    ├── used by web app
    ├── used by batch job
    └── used by worker service

  STEP 1: Identify each workload's actual permission needs
  STEP 2: Create dedicated SAs with specific roles
  STEP 3: Update workloads one at a time
  STEP 4: Monitor for 403 errors after each migration
  STEP 5: Remove workloads from shared SA
  STEP 6: Delete shared SA when empty

  AFTER:
  web-prod-reader@project.iam...   ──▶ roles/storage.objectViewer
  batch-prod-writer@project.iam... ──▶ roles/bigquery.dataEditor
  worker-prod-sub@project.iam...   ──▶ roles/pubsub.subscriber
```

> **RHDS parallel:** In RHDS, the migration is from `uid=genericapp,ou=Services` to `uid=webapp,ou=Services`, `uid=batchjob,ou=Services`, each with its own ACI granting exactly the subtree/attributes it needs.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Audit Current SA Usage

```bash
# List all SAs and their roles
echo "═══════════════════════════════════════"
echo "SERVICE ACCOUNT INVENTORY"
echo "═══════════════════════════════════════"

for SA in $(gcloud iam service-accounts list --format="value(email)"); do
  echo ""
  echo "SA: $SA"
  ROLES=$(gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:$SA" \
    --format="value(bindings.role)" 2>/dev/null)
  
  if [ -z "$ROLES" ]; then
    echo "  Roles: NONE (unused SA?)"
  else
    echo "  Roles:"
    echo "$ROLES" | while read role; do
      PERM_COUNT=$(gcloud iam roles describe $role \
        --format="value(includedPermissions)" 2>/dev/null | tr ';' '\n' | wc -l)
      echo "    - $role ($PERM_COUNT permissions)"
    done
  fi
done
```

### Lab 2.2 — Create Per-Workload SAs

```bash
# Simulate 3 workloads that currently share one SA

# Workload 1: Web frontend — reads from GCS
gcloud iam service-accounts create web-prod-reader \
  --display-name="Web Frontend - Production Reader" \
  --description="Reads static assets from GCS for web frontend"
export WEB_SA=web-prod-reader@${PROJECT_ID}.iam.gserviceaccount.com

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$WEB_SA" \
  --role="roles/storage.objectViewer"

# Workload 2: Batch processor — writes to BigQuery
gcloud iam service-accounts create batch-prod-writer \
  --display-name="Batch Processor - Production Writer" \
  --description="Writes processed data to BigQuery datasets"
export BATCH_SA=batch-prod-writer@${PROJECT_ID}.iam.gserviceaccount.com

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$BATCH_SA" \
  --role="roles/bigquery.dataEditor"

# Workload 3: Worker — subscribes to Pub/Sub
gcloud iam service-accounts create worker-prod-sub \
  --display-name="Worker Service - Production Subscriber" \
  --description="Subscribes to Pub/Sub for event processing"
export WORKER_SA=worker-prod-sub@${PROJECT_ID}.iam.gserviceaccount.com

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$WORKER_SA" \
  --role="roles/pubsub.subscriber"

# Verify isolation
echo ""
echo "═══════════════════════════════════════"
echo "PER-WORKLOAD SA VERIFICATION"
echo "═══════════════════════════════════════"
for SA in $WEB_SA $BATCH_SA $WORKER_SA; do
  echo ""
  echo "SA: $(echo $SA | cut -d@ -f1)"
  gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:$SA" \
    --format="value(bindings.role)"
done
```

### Lab 2.3 — Deploy VMs with Isolated SAs

```bash
# Each VM gets its own SA
gcloud compute instances create web-vm \
  --zone=$ZONE --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --service-account=$WEB_SA --scopes=cloud-platform \
  --no-address --labels=workload=web,env=prod

gcloud compute instances create batch-vm \
  --zone=$ZONE --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --service-account=$BATCH_SA --scopes=cloud-platform \
  --no-address --labels=workload=batch,env=prod

gcloud compute instances create worker-vm \
  --zone=$ZONE --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --service-account=$WORKER_SA --scopes=cloud-platform \
  --no-address --labels=workload=worker,env=prod

# Verify each VM has correct SA
echo ""
echo "═══════════════════════════════════════"
echo "VM → SA MAPPING"
echo "═══════════════════════════════════════"
for VM in web-vm batch-vm worker-vm; do
  SA=$(gcloud compute instances describe $VM --zone=$ZONE \
    --format="value(serviceAccounts.email)" 2>/dev/null)
  echo "$VM → $SA"
done
```

### Lab 2.4 — Test Permission Isolation

```bash
# Allow impersonation for testing
for SA in $WEB_SA $BATCH_SA $WORKER_SA; do
  gcloud iam service-accounts add-iam-policy-binding $SA \
    --member="user:$(gcloud config get-value account)" \
    --role="roles/iam.serviceAccountTokenCreator"
done

sleep 10

# Test: web SA can read storage but NOT BigQuery
echo "--- Web SA: storage (should work) ---"
gcloud storage ls --impersonate-service-account=$WEB_SA 2>&1 | head -3

echo "--- Web SA: BigQuery (should fail) ---"
gcloud bq ls --impersonate-service-account=$WEB_SA 2>&1 | head -3

# Test: batch SA can access BigQuery but NOT storage
echo "--- Batch SA: BigQuery (should work) ---"
bq ls --project_id=$PROJECT_ID 2>&1 | head -3 || echo "(BigQuery may have no datasets)"

echo ""
echo "✅ Permission isolation verified — each SA only has its own permissions"
```

### Lab 2.5 — Generate SA Inventory Report

```bash
cat << 'EOF'
═══════════════════════════════════════════════════════
SERVICE ACCOUNT INVENTORY REPORT
═══════════════════════════════════════════════════════

SA Name             │ Workload    │ Role                  │ Blast Radius
────────────────────┼─────────────┼───────────────────────┼─────────────
web-prod-reader     │ Web frontend│ storage.objectViewer  │ GCS read only
batch-prod-writer   │ Batch job   │ bigquery.dataEditor   │ BQ tables only
worker-prod-sub     │ Worker svc  │ pubsub.subscriber     │ PubSub only

SECURITY POSTURE:
- No shared SAs                    ✅
- No SA keys created               ✅
- Per-workload isolation            ✅
- Minimal permissions per SA        ✅
- Consistent naming convention      ✅

COMPARED TO SHARED SA:
- Editor role = ~5000 permissions per workload
- Per-workload = ~50 permissions per workload (average)
- Risk reduction: ~99%
═══════════════════════════════════════════════════════
EOF
```

### 🧹 Cleanup

```bash
# Delete VMs
gcloud compute instances delete web-vm batch-vm worker-vm \
  --zone=$ZONE --quiet

# Remove impersonation bindings
for SA in $WEB_SA $BATCH_SA $WORKER_SA; do
  gcloud iam service-accounts remove-iam-policy-binding $SA \
    --member="user:$(gcloud config get-value account)" \
    --role="roles/iam.serviceAccountTokenCreator" 2>/dev/null
done

# Remove project bindings
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$WEB_SA" --role="roles/storage.objectViewer"
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$BATCH_SA" --role="roles/bigquery.dataEditor"
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$WORKER_SA" --role="roles/pubsub.subscriber"

# Delete SAs
gcloud iam service-accounts delete $WEB_SA --quiet
gcloud iam service-accounts delete $BATCH_SA --quiet
gcloud iam service-accounts delete $WORKER_SA --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **One SA per workload** minimises blast radius
- Shared SAs = all permissions exposed if any workload is compromised
- SA naming: `{app}-{env}-{function}` (lowercase, hyphens)
- Use SAs for automation, user accounts for human access
- Migration: create new SAs → update workloads → remove shared SA
- Default Compute SA with `roles/editor` is the worst case — replace immediately
- Description field should document purpose and owning team
- 100 SAs per project default quota (can be increased)

### Essential Commands
```bash
# Create SA with description
gcloud iam service-accounts create NAME \
  --display-name="DISPLAY" \
  --description="PURPOSE + OWNER TEAM"

# Attach SA to existing VM (requires stop/start)
gcloud compute instances stop VM --zone=ZONE
gcloud compute instances set-service-account VM --zone=ZONE \
  --service-account=SA_EMAIL --scopes=cloud-platform
gcloud compute instances start VM --zone=ZONE

# List VMs and their SAs
gcloud compute instances list \
  --format="table(name, zone.basename(), serviceAccounts[0].email)"
```

---

## Part 4 — Quiz (15 min)

**Q1.** A project has 5 microservices all using the default Compute SA with Editor role. What's the risk and fix?

<details><summary>Answer</summary>

**Risk:** If ANY of the 5 microservices is compromised, the attacker has Editor access to the entire project — they can modify/delete any resource. The blast radius is the full project across all services.

**Fix:** Create 5 dedicated SAs, one per microservice. Grant each the minimum roles needed (e.g., one needs only Storage read, another only Pub/Sub write). Attach each SA to its respective VM/service. Blast radius shrinks from "entire project" to "one microservice's specific resources."

</details>

**Q2.** Should a CI/CD pipeline use a user account or a service account? Why?

<details><summary>Answer</summary>

**Service account.** Reasons: (1) Pipelines run unattended — no human to do interactive auth/2FA; (2) User accounts are tied to people who leave/change roles; (3) SA permissions can be scoped exactly to what the pipeline needs; (4) SA activity is clearly distinguished from human activity in audit logs; (5) SA access can be revoked without affecting any person's work. Use a dedicated SA like `cicd-prod-deploy@...` with only deployment-related roles.

</details>

**Q3.** You need to change the SA attached to a running VM. What's the process?

<details><summary>Answer</summary>

You cannot change the service account of a running VM. You must: (1) **Stop** the VM (`gcloud compute instances stop`), (2) **Set** the new SA (`gcloud compute instances set-service-account ... --service-account=NEW_SA`), (3) **Start** the VM. Alternatively, create a new VM with the correct SA and migrate the workload. For zero-downtime, use a Managed Instance Group (MIG) and update the instance template with the new SA.

</details>

**Q4.** Compare per-workload SAs to per-application bind DNs in RHDS.

<details><summary>Answer</summary>

| GCP Per-Workload SA | RHDS Per-App Bind DN |
|--------------------|-----------------------|
| `web-prod-reader@project.iam...` | `uid=webapp,ou=Services,dc=example,dc=com` |
| `roles/storage.objectViewer` | `aci: allow (read) subtree="ou=web"` |
| 1 SA = 1 application | 1 bind DN = 1 application |
| Compromise = limited to SA's roles | Compromise = limited to ACI grants |
| `gcloud iam service-accounts list` | `ldapsearch -b "ou=Services" "(objectClass=*)"` |

In RHDS, you'd never have all applications bind as `cn=Directory Manager`. In GCP, you should never have all workloads use the default SA with Editor. Same principle, same implementation pattern.

</details>
