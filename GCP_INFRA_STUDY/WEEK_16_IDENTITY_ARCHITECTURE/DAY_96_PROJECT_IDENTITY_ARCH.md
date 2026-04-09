# Day 96 — PROJECT: Identity Architecture Comparison & Migration Path

> **Week 16 — Identity Architecture** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 Project Overview

```
  PROJECT: DESIGN A COMPLETE IDENTITY ARCHITECTURE
  ═════════════════════════════════════════════════

  Deliverables:
  1. RHDS → Cloud Identity comparison matrix
  2. Migration path diagram (3 phases)
  3. Terraform IAM module for the target state
  4. Compliance evidence script
  5. Architecture decision records (ADRs)
```

### 1.2 Full Comparison Matrix

```
  RHDS vs CLOUD IDENTITY — COMPREHENSIVE COMPARISON
  ══════════════════════════════════════════════════

  ┌───────────────────────┬───────────────────────┬───────────────────────┐
  │ CATEGORY              │ RHDS (On-Prem)        │ GCP (Cloud)           │
  ├───────────────────────┼───────────────────────┼───────────────────────┤
  │ DIRECTORY SERVICE     │                       │                       │
  │ Server                │ RHDS (389-ds)         │ Cloud Identity        │
  │ Protocol              │ LDAP/LDAPS            │ REST API / gRPC       │
  │ Schema                │ LDAP schema (RFC 4512)│ Cloud Identity schema │
  │ Data model            │ DIT (tree)            │ Flat (users/groups)   │
  │ Data storage          │ LDBM / BDB            │ Google managed        │
  │ Query language        │ LDAP filter syntax    │ API filters           │
  ├───────────────────────┼───────────────────────┼───────────────────────┤
  │ IDENTITY              │                       │                       │
  │ User identity         │ uid=alice,ou=People   │ alice@example.com     │
  │ Group                 │ cn=admins (groupOfNames)│ admins@example.com  │
  │ Service identity      │ uid=app-sa            │ app@proj.iam.gsa.com  │
  │ Machine identity      │ fqdn=host.example.com │ Compute default SA    │
  │ External identity     │ N/A (referral)        │ Workforce IdF         │
  ├───────────────────────┼───────────────────────┼───────────────────────┤
  │ ACCESS CONTROL        │                       │                       │
  │ Policy model          │ ACI (in-tree)         │ IAM (separate layer)  │
  │ Granularity           │ Attribute-level       │ API method-level      │
  │ Deny support          │ Yes (deny ACI)        │ Yes (deny policies)   │
  │ Inheritance           │ Subtree               │ Org → Folder → Proj   │
  │ Conditions            │ Time, IP, DNS in ACI  │ IAM Conditions        │
  │ Roles                 │ None (permission-based)│ 900+ predefined roles│
  ├───────────────────────┼───────────────────────┼───────────────────────┤
  │ AUTHENTICATION        │                       │                       │
  │ User auth             │ LDAP bind (simple/SASL)│ OAuth 2.0 / SAML    │
  │ MFA                   │ External (PAM)        │ Built-in 2FA/FIDO2   │
  │ Password policy       │ passwordPolicy object │ Cloud Identity policy │
  │ SSO                   │ Kerberos ticket       │ SAML/OIDC federation  │
  │ Service auth          │ Bind DN + password    │ SA key / WIF / metadata│
  ├───────────────────────┼───────────────────────┼───────────────────────┤
  │ HIGH AVAILABILITY     │                       │                       │
  │ Replication           │ Multi-master (manual) │ Global (managed)      │
  │ Failover              │ HAProxy / DNS         │ Automatic             │
  │ DR                    │ Replica in DR site    │ Multi-region (default)│
  │ Backup                │ db2ldif / LDIF export │ Managed (automatic)   │
  │ Patching              │ Rolling restart       │ No patching needed    │
  ├───────────────────────┼───────────────────────┼───────────────────────┤
  │ AUDIT & COMPLIANCE    │                       │                       │
  │ Access logging        │ nsslapd-accesslog     │ Data Access audit logs│
  │ Change logging        │ nsslapd-auditlog      │ Admin Activity logs   │
  │ Error logging         │ nsslapd-errorlog      │ System Event logs     │
  │ Log analysis          │ grep/awk/ELK          │ Logs Explorer/BigQuery│
  │ Alerting              │ nagios/zabbix scripts │ Cloud Monitoring      │
  │ Compliance reporting  │ Manual scripts        │ SCC + custom queries  │
  ├───────────────────────┼───────────────────────┼───────────────────────┤
  │ AUTOMATION            │                       │                       │
  │ User provisioning     │ ldapadd / CSV scripts │ Cloud Identity API    │
  │ IaC                   │ Ansible LDAP module   │ Terraform             │
  │ Event-driven          │ Cron + scripts        │ Pub/Sub + Functions   │
  │ Bulk operations       │ ldapmodify -f file.ldif│ gcloud / API batch   │
  │ Config management     │ dse.ldif / cn=config  │ Org policies          │
  └───────────────────────┴───────────────────────┴───────────────────────┘
```

### 1.3 Migration Path

```
  RHDS → GCP IDENTITY: 3-PHASE MIGRATION
  ═══════════════════════════════════════

  PHASE 1: COEXISTENCE (Months 1-3)
  ┌──────────────────────────────────────────────────┐
  │ • Deploy GCDS to sync users/groups to Cloud ID   │
  │ • Configure SAML SSO (Keycloak + RHDS)           │
  │ • Enable Cloud Audit Logging                     │
  │ • Set up IAM structure (folders, projects)        │
  │ • Migrate first workload to GCP                  │
  │                                                  │
  │ RHDS ═══sync═══▶ Cloud Identity                  │
  │ (still primary)   (read-only copy)               │
  └──────────────────────────────────────────────────┘
                         │
                         ▼
  PHASE 2: HYBRID (Months 4-8)
  ┌──────────────────────────────────────────────────┐
  │ • Move authentication to Cloud Identity SSO      │
  │ • Implement Workforce IdF for non-Workspace users│
  │ • Deploy IAP for internal web apps               │
  │ • Automate JML via Cloud Functions               │
  │ • Set up compliance monitoring (BQ + alerts)     │
  │                                                  │
  │ RHDS ═══sync═══▶ Cloud Identity                  │
  │ (auth source)     (IAM + apps)                   │
  └──────────────────────────────────────────────────┘
                         │
                         ▼
  PHASE 3: CLOUD-PRIMARY (Months 9-12)
  ┌──────────────────────────────────────────────────┐
  │ • Cloud Identity becomes primary directory        │
  │ • RHDS reduced to legacy app support only         │
  │ • Full IAM Terraform automation                  │
  │ • Complete compliance dashboard                   │
  │ • Decommission: GCDS → direct Cloud ID mgmt      │
  │                                                  │
  │ Cloud Identity (PRIMARY)                         │
  │ RHDS (legacy only, sunset plan)                  │
  └──────────────────────────────────────────────────┘
```

### 1.4 Architecture Decision Records

```
  ADR-001: IDENTITY SOURCE OF TRUTH
  ══════════════════════════════════
  Status: ACCEPTED
  Context: Need single source of truth for user identity during migration.
  Decision: RHDS remains SoT during Phase 1-2. Cloud Identity becomes SoT in Phase 3.
  Rationale: GCDS is one-way; changes must originate in RHDS until migration complete.
  Consequences: JML automation targets RHDS in Phase 1-2, Cloud Identity API in Phase 3.

  ADR-002: AUTHENTICATION METHOD
  ══════════════════════════════
  Status: ACCEPTED
  Context: Users need SSO across on-prem and cloud apps.
  Decision: SAML SSO via Keycloak backed by RHDS.
  Rationale: Keeps password verification on-prem (RHDS bind). No password sync needed.
  Consequences: Keycloak becomes critical path for auth. Must be HA (2+ instances).

  ADR-003: GCP ACCESS FOR CONTRACTORS
  ═══════════════════════════════════
  Status: ACCEPTED
  Context: 20 contractors need GCP Console access only.
  Decision: Workforce Identity Federation (no Google accounts).
  Rationale: Avoids Cloud Identity licenses. Contractors leave → IdP removes access instantly.
  Consequences: Contractors can't use Google Workspace. Must use gcloud CLI with --login-config.

  ADR-004: SERVICE ACCOUNT STRATEGY
  ═════════════════════════════════
  Status: ACCEPTED
  Context: 15 workloads migrating to GCE/GKE.
  Decision: One SA per workload. No user-managed keys. Workload Identity for GKE.
  Rationale: Blast radius containment. SA key = RHDS service password (liability).
  Consequences: Each workload needs its own SA + specific IAM roles.
```

> **RHDS parallel:** ADRs are like the RHDS installation/design document you'd create for a new directory deployment — documenting suffix structure, replication topology, ACI strategy, and password policy decisions. Same discipline, cloud context.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Build the IAM Foundation (Terraform)

```bash
echo "=== IAM FOUNDATION MODULE ==="
echo ""

# Create Terraform directory
mkdir -p /tmp/identity-architecture
cd /tmp/identity-architecture

cat > main.tf << 'EOF'
# Identity Architecture — Terraform IAM Module
# Implements: ADR-001 (Cloud Identity SoT), ADR-004 (1 SA per workload)

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "europe-west2"
}

# --- Team Groups (mapped from RHDS cn=groups) ---
# In production, these would be Google Groups synced from RHDS via GCDS
variable "teams" {
  description = "Team definitions with roles"
  type = map(object({
    group_email = string
    roles       = list(string)
  }))
  default = {
    sre = {
      group_email = "sre-team@example.com"
      roles = [
        "roles/monitoring.viewer",
        "roles/compute.viewer",
        "roles/logging.viewer"
      ]
    }
    developers = {
      group_email = "developers@example.com"
      roles = [
        "roles/storage.objectViewer",
        "roles/container.developer"
      ]
    }
    security = {
      group_email = "security@example.com"
      roles = [
        "roles/iam.securityReviewer",
        "roles/logging.viewer",
        "roles/securitycenter.findingsViewer"
      ]
    }
  }
}

# --- Team IAM Bindings (≈ RHDS ACIs per group) ---
resource "google_project_iam_member" "team_roles" {
  for_each = {
    for pair in flatten([
      for team_key, team in var.teams : [
        for role in team.roles : {
          key   = "${team_key}-${replace(role, "/", "-")}"
          role  = role
          email = team.group_email
        }
      ]
    ]) : pair.key => pair
  }

  project = var.project_id
  role    = each.value.role
  member  = "group:${each.value.email}"
}

# --- Workload Service Accounts (ADR-004: 1 SA per workload) ---
variable "workloads" {
  description = "Workload definitions with SA and roles"
  type = map(object({
    display_name = string
    roles        = list(string)
  }))
  default = {
    web-app = {
      display_name = "Web Application SA"
      roles = [
        "roles/storage.objectViewer",
        "roles/logging.logWriter"
      ]
    }
    data-pipeline = {
      display_name = "Data Pipeline SA"
      roles = [
        "roles/bigquery.dataEditor",
        "roles/storage.objectAdmin"
      ]
    }
    monitoring-agent = {
      display_name = "Monitoring Agent SA"
      roles = [
        "roles/monitoring.metricWriter",
        "roles/logging.logWriter"
      ]
    }
  }
}

resource "google_service_account" "workload_sa" {
  for_each = var.workloads

  account_id   = "${each.key}-sa"
  display_name = each.value.display_name
  project      = var.project_id
}

resource "google_project_iam_member" "workload_roles" {
  for_each = {
    for pair in flatten([
      for wl_key, wl in var.workloads : [
        for role in wl.roles : {
          key  = "${wl_key}-${replace(role, "/", "-")}"
          role = role
          sa   = google_service_account.workload_sa[wl_key].email
        }
      ]
    ]) : pair.key => pair
  }

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${each.value.sa}"
}

# --- Org Policies (security guardrails) ---
# Disable SA key creation (ADR-004: no long-lived keys)
# Uncomment when you have org-level access:
# resource "google_project_organization_policy" "disable_sa_keys" {
#   project    = var.project_id
#   constraint = "iam.disableServiceAccountKeyCreation"
#   boolean_policy {
#     enforced = true
#   }
# }

# --- Outputs ---
output "workload_service_accounts" {
  value = {
    for key, sa in google_service_account.workload_sa :
    key => sa.email
  }
}

output "team_binding_count" {
  value = length(google_project_iam_member.team_roles)
}
EOF

echo "✓ main.tf created"
echo ""
echo "--- Terraform Configuration ---"
cat main.tf | head -30
echo "... ($(wc -l < main.tf) lines total)"
```

### Lab 2.2 — Validate Terraform Plan

```bash
echo "=== VALIDATE TERRAFORM ==="
echo ""
cd /tmp/identity-architecture

# Initialize Terraform
terraform init 2>/dev/null && echo "✓ Terraform initialized" || \
  echo "Terraform init requires provider download"

# Validate syntax
terraform validate 2>/dev/null && echo "✓ Configuration valid" || \
  echo "Validation requires provider initialization"

# Plan (dry run)
echo ""
echo "--- Terraform Plan (dry run) ---"
echo "terraform plan -var=\"project_id=$PROJECT_ID\""
echo ""
echo "Expected resources:"
echo "  • 3 workload service accounts"
echo "  • 6 workload IAM bindings"
echo "  • 8 team IAM bindings"
echo "  • Total: ~17 resources"
echo ""
echo "In production: terraform plan → review → terraform apply"
```

### Lab 2.3 — Build Compliance Evidence Script

```bash
echo "=== COMPLIANCE EVIDENCE SCRIPT ==="
echo ""

cat > /tmp/identity-architecture/compliance-audit.sh << 'SCRIPT'
#!/bin/bash
# compliance-audit.sh — Generate identity architecture compliance evidence
# Run monthly to verify IAM posture

set -euo pipefail

PROJECT_ID="${1:-$(gcloud config get-value project)}"
DATE=$(date +%Y-%m-%d)
REPORT="/tmp/identity-audit-${DATE}.txt"

{
echo "╔════════════════════════════════════════════════════════╗"
echo "║ IDENTITY ARCHITECTURE COMPLIANCE REPORT               ║"
echo "║ Project: $PROJECT_ID | Date: $DATE                    ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

echo "═══ 1. IAM MEMBER INVENTORY ═══"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="table(bindings.role, bindings.members)" 2>/dev/null
echo ""

echo "═══ 2. SERVICE ACCOUNT INVENTORY ═══"
gcloud iam service-accounts list --project=$PROJECT_ID \
  --format="table(email, displayName, disabled)" 2>/dev/null
echo ""

echo "═══ 3. SA KEY STATUS (should be 0 user keys) ═══"
KEY_TOTAL=0
for SA in $(gcloud iam service-accounts list --project=$PROJECT_ID \
  --format="value(email)" 2>/dev/null); do
  KEYS=$(gcloud iam service-accounts keys list \
    --iam-account=$SA --managed-by=user \
    --format="value(name)" 2>/dev/null | wc -l)
  KEY_TOTAL=$((KEY_TOTAL + KEYS))
  [ "$KEYS" -gt 0 ] && echo "  WARNING: $SA has $KEYS user key(s)"
done
echo "  Total user-managed keys: $KEY_TOTAL"
echo ""

echo "═══ 4. BROAD ROLES (Owner/Editor) ═══"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.role:(roles/editor OR roles/owner)" \
  --format="table(bindings.role, bindings.members)" 2>/dev/null || echo "  None found"
echo ""

echo "═══ 5. LOG RETENTION ═══"
gcloud logging buckets list --project=$PROJECT_ID \
  --format="table(name, retentionDays)" 2>/dev/null
echo ""

echo "═══ 6. SCORING ═══"
SCORE=100
[ "$KEY_TOTAL" -gt 0 ] && SCORE=$((SCORE - 20)) && echo "  -20: User-managed SA keys exist"
BROAD=$(gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.role:(roles/editor OR roles/owner)" \
  --format="value(bindings.members)" 2>/dev/null | wc -l)
[ "$BROAD" -gt 0 ] && SCORE=$((SCORE - 10 * BROAD)) && echo "  -$((10*BROAD)): Broad roles in use"
echo ""
echo "  COMPLIANCE SCORE: ${SCORE}/100"

echo ""
echo "═══ END OF REPORT ═══"
} | tee "$REPORT"

echo ""
echo "Report saved: $REPORT"
SCRIPT

chmod +x /tmp/identity-architecture/compliance-audit.sh
echo "✓ Compliance audit script created"
echo ""

# Run it
echo "--- Running compliance audit ---"
bash /tmp/identity-architecture/compliance-audit.sh $PROJECT_ID 2>/dev/null || \
  echo "Script requires gcloud auth"
```

### Lab 2.4 — Migration Runbook

```bash
echo "=== MIGRATION RUNBOOK ==="
echo ""

cat << 'RUNBOOK'
RHDS → GCP IDENTITY MIGRATION RUNBOOK
══════════════════════════════════════

PRE-MIGRATION CHECKLIST:
□ RHDS user/group export (ldapsearch → LDIF)
□ Cloud Identity domain verified
□ GCDS installed on server with LDAP access
□ Keycloak deployed with RHDS user federation
□ GCP org structure designed (folders, projects)
□ Terraform IAM modules written and tested

PHASE 1 — COEXISTENCE (Week 1-4):
□ Week 1: Configure GCDS sync (dry-run first)
    $ gcds-sync --dry-run --config=/etc/gcds/config.xml
    Verify: user count matches, groups correct
□ Week 2: Enable GCDS live sync (4-hour schedule)
    Verify: Cloud Identity shows all users
□ Week 3: Configure SAML SSO (Keycloak → Google)
    Test: login to console.cloud.google.com via SSO
□ Week 4: Deploy first workload with Terraform IAM
    Verify: SAs have specific roles, no keys

PHASE 2 — HYBRID (Week 5-12):
□ Week 5-6: Deploy IAP for internal web apps
□ Week 7-8: Implement Workforce IdF for contractors
□ Week 9-10: Automate JML via Cloud Functions
□ Week 11-12: Deploy compliance monitoring (BQ + alerts)

PHASE 3 — CLOUD-PRIMARY (Week 13-20):
□ Week 13-14: Switch JML target from RHDS to Cloud Identity API
□ Week 15-16: Move remaining apps off RHDS
□ Week 17-18: Run RHDS in read-only mode (monitoring period)
□ Week 19-20: Decommission RHDS (archive LDIF backup)

ROLLBACK PLAN:
At any phase, if issues arise:
1. Re-enable RHDS as primary auth
2. GCDS continues to sync (no data loss)
3. Keycloak can switch back to RHDS auth
4. IAP can be bypassed temporarily
RUNBOOK
```

### 🧹 Cleanup

```bash
# Clean up Terraform files
rm -rf /tmp/identity-architecture
echo "✓ Temporary files cleaned up"
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **Full comparison matrix:** RHDS maps to Cloud Identity across all categories — directory, access, auth, HA, audit, automation
- **3-phase migration:** Coexistence → Hybrid → Cloud-primary; RHDS stays as SoT until Phase 3
- **ADRs:** Document every major decision with context, decision, rationale, consequences
- **Terraform IAM module:** team bindings (from groups) + workload SAs (1 per app) + no keys
- **Compliance script:** automated evidence collection — run monthly, score the posture
- **Rollback plan:** every phase must be reversible. RHDS remains available until final decommission

### Essential Commands
```bash
# Terraform IAM
terraform plan -var="project_id=PROJECT_ID"
terraform apply -var="project_id=PROJECT_ID"

# Compliance check
gcloud projects get-iam-policy PROJECT  # Full IAM
gcloud iam service-accounts list         # SA inventory
gcloud iam service-accounts keys list --iam-account=SA --managed-by=user  # Key check

# GCDS (on the sync server)
gcds-sync --dry-run --config=/etc/gcds/config.xml
gcds-sync --apply --config=/etc/gcds/config.xml
```

---

## Part 4 — Quiz (15 min)

**Q1.** You're presenting the migration plan to your director. Summarise the 3-phase approach in 3 sentences.

<details><summary>Answer</summary>

"**Phase 1 (months 1-3):** We synchronise our existing RHDS directory to Google Cloud Identity using GCDS, keeping RHDS as the source of truth while enabling cloud access via SAML SSO — no disruption to existing workflows.

**Phase 2 (months 4-8):** We add BeyondCorp (IAP) for secure web app access without VPN, automate identity lifecycle with Cloud Functions, and deploy compliance monitoring — RHDS still handles authentication.

**Phase 3 (months 9-12):** Cloud Identity becomes the primary directory, RHDS is reduced to legacy support only, and we gain full Terraform automation, compliance dashboards, and zero-trust access — at every phase, we can roll back to RHDS if needed."

</details>

**Q2.** The Terraform plan shows 17 resources. An engineer asks: "Why not just use the Console?" What's your response?

<details><summary>Answer</summary>

1. **Reproducibility:** Terraform creates identical IAM in dev, staging, and prod. Console clicks can't be replayed.
2. **Auditability:** `main.tf` in git shows exactly what was granted, when, by whom (git blame). Console changes? Hope you remember.
3. **Review:** IAM changes go through pull request review before apply. Console? One click, no review.
4. **Drift detection:** `terraform plan` shows if someone changed IAM outside Terraform. Console? No drift detection.
5. **Speed:** 17 resources in one `terraform apply`. Console? 17 separate click-workflows.
6. **Documentation:** The Terraform code IS the documentation. No separate wiki page to maintain.

"Console is for exploration and troubleshooting. Terraform is for production IAM management."

</details>

**Q3.** During Phase 2, Keycloak goes down. What happens and what's the recovery plan?

<details><summary>Answer</summary>

**Impact:**
- Users cannot authenticate via SAML SSO → no GCP Console/Workspace login
- Users already authenticated (active sessions) continue to work
- Service accounts are unaffected (don't use SAML)
- IAP-protected apps are inaccessible (IAP needs identity)
- Direct gcloud CLI with stored tokens may still work

**Recovery plan:**
1. **Immediate (< 15 min):** Failover to Keycloak replica (you deployed HA, right?)
2. **If no HA:** Restart Keycloak service. Check RHDS connectivity (Keycloak's backend).
3. **If RHDS is also down:** This is a P1 incident. Restore RHDS from backup/replica.
4. **Temporary bypass:** Google Admin can temporarily disable SSO enforcement → users can auth with Cloud Identity password (if set).
5. **Post-incident:** Deploy Keycloak in HA mode (2+ instances behind load balancer). Add monitoring on Keycloak health endpoint.

**Prevention:** Keycloak must be as HA as RHDS — same replication and failover discipline.

</details>

**Q4.** Write the ADR for choosing `google_project_iam_member` (additive) over `google_project_iam_binding` (authoritative) in the Terraform module.

<details><summary>Answer</summary>

```
ADR-005: IAM TERRAFORM RESOURCE TYPE
═════════════════════════════════════
Status: ACCEPTED
Date: [today]

Context:
Terraform offers three IAM resources:
- google_project_iam_policy (fully authoritative — replaces ALL IAM)
- google_project_iam_binding (authoritative per role — replaces all members for a role)
- google_project_iam_member (additive — adds one member to one role)

Decision:
Use google_project_iam_member for all IAM bindings.

Rationale:
1. SAFETY: iam_member only adds; it cannot accidentally remove existing
   bindings created by other teams, Console, or other Terraform modules.
2. COMPOSABILITY: Multiple Terraform modules can manage the same project
   without conflicting on the same role.
3. RHDS ANALOGY: Adding an ACI never removed other ACIs. iam_member
   follows the same principle.
4. RISK: iam_binding would remove any member not in Terraform for that
   role — dangerous if team members were added via Console.

Consequences:
- Cannot guarantee "only these members have this role" (use iam_binding
  for that in security-critical cases, with explicit documentation).
- Removing access requires explicit removal of the iam_member resource.
- Acceptable trade-off: safety over strictness.
```

</details>
