# Day 41 — Ops Runbook: VM Baseline

> **Week 7 — Automation & Ops** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### What Is an Ops Runbook?

An ops runbook is a **standardised procedure** for a common operational task. Unlike a backup runbook (reactive), a VM baseline runbook is **proactive** — it defines how every VM should be built, checked, and maintained.

**Linux analogy:**

| Old Way (Ad Hoc) | Runbook Way |
|---|---|
| "Just spin up a VM and install stuff" | Standard build procedure with checklist |
| "It works on my VM" | Every VM is identical and verified |
| Troubleshoot from scratch each time | Known issues + fixes documented |
| "Call the senior admin" | Escalation path defined |

### VM Provisioning Lifecycle

```
┌──────────────────────────────────────────────────────────────┐
│             VM Provisioning Lifecycle                          │
│                                                               │
│  1. REQUEST                                                   │
│     └── Ticket with: purpose, size, network, access needs     │
│                                                               │
│  2. PRE-FLIGHT CHECKS                                         │
│     ├── Quota available?                                      │
│     ├── Network/subnet exists?                                │
│     ├── IAM roles correct?                                    │
│     ├── Golden image version current?                         │
│     └── Naming convention followed?                           │
│                                                               │
│  3. PROVISIONING                                              │
│     ├── Create VM from template/image                         │
│     ├── Startup script executes (packages, hardening)         │
│     ├── Monitoring agent configured                           │
│     └── Log rotation configured                               │
│                                                               │
│  4. POST-DEPLOYMENT CHECKS                                    │
│     ├── SSH works?                                            │
│     ├── Startup script completed?                             │
│     ├── Required packages installed?                          │
│     ├── Hardening applied?                                    │
│     ├── Monitoring reporting?                                 │
│     ├── DNS/LB updated?                                       │
│     └── Backup schedule attached?                             │
│                                                               │
│  5. HANDOVER                                                  │
│     ├── Update CMDB/inventory                                 │
│     ├── Notify requestor                                      │
│     └── Close ticket                                          │
│                                                               │
│  6. ONGOING OPERATIONS                                        │
│     ├── Patching (unattended-upgrades)                        │
│     ├── Monitoring (alerts)                                   │
│     ├── Backup verification (monthly)                         │
│     └── Image refresh (quarterly)                             │
└──────────────────────────────────────────────────────────────┘
```

### Naming Convention

```
┌─────────────────────────────────────────────────────┐
│           VM Naming Convention                      │
│                                                     │
│  Format: {env}-{role}-{region-code}-{instance}      │
│                                                     │
│  Examples:                                          │
│  prod-web-ew2-001    (production web, europe-west2) │
│  dev-api-ew2-001     (dev API server)               │
│  stg-db-ew2-001      (staging database)             │
│  prod-jump-ew2-001   (production jumpbox)           │
│                                                     │
│  Region codes:                                      │
│  europe-west2 → ew2                                 │
│  us-central1  → uc1                                 │
│  asia-east1   → ae1                                 │
└─────────────────────────────────────────────────────┘
```

### Standard VM Specifications

| Component | Dev/Test | Production |
|---|---|---|
| **Machine type** | e2-micro / e2-small | e2-standard-2+ |
| **Boot disk** | 10 GB pd-standard | 20 GB pd-balanced |
| **Image** | Latest golden-base | Pinned golden-base version |
| **Network** | dev-vpc/dev-subnet | prod-vpc/prod-subnet |
| **Tags** | dev, role | prod, role, monitoring |
| **Service account** | Default (limited) | Custom SA with minimal roles |
| **Snapshot schedule** | None | Daily (boot) + Hourly (data) |
| **Labels** | env=dev, team=X | env=prod, team=X, cost-center=Y |

### Common Troubleshooting

```
┌──────────────────────────────────────────────────────────┐
│          Common Issues Decision Tree                      │
│                                                          │
│  VM won't start?                                         │
│  ├── Check quota: gcloud compute regions describe REGION │
│  ├── Check disk: gcloud compute disks describe DISK      │
│  └── Check serial: get-serial-port-output                │
│                                                          │
│  Can't SSH?                                              │
│  ├── Firewall rule for port 22?                          │
│  ├── IAP tunnel configured?                              │
│  ├── Correct IAM (compute.osLogin)?                      │
│  └── OS Login vs metadata SSH keys?                      │
│                                                          │
│  Startup script didn't run?                              │
│  ├── Check serial output                                 │
│  ├── Check metadata is set correctly                     │
│  ├── GCS script URL accessible?                          │
│  └── Script syntax error? (bash -n check)                │
│                                                          │
│  High disk usage?                                        │
│  ├── Run cleanup script                                  │
│  ├── Check log rotation working                          │
│  ├── Identify large files: du -sh /* --max-depth=1       │
│  └── Resize disk online                                  │
│                                                          │
│  Performance issues?                                     │
│  ├── CPU: top, htop, check machine type                  │
│  ├── Memory: free -h, check for OOM in dmesg            │
│  ├── Disk I/O: iotop, check pd-standard vs pd-ssd       │
│  └── Network: check bandwidth limits for machine type    │
└──────────────────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Goal: Write a Complete VM Provisioning Ops Runbook

### Step 1 — Set Up and Test the Standard Build

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=europe-west2-a
export REGION=europe-west2
export PREFIX="lab41"
export VM_NAME="prod-web-ew2-001"
```

### Step 2 — Pre-Flight Check Script

```bash
cat > /tmp/preflight-check.sh << 'PREFLIGHT_EOF'
#!/bin/bash
#
# Pre-Flight Check Script
# Run before provisioning a new VM
#
set -euo pipefail

echo "============================================"
echo "  PRE-FLIGHT CHECKS"
echo "  $(date)"
echo "============================================"

PROJECT=${1:-$(gcloud config get-value project 2>/dev/null)}
REGION=${2:-europe-west2}
ZONE=${3:-europe-west2-a}

PASS=0
FAIL=0

check() {
    local DESC="$1"
    local CMD="$2"
    if eval "$CMD" > /dev/null 2>&1; then
        echo "  [PASS] $DESC"
        ((PASS++))
    else
        echo "  [FAIL] $DESC"
        ((FAIL++))
    fi
}

echo ""
echo "--- Project & Auth ---"
check "Authenticated to gcloud" "gcloud auth list --filter='status:ACTIVE' --format='value(account)' | grep -q '@'"
check "Project set: ${PROJECT}" "gcloud config get-value project 2>/dev/null | grep -q '${PROJECT}'"

echo ""
echo "--- Quotas ---"
check "CPU quota available" "gcloud compute regions describe ${REGION} --format='value(quotas[].limit)' | head -1"
check "Disk quota available" "gcloud compute regions describe ${REGION} --format='value(quotas[])' | grep -i ssd"

echo ""
echo "--- Network ---"
check "Default network exists" "gcloud compute networks list --filter='name=default' --format='value(name)' | grep -q 'default'"

echo ""
echo "--- Images ---"
check "Debian 12 image available" "gcloud compute images describe-from-family debian-12 --project=debian-cloud --format='value(name)'"

echo ""
echo "============================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "============================================"

if [ ${FAIL} -gt 0 ]; then
    echo "  ⚠ Fix failures before provisioning!"
    exit 1
fi
PREFLIGHT_EOF

chmod +x /tmp/preflight-check.sh
echo "Pre-flight script created"
```

### Step 3 — Provision Using the Standard Procedure

```bash
# Run pre-flight checks
bash /tmp/preflight-check.sh ${PROJECT_ID} ${REGION} ${ZONE}

# Provision the VM following the standard build
gcloud compute instances create ${VM_NAME} \
  --zone=${ZONE} \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=20GB \
  --boot-disk-type=pd-balanced \
  --tags=http-server,monitoring,${PREFIX} \
  --labels=env=prod,team=platform,week=7,day=41 \
  --metadata=startup-script='#!/bin/bash
set -euo pipefail

MARKER="/opt/.baseline-v1-complete"
[ -f "${MARKER}" ] && exit 0

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx curl jq htop iotop fail2ban

# SSH hardening
sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config
systemctl restart sshd

# Kernel hardening
cat > /etc/sysctl.d/99-hardening.conf << SYSEOF
net.ipv4.ip_forward = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.tcp_syncookies = 1
SYSEOF
sysctl -p /etc/sysctl.d/99-hardening.conf

# Monitoring placeholder
cat > /opt/monitor.sh << MONEOF
#!/bin/bash
echo "\$(date -Iseconds) | disk=\$(df / | tail -1 | awk "{print \\\$5}") | mem=\$(free -m | awk "/Mem:/{printf \"%.0f%%\", \\\$3*100/\\\$2}")" >> /var/log/monitor.log
MONEOF
chmod +x /opt/monitor.sh

# Cron: monitoring every 5 min + cleanup weekly
cat > /etc/cron.d/ops-baseline << CRONEOF
*/5 * * * * root /opt/monitor.sh
0 3 * * 0 root apt-get clean -qq && find /tmp -type f -mtime +7 -delete 2>/dev/null
CRONEOF
chmod 644 /etc/cron.d/ops-baseline

systemctl enable nginx fail2ban
systemctl restart nginx fail2ban

touch "${MARKER}"
'

echo "VM provisioned. Waiting for startup script..."
sleep 90
```

### Step 4 — Post-Deployment Check Script

```bash
cat > /tmp/post-deploy-check.sh << 'POSTCHECK_EOF'
#!/bin/bash
#
# Post-Deployment Verification Script
#
set -euo pipefail

VM_NAME="$1"
ZONE="$2"

echo "============================================"
echo "  POST-DEPLOYMENT CHECKS: ${VM_NAME}"
echo "  $(date)"
echo "============================================"

PASS=0
FAIL=0

check() {
    local DESC="$1"
    local CMD="$2"
    if eval "$CMD" > /dev/null 2>&1; then
        echo "  [PASS] $DESC"
        ((PASS++))
    else
        echo "  [FAIL] $DESC"
        ((FAIL++))
    fi
}

# Remote checks via SSH
REMOTE_RESULTS=$(gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command="
echo STARTUP_DONE=\$([ -f /opt/.baseline-v1-complete ] && echo yes || echo no)
echo NGINX=\$(systemctl is-active nginx)
echo FAIL2BAN=\$(systemctl is-active fail2ban)
echo ROOT_LOGIN=\$(grep -c 'PermitRootLogin no' /etc/ssh/sshd_config)
echo IP_FWD=\$(sysctl -n net.ipv4.ip_forward)
echo MONITOR_SCRIPT=\$([ -f /opt/monitor.sh ] && echo yes || echo no)
echo CRON_JOB=\$([ -f /etc/cron.d/ops-baseline ] && echo yes || echo no)
echo CURL_TEST=\$(curl -s -o /dev/null -w '%{http_code}' localhost)
" 2>/dev/null)

echo ""
echo "--- Startup Script ---"
echo "${REMOTE_RESULTS}" | grep -q "STARTUP_DONE=yes" && { echo "  [PASS] Startup script completed"; ((PASS++)); } || { echo "  [FAIL] Startup script not completed"; ((FAIL++)); }

echo ""
echo "--- Services ---"
echo "${REMOTE_RESULTS}" | grep -q "NGINX=active" && { echo "  [PASS] Nginx running"; ((PASS++)); } || { echo "  [FAIL] Nginx not running"; ((FAIL++)); }
echo "${REMOTE_RESULTS}" | grep -q "FAIL2BAN=active" && { echo "  [PASS] Fail2ban running"; ((PASS++)); } || { echo "  [FAIL] Fail2ban not running"; ((FAIL++)); }

echo ""
echo "--- Security ---"
echo "${REMOTE_RESULTS}" | grep -q "ROOT_LOGIN=1" && { echo "  [PASS] Root login disabled"; ((PASS++)); } || { echo "  [FAIL] Root login not disabled"; ((FAIL++)); }
echo "${REMOTE_RESULTS}" | grep -q "IP_FWD=0" && { echo "  [PASS] IP forwarding disabled"; ((PASS++)); } || { echo "  [FAIL] IP forwarding enabled"; ((FAIL++)); }

echo ""
echo "--- Monitoring ---"
echo "${REMOTE_RESULTS}" | grep -q "MONITOR_SCRIPT=yes" && { echo "  [PASS] Monitor script present"; ((PASS++)); } || { echo "  [FAIL] Monitor script missing"; ((FAIL++)); }
echo "${REMOTE_RESULTS}" | grep -q "CRON_JOB=yes" && { echo "  [PASS] Cron job configured"; ((PASS++)); } || { echo "  [FAIL] Cron job missing"; ((FAIL++)); }

echo ""
echo "--- Application ---"
echo "${REMOTE_RESULTS}" | grep -q "CURL_TEST=200" && { echo "  [PASS] HTTP 200 response"; ((PASS++)); } || { echo "  [FAIL] HTTP not responding"; ((FAIL++)); }

echo ""
echo "--- Labels ---"
LABELS=$(gcloud compute instances describe ${VM_NAME} --zone=${ZONE} --format="value(labels)")
echo "${LABELS}" | grep -q "env" && { echo "  [PASS] Labels present"; ((PASS++)); } || { echo "  [FAIL] Labels missing"; ((FAIL++)); }

echo ""
echo "============================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "============================================"

[ ${FAIL} -eq 0 ] && echo "  ✓ VM is READY for service" || echo "  ⚠ VM has issues — check failures above"
POSTCHECK_EOF

chmod +x /tmp/post-deploy-check.sh

# Run it
bash /tmp/post-deploy-check.sh ${VM_NAME} ${ZONE}
```

### Step 5 — Write the Complete Runbook Document

```bash
cat > /tmp/vm-provisioning-runbook.md << 'RUNBOOK_EOF'
# VM Provisioning Ops Runbook

| Field | Value |
|---|---|
| Version | 1.0 |
| Author | V. Brabhaharan |
| Last Updated | 2026-04-08 |
| Region | europe-west2 |

## 1. Purpose

Standard procedure for provisioning production VMs in GCP.

## 2. Pre-Flight Checklist

- [ ] Ticket approved with VM specifications
- [ ] Naming convention followed: `{env}-{role}-{region}-{instance}`
- [ ] Quota checked for region
- [ ] Network/subnet identified
- [ ] Golden image version confirmed
- [ ] Service account prepared (if custom)
- [ ] Labels planned (env, team, cost-center)

## 3. Provisioning Command

```bash
gcloud compute instances create {VM_NAME} \
  --zone=europe-west2-a \
  --machine-type={TYPE} \
  --image-family=golden-base \
  --boot-disk-size=20GB \
  --boot-disk-type=pd-balanced \
  --tags={role},monitoring \
  --labels=env={env},team={team} \
  --scopes=monitoring-write,logging-write \
  --metadata=startup-script-url=gs://{BUCKET}/golden-setup.sh
```

## 4. Post-Deployment Checklist

- [ ] Startup script completed (`/opt/.baseline-complete` exists)
- [ ] Nginx/application running
- [ ] SSH hardening applied (PermitRootLogin no)
- [ ] Kernel hardening applied (ip_forward=0)
- [ ] Fail2ban active
- [ ] Monitoring script running (cron)
- [ ] Log rotation configured
- [ ] Snapshot schedule attached (production only)
- [ ] Labels correct
- [ ] HTTP/application responding

## 5. Troubleshooting

| Issue | Diagnosis | Fix |
|---|---|---|
| VM won't create | Quota exceeded | Request quota increase |
| Startup script fails | Serial output shows error | Fix script, re-run: `google_metadata_script_runner startup` |
| Can't SSH | Firewall missing port 22 | Add firewall rule or use IAP tunnel |
| High disk usage | Logs not rotated | Check logrotate config, run cleanup |
| Performance slow | Undersized VM | Resize machine type (stop → resize → start) |

## 6. Escalation

| Level | Contact | When |
|---|---|---|
| L1 | On-call engineer | Standard issues (startup fails, SSH) |
| L2 | Platform team lead | Network/IAM issues |
| L3 | Cloud architect | Design changes, capacity planning |
RUNBOOK_EOF

echo "Runbook written to /tmp/vm-provisioning-runbook.md"
```

### Cleanup

```bash
# Delete VM
gcloud compute instances delete ${VM_NAME} --zone=${ZONE} --quiet

# Clean local files
rm -f /tmp/preflight-check.sh /tmp/post-deploy-check.sh /tmp/vm-provisioning-runbook.md
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Ops runbooks** standardise common tasks — predictable, trainable, auditable
- VM provisioning lifecycle: Request → Pre-flight → Provision → Post-check → Handover
- **Pre-flight checks**: quota, network, IAM, image version, naming convention
- **Post-deployment checks**: startup complete, services running, hardening applied, monitoring active
- **Naming convention** enables quick identification: `{env}-{role}-{region}-{instance}`
- Always include **troubleshooting** and **escalation** sections
- Automate the checks with scripts — don't rely on humans remembering

### Checklist Template

```
PRE-FLIGHT
  [ ] Quota available
  [ ] Network/subnet ready
  [ ] Golden image current
  [ ] Naming convention correct
  [ ] Labels planned

POST-DEPLOYMENT
  [ ] Startup script done
  [ ] Services running
  [ ] Hardening applied
  [ ] Monitoring active
  [ ] Backup scheduled
  [ ] HTTP responding
```

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: Why separate pre-flight checks from post-deployment checks? Can't you just check everything after?</strong></summary>

**Answer:** Pre-flight checks **prevent wasted time and resources:**

1. **Quota check** — discovering quota is exceeded after a 2-minute `gcloud create` +" 90-second startup script fails is a 3+ minute waste, multiplied by debugging time
2. **Network check** — if the subnet doesn't exist, the VM creates but can't communicate
3. **Image check** — using an outdated image means deploying a VM that immediately needs patching
4. **Permission check** — failing halfway through provisioning can leave orphaned resources

**Post-deployment checks verify the outcome** — the VM is correctly configured and ready for service. They catch issues that only manifest after boot (startup script failures, service conflicts).

**Analogy:** Airline pilots use pre-flight checklists before takeoff AND post-landing checks. Both are essential but serve different purposes.
</details>

<details>
<summary><strong>Q2: A new team member provisions a VM but names it "test-server-1". What problems does this cause?</strong></summary>

**Answer:** Without a naming convention:

1. **Unknown purpose** — is this dev? staging? prod? What role does it serve?
2. **Unknown location** — which region/zone? Can't tell from the name
3. **Inventory confusion** — when scanning 200 VMs, "test-server-1" tells you nothing
4. **Billing** — can't attribute costs to a team or environment
5. **Automation** — scripts that filter by name pattern (`prod-*`) won't find it
6. **Cleanup** — nobody knows if it's safe to delete

**Fix:** Enforce naming via automation — the provisioning script/Terraform should validate names against the pattern:
```
{env}-{role}-{region-code}-{NNN}
```
Example: `dev-web-ew2-001`
</details>

<details>
<summary><strong>Q3: Your post-deployment script shows that the startup script marker file is missing, but the VM shows RUNNING. What do you check?</strong></summary>

**Answer:** Systematic debugging:

1. **Serial output** (most informative):
   ```bash
   gcloud compute instances get-serial-port-output VM --zone=ZONE | tail -50
   ```
   Look for error messages, the `startup-script exit status` line, or script output

2. **Systemd journal:**
   ```bash
   journalctl -u google-startup-scripts.service --no-pager
   ```

3. **Metadata check** — is the script actually set?
   ```bash
   gcloud compute instances describe VM --format="value(metadata.items)"
   ```

4. **Manual re-run:**
   ```bash
   sudo google_metadata_script_runner startup
   ```
   Watch for errors in real-time

5. **Common causes:** Missing `#!/bin/bash` shebang, script URL inaccessible (permissions on GCS), dependency install failed (`apt-get` couldn't reach mirrors), `set -e` stopped on a non-critical error
</details>

<details>
<summary><strong>Q4: How would you evolve this manual runbook into a fully automated VM provisioning pipeline?</strong></summary>

**Answer:** Progressive automation:

1. **Current state:** Manual gcloud commands + verification scripts (this lab)

2. **Next step — Terraform:**
   - Define VM, disks, firewall, IAM as code
   - `terraform plan` = pre-flight check
   - `terraform apply` = provisioning
   - Post-deploy script as a `null_resource` with `remote-exec`

3. **CI/CD pipeline:**
   - Terraform in a Git repo with PR reviews
   - CI (Cloud Build) runs `terraform plan` on PR
   - Merge triggers `terraform apply`
   - Post-apply step runs verification script

4. **Self-service portal:**
   - Internal tool where teams request VMs via form
   - Backend triggers Terraform pipeline
   - Auto-assigns name, labels, network based on team/env
   - Auto-runs post-deployment checks
   - Notifies team on completion

5. **Policy guardrails:**
   - Organization policies enforce machine types, regions
   - Sentinel/OPA validates Terraform plans
   - All VMs must come from approved golden images
</details>
