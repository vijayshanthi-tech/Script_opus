# Day 79 — OS Login Deep Dive: SSH, 2FA & POSIX Accounts

> **Week 14 — Secure Access** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 SSH Access to GCE VMs — Two Approaches

```
  ┌─────────────────────────────────────────────────────────────┐
  │           TWO WAYS TO SSH INTO GCE VMs                       │
  ├──────────────────────────┬──────────────────────────────────┤
  │   METADATA SSH KEYS      │   OS LOGIN                       │
  │   (Legacy approach)      │   (Recommended)                  │
  ├──────────────────────────┼──────────────────────────────────┤
  │ Keys stored in metadata  │ IAM-based access control         │
  │ (project or instance)    │                                  │
  │                          │                                  │
  │ No IAM integration       │ Full IAM integration             │
  │                          │                                  │
  │ Manual key management    │ Automatic key lifecycle          │
  │                          │                                  │
  │ No audit trail for who   │ Audit log: who SSH'd when        │
  │ used which key           │                                  │
  │                          │                                  │
  │ Keys persist until       │ Access revoked when IAM          │
  │ manually removed         │ binding removed                  │
  │                          │                                  │
  │ No 2FA support           │ 2FA support                      │
  │                          │                                  │
  │ Like: ~/.ssh/authorized_ │ Like: SSSD + LDAP/FreeIPA for   │
  │ keys manually managed    │ centralized SSH                  │
  └──────────────────────────┴──────────────────────────────────┘
```

**Linux analogy:**
| Metadata SSH Keys | OS Login |
|-------------------|----------|
| Manually editing `~/.ssh/authorized_keys` | SSSD/PAM + LDAP (like RHDS) |
| Each VM manages its own keys | Centralized identity management |
| No central audit | PAM logs who logged in |
| No expiry | Access tied to directory membership |

### 1.2 How OS Login Works

```
  ┌────────────┐    ┌──────────────┐    ┌────────────────┐
  │   User     │    │  IAM checks  │    │   VM sshd      │
  │  (gcloud   │───▶│  OS Login    │───▶│   + NSS/PAM    │
  │   ssh)     │    │  roles       │    │   module        │
  └────────────┘    └──────┬───────┘    └───────┬────────┘
                           │                     │
                    ┌──────▼───────┐    ┌───────▼────────┐
                    │ Has role:    │    │ Creates POSIX  │
                    │ osLogin or   │    │ account:       │
                    │ osAdminLogin │    │ uid, gid, home │
                    │ ?            │    │ directory      │
                    └──────┬───────┘    └───────┬────────┘
                           │                     │
                    ┌──────▼───────┐    ┌───────▼────────┐
                    │ YES → allow  │    │ SSH session    │
                    │ NO  → deny   │    │ established    │
                    └──────────────┘    └────────────────┘

  OS Login IAM Roles:
  ┌────────────────────────────────────────────────────────┐
  │ roles/compute.osLogin        → standard user (no sudo) │
  │ roles/compute.osAdminLogin   → admin user (with sudo)  │
  │ roles/iam.serviceAccountUser → if VM has a SA attached  │
  └────────────────────────────────────────────────────────┘
```

### 1.3 POSIX Account Mapping

```
  Google Identity → POSIX Account
  ════════════════════════════════

  user:alice@company.com
       │
       ▼
  ┌──────────────────────────────────┐
  │ POSIX Account on VM:             │
  │ Username: alice_company_com      │
  │ UID:      auto-generated         │
  │ GID:      auto-generated         │
  │ Home:     /home/alice_company_com│
  │ Shell:    /bin/bash              │
  └──────────────────────────────────┘

  ⚠ Username is derived from email:
    - @ → _
    - . → _
    - Truncated to 32 chars
```

> **RHDS parallel:** This is exactly like `nss_ldap` / SSSD in RHDS. The LDAP directory stores `posixAccount` attributes (`uidNumber`, `gidNumber`, `homeDirectory`, `loginShell`), and NSS/PAM modules on the host resolve users from there. OS Login replaces the RHDS directory with Google Cloud Identity as the identity backend.

### 1.4 OS Login with 2FA

```
  SSH with 2FA (Two-Factor Authentication)
  ═════════════════════════════════════════

  ┌─────────┐   ┌──────────┐   ┌──────────┐   ┌─────────┐
  │ gcloud  │──▶│ IAM      │──▶│ 2FA      │──▶│ VM SSH  │
  │ ssh     │   │ check    │   │ challenge│   │ session │
  └─────────┘   └──────────┘   └──────────┘   └─────────┘
                                    │
                              ┌─────▼─────┐
                              │ Security  │
                              │ key or    │
                              │ phone     │
                              │ prompt    │
                              └───────────┘

  Enable: set metadata enable-oslogin-2fa=TRUE
  Requires: user has 2FA enrolled in Google account
```

### 1.5 OS Login with Terraform

```hcl
  # Enable OS Login at project level
  resource "google_compute_project_metadata" "oslogin" {
    metadata = {
      enable-oslogin = "TRUE"
    }
  }

  # Grant OS Login access
  resource "google_project_iam_member" "oslogin_user" {
    project = var.project_id
    role    = "roles/compute.osLogin"
    member  = "user:alice@company.com"
  }

  # For admin (sudo) access
  resource "google_project_iam_member" "oslogin_admin" {
    project = var.project_id
    role    = "roles/compute.osAdminLogin"
    member  = "user:bob@company.com"
  }
```

### 1.6 SSH Certificates (Advanced)

```
  SSH Certificates vs OS Login
  ════════════════════════════
  
  OS Login: GCP manages keys, IAM controls access
  SSH Certs: You manage a CA, issue short-lived signed certs
  
  ┌──────────────────────────────────────────────┐
  │ SSH Certificate Flow:                         │
  │                                               │
  │ CA signs user's public key → short-lived cert │
  │ VM trusts the CA → accepts the cert           │
  │ Cert expires → access revoked automatically   │
  │                                               │
  │ Use when: OS Login not available, need         │
  │ cross-cloud SSH, custom CA requirements        │
  └──────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Enable OS Login at Project Level

```bash
# Check current OS Login status
gcloud compute project-info describe --project=$PROJECT_ID \
  --format="value(commonInstanceMetadata.items.filter(key:enable-oslogin).value)"

# Enable OS Login for the project
gcloud compute project-info add-metadata \
  --metadata enable-oslogin=TRUE \
  --project=$PROJECT_ID

# Verify
echo "--- OS Login status ---"
gcloud compute project-info describe --project=$PROJECT_ID \
  --format="value(commonInstanceMetadata.items.filter(key:enable-oslogin).value)"
echo "(should show TRUE)"
```

### Lab 2.2 — Create a VM and Test OS Login SSH

```bash
# Create a VM (OS Login inherited from project metadata)
gcloud compute instances create oslogin-vm \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --no-address \
  --metadata=enable-oslogin=TRUE

# Ensure you have OS Login role
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/compute.osAdminLogin"

# SSH using OS Login
echo "--- SSH into VM using OS Login ---"
gcloud compute ssh oslogin-vm --zone=$ZONE --tunnel-through-iap --command="
  echo 'Logged in as:' \$(whoami)
  echo 'UID:' \$(id -u)
  echo 'GID:' \$(id -g)
  echo 'Home:' \$HOME
  echo 'Groups:' \$(groups)
  echo ''
  echo '--- POSIX account entry ---'
  getent passwd \$(whoami)
  echo ''
  echo '--- Can sudo? ---'
  sudo whoami 2>&1
"
```

### Lab 2.3 — Compare OS Login vs Metadata Keys

```bash
# Create a VM with OS Login DISABLED (metadata keys)
gcloud compute instances create metadata-key-vm \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --no-address \
  --metadata=enable-oslogin=FALSE

# SSH — this will push your SSH key to project metadata
gcloud compute ssh metadata-key-vm --zone=$ZONE --tunnel-through-iap --command="
  echo 'Logged in as:' \$(whoami)
  echo 'Auth method: metadata SSH key'
  echo ''
  echo '--- authorized_keys ---'
  cat ~/.ssh/authorized_keys 2>/dev/null | head -2
  echo ''
  echo '--- No POSIX account from directory ---'
  echo 'Note: username derived from local SSH key, not IAM'
"

# Check project metadata for the key
echo "--- SSH keys in project metadata ---"
gcloud compute project-info describe --project=$PROJECT_ID \
  --format="value(commonInstanceMetadata.items.filter(key:ssh-keys).value)" | head -5
```

### Lab 2.4 — OS Login POSIX Account Details

```bash
# View your OS Login POSIX profile
gcloud compute os-login describe-profile

# View POSIX accounts
echo "--- POSIX accounts ---"
gcloud compute os-login describe-profile \
  --format="yaml(posixAccounts)"

# View SSH keys managed by OS Login
echo "--- SSH keys ---"
gcloud compute os-login ssh-keys list --format="table(
  key.slice(0:40):label=KEY_PREFIX,
  expirationTimeUsec
)"
```

### Lab 2.5 — Enable OS Login 2FA (Observation Only)

```bash
# Enable 2FA at project level (requires users to have 2FA enrolled)
echo "--- Setting up OS Login 2FA metadata ---"
gcloud compute project-info add-metadata \
  --metadata enable-oslogin-2fa=TRUE \
  --project=$PROJECT_ID

# View the metadata
gcloud compute project-info describe --project=$PROJECT_ID \
  --format="yaml(commonInstanceMetadata.items)"

echo ""
echo "Note: 2FA will prompt on next SSH if your Google account has 2FA enrolled."
echo "If no 2FA enrolled, SSH will fail with 2FA requirement error."

# Disable 2FA (for lab convenience)
gcloud compute project-info remove-metadata \
  --keys=enable-oslogin-2fa \
  --project=$PROJECT_ID
```

### 🧹 Cleanup

```bash
# Delete VMs
gcloud compute instances delete oslogin-vm --zone=$ZONE --quiet
gcloud compute instances delete metadata-key-vm --zone=$ZONE --quiet

# Remove OS Login admin role (if added for lab)
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/compute.osAdminLogin" 2>/dev/null

# Optionally disable OS Login at project level
# gcloud compute project-info remove-metadata --keys=enable-oslogin --project=$PROJECT_ID
echo "Note: OS Login is still enabled at project level. Keep or remove as needed."
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **OS Login** = IAM-based SSH access (recommended over metadata SSH keys)
- **Metadata keys** = manually managed, no IAM integration, no audit trail
- Two OS Login roles: `osLogin` (standard user) and `osAdminLogin` (sudo)
- POSIX accounts auto-created: username derived from email, auto-assigned UID/GID
- **2FA** via `enable-oslogin-2fa=TRUE` metadata — requires enrolled Google 2FA
- OS Login works like **SSSD + LDAP** — centralized identity, local NSS/PAM resolution
- SSH certificates are an alternative for cross-cloud or custom CA scenarios
- Always use `--tunnel-through-iap` for VMs without external IPs

### Essential Commands
```bash
# Enable OS Login at project level
gcloud compute project-info add-metadata --metadata enable-oslogin=TRUE

# Grant OS Login access
gcloud projects add-iam-policy-binding PROJECT \
  --member="user:EMAIL" --role="roles/compute.osLogin"

# Grant OS Login admin (sudo)
gcloud projects add-iam-policy-binding PROJECT \
  --member="user:EMAIL" --role="roles/compute.osAdminLogin"

# View OS Login profile
gcloud compute os-login describe-profile

# List OS Login SSH keys
gcloud compute os-login ssh-keys list

# SSH via IAP tunnel
gcloud compute ssh VM --zone=ZONE --tunnel-through-iap
```

---

## Part 4 — Quiz (15 min)

**Q1.** A team uses metadata SSH keys. When an engineer leaves, their key remains on all VMs. How does OS Login solve this?

<details><summary>Answer</summary>

With OS Login, access is controlled via IAM. When the engineer's Google account is deactivated or their IAM binding is removed, they **immediately lose SSH access to all VMs**. No need to manually remove keys from individual VMs. This is identical to how disabling an account in RHDS immediately revokes SSH access on all hosts configured with SSSD/PAM — centralised identity, centralised revocation.

</details>

**Q2.** A user has `roles/compute.osLogin` but reports they cannot install packages on the VM. Why?

<details><summary>Answer</summary>

`roles/compute.osLogin` grants **standard user** access (no root/sudo). Installing packages requires root, which needs `roles/compute.osAdminLogin`. The distinction is like regular user access vs being in the `wheel`/`sudo` group on Linux. Grant `osAdminLogin` only if root access is justified.

</details>

**Q3.** How does OS Login's POSIX account mapping compare to RHDS `posixAccount` LDAP entries?

<details><summary>Answer</summary>

| RHDS `posixAccount` | OS Login POSIX |
|---------------------|---------------|
| `uid: john` | Username: `john_company_com` (from email) |
| `uidNumber: 1001` (you assign) | UID: auto-generated by Google |
| `gidNumber: 1001` (you assign) | GID: auto-generated by Google |
| `homeDirectory: /home/john` | Home: `/home/john_company_com` |
| `loginShell: /bin/bash` | Shell: `/bin/bash` |
| Resolved via `nss_ldap`/SSSD | Resolved via Google NSS module |

The key difference: in RHDS you manually manage UID/GID allocation (or use DNA plugin). OS Login auto-assigns them using Google's identity backend.

</details>

**Q4.** Should you enable OS Login 2FA on all production VMs? What are the trade-offs?

<details><summary>Answer</summary>

**Pros:** Stronger authentication, compliance requirement for many frameworks (PCI-DSS, SOC 2), prevents SSH access with stolen credentials alone.

**Cons:** Breaks automation (scripts/cron jobs can't do 2FA), service account SSH doesn't support 2FA, adds friction for on-call incident response. 

**Recommendation:** Enable 2FA for production VMs accessed by humans. Use service accounts (which bypass 2FA) for automation — but secure those SAs with IAM and ensure no key export. This mirrors the RHDS pattern: require strong auth for admin access, use Kerberos keytabs for service accounts.

</details>
