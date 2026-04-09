# Day 66 — PROJECT: Hardened Private VM Blueprint

> **Week 11 · Security Posture — Capstone Project**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Days 61–65 completed

---

## Part 1 — Concept (30 min)

### Project Overview

Build the **maximally secure VM deployment** that consolidates every security practice from this week into a single, production-ready blueprint.

### Target Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                   HARDENED VM BLUEPRINT                                │
│                                                                       │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │                 VPC: hardened-vpc                               │   │
│  │                 Subnet: 10.20.0.0/24                           │   │
│  │                 Private Google Access: ✓                       │   │
│  │                                                                │   │
│  │   ┌─────────────────────────────────────────────────┐         │   │
│  │   │         HARDENED VM: hardened-vm                  │         │   │
│  │   │                                                   │         │   │
│  │   │  ✓ No external IP (10.20.0.x only)               │         │   │
│  │   │  ✓ Shielded VM (Secure Boot + vTPM + Integrity)  │         │   │
│  │   │  ✓ Custom SA (hardened-vm-sa)                     │         │   │
│  │   │  ✓ Minimal scopes (logging + monitoring only)     │         │   │
│  │   │  ✓ OS Login enabled                               │         │   │
│  │   │  ✓ Serial port disabled                           │         │   │
│  │   │  ✓ Ops Agent installed (startup script)           │         │   │
│  │   │  ✓ Unattended upgrades enabled                    │         │   │
│  │   │  ✓ Host firewall (ufw)                            │         │   │
│  │   │  ✓ Deletion protection enabled                    │         │   │
│  │   └─────────────────────────────────────────────────┘         │   │
│  │                        │                                       │   │
│  │            Firewall Rules:                                     │   │
│  │            ✓ Allow IAP SSH (35.235.240.0/20 → tcp:22)         │   │
│  │            ✓ Allow internal (10.20.0.0/24 → all)              │   │
│  │            ✗ NO default allow rules                            │   │
│  │                                                                │   │
│  │   ┌────────────┐    ┌─────────────────┐                       │   │
│  │   │ Cloud NAT  │    │ Cloud Router     │                       │   │
│  │   │ (outbound  │◄───│ hardened-router  │                       │   │
│  │   │  internet) │    └─────────────────┘                       │   │
│  │   └────────────┘                                               │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                       │
│  External Access:                                                    │
│  ┌─────────────────────────────────────┐                            │
│  │  User → Google Auth → IAP Tunnel → VM                           │
│  │  (Identity verified, session logged)                             │
│  └─────────────────────────────────────┘                            │
│                                                                       │
│  Monitoring:                                                         │
│  ┌─────────────────────────────────────┐                            │
│  │  Ops Agent → Cloud Monitoring                                    │
│  │  Audit Logs → Cloud Logging                                     │
│  │  CPU Alert → Notification Channel                                │
│  └─────────────────────────────────────┘                            │
└──────────────────────────────────────────────────────────────────────┘
```

### Security Matrix

| Domain | Control | Implementation |
|--------|---------|----------------|
| Boot | Shielded VM | `--shielded-secure-boot --shielded-vtpm` |
| Auth | OS Login | Project metadata: `enable-oslogin=TRUE` |
| Auth | No serial port | Metadata: `serial-port-enable=FALSE` |
| Network | No external IP | `--no-address` |
| Network | IAP only | FW rule: `35.235.240.0/20` |
| Network | Private Google Access | Subnet setting |
| Network | Cloud NAT | For outbound internet |
| IAM | Custom SA | Minimal roles, no default SA |
| IAM | Restricted scopes | `logging-write,monitoring-write` only |
| Data | Encryption at rest | Default (Google-managed) |
| Monitor | Ops Agent | Startup script install |
| Monitor | CPU alert | Alert policy at 80% threshold |
| OS | Auto-updates | `unattended-upgrades` in startup |
| OS | Host firewall | `ufw` allow SSH only |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Deploy the complete hardened VM blueprint using gcloud, then validate every security control.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
export VPC_NAME=hardened-vpc
export SUBNET_NAME=hardened-subnet
export VM_NAME=hardened-vm
export SA_NAME=hardened-vm-sa
```

### Step 2 — Create Custom Service Account

```bash
# Create dedicated SA
gcloud iam service-accounts create $SA_NAME \
    --display-name="Hardened VM Service Account"

# Grant minimal roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter" \
    --condition=None

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/monitoring.metricWriter" \
    --condition=None
```

### Step 3 — Create VPC, Subnet, Firewall

```bash
# VPC
gcloud compute networks create $VPC_NAME \
    --subnet-mode=custom

# Subnet with Private Google Access
gcloud compute networks subnets create $SUBNET_NAME \
    --network=$VPC_NAME \
    --region=$REGION \
    --range=10.20.0.0/24 \
    --enable-private-ip-google-access

# Firewall: IAP SSH only
gcloud compute firewall-rules create ${VPC_NAME}-allow-iap-ssh \
    --network=$VPC_NAME \
    --action=allow \
    --direction=ingress \
    --source-ranges=35.235.240.0/20 \
    --rules=tcp:22 \
    --target-tags=hardened

# Firewall: internal only
gcloud compute firewall-rules create ${VPC_NAME}-allow-internal \
    --network=$VPC_NAME \
    --action=allow \
    --direction=ingress \
    --source-ranges=10.20.0.0/24 \
    --rules=all
```

### Step 4 — Create Cloud NAT

```bash
gcloud compute routers create hardened-router \
    --network=$VPC_NAME \
    --region=$REGION

gcloud compute routers nats create hardened-nat \
    --router=hardened-router \
    --region=$REGION \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges \
    --enable-logging
```

### Step 5 — Enable OS Login at Project Level

```bash
gcloud compute project-info add-metadata \
    --metadata=enable-oslogin=TRUE
```

### Step 6 — Create the Hardened VM

```bash
gcloud compute instances create $VM_NAME \
    --zone=$ZONE \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --network=$VPC_NAME \
    --subnet=$SUBNET_NAME \
    --no-address \
    --tags=hardened \
    --service-account=${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
    --scopes=logging-write,monitoring-write \
    --shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --deletion-protection \
    --metadata=serial-port-enable=FALSE \
    --metadata-from-file=startup-script=<(cat <<'STARTUP'
#!/bin/bash
set -e

LOG_FILE="/var/log/hardening.log"
echo "=== Hardening started: $(date) ===" | tee -a $LOG_FILE

# 1. Enable unattended upgrades
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y unattended-upgrades apt-listchanges
dpkg-reconfigure -plow unattended-upgrades
echo "✓ Unattended upgrades enabled" | tee -a $LOG_FILE

# 2. Install and configure UFW
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
echo "y" | ufw enable
echo "✓ UFW firewall configured" | tee -a $LOG_FILE

# 3. Install Ops Agent
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install
echo "✓ Ops Agent installed" | tee -a $LOG_FILE

# 4. Disable unused services
systemctl disable --now cups 2>/dev/null || true
systemctl disable --now avahi-daemon 2>/dev/null || true
echo "✓ Unused services disabled" | tee -a $LOG_FILE

# 5. Harden SSH config
sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
systemctl restart sshd
echo "✓ SSH hardened" | tee -a $LOG_FILE

echo "=== Hardening completed: $(date) ===" | tee -a $LOG_FILE
STARTUP
)
```

### Step 7 — Validate All Security Controls

```bash
echo "=== HARDENED VM VALIDATION ==="
echo ""

# 1. No external IP
EXT_IP=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
[ -z "$EXT_IP" ] && echo "✅ No external IP" || echo "❌ Has external IP: $EXT_IP"

# 2. Shielded VM
SBOOT=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="value(shieldedInstanceConfig.enableSecureBoot)")
[ "$SBOOT" = "True" ] && echo "✅ Secure Boot enabled" || echo "❌ Secure Boot disabled"

VTPM=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="value(shieldedInstanceConfig.enableVtpm)")
[ "$VTPM" = "True" ] && echo "✅ vTPM enabled" || echo "❌ vTPM disabled"

# 3. Custom SA
SA=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="value(serviceAccounts[0].email)")
echo "$SA" | grep -q "$SA_NAME" && echo "✅ Custom SA: $SA" || echo "❌ SA: $SA"

# 4. Deletion protection
DEL=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="value(deletionProtection)")
[ "$DEL" = "True" ] && echo "✅ Deletion protection on" || echo "❌ Deletion protection off"

# 5. Serial port
gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="json(metadata.items)" | grep -q '"serial-port-enable": "FALSE"' \
    && echo "✅ Serial port disabled" || echo "⚠️  Check serial port setting"

echo ""
echo "=== VALIDATION COMPLETE ==="
```

### Step 8 — SSH via IAP and Verify OS Hardening

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --tunnel-through-iap

# Inside the VM:
# Check hardening log
cat /var/log/hardening.log

# Verify UFW
sudo ufw status

# Verify Ops Agent
sudo systemctl status google-cloud-ops-agent

# Verify unattended upgrades
systemctl status unattended-upgrades

# Verify SSH config
grep -E "PermitRootLogin|PasswordAuthentication|MaxAuthTries" /etc/ssh/sshd_config

# Verify no public IP from inside
curl -sf -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/ \
    && echo "Has access config" || echo "✅ No external access config"

# Verify outbound works (Cloud NAT)
curl -s ifconfig.me && echo " (Cloud NAT IP)"

# Exit
exit
```

### Step 9 — Create Monitoring Alert

```bash
# Alert on high CPU
gcloud monitoring policies create \
    --display-name="Hardened VM CPU Alert" \
    --condition-display-name="CPU > 80%" \
    --condition-filter='resource.type="gce_instance" AND metric.type="compute.googleapis.com/instance/cpu/utilization" AND resource.labels.instance_id=INSTANCE_ID' \
    --condition-threshold-value=0.8 \
    --condition-threshold-comparison=COMPARISON_GT \
    --condition-threshold-duration=300s \
    --combiner=OR 2>/dev/null || echo "Alert creation may need Console (requires notification channel)"
```

### Cleanup

```bash
# Must remove deletion protection first
gcloud compute instances update $VM_NAME --zone=$ZONE --no-deletion-protection
gcloud compute instances delete $VM_NAME --zone=$ZONE --quiet
gcloud compute routers nats delete hardened-nat --router=hardened-router --region=$REGION --quiet
gcloud compute routers delete hardened-router --region=$REGION --quiet
gcloud compute firewall-rules delete ${VPC_NAME}-allow-iap-ssh ${VPC_NAME}-allow-internal --quiet
gcloud compute networks subnets delete $SUBNET_NAME --region=$REGION --quiet
gcloud compute networks delete $VPC_NAME --quiet
gcloud iam service-accounts delete ${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --quiet
gcloud compute project-info remove-metadata --keys=enable-oslogin
```

---

## Part 3 — Revision (15 min)

### Project Checklist

| # | Control | Status |
|---|---------|--------|
| 1 | Custom VPC with private subnet | ☐ |
| 2 | Private Google Access enabled | ☐ |
| 3 | Cloud NAT for outbound internet | ☐ |
| 4 | IAP-only firewall rule | ☐ |
| 5 | No default-allow firewall rules | ☐ |
| 6 | VM with no external IP | ☐ |
| 7 | Shielded VM (Secure Boot + vTPM) | ☐ |
| 8 | Custom service account | ☐ |
| 9 | Minimal scopes (logging + monitoring) | ☐ |
| 10 | OS Login enabled | ☐ |
| 11 | Serial port disabled | ☐ |
| 12 | Deletion protection | ☐ |
| 13 | Ops Agent installed | ☐ |
| 14 | Unattended upgrades | ☐ |
| 15 | Host firewall (ufw) | ☐ |
| 16 | SSH hardened (no root, no password) | ☐ |
| 17 | Monitoring alert configured | ☐ |

### Essential Commands Summary

```bash
# One-command secure VM creation
gcloud compute instances create VM \
    --no-address \
    --shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring \
    --service-account=SA@PROJECT.iam.gserviceaccount.com \
    --scopes=logging-write,monitoring-write \
    --deletion-protection \
    --metadata=serial-port-enable=FALSE \
    --tags=hardened

# SSH via IAP
gcloud compute ssh VM --zone=ZONE --tunnel-through-iap

# Audit Shielded VM
gcloud compute instances describe VM --format="yaml(shieldedInstanceConfig)"
```

---

## Part 4 — Quiz (15 min)

**Question 1: You built this hardened VM. Three months later, a team member asks to add a public IP "just for testing." What's your response?**

<details>
<summary>Show Answer</summary>

**No.** Adding a public IP undoes the core security architecture:

1. It exposes the VM to internet scanning and brute-force SSH attacks
2. It bypasses IAP authentication (direct SSH becomes possible)
3. Audit trail is weakened (IP-based access vs identity-based)
4. Cloud NAT becomes unnecessary for that VM
5. It may violate org policies

**Alternatives:**
- Use IAP tunnelling for SSH access (already configured)
- Use IAP TCP forwarding for port-based testing: `gcloud compute start-iap-tunnel VM PORT`
- If web testing is needed, use a load balancer (public IP on LB, not VM)

The correct pattern is to **never** give VMs public IPs. All external access goes through proxies (LB, IAP).

</details>

**Question 2: The startup script failed midway. The Ops Agent didn't install. How do you rerun just that part?**

<details>
<summary>Show Answer</summary>

Options (in order of preference):

1. **SSH in and run manually:**
   ```bash
   gcloud compute ssh VM --zone=ZONE --tunnel-through-iap
   curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
   sudo bash add-google-cloud-ops-agent-repo.sh --also-install
   ```

2. **Run via gcloud:**
   ```bash
   gcloud compute ssh VM --zone=ZONE --tunnel-through-iap \
       --command="curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh && sudo bash add-google-cloud-ops-agent-repo.sh --also-install"
   ```

3. **Check the hardening log first:**
   ```bash
   gcloud compute ssh VM --tunnel-through-iap --command="cat /var/log/hardening.log"
   ```

4. **Reset startup script** (reruns on restart):
   ```bash
   gcloud compute instances add-metadata VM --metadata=startup-script-rerun=true
   gcloud compute instances stop VM && gcloud compute instances start VM
   ```

</details>

**Question 3: Why do we set `--deletion-protection` on the hardened VM?**

<details>
<summary>Show Answer</summary>

Deletion protection prevents **accidental destruction** of a security-critical VM:

- A misconfigured Terraform `destroy` won't delete it
- A team member running cleanup scripts won't accidentally remove it
- `gcloud compute instances delete` will fail until protection is removed
- Forces a deliberate two-step process: remove protection, then delete

This is the GCP equivalent of Linux `chattr +i` (immutable flag). It doesn't prevent modification, just deletion.

To intentionally delete:
```bash
gcloud compute instances update VM --no-deletion-protection
gcloud compute instances delete VM
```

</details>

**Question 4: This blueprint uses gcloud. How would you make it repeatable for 50 VMs across 3 projects?**

<details>
<summary>Show Answer</summary>

Use **Terraform** with modules:

```hcl
module "hardened_vm" {
  source = "./modules/hardened-vm"

  for_each = var.vm_configs

  project_id = each.value.project
  name       = each.value.name
  zone       = each.value.zone
  network    = each.value.network
  subnet     = each.value.subnet
  sa_email   = each.value.sa_email
}
```

The Terraform module would encode all 17 security controls as defaults, making it impossible to deploy an insecure VM. Benefits over gcloud:

| Aspect | gcloud Script | Terraform Module |
|--------|--------------|-----------------|
| State tracking | None | State file |
| Drift detection | Manual audit | `terraform plan` |
| Multi-project | Multiple scripts | One module, many calls |
| Rollback | Manual | `terraform destroy` |
| Code review | Shell scripts | HCL PR review |
| Compliance | Post-deploy check | Pre-deploy enforcement |

</details>

---

*Congratulations! You've completed Week 11: Security Posture.*
*Next: [Week 12 — Incident Response](../WEEK_12_INCIDENT_RESPONSE/DAY_67_LOGGING_STRATEGY.md)*
