# Day 45 — Troubleshooting Notes

> **Week 8 — Portfolio & Review** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### The Troubleshooting Mindset

With 6 years of Linux infra, you've debugged countless issues. In GCP, the same systematic approach applies, but the tools and error surfaces are different.

**Linux analogy:**

| Linux Debugging | GCP Debugging |
|---|---|
| `dmesg`, `journalctl` | Serial console output, Cloud Logging |
| `strace` / `ltrace` | Cloud Audit Logs, VPC Flow Logs |
| `tcpdump` / `netstat` | Firewall rule logs, Packet Mirroring |
| `/var/log/messages` | Logs Explorer |
| `top` / `htop` / `iostat` | Cloud Monitoring metrics |
| `iptables -L` | `gcloud compute firewall-rules list` |

### Debugging Methodology

```
┌──────────────────────────────────────────────────────────┐
│              5-Step Debugging Framework                    │
│                                                          │
│  1. SYMPTOMS                                             │
│     What exactly is failing?                             │
│     Error message? Timeout? Wrong output?                │
│     When did it last work?                               │
│                                                          │
│  2. HYPOTHESIS                                           │
│     Based on symptoms, what are the likely causes?       │
│     List 3-5 possibilities, rank by probability          │
│                                                          │
│  3. TEST                                                 │
│     Test the most likely hypothesis first                │
│     Use the right tool (logs, metrics, commands)         │
│     Change ONE thing at a time                            │
│                                                          │
│  4. FIX                                                  │
│     Apply the fix                                        │
│     Verify the fix resolves the issue                    │
│     Check for side effects                               │
│                                                          │
│  5. DOCUMENT                                             │
│     Record: symptom, cause, fix                          │
│     Add to troubleshooting guide                         │
│     Update runbook if procedure gap                      │
└──────────────────────────────────────────────────────────┘
```

### Error Categories

| Category | Example Symptoms | Primary Debug Tool |
|---|---|---|
| **Compute** | VM won't start, SSH fails | Serial output, IAM |
| **Network** | Can't reach VM, timeout | Firewall rules, VPC Flow Logs |
| **Storage** | Permission denied on GCS | IAM, bucket ACLs |
| **Startup** | Script didn't execute | Serial output, journalctl |
| **Terraform** | Apply fails, state drift | `terraform plan`, state inspection |
| **Quota** | Create fails with 403 | `gcloud compute regions describe` |
| **IAM** | Permission denied | Policy troubleshooter, audit logs |

### Key Debugging Commands

```
┌──────────────────────────────────────────────────────────┐
│            GCP Debugging Swiss Army Knife                 │
│                                                          │
│  COMPUTE:                                                │
│  gcloud compute instances describe VM --zone=ZONE        │
│  gcloud compute instances get-serial-port-output VM      │
│  gcloud compute ssh VM --zone=ZONE --troubleshoot        │
│                                                          │
│  NETWORK:                                                │
│  gcloud compute firewall-rules list --filter="..."       │
│  gcloud compute networks subnets list                    │
│  gcloud compute routes list                              │
│                                                          │
│  IAM:                                                    │
│  gcloud projects get-iam-policy PROJECT                  │
│  gcloud policy-troubleshoot iam RESOURCE --permission=P  │
│                                                          │
│  STORAGE:                                                │
│  gsutil iam get gs://BUCKET                              │
│  gsutil ls -L gs://BUCKET/OBJECT                         │
│                                                          │
│  LOGGING:                                                │
│  gcloud logging read "resource.type=gce_instance"        │
│  gcloud logging read "severity>=ERROR" --limit=20        │
│                                                          │
│  QUOTA:                                                  │
│  gcloud compute regions describe REGION                  │
│  gcloud compute project-info describe --project=PROJECT  │
└──────────────────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Goal: Document Troubleshooting Guides for Common Issues

### Troubleshooting Guide 1: VM and SSH Issues

```bash
cat > /tmp/troubleshoot-compute.md << 'EOF'
# Troubleshooting: Compute & SSH

## Issue: VM Won't Start

### Symptoms
- `gcloud compute instances start VM` returns error
- Console shows "TERMINATED" or "STAGING" indefinitely

### Diagnosis

```bash
# Check VM status
gcloud compute instances describe VM --zone=europe-west2-a \
  --format="value(status,statusMessage)"

# Check quota
gcloud compute regions describe europe-west2 \
  --format="table(quotas.metric,quotas.limit,quotas.usage)" \
  | grep -i "cpu\|ssd\|instance"

# Check serial output for errors
gcloud compute instances get-serial-port-output VM \
  --zone=europe-west2-a 2>/dev/null | tail -30
```

### Common Causes & Fixes

| Cause | Error | Fix |
|---|---|---|
| CPU quota exceeded | `QUOTA_EXCEEDED` | Request quota increase or use smaller machine |
| Disk quota exceeded | `QUOTA_EXCEEDED` | Delete unused disks |
| Invalid machine type for zone | `ZONE_RESOURCE_POOL_EXHAUSTED` | Try different zone |
| Boot disk corrupted | Kernel panic in serial | Detach disk, attach to rescue VM |
| Service account deleted | Permission error | Recreate SA or use default |

---

## Issue: Can't SSH to VM

### Symptoms
- `gcloud compute ssh VM` hangs or returns "Connection timed out"
- or "Permission denied (publickey)"

### Diagnosis

```bash
# Step 1: Is the VM running?
gcloud compute instances describe VM --zone=europe-west2-a \
  --format="value(status)"

# Step 2: Does the VM have an external IP (or are you using IAP)?
gcloud compute instances describe VM --zone=europe-west2-a \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)"

# Step 3: Is there a firewall rule allowing SSH?
gcloud compute firewall-rules list \
  --filter="allowed[].ports:22" \
  --format="table(name,sourceRanges,targetTags)"

# Step 4: Try SSH with verbose output
gcloud compute ssh VM --zone=europe-west2-a --ssh-flag="-vvv" 2>&1 | tail -30

# Step 5: Try IAP tunnel
gcloud compute ssh VM --zone=europe-west2-a --tunnel-through-iap

# Step 6: Check OS Login vs metadata keys
gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items.filter(key:enable-oslogin))"
```

### Decision Tree

```
Can't SSH?
├── VM not running → Start it
├── No external IP
│   ├── Use IAP: --tunnel-through-iap
│   └── Check IAP firewall rule (35.235.240.0/20)
├── External IP exists
│   ├── Firewall rule for SSH? → Check tags match
│   └── Firewall source range includes your IP?
├── Permission denied
│   ├── OS Login enabled? → Check IAM roles (osLogin / osAdminLogin)
│   └── Metadata SSH keys? → Check project/instance metadata
└── Timeout
    ├── Network issue → Check VPC routes
    └── Guest agent not running → Check serial output
```
EOF

echo "Compute troubleshooting guide written"
```

### Troubleshooting Guide 2: Network Issues

```bash
cat > /tmp/troubleshoot-network.md << 'EOF'
# Troubleshooting: Network

## Issue: VM Can't Reach the Internet

### Symptoms
- `apt-get update` fails with timeout
- `curl google.com` hangs
- `ping 8.8.8.8` fails

### Diagnosis

```bash
# On the VM:
# 1. Check if it has an external IP
curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip
# Empty = no external IP

# 2. Check routes
ip route show
# Should see default via 10.x.x.1

# 3. Check DNS
cat /etc/resolv.conf
# Should show 169.254.169.254 (GCP metadata DNS proxy)
nslookup google.com

# From outside the VM:
# 4. Check Cloud NAT
gcloud compute routers list --filter="region=europe-west2"
gcloud compute routers nats list --router=ROUTER --region=europe-west2

# 5. Check egress firewall
gcloud compute firewall-rules list --filter="direction=EGRESS"
```

### Common Causes & Fixes

| Cause | Fix |
|---|---|
| No external IP + no Cloud NAT | Add Cloud NAT or add external IP |
| Egress firewall rule blocking | Check/add allow egress rule |
| Subnet has no routes to internet | Check routing table |
| DNS not resolving | Use metadata DNS (169.254.169.254) |
| Cloud NAT not attached to router | Attach NAT to the router in the correct region |

---

## Issue: Can't Reach a VM from Another VM

### Diagnosis

```bash
# 1. Are they in the same VPC?
gcloud compute instances describe VM1 --zone=ZONE \
  --format="value(networkInterfaces[0].network)"
gcloud compute instances describe VM2 --zone=ZONE \
  --format="value(networkInterfaces[0].network)"

# 2. Firewall rules allowing internal traffic?
gcloud compute firewall-rules list \
  --filter="allowed[].ports:PORT AND sourceRanges:10.0.0.0/8"

# 3. From VM1, can you reach VM2's internal IP?
ping 10.0.1.X
telnet 10.0.1.X 80
```

### Fix
```bash
# Allow internal traffic between tagged VMs
gcloud compute firewall-rules create allow-internal \
  --network=VPC_NAME \
  --allow=tcp,udp,icmp \
  --source-ranges=10.0.0.0/8
```
EOF

echo "Network troubleshooting guide written"
```

### Troubleshooting Guide 3: Terraform Issues

```bash
cat > /tmp/troubleshoot-terraform.md << 'EOF'
# Troubleshooting: Terraform

## Issue: Terraform Apply Fails

### Common Errors

| Error | Cause | Fix |
|---|---|---|
| `403 Forbidden` | Missing IAM role | Grant Terraform SA the needed role |
| `QUOTA_EXCEEDED` | Resource quota hit | Request increase or reduce resources |
| `ALREADY_EXISTS` | Resource exists outside TF | Import: `terraform import TYPE.NAME ID` |
| `RESOURCE_NOT_FOUND` | Dependency deleted | Remove from state: `terraform state rm` |
| `Provider error` | Wrong version / misconfigured | Check `required_providers` version |

### Diagnosis

```bash
# Detailed apply output
terraform apply -auto-approve 2>&1 | tee apply.log

# Check state
terraform state list
terraform state show TYPE.NAME

# Refresh state (sync with real world)
terraform refresh

# Plan to see what TF thinks needs changing
terraform plan -out=plan.tfplan
terraform show plan.tfplan
```

---

## Issue: State Drift (Resources Changed Outside Terraform)

### Symptoms
- `terraform plan` shows changes you didn't make
- Resources exist that aren't in state
- Resources in state no longer exist

### Fix

```bash
# Option 1: Accept the drift — refresh state
terraform refresh

# Option 2: Revert the drift — apply to restore desired state
terraform apply

# Option 3: Import existing resource into state
terraform import google_compute_instance.vm projects/PROJECT/zones/ZONE/instances/VM

# Option 4: Remove from state (if resource was manually deleted)
terraform state rm google_compute_instance.vm
```

---

## Issue: Terraform Destroy Hangs

### Common Causes
- Resource has `deletion_protection = true`
- Dependencies not properly declared
- GCS bucket not empty

### Fix

```bash
# Disable deletion protection
gcloud compute instances update VM --zone=ZONE --no-deletion-protection

# Empty the bucket first
gsutil rm -r gs://BUCKET/**

# Force destroy a specific resource
terraform destroy -target=google_compute_instance.vm
```
EOF

echo "Terraform troubleshooting guide written"
```

### Troubleshooting Guide 4: Startup Script Issues

```bash
cat > /tmp/troubleshoot-startup.md << 'EOF'
# Troubleshooting: Startup Scripts

## Issue: Startup Script Didn't Run

### Diagnosis

```bash
# 1. Check serial output (most informative)
gcloud compute instances get-serial-port-output VM \
  --zone=europe-west2-a 2>/dev/null | grep -i "startup"

# 2. Check metadata is set
gcloud compute instances describe VM --zone=europe-west2-a \
  --format="yaml(metadata.items)"

# 3. SSH in and check logs
journalctl -u google-startup-scripts.service --no-pager
cat /var/log/syslog | grep -i startup

# 4. Check if script URL is accessible
# (if using startup-script-url)
gsutil cat gs://BUCKET/script.sh | head -5
```

### Common Causes

| Cause | Symptom | Fix |
|---|---|---|
| Missing shebang (`#!/bin/bash`) | Script not executed | Add `#!/bin/bash` as first line |
| Script URL inaccessible | "Failed to download" in serial | Check GCS permissions + VM scopes |
| Syntax error in script | Partial execution | Test: `bash -n script.sh` |
| `set -e` exits on non-critical error | Script stops early | Use `|| true` for optional commands |
| Metadata key typo | Script ignored | Use exact key: `startup-script` |

### Manual Re-run

```bash
# Re-run startup script without rebooting
sudo google_metadata_script_runner startup

# Or re-run from metadata directly
curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/startup-script \
  | sudo bash
```
EOF

echo "Startup script troubleshooting guide written"
```

### Step 5 — Create Master Troubleshooting Index

```bash
cat > /tmp/troubleshooting-index.md << 'EOF'
# Troubleshooting Index

Quick reference for common GCP infrastructure issues.

## Quick Diagnosis Commands

```bash
# VM status
gcloud compute instances describe VM --zone=ZONE --format="value(status)"

# Serial console
gcloud compute instances get-serial-port-output VM --zone=ZONE

# Firewall rules
gcloud compute firewall-rules list --format="table(name,direction,allowed[],sourceRanges,targetTags)"

# IAM check
gcloud projects get-iam-policy PROJECT --format="table(bindings.role,bindings.members)"

# Recent errors
gcloud logging read "severity>=ERROR" --limit=10 --format="table(timestamp,textPayload)"

# Quota check
gcloud compute regions describe REGION --format="table(quotas.metric,quotas.limit,quotas.usage)"
```

## Issue Categories

| Category | Guide | Key Tools |
|---|---|---|
| VM & SSH | [Compute Guide](troubleshoot-compute.md) | Serial output, IAM, firewall |
| Networking | [Network Guide](troubleshoot-network.md) | Firewall rules, routes, NAT |
| Terraform | [Terraform Guide](troubleshoot-terraform.md) | State, plan, import |
| Startup Scripts | [Startup Guide](troubleshoot-startup.md) | Serial, journalctl, metadata |
| Storage | Check IAM + bucket policies | gsutil iam, bucket info |
| Monitoring | Check Ops Agent status | systemctl status google-cloud-ops-agent |
EOF

echo "Master troubleshooting index written"
```

### Cleanup

```bash
rm -f /tmp/troubleshoot-*.md /tmp/troubleshooting-index.md
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **5-step framework:** Symptom → Hypothesis → Test → Fix → Document
- **Serial console output** is the #1 diagnostic tool for VM issues
- **Firewall rules** are the #1 cause of network connectivity issues
- **State drift** is the #1 Terraform issue in multi-person teams
- Always check **quota** before blaming code for creation failures
- Document **every** issue you solve — future you will thank present you

### Top Debugging Commands

```bash
# The Big Five:
gcloud compute instances get-serial-port-output VM --zone=ZONE
gcloud compute firewall-rules list
gcloud logging read "severity>=ERROR" --limit=10
terraform plan                          # Shows drift
gcloud compute regions describe REGION  # Shows quotas
```

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: A new VM is RUNNING but you can't SSH to it. Walk through your debugging steps in order.</strong></summary>

**Answer:**

1. **External IP?** `gcloud compute instances describe VM --format="value(networkInterfaces[0].accessConfigs[0].natIP)"`
   - No IP → try IAP: `gcloud compute ssh VM --tunnel-through-iap`

2. **Firewall?** `gcloud compute firewall-rules list --filter="allowed[].ports:22"`
   - Check source ranges include your IP or IAP range (35.235.240.0/20)
   - Check target tags match the VM's tags

3. **OS Login vs SSH keys?** `gcloud compute project-info describe --format="value(commonInstanceMetadata.items)"`
   - OS Login enabled → need `roles/compute.osLogin`
   - OS Login disabled → check SSH keys in metadata

4. **Guest agent?** Check serial output for guest agent startup
   - If no serial output → VM may be stuck in boot

5. **Last resort:** Stop VM, detach boot disk, attach to rescue VM, check `/var/log/auth.log`
</details>

<details>
<summary><strong>Q2: Terraform plan shows 4 resources will be destroyed and recreated, but you didn't change your TF code. What happened?</strong></summary>

**Answer:** **State drift** — resources were modified outside Terraform. Common causes:

1. Someone used `gcloud` to change a VM (labels, metadata, machine type)
2. Console was used to modify firewall rules
3. A scheduled process (snapshot schedule, auto-update) changed metadata

**Diagnosis:**
```bash
terraform plan  # Shows what will change and why
terraform state show google_compute_instance.vm  # Current state
gcloud compute instances describe VM  # Real world
```

**Resolution (choose one):**
- `terraform refresh` → accept the drift (update state to match reality)
- `terraform apply` → revert the drift (make reality match TF code)
- Update TF code to match the new reality → `terraform apply` (no changes)
</details>

<details>
<summary><strong>Q3: Your startup script used to work but stopped after you changed the GCS bucket permissions. How do you diagnose?</strong></summary>

**Answer:**

1. **Check serial output** for the download error:
   ```bash
   gcloud compute instances get-serial-port-output VM --zone=ZONE | grep -i "startup\|error\|download"
   ```
   Look for: "Failed to download startup-script-url"

2. **Check VM scopes:**
   ```bash
   gcloud compute instances describe VM --format="value(serviceAccounts[0].scopes)"
   ```
   Must include `storage-ro` or `cloud-platform`

3. **Check bucket IAM:**
   ```bash
   gsutil iam get gs://BUCKET
   ```
   The VM's service account must have `storage.objects.get`

4. **Test the URL manually from the VM:**
   ```bash
   gcloud compute ssh VM --command="
     curl -s -H 'Metadata-Flavor: Google' \
       http://metadata.google.internal/computeMetadata/v1/instance/attributes/startup-script-url
     gsutil cat gs://BUCKET/script.sh | head -3"
   ```
</details>

<details>
<summary><strong>Q4: Why is documenting troubleshooting steps valuable for your career, beyond just solving the immediate problem?</strong></summary>

**Answer:**

1. **Portfolio evidence** — shows operational experience, not just provisioning skills
2. **Interview gold** — "Tell me about a time you debugged a difficult issue" → you have documented examples with exact steps
3. **Team force multiplier** — your troubleshooting guides help the whole team, reducing tickets and on-call burden
4. **Pattern recognition** — documenting builds your mental model; after 10 issues, you see patterns faster
5. **Reduced MTTR** — next time the same issue occurs, the fix is documented and immediate
6. **Professional habit** — SRE/DevOps culture values documentation; this demonstrates cultural fit
</details>
