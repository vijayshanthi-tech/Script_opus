# Week 1, Day 5 (Fri) — Linux Baseline Hardening on GCP

## Today's Objective

Apply CIS-style hardening to a GCP Linux VM: patching, non-root admin, disabling unnecessary services, SSH hardening, and firewall configuration.

**Source:** [CIS Benchmarks](https://www.cisecurity.org/benchmark/google_cloud_computing_platform) | Your Linux runbook

**Deliverable:** Hardening commands + before/after comparison

---

## Part 1: Concept (30 minutes)

### 1.1 Why Harden a GCP VM?

GCP secures the infrastructure layer (physical, hypervisor), but **you're responsible for the guest OS**:

```
┌────────────────────────────────────────────┐
│         Shared Responsibility Model         │
│                                             │
│  Google manages:                            │
│  ✅ Physical security, network, hypervisor  │
│  ✅ Infrastructure patching                 │
│  ✅ DDoS protection, encryption at rest     │
│                                             │
│  You manage:                                │
│  🔧 OS patching and updates                │
│  🔧 User accounts and SSH access           │
│  🔧 Firewall rules (GCP + OS level)        │
│  🔧 Service hardening (disable unused)     │
│  🔧 Log collection and monitoring          │
│  🔧 Application security                   │
└────────────────────────────────────────────┘
```

### 1.2 Hardening Checklist (CIS-Inspired)

| Category | Action | Priority |
|---|---|---|
| **Patching** | Apply all security updates | Critical |
| **Users** | Create non-root admin, disable root login | Critical |
| **SSH** | Key-only auth, no password auth, change port (optional) | Critical |
| **Services** | Disable unnecessary services (cups, avahi, etc.) | High |
| **Firewall** | Enable UFW/iptables, deny by default, allow only needed | High |
| **File permissions** | Restrict /etc/passwd, /etc/shadow, home dirs | Medium |
| **Logging** | Ensure syslog/journald active, forward to Cloud Logging | Medium |
| **Kernel** | Disable IP forwarding, ICMP redirects (if not a router) | Medium |
| **Cron** | Restrict cron access to authorized users | Low |
| **Banners** | Add legal warning banner | Low |

### 1.3 GCP-Specific Hardening

| GCP Feature | Hardening Action |
|---|---|
| **OS Login** | Enable for IAM-controlled SSH access |
| **No external IP** | Remove external IP, use IAP Tunnel |
| **Shielded VM** | Enable Secure Boot, vTPM, Integrity Monitoring |
| **Service Account** | Use custom SA with minimal IAM roles |
| **Firewall Rules** | Restrict SSH to IAP ranges (35.235.240.0/20) |
| **Ops Agent** | Install for OS-level metrics and logs |

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create a VM to Harden (5 min)

```bash
gcloud compute instances create harden-lab-vm \
  --zone=europe-west2-a \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --shielded-secure-boot \
  --shielded-vtpm \
  --shielded-integrity-monitoring \
  --labels=env=learning,week=1,day=5

gcloud compute ssh harden-lab-vm --zone=europe-west2-a
```

### Step 2: BEFORE — Capture Current State (5 min)

```bash
echo "=== BEFORE HARDENING ==="
echo ""
echo "== Users with login shell =="
grep -v '/nologin\|/false' /etc/passwd
echo ""
echo "== SSH config =="
grep -E "^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)" /etc/ssh/sshd_config
echo ""
echo "== Running services =="
systemctl list-units --type=service --state=running --no-pager | head -20
echo ""
echo "== Open ports =="
sudo ss -tlnp
echo ""
echo "== Kernel params =="
sudo sysctl net.ipv4.ip_forward
sudo sysctl net.ipv4.conf.all.accept_redirects
echo ""
echo "== OS updates pending =="
sudo apt-get update -qq && apt list --upgradable 2>/dev/null | head -10
```

Save this output for your before/after comparison.

### Step 3: Apply OS Updates (5 min)

```bash
# Update package lists and upgrade all packages
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get dist-upgrade -y
sudo apt-get autoremove -y

# Check kernel version
uname -r
```

### Step 4: Create Non-Root Admin User (5 min)

```bash
# Create admin user
sudo useradd -m -s /bin/bash adminuser
sudo usermod -aG sudo adminuser

# Set a strong password (for emergency console access only)
sudo passwd adminuser

# Verify
id adminuser
groups adminuser
# Should show: adminuser : adminuser sudo
```

### Step 5: Harden SSH Configuration (10 min)

```bash
# Backup original config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Apply hardening
sudo tee /etc/ssh/sshd_config.d/hardening.conf << 'EOF'
# === SSH Hardening ===
# Disable root login
PermitRootLogin no

# Key-based authentication only
PubkeyAuthentication yes
PasswordAuthentication no

# Disable empty passwords
PermitEmptyPasswords no

# Disable X11 forwarding
X11Forwarding no

# Set idle timeout (5 min)
ClientAliveInterval 300
ClientAliveCountMax 2

# Limit authentication attempts
MaxAuthTries 3

# Disable agent forwarding (unless needed)
AllowAgentForwarding no

# Show last login
PrintLastLog yes

# Use strong key exchange algorithms
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org

# Use strong ciphers
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com

# Use strong MACs
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
EOF

# Validate configuration
sudo sshd -t
# No output = valid config

# Restart SSH
sudo systemctl restart sshd
```

### Step 6: Disable Unnecessary Services (5 min)

```bash
# List running services
systemctl list-units --type=service --state=running --no-pager

# Disable services not needed (adjust based on what's running)
# Common ones to disable on a server:
for svc in cups avahi-daemon bluetooth ModemManager; do
  if systemctl is-active --quiet $svc 2>/dev/null; then
    sudo systemctl stop $svc
    sudo systemctl disable $svc
    echo "Disabled: $svc"
  else
    echo "Not running: $svc"
  fi
done
```

### Step 7: Harden Kernel Parameters (5 min)

```bash
sudo tee /etc/sysctl.d/99-hardening.conf << 'EOF'
# Disable IP forwarding (not a router)
net.ipv4.ip_forward = 0

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# Enable SYN flood protection
net.ipv4.tcp_syncookies = 1

# Log suspicious packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP broadcasts
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
EOF

sudo sysctl --system
```

### Step 8: Set File Permissions (5 min)

```bash
# Restrict sensitive files
sudo chmod 644 /etc/passwd
sudo chmod 640 /etc/shadow
sudo chmod 644 /etc/group
sudo chmod 640 /etc/gshadow

# Restrict cron
sudo chmod 600 /etc/crontab
sudo chmod 700 /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly

# Verify
ls -la /etc/passwd /etc/shadow /etc/group
```

### Step 9: Add Login Banner (2 min)

```bash
sudo tee /etc/issue.net << 'EOF'
*************************************************************
* WARNING: Unauthorized access to this system is prohibited. *
* All activities are monitored and logged.                   *
*************************************************************
EOF

# Enable banner in SSH
echo "Banner /etc/issue.net" | sudo tee -a /etc/ssh/sshd_config.d/hardening.conf
sudo systemctl restart sshd
```

### Step 10: AFTER — Capture Hardened State (5 min)

```bash
echo "=== AFTER HARDENING ==="
echo ""
echo "== SSH config =="
grep -rE "^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)" /etc/ssh/sshd_config.d/
echo ""
echo "== Running services =="
systemctl list-units --type=service --state=running --no-pager | head -20
echo ""
echo "== Kernel params =="
sudo sysctl net.ipv4.ip_forward
sudo sysctl net.ipv4.conf.all.accept_redirects
sudo sysctl net.ipv4.tcp_syncookies
echo ""
echo "== File permissions =="
ls -la /etc/passwd /etc/shadow
echo ""
echo "== Non-root admin =="
id adminuser

exit
```

### Step 11: Clean Up

```bash
gcloud compute instances delete harden-lab-vm --zone=europe-west2-a --quiet
```

---

## Part 3: Revision (15 minutes)

### Hardening Summary

| Area | Before | After |
|---|---|---|
| SSH root login | Allowed | `PermitRootLogin no` |
| Password auth | Enabled | `PasswordAuthentication no` |
| Non-root admin | None | `adminuser` with sudo |
| Unused services | Running | Disabled (cups, avahi, etc.) |
| IP forwarding | Enabled (1) | Disabled (0) |
| SYN cookies | Default | Enabled (1) |
| File permissions | Loose | Restricted (/etc/shadow 640) |
| Login banner | None | Warning banner displayed |

### Key Commands

```bash
sudo apt-get update && sudo apt-get upgrade -y     # Patch
sudo useradd -m -s /bin/bash -G sudo USERNAME       # Non-root admin
sudo sshd -t                                        # Validate SSH config
sudo sysctl --system                                # Apply kernel params
systemctl list-units --type=service --state=running  # List services
```

---

## Part 4: Quiz (15 minutes)

**Q1:** What's the difference between GCP-level and OS-level hardening?
<details><summary>Answer</summary>GCP-level: firewall rules, OS Login, IAP, Shielded VM, no external IP, custom SA. OS-level: patching, SSH config, user management, kernel params, service hardening, file permissions. <b>Both are needed</b> — shared responsibility model.</details>

**Q2:** Why disable PasswordAuthentication in SSH?
<details><summary>Answer</summary>Password auth is vulnerable to <b>brute force attacks</b>. Key-based auth uses cryptographic key pairs which are far harder to compromise. With OS Login, keys are managed centrally via IAM.</details>

**Q3:** What does `net.ipv4.tcp_syncookies = 1` do?
<details><summary>Answer</summary>Enables <b>SYN flood protection</b>. When the SYN queue overflows, the kernel uses SYN cookies to continue accepting connections without filling the queue. Protects against DoS attacks.</details>

**Q4:** A CIS benchmark says to disable `cups` service. Why?
<details><summary>Answer</summary>CUPS is a <b>printing service</b>. Servers don't need printing. Every running service increases attack surface — unnecessary services should be disabled. Less running code = fewer potential vulnerabilities.</details>
