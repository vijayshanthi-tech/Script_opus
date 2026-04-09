# Day 93 — Directory Sync: GCDS, Federation, and SAML/OIDC

> **Week 16 — Identity Architecture** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 The Synchronisation Problem

```
  WHY DIRECTORY SYNC?
  ══════════════════

  WITHOUT SYNC:                      WITH SYNC:
  ┌──────────────┐                   ┌──────────────┐
  │ On-Prem LDAP │  Manual copy      │ On-Prem LDAP │
  │ alice: eng   │ ──────────────▶   │ alice: eng   │
  │ bob: finance │  Error-prone      │ bob: finance │
  │ carol: left  │  Stale data       │ carol: left  │
  └──────────────┘                   └──────┬───────┘
                   ┌──────────────┐         │ GCDS
                   │ Cloud Identy │         │ (automated)
                   │ alice: eng?? │         │
                   │ bob: ????    │         ▼
                   │ (outdated)   │  ┌──────────────┐
                   └──────────────┘  │ Cloud Identity│
                                     │ alice: eng   │
                                     │ bob: finance │
                                     │ carol: sus'd │
                                     └──────────────┘
```

### 1.2 Google Cloud Directory Sync (GCDS)

```
  GCDS ARCHITECTURE
  ═════════════════

  ┌────────────────────────────────────────────────────┐
  │                 ON-PREMISES                         │
  │                                                    │
  │  ┌──────────────┐     ┌──────────────────────────┐│
  │  │ RHDS / AD    │     │ GCDS Server              ││
  │  │              │────▶│ (runs on Linux/Windows)   ││
  │  │ LDAP:389     │     │                          ││
  │  │ LDAPS:636    │     │ • Reads LDAP entries     ││
  │  │              │     │ • Maps attributes        ││
  │  └──────────────┘     │ • Pushes to Google APIs  ││
  │                       └────────────┬─────────────┘│
  └────────────────────────────────────│──────────────┘
                                       │ HTTPS (443)
                                       │ Outbound only
                                       ▼
                              ┌──────────────────┐
                              │ Google Cloud      │
                              │ Identity / Wksp   │
                              │                  │
                              │ Users, Groups,   │
                              │ Org Units        │
                              └──────────────────┘

  KEY POINT: GCDS is ONE-WAY (LDAP → Google).
  Changes in Google do NOT sync back to LDAP.
```

### 1.3 GCDS Configuration Mapping

| GCDS Config | LDAP Equivalent | Purpose |
|-------------|----------------|---------|
| User sync rule | `ldapsearch -b "ou=People" "(objectclass=inetOrgPerson)"` | Which users to sync |
| Group sync rule | `ldapsearch -b "ou=Groups" "(objectclass=groupOfNames)"` | Which groups to sync |
| Attribute mapping: `mail → primaryEmail` | LDAP `mail` attribute | Map directory fields |
| Attribute mapping: `uid → username` | LDAP `uid` attribute | User identifier |
| Exclusion rule | `(&(ou=People)(!(nsAccountLock=true)))` | Skip disabled accounts |
| Search base DN | `-b "dc=example,dc=com"` | Where to search |
| LDAP bind DN | `-D "cn=gcds-reader,ou=Services,dc=..."` | How to authenticate |

### 1.4 Federation: SAML and OIDC

```
  AUTHENTICATION FEDERATION FLOW
  ═══════════════════════════════

  SAML 2.0 (Service Provider initiated):
  ┌────────┐    ┌──────────────┐    ┌──────────────────┐
  │ User   │───▶│ Google Cloud  │───▶│ On-Prem IdP      │
  │ Browser│    │ (SP)          │    │ (SAML provider)  │
  │        │    │ "Who are you?"│    │ ADFS / Keycloak  │
  │        │◀───│               │◀───│ "This is Alice"  │
  │        │    │ "OK, welcome" │    │ + SAML assertion │
  └────────┘    └──────────────┘    └──────────────────┘

  OIDC (OAuth 2.0 + identity):
  ┌────────┐    ┌──────────────┐    ┌──────────────────┐
  │ App    │───▶│ OIDC Provider│───▶│ Token Endpoint   │
  │        │    │ (authorize)  │    │ (exchange code   │
  │        │◀───│              │◀───│  for ID token)   │
  │        │    │ ID token     │    │                  │
  │        │    │ (JWT)        │    │                  │
  └────────┘    └──────────────┘    └──────────────────┘

  WORKFORCE IDENTITY FEDERATION (no sync needed!):
  ┌────────┐    ┌──────────────┐    ┌──────────────────┐
  │ User   │───▶│ GCP Console  │───▶│ External IdP     │
  │        │    │ / CLI        │    │ (Okta, Azure AD, │
  │        │◀───│              │◀───│  RHDS+Keycloak)  │
  │        │    │ Temporary    │    │                  │
  │        │    │ GCP token    │    │                  │
  └────────┘    └──────────────┘    └──────────────────┘
  
  No Google account needed! External identity → GCP access.
```

### 1.5 SAML vs OIDC vs GCDS

```
  CHOOSING THE RIGHT APPROACH
  ═══════════════════════════

  ┌──────────┬──────────────────┬──────────────┬───────────────┐
  │          │ GCDS             │ SAML SSO     │ Workforce IdF │
  ├──────────┼──────────────────┼──────────────┼───────────────┤
  │ What     │ Sync users/groups│ SSO to Google│ Direct GCP    │
  │          │ to Cloud Identity│ apps         │ access        │
  ├──────────┼──────────────────┼──────────────┼───────────────┤
  │ Accounts │ Creates Google   │ Uses synced  │ NO Google     │
  │          │ accounts         │ accounts     │ account needed│
  ├──────────┼──────────────────┼──────────────┼───────────────┤
  │ Auth     │ Password in      │ On-prem IdP  │ External IdP  │
  │          │ Cloud Identity   │ (SAML assert)│ (OIDC/SAML)   │
  ├──────────┼──────────────────┼──────────────┼───────────────┤
  │ Use case │ Full migration   │ Hybrid (both │ Cloud-only    │
  │          │ to Google        │ on-prem+cloud│ access        │
  ├──────────┼──────────────────┼──────────────┼───────────────┤
  │ LDAP     │ Reads from LDAP  │ IdP reads    │ IdP reads     │
  │ relation │ one-way sync     │ LDAP for auth│ LDAP for auth │
  └──────────┴──────────────────┴──────────────┴───────────────┘
```

> **RHDS parallel:** RHDS itself can be the identity source for all three approaches. GCDS reads from RHDS LDAP. For SAML, you'd put Keycloak in front of RHDS. For Workforce Identity Federation, RHDS backs the external IdP. Your RHDS experience makes you the integration point expert.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
```

### Lab 2.1 — Understand GCDS Configuration

```bash
echo "=== GCDS CONFIGURATION WALKTHROUGH ==="
echo ""
echo "GCDS is installed on-prem (or a VM with LDAP access)."
echo "We'll walk through the configuration concepts."
echo ""

cat << 'CONFIG'
╔══════════════════════════════════════════════════════════════╗
║  GCDS CONFIG FILE (gcds-config.xml) — KEY SECTIONS          ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  1. LDAP CONNECTION                                          ║
║     Host: ldap.internal.example.com                          ║
║     Port: 636 (LDAPS — always use TLS!)                      ║
║     Bind DN: cn=gcds-reader,ou=Services,dc=example,dc=com   ║
║     Base DN: dc=example,dc=com                               ║
║                                                              ║
║  2. USER SYNC RULES                                          ║
║     Search: (objectclass=inetOrgPerson)                      ║
║     Exclude: (nsAccountLock=true)                            ║
║     Mapping:                                                 ║
║       mail → primaryEmail                                    ║
║       givenName → name.givenName                             ║
║       sn → name.familyName                                   ║
║       uid → externalIds[0].value                             ║
║                                                              ║
║  3. GROUP SYNC RULES                                         ║
║     Search: (objectclass=groupOfNames)                       ║
║     Mapping:                                                 ║
║       cn → groupEmail (cn@example.com)                       ║
║       member → member emails                                 ║
║                                                              ║
║  4. OU SYNC RULES                                            ║
║     Map LDAP OUs → Google Org Units                          ║
║     ou=Engineering → /Engineering                            ║
║     ou=Finance → /Finance                                    ║
║                                                              ║
║  5. SYNC BEHAVIOUR                                           ║
║     Delete policy: SUSPEND (don't delete!)                   ║
║     Conflict: Google account wins (manual override)          ║
║     Schedule: Every 4 hours via cron                         ║
╚══════════════════════════════════════════════════════════════╝
CONFIG
```

### Lab 2.2 — Simulate What GCDS Reads from LDAP

```bash
echo "=== SIMULATING GCDS LDAP QUERIES ==="
echo ""
echo "These are the LDAP queries GCDS would run against your RHDS:"
echo ""

echo "--- Query 1: Find all users ---"
echo 'ldapsearch -H ldaps://ldap.internal:636 \'
echo '  -D "cn=gcds-reader,ou=Services,dc=example,dc=com" \'
echo '  -W -b "ou=People,dc=example,dc=com" \'
echo '  "(&(objectclass=inetOrgPerson)(!(nsAccountLock=true)))" \'
echo '  mail uid givenName sn'
echo ""

echo "--- Query 2: Find all groups ---"
echo 'ldapsearch -H ldaps://ldap.internal:636 \'
echo '  -D "cn=gcds-reader,ou=Services,dc=example,dc=com" \'
echo '  -W -b "ou=Groups,dc=example,dc=com" \'
echo '  "(objectclass=groupOfNames)" \'
echo '  cn member description'
echo ""

echo "--- Expected Output Format ---"
cat << 'LDIF'
# User entry (what GCDS reads)
dn: uid=alice,ou=People,dc=example,dc=com
mail: alice@example.com
uid: alice
givenName: Alice
sn: Thompson

# Group entry (what GCDS reads)
dn: cn=sre-team,ou=Groups,dc=example,dc=com
cn: sre-team
member: uid=alice,ou=People,dc=example,dc=com
member: uid=bob,ou=People,dc=example,dc=com
description: Site Reliability Engineering team

# GCDS transforms this to:
# User: alice@example.com → Cloud Identity user
# Group: sre-team@example.com → Google Group with alice, bob as members
LDIF
```

### Lab 2.3 — Workforce Identity Federation Setup

```bash
echo "=== WORKFORCE IDENTITY FEDERATION ==="
echo ""
echo "This allows external identities to access GCP without Google accounts."
echo ""

# Create a workforce identity pool (requires org access)
echo "--- Step 1: Create Workforce Pool ---"
echo "Command (requires org admin):"
echo 'gcloud iam workforce-pools create rhds-pool \'
echo '  --organization=ORG_NUMBER \'
echo '  --location=global \'
echo '  --display-name="RHDS Identity Pool" \'
echo '  --description="Pool for RHDS-backed identities"'
echo ""

echo "--- Step 2: Create OIDC Provider in Pool ---"
echo "Command (connects to your IdP — e.g., Keycloak fronting RHDS):"
echo 'gcloud iam workforce-pools providers create-oidc keycloak-rhds \'
echo '  --workforce-pool=rhds-pool \'
echo '  --location=global \'
echo '  --issuer-uri="https://keycloak.internal/realms/rhds" \'
echo '  --client-id="gcp-workforce" \'
echo '  --attribute-mapping="google.subject=assertion.sub" \'
echo '  --attribute-condition="assertion.email_verified==true"'
echo ""

echo "--- Step 3: Grant IAM to Workforce Identity ---"
echo "Command:"
echo 'gcloud projects add-iam-binding PROJECT_ID \'
echo '  --role="roles/viewer" \'
echo '  --member="principalSet://iam.googleapis.com/locations/global/workforcePools/rhds-pool/group/sre-team"'
echo ""

echo "--- Architecture ---"
echo "User → Keycloak (OIDC) → RHDS (LDAP bind) → Token → GCP Access"
echo "No Google account needed! RHDS is the source of truth."
```

### Lab 2.4 — SAML SSO Configuration Walkthrough

```bash
echo "=== SAML SSO CONFIGURATION FOR GOOGLE CLOUD ==="
echo ""

cat << 'SAML'
SAML SSO SETUP STEPS
════════════════════

1. SET UP IdP (e.g., Keycloak with RHDS backend):
   - Create SAML client for Google
   - Entity ID: google.com
   - ACS URL: https://www.google.com/a/example.com/acs
   - Sign assertions with X.509 cert

2. CONFIGURE GOOGLE SSO (Admin Console):
   Admin Console → Security → Authentication → SSO with third-party IdP
   - Sign-in page URL: https://keycloak.internal/realms/rhds/protocol/saml
   - Sign-out page URL: https://keycloak.internal/realms/rhds/protocol/saml/logout
   - Upload IdP certificate (X.509)
   - Domain: example.com

3. ATTRIBUTE MAPPING:
   IdP Attribute     → Google Attribute
   ═══════════════     ════════════════
   uid               → nameID (required)
   mail              → email
   givenName         → firstName
   sn                → lastName

4. TEST FLOW:
   User visits console.cloud.google.com
   → Redirected to Keycloak
   → Keycloak authenticates against RHDS (LDAP bind)
   → SAML assertion sent to Google
   → User logs into GCP Console

5. RHDS IS STILL THE AUTH SOURCE:
   Keycloak does: ldapsearch + ldapbind against RHDS
   Password is verified by RHDS, not Google.
SAML
```

### Lab 2.5 — Verify Cloud Identity Configuration

```bash
echo "=== CLOUD IDENTITY VERIFICATION ==="
echo ""

# Check current auth configuration
echo "--- Your current authentication ---"
gcloud auth list --format="table(account, status)" 2>/dev/null

echo ""
echo "--- Organisation domain ---"
gcloud organizations list \
  --format="table(displayName, name, owner.directoryCustomerId)" 2>/dev/null || \
  echo "No org access"

echo ""
echo "--- Project IAM (shows member types) ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="value(bindings.members)" 2>/dev/null | \
  while read -r MEMBER; do
    TYPE=$(echo $MEMBER | cut -d: -f1)
    ID=$(echo $MEMBER | cut -d: -f2)
    echo "  Type: $TYPE | Identity: $ID"
  done | sort -u

echo ""
echo "Member types you might see:"
echo "  user:           → Cloud Identity / Google account"
echo "  serviceAccount: → GCP service account"
echo "  group:          → Google Group"
echo "  domain:         → All users in domain"
echo "  principal:      → Workforce/Workload identity federation"
```

### 🧹 Cleanup

```bash
echo "No resources were created in this lab (configuration walkthrough)."
echo "Cleanup not needed."
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **GCDS** syncs users/groups from LDAP to Cloud Identity (one-way, LDAP→Google)
- **GCDS reads only** — never writes back to LDAP; safe for production directories
- **SAML SSO** keeps authentication on-prem (Keycloak + RHDS); Google trusts the SAML assertion
- **Workforce Identity Federation** grants GCP access to external identities without Google accounts
- **OIDC** is the modern alternative to SAML; uses JWT tokens instead of XML assertions
- **GCDS bind DN** needs read-only access to `ou=People` and `ou=Groups` — apply least privilege
- **Sync frequency:** typically every 4-6 hours for GCDS; federation is real-time
- **Delete policy:** always set to SUSPEND, never DELETE in GCDS

### Essential Commands
```bash
# Workforce Identity Pool
gcloud iam workforce-pools create POOL --organization=ORG --location=global
gcloud iam workforce-pools providers create-oidc PROVIDER \
  --workforce-pool=POOL --issuer-uri=URI --client-id=ID

# Grant access to federated identity
gcloud projects add-iam-binding PROJECT \
  --member="principalSet://iam.googleapis.com/.../group/NAME" --role=ROLE

# Check auth
gcloud auth list
gcloud organizations list
```

---

## Part 4 — Quiz (15 min)

**Q1.** Your RHDS directory has 5,000 users across 3 OUs. Design a GCDS sync strategy.

<details><summary>Answer</summary>

1. **GCDS Service Account:** Create `cn=gcds-reader,ou=Services,dc=example,dc=com` with read-only access (ACI allowing only `read,search,compare` on `ou=People` and `ou=Groups`)
2. **User sync rules:**
   - Base DN: `dc=example,dc=com`
   - Filter: `(&(objectclass=inetOrgPerson)(!(nsAccountLock=true)))`
   - Map: `mail→primaryEmail`, `uid→externalId`, `givenName+sn→name`
3. **Group sync:** `(objectclass=groupOfNames)` → Google Groups, map `cn` to group email
4. **OU mapping:** Map each LDAP OU to a Google Org Unit for delegation
5. **Schedule:** Every 4 hours via cron (`0 */4 * * * /usr/local/bin/gcds-sync.sh`)
6. **Delete policy:** SUSPEND (never delete — allows recovery)
7. **Test:** Run in simulation mode first (`--dry-run`), review changes, then go live

</details>

**Q2.** Why would you choose Workforce Identity Federation over GCDS + SAML SSO?

<details><summary>Answer</summary>

**Use Workforce Identity Federation when:**
1. You don't want to create Google accounts (no Cloud Identity licenses needed)
2. Users only need GCP access, not Google Workspace (Gmail, Drive, etc.)
3. You want real-time authentication (no sync delay)
4. You have a strong existing IdP (Okta, Azure AD, Keycloak+RHDS)
5. You want to avoid managing two directories

**Use GCDS + SAML when:**
1. Users need Google Workspace apps (Gmail, Drive, Calendar)
2. You want Google Groups for collaboration
3. You need to manage devices via Google Endpoint Management
4. You're fully migrating to Google ecosystem

**Key difference:** Federation = no Google accounts. GCDS = creates Google accounts.

</details>

**Q3.** The GCDS sync fails with "LDAP connection error." How do you troubleshoot?

<details><summary>Answer</summary>

1. **Network:** Can the GCDS server reach LDAP? `telnet ldap.internal 636` or `openssl s_client -connect ldap.internal:636`
2. **TLS/Certificate:** Is the LDAPS cert trusted? Check `GCDS_HOME/jre/lib/security/cacerts`. Import with `keytool -importcert`
3. **Bind credentials:** Test manually: `ldapsearch -H ldaps://ldap.internal:636 -D "cn=gcds-reader,..." -W -b "dc=..." "(uid=test)"`
4. **Account lock:** Is the GCDS bind DN locked? Check `nsAccountLock` attribute
5. **Password expiry:** Has the bind password expired? Check `passwordExpirationTime`
6. **Firewall:** On-prem firewall blocking outbound 443 to Google APIs? GCDS needs `googleapis.com`
7. **GCDS logs:** Check `~/gcds/sync.log` for detailed error messages

As an RHDS admin, you already know these LDAP troubleshooting steps. The GCDS layer is just another LDAP client.

</details>

**Q4.** Map the RHDS replication architecture to GCDS sync architecture.

<details><summary>Answer</summary>

| RHDS Replication | GCDS Sync |
|-----------------|-----------|
| Supplier (master) | On-prem RHDS server |
| Consumer (replica) | Cloud Identity (Google) |
| Replication agreement | GCDS config file (XML) |
| `nsDS5ReplicaBindDN` | GCDS bind DN (LDAP credentials) |
| `nsDS5ReplicaPort: 636` | GCDS LDAP connection (port 636) |
| Changelog (`cn=changelog`) | GCDS reads full state each sync |
| Push-based (immediate) | Pull-based (scheduled, 4-6 hours) |
| Bi-directional (multi-master) | One-way only (LDAP→Google) |
| Attribute-level replication | User/group-level sync |
| Fractional replication | Attribute mapping (selective) |

Key difference: RHDS replication is real-time push. GCDS is scheduled pull. For real-time, use Workforce Identity Federation instead.

</details>
