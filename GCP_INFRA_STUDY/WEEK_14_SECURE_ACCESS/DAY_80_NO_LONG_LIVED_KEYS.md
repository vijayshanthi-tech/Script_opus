# Day 80 — No Long-Lived Keys: SA Key Dangers & Alternatives

> **Week 14 — Secure Access** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 The Problem with SA Keys

```
  LONG-LIVED SA KEY LIFECYCLE
  ═══════════════════════════

  ┌────────────┐    ┌──────────────┐    ┌──────────────────┐
  │ Create key │───▶│ Download     │───▶│ Store somewhere  │
  │ (JSON)     │    │ key.json     │    │ filesystem / env │
  └────────────┘    └──────────────┘    └────────┬─────────┘
                                                  │
                    WHERE KEYS END UP:            │
                    ┌─────────────────────────────▼─────┐
                    │ ❌ Committed to git                 │
                    │ ❌ Stored in plain text config      │
                    │ ❌ Shared via Slack/email            │
                    │ ❌ Copied to dev laptops             │
                    │ ❌ Left in Docker images              │
                    │ ❌ Stored in CI/CD env vars          │
                    │ ❌ Never rotated (default: no expiry)│
                    └───────────────────────────────────┘

  RISK: A leaked key = FULL SA access until key is revoked
  Keys don't expire by default!
```

**Linux analogy:**
| SA Key Risk | Linux Equivalent |
|------------|------------------|
| Key leaked in git | SSH private key committed to repo |
| Key never rotated | Password set once, never changed |
| Key shared across team | Shared root password |
| RHDS: bind DN password in config | Same problem — stored credential |

### 1.2 Key Statistics to Remember

```
  WHY SA KEYS ARE DANGEROUS — BY THE NUMBERS
  ══════════════════════════════════════════

  • SA keys are the #1 source of GCP credential leaks
  • GitHub secret scanning finds thousands of GCP keys monthly
  • Average time from key leak to exploitation: < 24 hours
  • Keys have NO EXPIRY by default
  • Each SA can have up to 10 keys (sprawl risk)
  • No built-in alert when a key is used from unexpected location
```

### 1.3 Four Alternatives to SA Keys

```
  ┌────────────────────────────────────────────────────────────┐
  │               ALTERNATIVES TO SA KEYS                       │
  ├────────────────────────────────────────────────────────────┤
  │                                                             │
  │  1. METADATA SERVER (on-GCP workloads)                      │
  │  ──────────────────────────────────────                     │
  │  VM/Cloud Function/Cloud Run → metadata server → token      │
  │  No credential file needed. Automatic token refresh.        │
  │  ┌──────────┐    ┌──────────────┐    ┌──────────┐         │
  │  │ App code │───▶│ 169.254.169. │───▶│ Token    │         │
  │  │          │    │ 254/metadata │    │ (1hr TTL)│         │
  │  └──────────┘    └──────────────┘    └──────────┘         │
  │                                                             │
  │  2. WORKLOAD IDENTITY FEDERATION (off-GCP workloads)        │
  │  ──────────────────────────────────────────────────         │
  │  AWS/Azure/on-prem → token exchange → GCP access            │
  │  Uses OIDC/SAML tokens from external IdP                    │
  │  ┌──────────┐    ┌──────────────┐    ┌──────────┐         │
  │  │ AWS app  │───▶│ STS token    │───▶│ GCP      │         │
  │  │ (has IAM │    │ exchange     │    │ token    │         │
  │  │  role)   │    │              │    │ (1hr TTL)│         │
  │  └──────────┘    └──────────────┘    └──────────┘         │
  │                                                             │
  │  3. SA IMPERSONATION (user → SA)                            │
  │  ─────────────────────────────────                          │
  │  User authenticates normally → acts as SA → short-lived     │
  │  ┌──────────┐    ┌──────────────┐    ┌──────────┐         │
  │  │ User     │───▶│ Impersonate  │───▶│ SA       │         │
  │  │ (gcloud  │    │ SA (token    │    │ actions  │         │
  │  │  login)  │    │  creator)    │    │ (1hr TTL)│         │
  │  └──────────┘    └──────────────┘    └──────────┘         │
  │                                                             │
  │  4. WORKLOAD IDENTITY (GKE pods)                            │
  │  ──────────────────────────────                             │
  │  K8s SA → mapped to GCP SA → API access                     │
  │  ┌──────────┐    ┌──────────────┐    ┌──────────┐         │
  │  │ K8s Pod  │───▶│ K8s SA       │───▶│ GCP SA   │         │
  │  │          │    │ (annotated)  │    │ (roles)  │         │
  │  └──────────┘    └──────────────┘    └──────────┘         │
  └────────────────────────────────────────────────────────────┘
```

### 1.4 Key Rotation (When Keys Are Unavoidable)

```
  IF YOU MUST USE KEYS (rare cases):
  ══════════════════════════════════

  When:
  - Legacy on-prem app that can't use WIF
  - Third-party SaaS requiring key file upload
  - Air-gapped environment

  Rotation procedure:
  ┌────────────────────────────────────────────┐
  │ 1. Create new key for SA                   │
  │ 2. Deploy new key to application           │
  │ 3. Verify application uses new key         │
  │ 4. Disable old key                         │
  │ 5. Monitor for 24h (any failures?)         │
  │ 6. Delete old key                          │
  │                                            │
  │ Rotation frequency: every 90 days MINIMUM  │
  │                                            │
  │ ⚠ NEVER have more than 2 active keys       │
  │ ⚠ Store keys in Secret Manager, not files  │
  └────────────────────────────────────────────┘
```

### 1.5 Detecting Leaked Keys

```
  LEAK DETECTION METHODS
  ═══════════════════════

  1. GitHub Secret Scanning → auto-alerts on push
  2. GCP Security Command Center → finds exposed keys
  3. Cloud Audit Logs → unusual SA activity
  4. Key usage alerts:
     - SA used from unexpected IP
     - SA used outside normal hours
     - SA accessed resources it normally doesn't
  
  RESPONSE TO LEAKED KEY:
  ┌─────────────────────────────────────┐
  │ 1. IMMEDIATELY disable the key      │
  │ 2. Audit what the key accessed      │
  │ 3. Rotate all keys for that SA      │
  │ 4. Check for unauthorized changes   │
  │ 5. Consider disabling the SA        │
  │ 6. Review how the leak occurred     │
  │ 7. Implement prevention measures    │
  └─────────────────────────────────────┘
```

> **RHDS parallel:** SA keys in GCP are like LDAP bind passwords. In RHDS, you'd store the `nsDS5ReplicaCredentials` in the config. If someone exfiltrates that password, they have replication-level access. The fix is the same: avoid stored passwords (use SASL/GSSAPI), monitor for unauthorized binds, rotate regularly.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Inventory Existing SA Keys

```bash
# List all service accounts
echo "--- All service accounts ---"
gcloud iam service-accounts list --format="table(email, displayName)"

# Check for existing keys on each SA
echo ""
echo "--- SA keys inventory ---"
for SA in $(gcloud iam service-accounts list --format="value(email)"); do
  KEY_COUNT=$(gcloud iam service-accounts keys list \
    --iam-account=$SA \
    --managed-by=user \
    --format="value(name)" 2>/dev/null | wc -l)
  if [ "$KEY_COUNT" -gt 0 ]; then
    echo "⚠ $SA has $KEY_COUNT user-managed key(s)"
    gcloud iam service-accounts keys list \
      --iam-account=$SA \
      --managed-by=user \
      --format="table(name.basename(), validAfterTime, validBeforeTime)"
  fi
done
echo ""
echo "Accounts with 0 user-managed keys are using best practice."
```

### Lab 2.2 — Demonstrate Key Creation and Risks

```bash
# Create a test SA
gcloud iam service-accounts create key-demo-sa \
  --display-name="Key Demo SA"
export KEY_SA=key-demo-sa@${PROJECT_ID}.iam.gserviceaccount.com

# Create a key (to demonstrate — we'll delete it after)
gcloud iam service-accounts keys create /tmp/key-demo.json \
  --iam-account=$KEY_SA

# Inspect the key file
echo "--- Key file contents (sensitive!) ---"
echo "File size: $(wc -c < /tmp/key-demo.json) bytes"
echo "Key type: $(python3 -c "import json; print(json.load(open('/tmp/key-demo.json'))['type'])" 2>/dev/null || echo 'service_account')"
echo "Client email: $(python3 -c "import json; print(json.load(open('/tmp/key-demo.json'))['client_email'])" 2>/dev/null || echo "$KEY_SA")"
echo ""
echo "⚠ This JSON file is ALL that's needed to authenticate as this SA"
echo "⚠ Anyone with this file has the SA's permissions"

# List keys for this SA
echo ""
echo "--- Keys for $KEY_SA ---"
gcloud iam service-accounts keys list \
  --iam-account=$KEY_SA \
  --format="table(name.basename(), keyAlgorithm, validAfterTime, validBeforeTime, keyType)"
```

### Lab 2.3 — Use Impersonation Instead of Keys

```bash
# Grant the SA a role
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$KEY_SA" \
  --role="roles/storage.objectViewer"

# Grant yourself token creator on the SA
gcloud iam service-accounts add-iam-policy-binding $KEY_SA \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/iam.serviceAccountTokenCreator"

sleep 10

# Method 1: Using key file (BAD)
echo "--- Method 1: Key file (insecure) ---"
echo "Would run: gcloud auth activate-service-account --key-file=/tmp/key-demo.json"
echo "This stores the key permanently on disk. Avoid!"

# Method 2: Using impersonation (GOOD)
echo ""
echo "--- Method 2: Impersonation (secure) ---"
gcloud storage ls --impersonate-service-account=$KEY_SA 2>&1 | head -5
echo "Token is short-lived (1hr), no file on disk!"

# Method 3: Generate access token for API calls
echo ""
echo "--- Method 3: Short-lived access token ---"
TOKEN=$(gcloud auth print-access-token --impersonate-service-account=$KEY_SA 2>/dev/null)
echo "Token preview: ${TOKEN:0:30}..."
echo "This token expires in 1 hour"
```

### Lab 2.4 — Key Rotation Demonstration

```bash
# Create a second key (simulating rotation)
gcloud iam service-accounts keys create /tmp/key-demo-new.json \
  --iam-account=$KEY_SA

echo "--- Keys after creating second key ---"
gcloud iam service-accounts keys list \
  --iam-account=$KEY_SA \
  --managed-by=user \
  --format="table(name.basename(), validAfterTime)"

# Get the old key ID
OLD_KEY_ID=$(python3 -c "import json; print(json.load(open('/tmp/key-demo.json'))['private_key_id'])" 2>/dev/null)

# Disable the old key
if [ -n "$OLD_KEY_ID" ]; then
  gcloud iam service-accounts keys disable $OLD_KEY_ID \
    --iam-account=$KEY_SA 2>/dev/null && echo "Old key disabled" || echo "Disable API may not be available in your env"
fi

# Delete the old key
if [ -n "$OLD_KEY_ID" ]; then
  gcloud iam service-accounts keys delete $OLD_KEY_ID \
    --iam-account=$KEY_SA --quiet 2>/dev/null && echo "Old key deleted"
fi

echo "--- Keys after rotation ---"
gcloud iam service-accounts keys list \
  --iam-account=$KEY_SA \
  --managed-by=user \
  --format="table(name.basename(), validAfterTime)"
```

### Lab 2.5 — Org Policy to Prevent Key Creation

```bash
# Check if constraint exists (observation only — requires Org Admin)
echo "--- Org policy: disable SA key creation ---"
echo "Constraint: constraints/iam.disableServiceAccountKeyCreation"
echo ""
echo "If enabled at org level, this BLOCKS all SA key creation."
echo "This is the strongest enforcement of 'no long-lived keys'."
echo ""
gcloud org-policies describe constraints/iam.disableServiceAccountKeyCreation \
  --project=$PROJECT_ID 2>&1 || echo "(Requires organization — may not be available in personal projects)"
```

### 🧹 Cleanup

```bash
# Delete all keys for the test SA
for KEY_ID in $(gcloud iam service-accounts keys list \
  --iam-account=$KEY_SA --managed-by=user --format="value(name.basename())"); do
  gcloud iam service-accounts keys delete $KEY_ID \
    --iam-account=$KEY_SA --quiet 2>/dev/null
done

# Remove key files
rm -f /tmp/key-demo.json /tmp/key-demo-new.json

# Remove IAM bindings
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$KEY_SA" \
  --role="roles/storage.objectViewer" 2>/dev/null

gcloud iam service-accounts remove-iam-policy-binding $KEY_SA \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/iam.serviceAccountTokenCreator" 2>/dev/null

# Delete SA
gcloud iam service-accounts delete $KEY_SA --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **SA keys are the #1 credential leak vector** in GCP
- Keys have **no expiry by default** — they persist until deleted
- **4 alternatives:** metadata server, workload identity federation, impersonation, workload identity (GKE)
- **Metadata server** tokens expire in 1 hour, auto-refresh, no file on disk
- **Impersonation** requires `roles/iam.serviceAccountTokenCreator`
- If keys are unavoidable: **rotate every 90 days**, store in Secret Manager, limit to 2 keys max
- **Org policy** `iam.disableServiceAccountKeyCreation` blocks all key creation
- Leaked key response: disable immediately → audit → rotate → prevent

### Essential Commands
```bash
# List SA keys
gcloud iam service-accounts keys list --iam-account=SA_EMAIL --managed-by=user

# Create key (avoid this!)
gcloud iam service-accounts keys create FILE --iam-account=SA_EMAIL

# Delete key
gcloud iam service-accounts keys delete KEY_ID --iam-account=SA_EMAIL

# Impersonate instead
gcloud COMMAND --impersonate-service-account=SA_EMAIL

# Get short-lived token
gcloud auth print-access-token --impersonate-service-account=SA_EMAIL
```

---

## Part 4 — Quiz (15 min)

**Q1.** A developer asks for a SA key JSON file to run their app locally. What should you recommend instead?

<details><summary>Answer</summary>

Recommend **Application Default Credentials (ADC)** with `gcloud auth application-default login`. This stores a temporary user credential that client libraries use automatically. If the app needs SA-specific access, use `--impersonate-service-account` with ADC. No key file download needed, credentials expire, and usage is audited.

</details>

**Q2.** Your application runs on a GCE VM and needs to access Cloud Storage. Why is the metadata server approach better than a key file?

<details><summary>Answer</summary>

The metadata server approach: (1) **No file to leak** — the token exists only in memory, (2) **Auto-rotates** — tokens refresh every hour automatically, (3) **No management overhead** — no rotation process needed, (4) **Auditable** — access is tied to the VM's SA, (5) **Revocable** — remove the SA's IAM binding to revoke. A key file sits on disk indefinitely, can be copied, never expires, and requires manual rotation.

</details>

**Q3.** An on-premises application needs to access GCP APIs. Keys seem like the only option. What alternative exists?

<details><summary>Answer</summary>

**Workload Identity Federation (WIF)**. Configure your on-prem identity provider (OIDC or SAML) as a workload identity pool provider in GCP. The on-prem app authenticates with its existing IdP, exchanges that token for a short-lived GCP token via the Security Token Service (STS). No key file ever leaves GCP. This works with on-prem OIDC providers, Active Directory (via ADFS), and even custom token providers.

</details>

**Q4.** Compare SA key management in GCP to LDAP bind DN password management in RHDS.

<details><summary>Answer</summary>

| GCP SA Keys | RHDS Bind DN Passwords |
|------------|----------------------|
| JSON key file on disk | `nsDS5ReplicaCredentials` or app config password |
| No expiry by default | Password policy may enforce expiry |
| Can have up to 10 keys per SA | Single password per bind DN |
| Org policy can block key creation | `passwordMustChange` can force rotation |
| Workload Identity Fed = alternative | SASL/GSSAPI = Kerberos-based alternative |
| Key leaked = full SA access | Password leaked = full bind DN access |

The principle is the same: **avoid stored credentials, prefer token-based authentication, rotate when you can't avoid**. GSSAPI in RHDS is the predecessor concept to Workload Identity Federation in GCP — both exchange machine identity for short-lived access tokens.

</details>
