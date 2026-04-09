# Day 94 — Hybrid Identity: On-Prem + Cloud SSO and BeyondCorp

> **Week 16 — Identity Architecture** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 Hybrid Identity Architecture

```
  HYBRID IDENTITY: ON-PREM + CLOUD
  ═════════════════════════════════

  ┌───────────────────────────────────────────────────────────┐
  │                     ON-PREMISES                            │
  │  ┌──────────┐  ┌──────────────┐  ┌─────────────────────┐ │
  │  │ RHDS     │  │ Keycloak /   │  │ Internal Apps       │ │
  │  │ (LDAP)   │──│ ADFS (IdP)   │  │ (LDAP-authenticated)│ │
  │  │ Source of│  │              │  │                     │ │
  │  │ truth    │  │ SAML / OIDC  │  │                     │ │
  │  └──────────┘  └──────┬───────┘  └─────────────────────┘ │
  └────────────────────────│──────────────────────────────────┘
                           │
            ┌──────────────┼──────────────┐
            │    FEDERATION LAYER          │
            │    (SAML / OIDC / WIF)      │
            └──────────────┼──────────────┘
                           │
  ┌────────────────────────│──────────────────────────────────┐
  │                     GOOGLE CLOUD                          │
  │           ┌────────────▼─────────────┐                    │
  │           │ Cloud Identity / WIF     │                    │
  │           └────────────┬─────────────┘                    │
  │                        │                                  │
  │  ┌─────────────────────┼──────────────────────────┐      │
  │  │                     │                          │      │
  │  ▼                     ▼                          ▼      │
  │ ┌────────────┐  ┌──────────────┐  ┌──────────────────┐  │
  │ │ GCP Console│  │ Cloud Apps   │  │ GKE / Compute    │  │
  │ │ (IAM)      │  │ (Workspace)  │  │ (workloads)      │  │
  │ └────────────┘  └──────────────┘  └──────────────────┘  │
  └───────────────────────────────────────────────────────────┘

  KEY PRINCIPLE: One identity, two worlds.
  User authenticates once (on-prem IdP), accesses both.
```

### 1.2 SSO Patterns for Hybrid

```
  SSO PATTERNS — WHICH TO USE?
  ═══════════════════════════

  PATTERN 1: GCDS + SAML SSO (most common for Workspace)
  ┌─────────────────────────────────────────────────┐
  │ RHDS ──sync──▶ Cloud Identity ──SAML──▶ IdP     │
  │ Users exist in both. Auth happens on-prem.       │
  │ Good for: Workspace + GCP Console.               │
  └─────────────────────────────────────────────────┘

  PATTERN 2: Workforce Identity Federation (modern, GCP only)
  ┌─────────────────────────────────────────────────┐
  │ User ──OIDC──▶ External IdP ──token──▶ GCP     │
  │ No Google account. Direct federation.            │
  │ Good for: GCP-only access, contractors.          │
  └─────────────────────────────────────────────────┘

  PATTERN 3: BeyondCorp Enterprise (zero trust)
  ┌─────────────────────────────────────────────────┐
  │ User + Device ──▶ IAP ──▶ App (checks identity  │
  │ AND device posture AND context)                  │
  │ Good for: internal apps without VPN.             │
  └─────────────────────────────────────────────────┘
```

### 1.3 BeyondCorp: Zero Trust Access

```
  BEYONDCORP vs TRADITIONAL VPN
  ═════════════════════════════

  TRADITIONAL (castle-and-moat):
  ┌────────────────────────────────────────┐
  │ INTERNET ──VPN──▶ CORP NETWORK         │
  │                   │                    │
  │   "Once inside,  │ ┌──────────────┐   │
  │    access all"    ├─│ App A        │   │
  │                   │ ├──────────────┤   │
  │                   ├─│ App B        │   │
  │                   │ ├──────────────┤   │
  │                   └─│ Sensitive DB │   │
  │                     └──────────────┘   │
  └────────────────────────────────────────┘
  Problem: VPN = trusted. Lateral movement = easy.

  BEYONDCORP (zero trust):
  ┌────────────────────────────────────────┐
  │ INTERNET ──HTTPS──▶ IAP PROXY          │
  │                     │                  │
  │ Check:              │  Per-app access: │
  │ ✓ Identity (who)   │  ┌────────────┐  │
  │ ✓ Device (posture) ├──│ App A ✓    │  │
  │ ✓ Context (where)  │  ├────────────┤  │
  │ ✓ Access level     ├──│ App B ✗    │  │
  │                     │  ├────────────┤  │
  │ No VPN needed!      └──│ DB ✗      │  │
  │                        └────────────┘  │
  └────────────────────────────────────────┘
  Every request verified. No implicit trust.
```

### 1.4 Identity-Aware Proxy (IAP)

```
  IAP ARCHITECTURE
  ═══════════════

  ┌────────┐     ┌──────────────┐     ┌──────────────┐
  │ User   │────▶│ Google Load  │────▶│ IAP          │
  │ browser│     │ Balancer     │     │ (check       │
  │        │     │              │     │  identity    │
  │        │     │              │     │  + context)  │
  └────────┘     └──────────────┘     └──────┬───────┘
                                             │
                              ┌──────────────┤
                              │ IAM check:   │
                              │ Has role     │
                              │ iap.httpsUser│
                              │ on this app? │
                              └──────┬───────┘
                                     │ YES
                              ┌──────▼───────┐
                              │ Backend App  │
                              │ (GCE / GKE / │
                              │  App Engine) │
                              └──────────────┘

  IAP adds headers to the request:
  X-Goog-Authenticated-User-Email: accounts.google.com:alice@example.com
  X-Goog-Authenticated-User-ID: 123456789

  App never handles auth — IAP does it all.
```

> **RHDS parallel:** BeyondCorp/IAP is like putting an LDAP-authenticating reverse proxy in front of every application — similar to Apache `mod_auth_ldap` or `mod_auth_mellon` (SAML), but managed by Google. In RHDS environments, you'd combine Apache reverse proxy + `mod_ldap` + certificate-based client auth + IP restrictions. BeyondCorp does all of this in one managed service.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Explore IAP Configuration

```bash
echo "=== IDENTITY-AWARE PROXY (IAP) ==="
echo ""

# Check if IAP API is enabled
gcloud services list --enabled --project=$PROJECT_ID \
  --filter="name:iap.googleapis.com" \
  --format="table(name, title)" 2>/dev/null

# Enable IAP API
echo ""
echo "--- Enabling IAP API ---"
gcloud services enable iap.googleapis.com --project=$PROJECT_ID 2>/dev/null && \
  echo "✓ IAP API enabled" || echo "IAP API already enabled or requires permissions"
```

### Lab 2.2 — Set Up a Simple Web App with IAP

```bash
echo "=== LAB: WEB APP BEHIND IAP ==="
echo ""
echo "We'll create a simple compute instance with a web server,"
echo "then protect it with IAP."
echo ""

# Create a simple web server VM
echo "--- Step 1: Create VM with web server ---"
gcloud compute instances create iap-demo-vm \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --tags=http-server \
  --metadata=startup-script='#!/bin/bash
    apt-get update && apt-get install -y nginx
    echo "<h1>Hello from IAP-protected app</h1><p>Your identity was verified by IAP.</p>" > /var/www/html/index.html
    systemctl start nginx' \
  --project=$PROJECT_ID 2>/dev/null && \
  echo "✓ VM created" || echo "VM creation failed or already exists"

# Create firewall rule for IAP tunnel
echo ""
echo "--- Step 2: Create firewall rule for IAP SSH ---"
gcloud compute firewall-rules create allow-iap-ssh \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --target-tags=http-server \
  --project=$PROJECT_ID 2>/dev/null && \
  echo "✓ IAP SSH firewall rule created" || echo "Rule already exists"

echo ""
echo "--- Step 3: Test IAP tunnel (SSH through IAP) ---"
echo "Command to SSH via IAP (no external IP needed!):"
echo "gcloud compute ssh iap-demo-vm --zone=$ZONE --tunnel-through-iap"
echo ""
echo "This is the BeyondCorp way: no VPN, no public IP,"
echo "identity verified at every connection."
```

### Lab 2.3 — IAP TCP Forwarding (SSH via Identity)

```bash
echo "=== IAP TCP FORWARDING ==="
echo ""
echo "IAP TCP Forwarding replaces traditional VPN + bastion host."
echo ""

echo "Traditional approach:"
echo "  User → VPN → Bastion Host → SSH → Target VM"
echo "  (Identity checked: once at VPN login)"
echo ""
echo "BeyondCorp approach:"
echo "  User → IAP Tunnel → SSH → Target VM"
echo "  (Identity checked: at every connection)"
echo ""

# Check IAP tunnel permissions
echo "--- IAP Tunnel IAM Binding ---"
echo "To allow a user to SSH via IAP, they need:"
echo "  Role: roles/iap.tunnelResourceAccessor"
echo "  On: the VM instance or project"
echo ""

# Check if we can tunnel
echo "--- Testing IAP tunnel connectivity ---"
gcloud compute instances describe iap-demo-vm \
  --zone=$ZONE --project=$PROJECT_ID \
  --format="table(name, status, networkInterfaces[0].networkIP:label=INTERNAL_IP)" 2>/dev/null

echo ""
echo "Note: VM has internal IP only (no external IP). IAP is the only way in."
echo "This is more secure than exposing SSH to the internet."
```

### Lab 2.4 — Context-Aware Access Levels

```bash
echo "=== CONTEXT-AWARE ACCESS ==="
echo ""

# Access levels define additional conditions beyond identity
cat << 'ACCESS_LEVELS'
ACCESS LEVELS FOR BEYONDCORP
════════════════════════════

Access Level 1: "Corporate Device"
  Conditions:
  - Device is company-managed (MDM enrolled)
  - OS is up to date
  - Screen lock is enabled
  - Disk encryption is on

Access Level 2: "Corporate Network"  
  Conditions:
  - IP is in corporate range (10.0.0.0/8)
  - OR connecting from approved VPN

Access Level 3: "High Security"
  Conditions:
  - Corporate Device AND Corporate Network
  - AND MFA was used in last 1 hour

MAPPING TO IAP:
┌─────────────────┬────────────────────────┐
│ Access Level    │ Allowed Apps           │
├─────────────────┼────────────────────────┤
│ Any (identity)  │ Company wiki, status   │
│ Corporate Device│ Internal tools, email  │
│ Corp Net + MFA  │ Production console     │
│ High Security   │ Financial systems, PII │
└─────────────────┴────────────────────────┘
ACCESS_LEVELS

echo ""
echo "--- Access Context Manager (gcloud) ---"
echo "Create access levels with:"
echo "gcloud access-context-manager levels create LEVEL_NAME \\"
echo "  --policy=POLICY_ID \\"
echo "  --basic-level-spec=YAML_FILE"
echo ""
echo "This requires Access Context Manager API + org-level permissions."
```

### Lab 2.5 — Hybrid Identity Decision Framework

```bash
echo "=== HYBRID IDENTITY DECISION TREE ==="
echo ""

cat << 'DECISION'
START: Do users need Google Workspace (Gmail, Drive, etc.)?
│
├─── YES ──▶ Use GCDS + SAML SSO
│            ├── GCDS syncs users from RHDS to Cloud Identity
│            ├── SAML SSO keeps auth on-prem (Keycloak + RHDS)
│            └── Users get Google accounts + Workspace apps + GCP
│
└─── NO ───▶ Do they need GCP Console/CLI access only?
             │
             ├─── YES ──▶ Use Workforce Identity Federation
             │            ├── No Google accounts needed
             │            ├── External IdP (Keycloak + RHDS) provides tokens
             │            └── Grant IAM roles to federated identities
             │
             └─── NO ───▶ Do they need to access internal web apps?
                          │
                          ├─── YES ──▶ Use IAP (BeyondCorp)
                          │            ├── Identity verified per-request
                          │            ├── Device posture checked
                          │            └── No VPN required
                          │
                          └─── NO ───▶ Service-to-service?
                                       └── Use Workload Identity Federation
                                           ├── On-prem workloads get GCP tokens
                                           └── No SA keys needed
DECISION
```

### 🧹 Cleanup

```bash
echo "=== CLEANUP ==="

# Delete the demo VM
gcloud compute instances delete iap-demo-vm \
  --zone=$ZONE --project=$PROJECT_ID --quiet 2>/dev/null && \
  echo "✓ VM deleted" || echo "VM already deleted"

# Delete IAP firewall rule
gcloud compute firewall-rules delete allow-iap-ssh \
  --project=$PROJECT_ID --quiet 2>/dev/null && \
  echo "✓ Firewall rule deleted" || echo "Rule already deleted"

echo "Cleanup complete."
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **Hybrid identity:** one identity source (RHDS), two access planes (on-prem + cloud)
- **Three SSO patterns:** GCDS+SAML (Workspace), Workforce IdF (GCP-only), IAP (web apps)
- **BeyondCorp:** zero-trust model — verify identity+device+context on every request
- **IAP** replaces VPN — identity-based access to web apps and SSH tunnels
- **No VPN needed** with IAP TCP tunneling — SSH via identity, not network position
- **Access levels** add context (device posture, network, MFA) beyond just identity
- **RHDS is the auth source** in all patterns: GCDS reads it, SAML IdP binds to it, WIF trusts its IdP

### Essential Commands
```bash
# Enable IAP
gcloud services enable iap.googleapis.com

# SSH via IAP (no VPN, no public IP)
gcloud compute ssh VM_NAME --zone=ZONE --tunnel-through-iap

# IAP firewall rule (allow IAP source range)
gcloud compute firewall-rules create allow-iap \
  --source-ranges=35.235.240.0/20 --rules=tcp:22 --action=ALLOW

# Grant IAP tunnel access
gcloud projects add-iam-binding PROJECT \
  --role=roles/iap.tunnelResourceAccessor --member=user:EMAIL
```

---

## Part 4 — Quiz (15 min)

**Q1.** Your company has 200 Linux admins using RHDS for authentication. They need GCP Console access but NOT Google Workspace. Which identity approach?

<details><summary>Answer</summary>

**Workforce Identity Federation.**

Rationale:
1. No Google accounts needed → no Cloud Identity licenses for 200 users
2. RHDS remains the single source of truth for authentication
3. Set up: Keycloak fronting RHDS → OIDC provider → Workforce Identity Pool → IAM bindings
4. Users authenticate with their RHDS credentials via Keycloak
5. They get temporary GCP tokens → access Console/CLI
6. Offboarding: disable in RHDS → instant GCP access revocation

GCDS+SAML would work but creates 200 Google accounts unnecessarily when they only need GCP access.

</details>

**Q2.** Explain how IAP SSH tunneling is more secure than a traditional bastion host.

<details><summary>Answer</summary>

**Bastion host:**
- Has a public IP (attack surface)
- SSH port open to internet or VPN range
- Once connected to bastion, lateral movement possible
- Identity checked once at SSH login
- Key management burden (distribute SSH keys)
- If bastion compromised, all internal VMs at risk

**IAP TCP tunneling:**
- No public IPs on any VM
- SSH only from Google's IAP range (35.235.240.0/20)
- Every connection individually authenticated via IAM
- Google account + MFA required
- Fine-grained: IAM binding per user per VM (or project)
- No SSH keys to manage if using OS Login
- Access logged in audit logs per-connection
- Can add access levels (device posture, network context)

IAP eliminates: public IPs, SSH key management, bastion maintenance, VPN overhead.

</details>

**Q3.** A Linux admin asks: "Why do I need BeyondCorp when we have iptables and SSH keys?" How do you explain it?

<details><summary>Answer</summary>

| iptables + SSH keys | BeyondCorp + IAP |
|--------------------|--------------------|
| Controls based on IP address | Controls based on identity |
| "Trust this IP range" | "Trust this verified person" |
| SSH key on disk (can be stolen) | OAuth token (short-lived) |
| No MFA in SSH by default | MFA enforced via Google |
| One firewall rule = all users | IAM binding = per-user |
| No device posture check | Check: encrypted disk, OS patched |
| VPN gives broad network access | IAP gives per-app access |
| Manual key rotation | Automatic token expiry |
| Audit: `/var/log/auth.log` | Audit: Cloud Audit Logs (searchable) |

**The shift:** iptables asks "where are you coming from?" BeyondCorp asks "who are you, what device, and should you have access to this specific resource?"

</details>

**Q4.** Design a hybrid identity architecture for a company with RHDS on-prem, 50 developers needing GCP, and 200 staff needing Google Workspace.

<details><summary>Answer</summary>

```
Architecture:
┌─────────────────────────────────┐
│ RHDS (source of truth)          │
│ 250 users, groups, policies      │
└──────────┬──────────────────────┘
           │
    ┌──────┴──────────────────────────┐
    │                                 │
    ▼                                 ▼
┌──────────────┐            ┌──────────────────┐
│ GCDS Sync    │            │ Keycloak (IdP)   │
│ 250 users →  │            │ SAML + OIDC      │
│ Cloud Identity│            │ Backs to RHDS    │
└──────┬───────┘            └────────┬─────────┘
       │                             │
       ▼                             │
┌──────────────┐            ┌────────▼─────────┐
│ Cloud Identity│            │ SAML SSO config  │
│ 250 accounts │            │ (Admin Console)  │
└──────┬───────┘            └──────────────────┘
       │
┌──────┴──────────┐
│                 │
▼                 ▼
200 Workspace    50 Devs
users (Gmail,    (Console,
Drive, etc.)    CLI, APIs)
```

- GCDS syncs all 250 users to Cloud Identity
- SAML SSO keeps authentication on RHDS (via Keycloak)
- 200 staff get Workspace licenses
- 50 devs get GCP IAM roles (via Google Groups synced from RHDS)
- All auth flows through Keycloak → RHDS — single password, single MFA

</details>
