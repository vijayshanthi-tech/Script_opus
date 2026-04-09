# Day 38 — Automated Package Install & Hardening

> **Week 7 — Automation & Ops** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### Why Automate Package Installation and Hardening?

With 6 years of Linux infra experience, you've likely manually hardened servers via SSH. In cloud, VMs are **ephemeral** — they can be replaced at any time. Automation ensures every VM starts identically.

**Linux analogy:**

| Manual Approach | Automated Approach |
|---|---|
| SSH in, `apt install nginx` | Startup script installs on boot |
| Edit `/etc/ssh/sshd_config` by hand | Script writes config from template |
| "Follow the wiki" hardening guide | Single idempotent hardening script |
| "Dave's VM is different from Mike's" | Every VM from golden image + script |
| Build once, patch manually | Rebuild from script, redeploy |

### Golden Image Pipeline

```
┌──────────────────────────────────────────────────────────┐
│              Golden Image Pipeline                        │
│                                                          │
│  ┌───────────┐    ┌───────────────┐    ┌──────────────┐  │
│  │ Base Image│    │ Startup Script│    │ Golden Image │  │
│  │ (Debian   │──►│ + Packages    │──►│ (Custom)     │  │
│  │  12 stock)│    │ + Hardening   │    │              │  │
│  └───────────┘    │ + Config      │    │ Snapshot     │  │
│                   └───────────────┘    │ and save     │  │
│                                        └──────┬───────┘  │
│                                               │          │
│                              ┌────────────────┼────┐     │
│                              ▼                ▼    ▼     │
│                         ┌──────┐  ┌──────┐  ┌──────┐    │
│                         │ VM-1 │  │ VM-2 │  │ VM-3 │    │
│                         └──────┘  └──────┘  └──────┘    │
│                         (All identical, all hardened)     │
└──────────────────────────────────────────────────────────┘
```

### Idempotency

A script is **idempotent** if running it multiple times produces the same result as running it once. This is critical because startup scripts run on **every boot**.

```
┌──────────────────────────────────────────────────┐
│           Idempotent vs Non-Idempotent           │
│                                                  │
│  NON-IDEMPOTENT (BAD):                           │
│  echo "new line" >> /etc/config.conf             │
│  → Adds a duplicate line on every reboot!        │
│                                                  │
│  IDEMPOTENT (GOOD):                              │
│  grep -q "new line" /etc/config.conf || \        │
│    echo "new line" >> /etc/config.conf           │
│  → Only adds if not already present              │
│                                                  │
│  EVEN BETTER:                                    │
│  cat > /etc/config.conf << 'EOF'                 │
│  new line                                        │
│  EOF                                             │
│  → Overwrites entire file (always same state)    │
└──────────────────────────────────────────────────┘
```

### Hardening Checklist (CIS-Inspired)

| Category | Actions | Linux Command |
|---|---|---|
| **SSH** | Disable root login, disable password auth | `sshd_config` |
| **Kernel** | Disable IP forwarding, ignore ICMP redirects | `sysctl.conf` |
| **Services** | Disable unnecessary services | `systemctl disable` |
| **Users** | Remove unused accounts, strong password policy | `userdel`, `pam.d` |
| **Filesystem** | Set `noexec` on /tmp, limit core dumps | `/etc/fstab`, `limits.conf` |
| **Firewall** | Default deny, allow only needed ports | `iptables` / GCP firewall |
| **Updates** | Enable unattended security updates | `unattended-upgrades` |
| **Audit** | Enable auditd, log critical file access | `auditd` rules |

### Idempotent Script Patterns

```
┌──────────────────────────────────────────────────────────┐
│              Idempotent Patterns                          │
│                                                          │
│  Pattern 1: Guard file                                   │
│  ┌──────────────────────────────────────────────────┐    │
│  │  if [ -f /opt/.setup-done ]; then exit 0; fi    │    │
│  │  # ... do setup ...                              │    │
│  │  touch /opt/.setup-done                          │    │
│  └──────────────────────────────────────────────────┘    │
│                                                          │
│  Pattern 2: Overwrite (not append)                       │
│  ┌──────────────────────────────────────────────────┐    │
│  │  cat > /etc/myapp.conf << 'EOF'                  │    │
│  │  key=value                                       │    │
│  │  EOF                                             │    │
│  └──────────────────────────────────────────────────┘    │
│                                                          │
│  Pattern 3: Check before modify                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │  systemctl is-enabled nginx || \                 │    │
│  │    systemctl enable nginx                        │    │
│  └──────────────────────────────────────────────────┘    │
│                                                          │
│  Pattern 4: Desired state with sed                       │
│  ┌──────────────────────────────────────────────────┐    │
│  │  sed -i 's/^#\?PermitRootLogin.*/                │    │
│  │    PermitRootLogin no/' /etc/ssh/sshd_config     │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=europe-west2-a
export REGION=europe-west2
export PREFIX="lab38"
export SCRIPT_BUCKET="${PROJECT_ID}-scripts-${PREFIX}"
```

### Step 1 — Write the Idempotent Setup Script

```bash
# Create the script locally first
cat > /tmp/golden-setup.sh << 'SCRIPT_EOF'
#!/bin/bash
#
# Golden VM Setup Script — Idempotent
# Installs packages, configures services, hardens OS
#
set -euo pipefail

SETUP_MARKER="/opt/.golden-setup-v1-complete"
LOG="/var/log/golden-setup.log"

exec > >(tee -a "$LOG") 2>&1

echo "=== Golden Setup Begin: $(date) ==="

# Pattern 1: Guard — skip if already completed (same version)
if [ -f "${SETUP_MARKER}" ]; then
    echo "Setup v1 already completed. Skipping."
    exit 0
fi

# ─────────────────────────────────
# PHASE 1: Package Installation
# ─────────────────────────────────
echo "[Phase 1] Installing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    nginx \
    curl \
    jq \
    htop \
    iotop \
    fail2ban \
    unattended-upgrades \
    apt-listchanges \
    auditd \
    logrotate

# ─────────────────────────────────
# PHASE 2: Service Configuration
# ─────────────────────────────────
echo "[Phase 2] Configuring services..."

# Nginx: custom default page
cat > /var/www/html/index.html << 'NGINX_EOF'
<!DOCTYPE html>
<html>
<body>
  <h1>Golden VM</h1>
  <p>Configured by automated setup script</p>
</body>
</html>
NGINX_EOF

systemctl enable nginx
systemctl restart nginx

# Fail2ban: enable and start
systemctl enable fail2ban
systemctl restart fail2ban

# Unattended upgrades: enable security updates
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'APT_EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
APT_EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'APT2_EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT2_EOF

# ─────────────────────────────────
# PHASE 3: SSH Hardening
# ─────────────────────────────────
echo "[Phase 3] Hardening SSH..."

# Backup original config (only on first run)
[ ! -f /etc/ssh/sshd_config.orig ] && cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig

# Apply hardening (sed is idempotent — same result on re-run)
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config

systemctl restart sshd

# ─────────────────────────────────
# PHASE 4: Kernel Hardening
# ─────────────────────────────────
echo "[Phase 4] Hardening kernel parameters..."

cat > /etc/sysctl.d/99-hardening.conf << 'SYSCTL_EOF'
# Disable IP forwarding
net.ipv4.ip_forward = 0

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Ignore source-routed packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Enable SYN flood protection
net.ipv4.tcp_syncookies = 1

# Log martian packets
net.ipv4.conf.all.log_martians = 1

# Disable ICMP broadcast replies
net.ipv4.icmp_echo_ignore_broadcasts = 1
SYSCTL_EOF

sysctl -p /etc/sysctl.d/99-hardening.conf

# ─────────────────────────────────
# PHASE 5: Audit Configuration
# ─────────────────────────────────
echo "[Phase 5] Configuring audit rules..."

cat > /etc/audit/rules.d/hardening.rules << 'AUDIT_EOF'
# Monitor SSH config changes
-w /etc/ssh/sshd_config -p wa -k sshd_config
# Monitor user/group changes
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
# Monitor sudo usage
-w /etc/sudoers -p wa -k sudoers
AUDIT_EOF

systemctl enable auditd
systemctl restart auditd

# ─────────────────────────────────
# PHASE 6: Cleanup
# ─────────────────────────────────
echo "[Phase 6] Cleaning up..."
apt-get autoremove -y -qq
apt-get clean

# Mark setup as complete
touch "${SETUP_MARKER}"
echo "=== Golden Setup Complete: $(date) ==="
SCRIPT_EOF

chmod +x /tmp/golden-setup.sh
echo "Script created: $(wc -l /tmp/golden-setup.sh) lines"
```

### Step 2 — Upload Script and Deploy VM

```bash
# Create GCS bucket for scripts
gsutil mb -p ${PROJECT_ID} -l ${REGION} -b on gs://${SCRIPT_BUCKET}
gsutil cp /tmp/golden-setup.sh gs://${SCRIPT_BUCKET}/golden-setup.sh

# Create VM with the script
gcloud compute instances create golden-test-${PREFIX} \
  --zone=${ZONE} \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --tags=${PREFIX} \
  --scopes=storage-ro \
  --metadata=startup-script-url=gs://${SCRIPT_BUCKET}/golden-setup.sh

echo "VM created. Waiting for startup script to complete..."
sleep 120
```

### Step 3 — Verify the Setup

```bash
# Comprehensive verification
gcloud compute ssh golden-test-${PREFIX} --zone=${ZONE} --command="
echo '=========================================='
echo '  GOLDEN VM VERIFICATION REPORT'
echo '=========================================='

echo ''
echo '--- Phase 1: Packages ---'
for pkg in nginx curl jq htop iotop fail2ban auditd; do
  dpkg -l | grep -q \"\${pkg}\" && echo \"  [OK] \${pkg} installed\" || echo \"  [FAIL] \${pkg} missing\"
done

echo ''
echo '--- Phase 2: Services ---'
for svc in nginx fail2ban auditd; do
  systemctl is-active \${svc} > /dev/null 2>&1 && echo \"  [OK] \${svc} running\" || echo \"  [FAIL] \${svc} not running\"
done

echo ''
echo '--- Phase 3: SSH Hardening ---'
grep -q 'PermitRootLogin no' /etc/ssh/sshd_config && echo '  [OK] Root login disabled' || echo '  [FAIL] Root login not disabled'
grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config && echo '  [OK] Password auth disabled' || echo '  [FAIL] Password auth enabled'
grep -q 'X11Forwarding no' /etc/ssh/sshd_config && echo '  [OK] X11 forwarding disabled' || echo '  [FAIL] X11 forwarding enabled'
grep -q 'MaxAuthTries 3' /etc/ssh/sshd_config && echo '  [OK] Max auth tries = 3' || echo '  [FAIL] Max auth tries not set'

echo ''
echo '--- Phase 4: Kernel Hardening ---'
[ \"\$(sysctl -n net.ipv4.ip_forward)\" = \"0\" ] && echo '  [OK] IP forwarding disabled' || echo '  [FAIL] IP forwarding enabled'
[ \"\$(sysctl -n net.ipv4.tcp_syncookies)\" = \"1\" ] && echo '  [OK] SYN cookies enabled' || echo '  [FAIL] SYN cookies disabled'
[ \"\$(sysctl -n net.ipv4.conf.all.accept_redirects)\" = \"0\" ] && echo '  [OK] ICMP redirects ignored' || echo '  [FAIL] ICMP redirects accepted'

echo ''
echo '--- Phase 5: Audit ---'
auditctl -l 2>/dev/null | grep -q sshd_config && echo '  [OK] SSH config audited' || echo '  [FAIL] SSH config not audited'
auditctl -l 2>/dev/null | grep -q identity && echo '  [OK] User changes audited' || echo '  [FAIL] User changes not audited'

echo ''
echo '--- Setup Marker ---'
[ -f /opt/.golden-setup-v1-complete ] && echo '  [OK] Setup marker present' || echo '  [FAIL] Setup marker missing'

echo ''
echo '--- Nginx Test ---'
curl -s localhost | head -5

echo ''
echo '=========================================='
echo '  REPORT COMPLETE'
echo '=========================================='
"
```

### Step 4 — Test Idempotency

```bash
# Reboot the VM — startup script should skip (guard file exists)
gcloud compute instances reset golden-test-${PREFIX} --zone=${ZONE}
sleep 90

# Check the log — should show "already completed"
gcloud compute ssh golden-test-${PREFIX} --zone=${ZONE} --command="
echo '--- Last 10 lines of setup log ---'
tail -10 /var/log/golden-setup.log
"
```

### Step 5 — Create a Fresh VM to Confirm Reproducibility

```bash
# Second VM from the same script — should get identical result
gcloud compute instances create golden-test2-${PREFIX} \
  --zone=${ZONE} \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --tags=${PREFIX} \
  --scopes=storage-ro \
  --metadata=startup-script-url=gs://${SCRIPT_BUCKET}/golden-setup.sh

sleep 120

# Quick verify
gcloud compute ssh golden-test2-${PREFIX} --zone=${ZONE} --command="
[ -f /opt/.golden-setup-v1-complete ] && echo 'PASS: Setup complete' || echo 'FAIL: Setup not done'
systemctl is-active nginx && echo 'PASS: Nginx running' || echo 'FAIL: Nginx down'
sysctl -n net.ipv4.ip_forward | grep -q 0 && echo 'PASS: Hardened' || echo 'FAIL: Not hardened'
"
```

### Cleanup

```bash
# Delete VMs
for vm in golden-test-${PREFIX} golden-test2-${PREFIX}; do
  gcloud compute instances delete ${vm} --zone=${ZONE} --quiet 2>/dev/null
done

# Delete GCS bucket
gsutil rm -r gs://${SCRIPT_BUCKET} 2>/dev/null

# Clean local files
rm -f /tmp/golden-setup.sh
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Golden image pipeline** = base image → install + harden → save as custom image
- **Idempotent scripts** = safe to re-run; use guard files, overwrite (not append), `sed` patterns
- **CIS hardening basics**: SSH (no root, no password), kernel (`sysctl`), audit (`auditd`), services
- Startup scripts run on **every boot** — idempotency is critical
- **Unattended-upgrades** for auto-patching security vulnerabilities
- **fail2ban** for SSH brute-force protection
- Always **verify** automated setup with a structured verification script

### Essential Commands

```bash
# Package management (idempotent)
apt-get install -y -qq PACKAGE       # -y = auto-yes, -qq = quiet

# SSH hardening
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Kernel hardening
cat > /etc/sysctl.d/99-hardening.conf << 'EOF' ... EOF
sysctl -p /etc/sysctl.d/99-hardening.conf

# Audit rules
cat > /etc/audit/rules.d/hardening.rules << 'EOF' ... EOF
auditctl -l   # List current rules

# Idempotency guard
if [ -f /opt/.setup-done ]; then exit 0; fi
```

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: Your startup script appends a line to /etc/sysctl.conf on every boot, creating duplicates. How do you fix it?</strong></summary>

**Answer:** Three approaches, from best to okay:

1. **Overwrite a dedicated file (BEST):**
   ```bash
   cat > /etc/sysctl.d/99-custom.conf << 'EOF'
   net.ipv4.ip_forward = 0
   EOF
   sysctl -p /etc/sysctl.d/99-custom.conf
   ```
   Uses `/etc/sysctl.d/` directory (designed for drop-in configs). Overwriting is always idempotent.

2. **Check before append:**
   ```bash
   grep -q "net.ipv4.ip_forward = 0" /etc/sysctl.conf || \
     echo "net.ipv4.ip_forward = 0" >> /etc/sysctl.conf
   ```

3. **Guard file:**
   ```bash
   if [ -f /opt/.sysctl-done ]; then exit 0; fi
   ```

Option 1 is best because it uses the OS's intended mechanism and is inherently idempotent.
</details>

<details>
<summary><strong>Q2: Why is `set -euo pipefail` important at the top of a setup script?</strong></summary>

**Answer:**

| Flag | Meaning | Why It Matters |
|---|---|---|
| `-e` | Exit on any command failure | Prevents partial/broken setup (stops at first error) |
| `-u` | Error on undefined variables | Catches typos like `$UNDEFINED_VAR` (otherwise empty) |
| `-o pipefail` | Pipeline fails if any command in pipe fails | `cmd1 | cmd2` fails if `cmd1` fails, not just `cmd2` |

**Without these flags:**
- A failing `apt-get install` would be silently ignored
- The script would continue, marking setup as "complete" even though packages are missing
- You'd have a half-configured, unhardened VM that looks ready

**Exception:** Sometimes you want specific commands to be allowed to fail. Use `|| true`:
```bash
systemctl stop legacy-service || true  # OK if service doesn't exist
```
</details>

<details>
<summary><strong>Q3: What's the difference between a startup script approach and a golden image approach for hardening?</strong></summary>

**Answer:**

| Aspect | Startup Script | Golden Image |
|---|---|---|
| **Boot time** | Slower (installs on every new VM) | Faster (pre-installed) |
| **Flexibility** | Change script, new VMs get changes | Must rebuild image for changes |
| **Maintenance** | Single script to update | Image pipeline to maintain |
| **Consistency** | Depends on external repos (apt mirrors) | Baked in, no external deps at boot |
| **Testing** | Test on deploy | Test during image build |

**Best practice (combine both):**
1. Create a golden image with base packages + hardening
2. Use a lightweight startup script for runtime config (hostname, metadata, service registration)
3. Rebuild golden image periodically (weekly/monthly) with latest patches
</details>

<details>
<summary><strong>Q4: You're asked to ensure all VMs in the project have auditd monitoring SSH config changes. How would you automate this at scale?</strong></summary>

**Answer:**

1. **Bake into golden image:** Add audit rules to the golden image build script — all new VMs get it automatically
2. **Instance template:** Reference golden image + startup script that configures auditd
3. **Organization Policy + Startup script:** Use a project-level metadata startup script (applies to ALL VMs in the project):
   ```bash
   gcloud compute project-info add-metadata \
     --metadata=startup-script='#!/bin/bash
   cat > /etc/audit/rules.d/ssh-monitor.rules << EOF
   -w /etc/ssh/sshd_config -p wa -k sshd_config
   EOF
   systemctl restart auditd'
   ```
4. **Verify compliance:** Write a script that SSHs to each VM and checks `auditctl -l | grep sshd_config`
5. **Alert on drift:** Use Cloud Asset Inventory or a custom Cloud Function to detect VMs without the expected metadata key
</details>
