# Day 61 — Shared Responsibility Model

> **Week 11 · Security Posture**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Weeks 9-10 completed

---

## Part 1 — Concept (30 min)

### Shared Responsibility Model

```
┌──────────────────────────────────────────────────────────────┐
│              SHARED RESPONSIBILITY MODEL                      │
│                                                               │
│  WHO IS RESPONSIBLE?                                          │
│                                                               │
│  ┌──────────────────────────────────────────────────┐        │
│  │  GOOGLE's Responsibility                          │        │
│  │  (you CANNOT change these)                        │        │
│  │                                                   │        │
│  │  ✓ Physical security (data centres)              │        │
│  │  ✓ Hardware (servers, disks, network)            │        │
│  │  ✓ Host OS & hypervisor patches                  │        │
│  │  ✓ Network infrastructure (backbone, DDoS)       │        │
│  │  ✓ Encryption at rest (default)                  │        │
│  │  ✓ Google employee access controls               │        │
│  └──────────────────────────────────────────────────┘        │
│                                                               │
│  ┌──────────────────────────────────────────────────┐        │
│  │  CUSTOMER's Responsibility                        │        │
│  │  (you MUST manage these)                          │        │
│  │                                                   │        │
│  │  ✓ IAM: who can access what                      │        │
│  │  ✓ Network security: firewall rules, VPC         │        │
│  │  ✓ Guest OS: patches, hardening, SSH keys        │        │
│  │  ✓ Application security: code, data, config      │        │
│  │  ✓ Data protection: classification, access       │        │
│  │  ✓ Compliance: regulatory requirements           │        │
│  │  ✓ Logging & monitoring: detection, response     │        │
│  └──────────────────────────────────────────────────┘        │
│                                                               │
│  ┌──────────────────────────────────────────────────┐        │
│  │  SHARED                                           │        │
│  │  ✓ Encryption in transit (HTTPS config)          │        │
│  │  ✓ DDoS mitigation (LB/Cloud Armor config)      │        │
│  │  ✓ Audit logging (enable & review)               │        │
│  └──────────────────────────────────────────────────┘        │
└──────────────────────────────────────────────────────────────┘
```

### Linux Analogy

```
On-Premises (you own everything):
  ├── Physical security     ← Your team
  ├── Hardware              ← Your team
  ├── Network               ← Your team
  ├── Host OS               ← Your team (yum update, etc.)
  ├── Guest OS              ← Your team
  ├── Application           ← Your team
  └── Data                  ← Your team

GCP IaaS (Compute Engine):
  ├── Physical security     ← Google
  ├── Hardware              ← Google
  ├── Network infra         ← Google
  ├── Host OS / hypervisor  ← Google
  ├── Guest OS              ← YOU (apt-get upgrade)
  ├── Application           ← YOU
  └── Data                  ← YOU
```

### Security Command Center (SCC)

```
┌──────────────────────────────────────────────────────┐
│          SECURITY COMMAND CENTER                      │
│                                                       │
│  ┌─────────────────┐  ┌──────────────────┐          │
│  │ Security Health  │  │ Threat Detection │          │
│  │ Analytics (SHA)  │  │ (Event Threat    │          │
│  │                  │  │  Detection)      │          │
│  │ - Misconfigs     │  │ - Anomalies      │          │
│  │ - Vulnerabilities│  │ - Malware        │          │
│  │ - Open firewall  │  │ - Crypto-mining  │          │
│  │ - Public buckets │  │ - Suspicious IAM │          │
│  └─────────────────┘  └──────────────────┘          │
│                                                       │
│  ┌─────────────────┐  ┌──────────────────┐          │
│  │ Web Security    │  │ Container Threat │          │
│  │ Scanner         │  │ Detection        │          │
│  │                  │  │                  │          │
│  │ - XSS           │  │ - GKE anomalies  │          │
│  │ - SQLi          │  │ - Node compromise│          │
│  │ - Mixed content │  │                  │          │
│  └─────────────────┘  └──────────────────┘          │
│                                                       │
│  Tiers: Standard (free) │ Premium (paid)             │
└──────────────────────────────────────────────────────┘
```

### Cloud Armor Overview

| Feature                | Description                                    |
|------------------------|------------------------------------------------|
| WAF rules              | OWASP Top 10 protection (SQLi, XSS)           |
| DDoS protection        | Volumetric + protocol attack mitigation        |
| IP allowlist/denylist  | Block by IP/CIDR range                         |
| Geo-based policies     | Allow/deny by country                          |
| Rate limiting          | Throttle requests per IP                       |
| Integration            | Applies to HTTP(S) Load Balancer only          |
| Linux analogy          | `mod_security` + `iptables` + `fail2ban`       |

### Organizational Policies

| Policy                              | Effect                                      |
|--------------------------------------|---------------------------------------------|
| `constraints/compute.vmExternalIpAccess` | Deny external IPs on VMs                 |
| `constraints/iam.allowedPolicyMemberDomains` | Restrict IAM to specific domains     |
| `constraints/compute.restrictLoadBalancerCreationForTypes` | Limit LB types |
| `constraints/gcp.resourceLocations`  | Restrict resources to specific regions      |
| `constraints/compute.requireShieldedVm` | Mandate Shielded VMs                     |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Explore the security posture of your GCP project using SCC findings, audit logs, and basic Cloud Armor setup.

### Step 1 — Check Security Health

```bash
export PROJECT_ID=$(gcloud config get-value project)

# List any Security Command Center findings (if SCC is enabled)
gcloud scc findings list $PROJECT_ID \
    --source="-" \
    --filter="state=\"ACTIVE\"" \
    --format="table(finding.category, finding.severity, finding.resourceName)" \
    --limit=20
```

### Step 2 — Audit Current IAM Bindings

```bash
# List all IAM bindings on the project
gcloud projects get-iam-policy $PROJECT_ID \
    --format="table(bindings.role, bindings.members)"

# Check for overly permissive roles
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.role:roles/owner OR bindings.role:roles/editor" \
    --format="table(bindings.role, bindings.members)"
```

### Step 3 — Check Firewall Rules for Overly Permissive Access

```bash
# Find firewall rules allowing all traffic from 0.0.0.0/0
gcloud compute firewall-rules list \
    --filter="sourceRanges:0.0.0.0/0 AND direction:INGRESS" \
    --format="table(name, allowed[].map().firewall_rule().list(), sourceRanges)"

# Find rules allowing SSH from anywhere
gcloud compute firewall-rules list \
    --filter="sourceRanges:0.0.0.0/0 AND allowed[].ports:22" \
    --format="table(name, sourceRanges, targetTags)"
```

### Step 4 — Check for VMs with External IPs

```bash
# List all VMs with external IPs (potential attack surface)
gcloud compute instances list \
    --format="table(name, zone, networkInterfaces[0].accessConfigs[0].natIP)" \
    --filter="networkInterfaces[0].accessConfigs[0].natIP:*"
```

### Step 5 — Review Audit Logs

```bash
# Admin activity logs (always on, free)
gcloud logging read \
    'logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"' \
    --limit=10 \
    --format="table(timestamp, protoPayload.methodName, protoPayload.authenticationInfo.principalEmail)"

# Data access logs (must be enabled, shows who read what)
gcloud logging read \
    'logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Fdata_access"' \
    --limit=10 \
    --format="table(timestamp, protoPayload.methodName, protoPayload.authenticationInfo.principalEmail)"
```

### Step 6 — Create a Basic Cloud Armor Policy

```bash
# Create security policy
gcloud compute security-policies create demo-armor-policy \
    --description="Demo Cloud Armor policy"

# Add rule: block a specific IP range (example)
gcloud compute security-policies rules create 1000 \
    --security-policy=demo-armor-policy \
    --action=deny-403 \
    --src-ip-ranges="192.168.99.0/24" \
    --description="Block test range"

# Add rule: allow everything else (default)
gcloud compute security-policies rules update 2147483647 \
    --security-policy=demo-armor-policy \
    --action=allow

# List rules
gcloud compute security-policies describe demo-armor-policy

# To attach to a backend service (if you have one):
# gcloud compute backend-services update BACKEND --security-policy=demo-armor-policy --global
```

### Step 7 — Check Organization Policies (if applicable)

```bash
# List effective org policies on the project
gcloud resource-manager org-policies list --project=$PROJECT_ID \
    --format="table(constraint, listPolicy, booleanPolicy)"

# Check specific constraint
gcloud resource-manager org-policies describe \
    constraints/compute.vmExternalIpAccess --project=$PROJECT_ID
```

### Cleanup

```bash
gcloud compute security-policies delete demo-armor-policy --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Shared responsibility**: Google secures the infrastructure; you secure everything above it
- **Customer owns**: IAM, firewall, guest OS patches, application security, data protection
- **Security Command Center**: finds misconfigs, vulnerabilities, threats
- **Cloud Armor**: WAF + DDoS for HTTP(S) LB (like mod_security + iptables)
- **Audit logs**: Admin Activity (always on, free), Data Access (must enable, paid)
- **Org policies**: enforce constraints across projects (no external IPs, region restrictions)
- Key red flags: `0.0.0.0/0` on SSH, roles/owner on user accounts, VMs with public IPs

### Essential Commands

```bash
# IAM audit
gcloud projects get-iam-policy PROJECT

# Firewall audit
gcloud compute firewall-rules list --filter="sourceRanges:0.0.0.0/0"

# VMs with public IPs
gcloud compute instances list --filter="networkInterfaces[0].accessConfigs[0].natIP:*"

# Audit logs
gcloud logging read 'logName=".../cloudaudit.googleapis.com%2Factivity"' --limit=10

# Cloud Armor
gcloud compute security-policies create POLICY
gcloud compute security-policies rules create PRIORITY --security-policy=POLICY --action=deny-403
```

---

## Part 4 — Quiz (15 min)

**Question 1: A production VM running on GCE has an unpatched kernel vulnerability. Whose responsibility is it to patch it?**

<details>
<summary>Show Answer</summary>

**The customer's (your) responsibility.** In the shared responsibility model for IaaS (Compute Engine), Google is responsible for the **host OS and hypervisor** underneath, but the **guest OS** running inside the VM is the customer's responsibility. You must:

1. Regularly run `apt-get upgrade` / `yum update`
2. Use OS Patch Management (part of VM Manager) for automated patching
3. Use custom images with patches pre-applied
4. Monitor for CVEs affecting your OS version

</details>

**Question 2: What is the difference between Security Command Center Standard and Premium tiers?**

<details>
<summary>Show Answer</summary>

| Feature                          | Standard (Free)    | Premium (Paid)         |
|----------------------------------|--------------------|------------------------|
| Security Health Analytics        | Basic findings     | All findings + custom  |
| Event Threat Detection           | ❌                 | ✅ (anomaly detection) |
| Container Threat Detection       | ❌                 | ✅                     |
| Web Security Scanner             | Basic              | Managed scans          |
| Compliance reporting             | ❌                 | ✅ (CIS, PCI, NIST)   |
| Continuous exports               | ❌                 | ✅                     |
| Attack path simulation           | ❌                 | ✅                     |

For most production environments, **Premium** is recommended for threat detection and compliance.

</details>

**Question 3: You find a firewall rule allowing SSH (port 22) from `0.0.0.0/0`. Why is this a problem and what should you do?**

<details>
<summary>Show Answer</summary>

Allowing SSH from `0.0.0.0/0` means **anyone on the internet** can attempt to SSH into your VMs. This creates:
- Brute-force attack surface
- If SSH keys are compromised, direct access from anywhere
- Compliance violations (PCI DSS, CIS benchmarks)

**Fix**: Replace with **IAP (Identity-Aware Proxy) SSH**:
```bash
# Delete the rule
gcloud compute firewall-rules delete allow-ssh-all --quiet

# Create IAP-only SSH rule
gcloud compute firewall-rules create allow-iap-ssh \
    --source-ranges=35.235.240.0/20 \
    --rules=tcp:22 \
    --action=allow

# SSH via IAP
gcloud compute ssh VM_NAME --tunnel-through-iap
```

IAP authenticates the user via Google identity before creating the SSH tunnel.

</details>

**Question 4: An org policy `constraints/compute.vmExternalIpAccess` is enforced. A developer needs a VM with a public IP for testing. What should they do?**

<details>
<summary>Show Answer</summary>

Options (in order of preference):

1. **Don't use a public IP** — use **IAP tunnel** for SSH and **Cloud NAT** for outbound internet access. This is the secure pattern.

2. **Request an exception** — the org admin can add the specific VM's resource name to the policy's allowed list (per-VM exception).

3. **Use a separate project** — create a sandbox project with relaxed policies for testing (with proper guardrails).

The org policy exists for a reason — public IPs are an attack surface. The recommended approach is to **design without public IPs** and use IAP + Cloud NAT instead.

</details>

---

*Next: [Day 62 — IAM Introduction](DAY_62_IAM_INTRO.md)*
