# Day 91 — LDAP to IAM: Mapping Directory Concepts to Cloud

> **Week 16 — Identity Architecture** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 The Conceptual Bridge

```
  RHDS LDAP → GCP IAM: CONCEPT MAPPING
  ═════════════════════════════════════

  RHDS DIRECTORY TREE              GCP RESOURCE HIERARCHY
  ══════════════════               ═════════════════════

  dc=example,dc=com               Organisation (example.com)
        │                                  │
        ├── ou=People                      ├── Folder: Production
        │   ├── uid=alice                  │   ├── Project: prod-web
        │   └── uid=bob                    │   └── Project: prod-api
        │                                  │
        ├── ou=Groups                      ├── Folder: Development
        │   ├── cn=admins                  │   ├── Project: dev-web
        │   └── cn=developers              │   └── Project: dev-api
        │                                  │
        └── ou=ServiceAccounts             └── Folder: Shared-Services
            ├── uid=app-ldap                   ├── Project: shared-net
            └── uid=repl-agent                 └── Project: shared-logs

  RHDS ACI                         GCP IAM Binding
  ════════                         ════════════════
  target: ou=People                resource: projects/prod-web
  allow: read,search               role: roles/viewer
  subject: cn=developers           member: group:devs@example.com
```

### 1.2 Detailed Concept Mapping

| RHDS / LDAP Concept | GCP Equivalent | Notes |
|---------------------|---------------|-------|
| `dc=example,dc=com` (root) | Organisation | Top of hierarchy |
| `ou=Engineering` (OU) | Folder | Organise projects by team/env |
| LDAP entry (`uid=alice`) | Google account (`alice@example.com`) | Identity |
| `cn=admins` (groupOfNames) | Google Group (`admins@example.com`) | Group membership |
| `memberOf` attribute | IAM binding on group | How access is granted |
| ACI (Access Control Instruction) | IAM policy (bindings) | Who can do what |
| `(targetattr="*")(allow all)` | `roles/editor` or `roles/owner` | Over-privileged access |
| `(targetattr="cn")(allow read)` | `roles/viewer` | Read-only access |
| `nsDS5ReplicaBindDN` | Service account email | Machine identity |
| `passwordPolicy` objectclass | Cloud Identity password policy | Auth requirements |
| `nsslapd-security: on` (TLS) | Default TLS on all GCP APIs | Encryption in transit |
| Replication agreement | Cross-project IAM / Shared VPC | Resource sharing |
| `nsAccountLock: true` | `gcloud iam service-accounts disable` | Disable identity |
| `nsslapd-auditlog` | Admin Activity audit logs | Change tracking |
| `nsslapd-accesslog` | Data Access audit logs | Read tracking |

### 1.3 Access Control: ACI vs IAM

```
  ACCESS CONTROL COMPARISON
  ═════════════════════════

  RHDS ACI EXAMPLE:
  ┌────────────────────────────────────────────────────────┐
  │ aci: (targetattr="cn || sn || mail || telephoneNumber")│
  │      (version 3.0; acl "Dev team read contacts";      │
  │       allow (read, search, compare)                    │
  │       groupdn="ldap:///cn=developers,ou=Groups,        │
  │                dc=example,dc=com";)                    │
  └────────────────────────────────────────────────────────┘

  MAPS TO GCP IAM BINDING:
  ┌────────────────────────────────────────────────────────┐
  │ resource: projects/contact-db                          │
  │ role: roles/datastore.viewer                           │
  │   (permissions: datastore.entities.get,                │
  │                 datastore.entities.list)                │
  │ member: group:developers@example.com                   │
  └────────────────────────────────────────────────────────┘

  KEY DIFFERENCES:
  ┌──────────────────┬──────────────────────────────────────┐
  │ RHDS ACI         │ GCP IAM                              │
  ├──────────────────┼──────────────────────────────────────┤
  │ Attribute-level  │ API/resource-level                   │
  │ Targets: attrs   │ Targets: API methods                 │
  │ Evaluated at     │ Evaluated at API gateway             │
  │ directory server │                                      │
  │ Deny + Allow     │ Allow only (+ Deny policies)         │
  │ In DIT itself    │ Separate IAM layer                   │
  │ Complex regex    │ Role-based (predefined/custom)       │
  └──────────────────┴──────────────────────────────────────┘
```

### 1.4 Group Membership Models

```
  GROUP MEMBERSHIP COMPARISON
  ═══════════════════════════

  RHDS:
  ┌──────────────────────────────────────────┐
  │ dn: cn=admins,ou=Groups,dc=example,dc=com│
  │ objectClass: groupOfNames                 │
  │ member: uid=alice,ou=People,dc=...        │
  │ member: uid=bob,ou=People,dc=...          │
  └──────────────────────────────────────────┘
  
  GCP Cloud Identity:
  ┌──────────────────────────────────────────┐
  │ Group: admins@example.com                │
  │ Type: Security group                     │
  │ Members:                                 │
  │   alice@example.com (MEMBER)             │
  │   bob@example.com (MEMBER)               │
  │   carol@example.com (MANAGER)            │
  │ IAM: Bound to roles at project/folder    │
  └──────────────────────────────────────────┘

  RHDS nested groups:           GCP nested groups:
  cn=super-admins               super-admins@example.com
   └── member: cn=admins         └── member: admins@example.com
       └── member: uid=alice         └── member: alice@example.com
```

> **Key insight:** In RHDS, ACIs live inside the directory tree alongside data. In GCP, IAM policies are a separate layer above resources. This separation makes GCP IAM easier to audit but harder to do attribute-level control.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Explore the GCP Resource Hierarchy

```bash
echo "=== GCP RESOURCE HIERARCHY (Your LDAP DIT Equivalent) ==="
echo ""

# Show current project
echo "--- Current Project (≈ LDAP subtree) ---"
gcloud config get-value project

# Show project details
gcloud projects describe $PROJECT_ID \
  --format="table(projectId, name, projectNumber, parent.type, parent.id)" 2>/dev/null

# Show folders (if you have org access)
echo ""
echo "--- Folders (≈ OUs in LDAP) ---"
gcloud resource-manager folders list \
  --organization=$(gcloud organizations list --format="value(name)" 2>/dev/null | head -1) \
  --format="table(name.basename(), displayName, parent)" 2>/dev/null || \
  echo "Requires org-level access (similar to needing 'cn=Directory Manager' for full tree view)"

# Show organisation
echo ""
echo "--- Organisation (≈ dc=example,dc=com) ---"
gcloud organizations list \
  --format="table(displayName, name, owner.directoryCustomerId)" 2>/dev/null || \
  echo "No org access (like accessing root DSE without bind)"
```

### Lab 2.2 — Map RHDS Groups to GCP IAM

```bash
echo "=== MAPPING RHDS GROUPS TO IAM ==="
echo ""

# In RHDS you'd run:
# ldapsearch -b "ou=Groups,dc=example,dc=com" "(objectclass=groupOfNames)" cn member

# GCP equivalent: List groups (requires Cloud Identity / Workspace admin)
echo "--- Google Groups (≈ groupOfNames entries) ---"
gcloud identity groups list \
  --organization=$(gcloud organizations list --format="value(name)" 2>/dev/null | head -1) \
  --format="table(groupKey.id, displayName)" 2>/dev/null || \
  echo "Requires Cloud Identity admin (like cn=Directory Manager)"

echo ""
echo "--- IAM Bindings (≈ ACIs granting access to groups) ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:group:" \
  --format="table(bindings.role, bindings.members)" 2>/dev/null || \
  echo "No group bindings found"

echo ""
echo "--- All Members (≈ ldapsearch '(uid=*)' uid) ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="value(bindings.members)" 2>/dev/null | sort -u
```

### Lab 2.3 — Compare SA to RHDS Service Identities

```bash
echo "=== SERVICE ACCOUNTS (≈ RHDS Service Identities) ==="
echo ""

# In RHDS: uid=repl-agent,ou=ServiceAccounts,dc=example,dc=com
# In GCP: sa-name@project.iam.gserviceaccount.com

echo "--- Service Accounts (≈ uid entries in ou=ServiceAccounts) ---"
gcloud iam service-accounts list --project=$PROJECT_ID \
  --format="table(email:label=SA_EMAIL_≈_DN, displayName:label=DESCRIPTION, disabled:label=nsAccountLock)"

echo ""
echo "RHDS Service Identity → GCP SA Comparison:"
echo "┌─────────────────────────┬──────────────────────────────┐"
echo "│ RHDS Service Identity   │ GCP Service Account          │"
echo "├─────────────────────────┼──────────────────────────────┤"
echo "│ uid=app-ldap            │ app-ldap@project.iam.gsa.com │"
echo "│ userPassword: {SSHA}... │ SA key (JSON) or WIF         │"
echo "│ memberOf: cn=readers    │ IAM binding: roles/viewer    │"
echo "│ nsAccountLock: true     │ --disabled                   │"
echo "│ passwordExpirationTime  │ Key expiry / rotation policy │"
echo "└─────────────────────────┴──────────────────────────────┘"
```

### Lab 2.4 — Translate an ACI to an IAM Binding

```bash
echo "=== ACI → IAM BINDING TRANSLATION ==="
echo ""

echo "SCENARIO: Developers need read access to storage (like LDAP read to ou=Data)"
echo ""

echo "RHDS ACI:"
echo '  aci: (targetattr="*")(version 3.0; acl "Dev Storage Read";'
echo '       allow (read, search, compare)'
echo '       groupdn="ldap:///cn=developers,ou=Groups,dc=example,dc=com";)'
echo ""

echo "EQUIVALENT GCP IAM COMMAND:"
echo '  gcloud projects add-iam-binding PROJECT_ID \'
echo '    --role="roles/storage.objectViewer" \'
echo '    --member="group:developers@example.com"'
echo ""

# Demonstrate with a real SA (safe, uses SA instead of group)
gcloud iam service-accounts create aci-demo-sa \
  --display-name="ACI Demo SA (≈ uid=aci-demo)" 2>/dev/null

export DEMO_SA=aci-demo-sa@${PROJECT_ID}.iam.gserviceaccount.com

echo "--- Creating IAM binding (≈ ACI allowing viewer access) ---"
gcloud projects add-iam-binding $PROJECT_ID \
  --role="roles/viewer" \
  --member="serviceAccount:$DEMO_SA" \
  --condition=None 2>/dev/null | tail -5

echo ""
echo "--- Verify binding (≈ ldapsearch for ACI) ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$DEMO_SA" \
  --format="table(bindings.role, bindings.members)" 2>/dev/null
```

### Lab 2.5 — Audit Trail Comparison

```bash
echo "=== AUDIT TRAIL (≈ access-log + audit-log) ==="
echo ""

echo "RHDS audit entries:"
echo '  [03/Jun/2024:14:23:15 +0000] MODIFY dn="uid=alice,ou=People,dc=..."'
echo '  [03/Jun/2024:14:23:15 +0000] changetype: modify'
echo '  [03/Jun/2024:14:23:15 +0000] replace: telephoneNumber'
echo ""

echo "GCP audit log equivalent:"
gcloud logging read '
  protoPayload.methodName="SetIamPolicy"
' --limit=3 --freshness=7d --project=$PROJECT_ID \
  --format="table(
    timestamp:label=TIMESTAMP,
    protoPayload.authenticationInfo.principalEmail:label=WHO_≈_BIND_DN,
    protoPayload.methodName:label=METHOD_≈_OPERATION,
    protoPayload.resourceName:label=RESOURCE_≈_TARGET_DN
  )" 2>/dev/null || echo "No recent IAM changes in logs"

echo ""
echo "RHDS Log → GCP Log Mapping:"
echo "┌──────────────────────┬──────────────────────────────────────┐"
echo "│ RHDS Log Field       │ GCP Audit Log Field                  │"
echo "├──────────────────────┼──────────────────────────────────────┤"
echo "│ timestamp            │ timestamp                            │"
echo "│ BIND dn (who)        │ principalEmail                       │"
echo "│ MODIFY/ADD/DELETE    │ methodName                           │"
echo "│ target dn            │ resourceName                         │"
echo "│ changetype: modify   │ serviceData.policyDelta              │"
echo "│ conn= op=            │ requestMetadata.requestId            │"
echo "└──────────────────────┴──────────────────────────────────────┘"
```

### 🧹 Cleanup

```bash
# Remove demo SA and its IAM binding
gcloud projects remove-iam-binding $PROJECT_ID \
  --role="roles/viewer" \
  --member="serviceAccount:$DEMO_SA" 2>/dev/null

gcloud iam service-accounts delete $DEMO_SA --quiet 2>/dev/null

echo "Cleanup complete."
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **dc=example,dc=com** → Organisation; **ou** → Folder; **uid** → Google account; **cn (group)** → Google Group
- **ACI** maps to IAM binding: target → resource, allow → role, subject → member
- **RHDS ACIs** are attribute-level; **GCP IAM** is API/resource-level
- **Service accounts** are the GCP equivalent of RHDS service identities (`uid=app-ldap`)
- **SA keys** are the GCP equivalent of `userPassword` for service binds
- **nsAccountLock** → `gcloud iam service-accounts disable`
- **access-log / audit-log** → Cloud Audit Logs (Admin Activity + Data Access)
- **Nested groups** work in both: RHDS `memberOf` ≈ GCP nested Google Groups

### Essential Commands
```bash
# View hierarchy (≈ ldapsearch the DIT)
gcloud organizations list
gcloud resource-manager folders list --organization=ORG_ID
gcloud projects list

# View IAM (≈ dump ACIs)
gcloud projects get-iam-policy PROJECT_ID

# Manage SAs (≈ manage service identities)
gcloud iam service-accounts list
gcloud iam service-accounts create NAME --display-name="DESC"
gcloud iam service-accounts disable SA_EMAIL

# Add IAM binding (≈ add ACI)
gcloud projects add-iam-binding PROJECT_ID --role=ROLE --member=MEMBER
```

---

## Part 4 — Quiz (15 min)

**Q1.** Your RHDS directory has `ou=Engineering` and `ou=Finance` with different ACIs. How do you replicate this in GCP?

<details><summary>Answer</summary>

Create **Folders** for each OU:
- Folder: `Engineering` → contains engineering projects
- Folder: `Finance` → contains finance projects

Apply IAM bindings at the folder level:
- `Engineering` folder: `group:engineers@example.com` → `roles/editor`
- `Finance` folder: `group:finance@example.com` → `roles/viewer`

This replicates the RHDS pattern where ACIs on an OU scope are inherited by entries beneath it. GCP IAM inheritance works the same way: bindings on a folder are inherited by all projects in that folder.

</details>

**Q2.** An RHDS ACI grants `(targetattr="userPassword")(allow write)` to `cn=password-admins`. What's the GCP equivalent?

<details><summary>Answer</summary>

There's no direct attribute-level equivalent in GCP IAM. The closest mapping:

- **For Cloud Identity password management:** Grant `roles/admin.directoryUser` to the `password-admins@example.com` group in Google Admin
- **For SA key management:** Grant `roles/iam.serviceAccountKeyAdmin` — allows creating/deleting SA keys (≈ password write)
- **For OS Login:** The OS Login role `roles/compute.osAdminLogin` allows sudo, which includes password changes on VMs

Key difference: RHDS allows attribute-level control (`userPassword` only). GCP roles bundle permissions at the resource/API level. You can't grant "change password only" without other admin permissions. This is a granularity trade-off.

</details>

**Q3.** How do RHDS replication agreements map to GCP cross-project resource sharing?

<details><summary>Answer</summary>

| RHDS Replication | GCP Equivalent |
|-----------------|---------------|
| Replication agreement between servers | Shared VPC (network sharing between projects) |
| `nsDS5ReplicaBindDN` (replication identity) | Service account with cross-project IAM binding |
| `nsDS5ReplicaPort: 636` (TLS) | Default TLS on all GCP internal APIs |
| Multi-master replication | Multi-region global resources |
| Read-only replica (consumer) | Read-only IAM binding (`roles/viewer`) |
| Replication conflict resolution | IAM is centralized (no conflicts) |
| Agreement-level ACI | Cross-project IAM conditions |

The key architecture difference: RHDS replicates data between servers. GCP shares access to centralized resources. There's no data replication needed for IAM because it's a global service.

</details>

**Q4.** You're migrating from RHDS to GCP. What are the three biggest conceptual shifts for the team?

<details><summary>Answer</summary>

1. **From attribute-level to resource-level control:** RHDS ACIs target specific attributes (`cn`, `mail`, `telephoneNumber`). GCP IAM targets API methods (`storage.objects.get`). The team must think in terms of "what API operations" instead of "what data fields."

2. **From server-managed to cloud-managed identity:** No more managing `cn=config`, replication topology, certificate renewal, suffix creation. Cloud Identity handles it. The team focuses on policy, not plumbing.

3. **From deny-first ACIs to allow-only IAM:** RHDS evaluates deny ACIs first, then allow. GCP IAM is allow-only by default (deny policies exist but are separate). The team must think "what do I explicitly allow" instead of "what do I explicitly deny."

</details>
