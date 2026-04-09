# Day 65 — Security Checklist for VMs

> **Week 11 · Security Posture**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 64 completed

---

## Part 1 — Concept (30 min)

### Why a Security Checklist?

```
Without Checklist:                   With Checklist:
┌─────────────────┐                 ┌─────────────────┐
│ VM deployed     │                 │ VM deployed     │
│ "It works!"     │                 │ ✓ No public IP  │
│                 │                 │ ✓ OS Login      │
│ ? SSH keys      │                 │ ✓ Shielded VM   │
│ ? Firewall      │                 │ ✓ Custom SA     │
│ ? Public IP     │                 │ ✓ Firewall      │
│ ? Service acct  │                 │ ✓ Minimal ports │
│ ? Disk encrypt  │                 │ ✓ Disk encrypt  │
│ ? Logging       │                 │ ✓ Ops Agent     │
│                 │                 │ ✓ Audit logging │
│ → Breach in 3   │                 │                 │
│   months        │                 │ → Audit-ready   │
└─────────────────┘                 └─────────────────┘
```

### The Seven Security Domains

```
┌──────────────────────────────────────────────────────────────┐
│                    VM SECURITY DOMAINS                        │
│                                                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐               │
│  │ 1. BOOT  │  │ 2. AUTH  │  │ 3. NETWORK   │               │
│  │ Shielded │  │ OS Login │  │ No public IP  │               │
│  │ vTPM     │  │ SSH keys │  │ IAP only      │               │
│  │ Secure   │  │ MFA      │  │ Min firewall  │               │
│  │ Boot     │  │ IAM      │  │ VPC Service   │               │
│  └──────────┘  └──────────┘  │ Controls      │               │
│                               └──────────────┘               │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐               │
│  │ 4. IAM   │  │ 5. DATA  │  │ 6. MONITOR   │               │
│  │ Custom SA│  │ CMEK     │  │ Ops Agent     │               │
│  │ No def-  │  │ In-trans │  │ Audit logs    │               │
│  │ ault SA  │  │ At-rest  │  │ Alerts        │               │
│  │ Least    │  │ Secret   │  │ Log metrics   │               │
│  │ priv     │  │ Manager  │  │ SCC           │               │
│  └──────────┘  └──────────┘  └──────────────┘               │
│                                                               │
│  ┌────────────────────────────────────┐                      │
│  │ 7. OS HARDENING                    │                      │
│  │ Unattended upgrades, CIS bench,   │                      │
│  │ disable unused services, fail2ban  │                      │
│  └────────────────────────────────────┘                      │
└──────────────────────────────────────────────────────────────┘
```

### Complete Security Checklist

#### Domain 1: Boot Integrity

| Check | Setting | Linux Analogy | gcloud Flag |
|-------|---------|---------------|-------------|
| Shielded VM | Enabled | UEFI Secure Boot | `--shielded-secure-boot` |
| vTPM | Enabled | hardware TPM chip | `--shielded-vtpm` |
| Integrity Monitoring | Enabled | `aide --check` file integrity | `--shielded-integrity-monitoring` |

#### Domain 2: Authentication & Access

| Check | Setting | Linux Analogy | gcloud Flag / Config |
|-------|---------|---------------|---------------------|
| OS Login | Enabled at project | `/etc/pam.d/sshd` LDAP | `enable-oslogin=TRUE` metadata |
| OS Login 2FA | Enabled (if possible) | Google Authenticator PAM | `enable-oslogin-2fa=TRUE` metadata |
| SSH keys | No project/instance keys | `~/.ssh/authorized_keys` | Avoid `--metadata=ssh-keys=...` |
| Serial port | Disabled | No `/dev/ttyS0` access | `serial-port-enable=FALSE` |
| Root login | Disabled | `PermitRootLogin no` | OS Login enforces this |

#### Domain 3: Network

| Check | Setting | Linux Analogy | gcloud Config |
|-------|---------|---------------|---------------|
| No external IP | `--no-address` | `ifconfig eth0` no public | Org policy: `compute.vmExternalIpAccess` |
| IAP SSH only | FW: `35.235.240.0/20` | `iptables -A INPUT -s bastion` | Firewall rule |
| Minimal ports | Only needed ports | `ufw default deny incoming` | Firewall target tags |
| Cloud NAT | For outbound | `iptables MASQUERADE` | Cloud Router + NAT |
| Private Google Access | For GCP APIs | Internal DNS redirect | Subnet setting |

#### Domain 4: IAM & Service Accounts

| Check | Setting | Linux Analogy | gcloud Config |
|-------|---------|---------------|---------------|
| Custom SA | VM-specific SA | Dedicated service user | `--service-account=SA@...` |
| No default SA | Never use default | Don't use root | Remove default SA |
| Minimal scopes | Not `cloud-platform` | `chmod 640` not `777` | `--scopes=` specific |
| No SA key download | Use attached SA | No password files | Best practice |

#### Domain 5: Data Protection

| Check | Setting | Linux Analogy | GCP Feature |
|-------|---------|---------------|-------------|
| Encryption at rest | Default (Google-managed) | LUKS disk encryption | Automatic |
| CMEK | Customer-managed key | You manage LUKS keys | Cloud KMS |
| Encryption in transit | TLS for all APIs | nginx TLS termination | Default for GCP APIs |
| Secrets | Secret Manager | `ansible-vault` | `gcloud secrets` |
| No secrets in metadata | Never store creds | Never in env vars | Audit metadata |

#### Domain 6: Monitoring & Logging

| Check | Setting | Linux Analogy | GCP Feature |
|-------|---------|---------------|-------------|
| Ops Agent | Installed and running | `rsyslog` + `collectd` | Ops Agent |
| Audit logs | Admin Activity (auto) | `auditd` | Cloud Audit Logs |
| Data Access logs | Enabled per service | `strace` for data | IAM audit config |
| Log-based metrics | Key events tracked | `logwatch` | Cloud Logging |
| Alerts | Critical conditions | `monit` / Nagios | Cloud Monitoring |

#### Domain 7: OS Hardening

| Check | Setting | Linux Analogy | Implementation |
|-------|---------|---------------|----------------|
| Auto-updates | Unattended upgrades | `unattended-upgrades` | Startup script |
| CIS benchmark | CIS Level 1 | CIS hardening guide | Chef/Ansible/script |
| Unused services | Disabled | `systemctl disable ...` | Startup script |
| Fail2ban | Installed (if SSH used) | `fail2ban-server` | Package install |
| Firewall (host) | `ufw` or `iptables` | Defence in depth | Startup script |

### Priority Matrix

```
                    HIGH IMPACT
                        │
    ┌───────────────────┼───────────────────┐
    │                   │                   │
    │ ★ No public IP    │ ★ Shielded VM     │
    │ ★ Custom SA       │ ★ Ops Agent       │
    │ ★ IAP SSH only    │ ★ Auto-updates    │
    │                   │                   │
LOW ├───────────────────┼───────────────────┤ HIGH
EFF │                   │                   │ EFFORT
ORT │ ○ Min firewall    │ ○ CMEK            │
    │ ○ Disable serial  │ ○ VPC SC          │
    │ ○ OS Login        │ ○ CIS benchmark   │
    │                   │                   │
    └───────────────────┼───────────────────┘
                        │
                    LOW IMPACT
    
★ = Do first (quick wins with high impact)
○ = Plan for later
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Create an audit script that checks VM security posture against the checklist, then fix any findings.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
export VM_NAME=audit-target-vm
```

### Step 2 — Create a Deliberately Insecure VM

```bash
# Create a VM with several security issues
gcloud compute instances create $VM_NAME \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=audit-test \
    --metadata=serial-port-enable=TRUE
# Issues: default SA, public IP, serial port enabled,
#         no Shielded VM flags, no Ops Agent
```

### Step 3 — Audit the VM

```bash
echo "=== SECURITY AUDIT: $VM_NAME ==="
echo ""

# Check 1: External IP
EXT_IP=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
if [ -n "$EXT_IP" ]; then
    echo "❌ FAIL: VM has external IP: $EXT_IP"
else
    echo "✅ PASS: No external IP"
fi

# Check 2: Service Account
SA=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="value(serviceAccounts[0].email)")
if echo "$SA" | grep -q "compute@developer.gserviceaccount.com"; then
    echo "❌ FAIL: Using default compute service account"
else
    echo "✅ PASS: Custom service account: $SA"
fi

# Check 3: Shielded VM
SECURE_BOOT=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="value(shieldedInstanceConfig.enableSecureBoot)")
if [ "$SECURE_BOOT" != "True" ]; then
    echo "❌ FAIL: Secure Boot not enabled"
else
    echo "✅ PASS: Secure Boot enabled"
fi

VTPM=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="value(shieldedInstanceConfig.enableVtpm)")
if [ "$VTPM" != "True" ]; then
    echo "❌ FAIL: vTPM not enabled"
else
    echo "✅ PASS: vTPM enabled"
fi

# Check 4: Serial Port
SERIAL=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="value(metadata.items[0].value)" 2>/dev/null)
if [ "$SERIAL" = "TRUE" ]; then
    echo "❌ FAIL: Serial port access enabled"
else
    echo "✅ PASS: Serial port disabled"
fi

# Check 5: OS Login at project level
OSLOGIN=$(gcloud compute project-info describe \
    --format="value(commonInstanceMetadata.items.filter(key:enable-oslogin).extract(value).flatten())")
if [ "$OSLOGIN" != "TRUE" ]; then
    echo "❌ FAIL: OS Login not enabled at project level"
else
    echo "✅ PASS: OS Login enabled"
fi

echo ""
echo "=== AUDIT COMPLETE ==="
```

### Step 4 — Remediate Findings

```bash
# Fix 1: Enable Shielded VM (requires stop)
gcloud compute instances stop $VM_NAME --zone=$ZONE --quiet
gcloud compute instances update $VM_NAME --zone=$ZONE \
    --shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring
gcloud compute instances start $VM_NAME --zone=$ZONE

# Fix 2: Disable serial port
gcloud compute instances add-metadata $VM_NAME --zone=$ZONE \
    --metadata=serial-port-enable=FALSE

# Fix 3: Enable OS Login at project level
gcloud compute project-info add-metadata \
    --metadata=enable-oslogin=TRUE

# Fix 4: Create custom service account
gcloud iam service-accounts create audit-vm-sa \
    --display-name="Audit VM Service Account"

# Attach custom SA (requires recreating the VM or using API)
# For an existing VM, you must stop → set SA → start
gcloud compute instances stop $VM_NAME --zone=$ZONE --quiet
gcloud compute instances set-service-account $VM_NAME \
    --zone=$ZONE \
    --service-account=audit-vm-sa@${PROJECT_ID}.iam.gserviceaccount.com \
    --scopes=logging-write,monitoring-write
gcloud compute instances start $VM_NAME --zone=$ZONE
```

### Step 5 — Re-Audit After Remediation

```bash
# Rerun the audit checks from Step 3
# Expected: all green except external IP (requires VM recreation)
echo "=== POST-REMEDIATION AUDIT ==="

SECURE_BOOT=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="value(shieldedInstanceConfig.enableSecureBoot)")
echo "Secure Boot: $SECURE_BOOT"

SA=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="value(serviceAccounts[0].email)")
echo "Service Account: $SA"

SERIAL=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="json(metadata.items)" | grep -c "TRUE")
echo "Serial port enabled entries: $SERIAL"
```

### Step 6 — Create Org Policy (Simulate)

```bash
# In production, you'd enforce no external IPs org-wide:
# gcloud resource-manager org-policies enable-enforce \
#     compute.vmExternalIpAccess \
#     --organization=ORG_ID

# For a project, you can simulate with:
gcloud compute project-info add-metadata \
    --metadata=VmDnsSetting=ZonalOnly

# Verify project metadata
gcloud compute project-info describe \
    --format="yaml(commonInstanceMetadata.items)"
```

### Cleanup

```bash
gcloud compute instances delete $VM_NAME --zone=$ZONE --quiet
gcloud iam service-accounts delete audit-vm-sa@${PROJECT_ID}.iam.gserviceaccount.com --quiet
gcloud compute project-info remove-metadata --keys=enable-oslogin
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **7 Security Domains**: Boot integrity, Authentication, Network, IAM, Data, Monitoring, OS Hardening
- **Quick wins**: No public IP, custom SA, IAP SSH, OS Login, Shielded VM
- Default compute SA has `Editor` role — **never use it** in production
- Shielded VM requires **stopping** the VM to enable after creation
- OS Login replaces SSH key management with IAM-based access
- Serial port access should always be disabled (data exfiltration risk)
- Audit regularly — manual + automated (SCC, custom scripts)

### Essential Commands

```bash
# Shielded VM
gcloud compute instances update VM --shielded-secure-boot --shielded-vtpm

# OS Login
gcloud compute project-info add-metadata --metadata=enable-oslogin=TRUE

# Disable serial port
gcloud compute instances add-metadata VM --metadata=serial-port-enable=FALSE

# Set custom service account
gcloud compute instances set-service-account VM \
    --service-account=SA@PROJECT.iam.gserviceaccount.com \
    --scopes=logging-write,monitoring-write

# Describe security config
gcloud compute instances describe VM --format="yaml(shieldedInstanceConfig)"
```

---

## Part 4 — Quiz (15 min)

**Question 1: You discover a VM using the default compute service account with `cloud-platform` scope. What's the risk?**

<details>
<summary>Show Answer</summary>

The default compute SA has the **Editor** role on the project, and `cloud-platform` scope gives it access to every GCP API. This means:

- The VM can read/write **all** Cloud Storage buckets in the project
- It can create/delete **other VMs**
- It can read all secrets, databases, and BigQuery tables
- If the VM is compromised, the attacker gets near-admin access

**Fix**: Create a custom service account with only the specific roles needed (e.g., `roles/logging.logWriter`, `roles/monitoring.metricWriter`) and use specific scopes instead of `cloud-platform`.

Linux analogy: Running every application as `root` with `chmod 777` on all files.

</details>

**Question 2: What does Shielded VM protect against that a standard VM doesn't?**

<details>
<summary>Show Answer</summary>

Shielded VM protects the **boot integrity** of the VM:

| Feature | Protection | Attack Prevented |
|---------|-----------|-----------------|
| **Secure Boot** | Verifies bootloader and kernel signatures | Bootkits, rootkits |
| **vTPM** | Stores measurements of boot sequence | Boot tamper detection |
| **Integrity Monitoring** | Compares boot measurements over time | Persistent rootkits |

Without Shielded VM, an attacker who gains root access could:
- Replace the kernel with a malicious one
- Install a bootkit that survives reboots
- Hide malware below the OS layer

Linux analogy: Like having UEFI Secure Boot + TPM + `aide` (file integrity monitoring) built into the hypervisor.

</details>

**Question 3: Why should serial port access be disabled?**

<details>
<summary>Show Answer</summary>

Serial port access (`serial-port-enable=TRUE`) creates a secondary access channel:

1. **Bypasses IAP** — serial console doesn't go through IAP tunnel
2. **Bypasses network firewall** — connects through Google infrastructure
3. **Data exfiltration** — can output data to serial log readable via API
4. **No MFA** — may not require same authentication as SSH
5. **Hard to audit** — separate log from SSH access logs

Only enable temporarily for **debugging boot issues** when SSH is broken, then immediately disable.

Linux analogy: Leaving a KVM console attached to a server with auto-login.

</details>

**Question 4: A new team member asks: "Why not just use a firewall rule to restrict SSH to our office IP instead of IAP?" What's your response?**

<details>
<summary>Show Answer</summary>

Office IP restriction has multiple problems:

| Issue | Office IP Restriction | IAP |
|-------|----------------------|-----|
| Remote work | Fails from home/VPN | Works from anywhere |
| IP changes | Must update rules constantly | No IP dependency |
| Identity | Knows *where* but not *who* | Authenticates *who* |
| MFA | None (IP-based trust) | Google 2FA built-in |
| Audit trail | "Someone from office" | "user@company.com at 14:32" |
| Shared office | Everyone at that IP gets access | Individual permissions |
| IP spoofing | Possible to spoof | Not applicable |

IAP authenticates **identity**, not **location**. This is the zero-trust principle: never trust the network, always verify the user.

You can combine both: IAP + context-aware access policies that also check device posture.

</details>

---

*Next: [Day 66 — PROJECT: Hardened Private VM Blueprint](DAY_66_PROJECT_HARDENED_VM.md)*
