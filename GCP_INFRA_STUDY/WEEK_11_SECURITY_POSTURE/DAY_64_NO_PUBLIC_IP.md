# Day 64 — No Public IP Approach

> **Week 11 · Security Posture**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 63 completed

---

## Part 1 — Concept (30 min)

### Why No Public IP?

```
With Public IP:                    Without Public IP:
┌──────────┐                      ┌──────────┐
│ Internet │                      │ Internet │
│ (anyone) │                      │ (anyone) │
└────┬─────┘                      └────┬─────┘
     │ Direct SSH/HTTP                  │
     │ attacks possible                 │ BLOCKED — no route
     ▼                                  │
┌──────────┐                            │
│  VM      │                      ┌─────┴──────┐
│ 34.x.x.x│ ← Attack surface     │ IAP Tunnel │ ← Authenticated
└──────────┘                      └─────┬──────┘   identity check
                                        │
                                  ┌──────────┐
                                  │  VM      │
                                  │ 10.x.x.x│ ← No direct access
                                  └──────────┘
```

### No-Public-IP Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│              NO-PUBLIC-IP ARCHITECTURE                             │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │                    VPC: secure-vpc                        │     │
│  │                                                          │     │
│  │  ┌──────────────┐  ┌──────────────┐                     │     │
│  │  │  VM (no ext  │  │  VM (no ext  │                     │     │
│  │  │  IP) 10.0.1.5│  │  IP) 10.0.1.6│                     │     │
│  │  └──────┬───────┘  └──────┬───────┘                     │     │
│  │         │                  │                              │     │
│  │         └────────┬─────────┘                              │     │
│  │                  │                                        │     │
│  │         ┌────────┴────────┐                               │     │
│  │         │                 │                               │     │
│  │    ┌────┴──────┐    ┌────┴──────────┐                    │     │
│  │    │ Cloud NAT │    │ Private Google│                    │     │
│  │    │ (outbound │    │ Access (PGA)  │                    │     │
│  │    │  internet)│    │ (GCP APIs)    │                    │     │
│  │    └────┬──────┘    └───────────────┘                    │     │
│  │         │                                                 │     │
│  └─────────┼─────────────────────────────────────────────────┘     │
│            │                                                       │
│            ▼                                                       │
│       Internet                                                     │
│       (apt-get, pip, etc.)                                        │
│                                                                   │
│  ACCESS METHODS:                                                  │
│  ┌──────────────────┐                                            │
│  │ IAP SSH Tunnel   │ ← For admin SSH access                     │
│  │ 35.235.240.0/20  │   (authenticates via Google identity)      │
│  └──────────────────┘                                            │
│  ┌──────────────────┐                                            │
│  │ Bastion Host     │ ← Legacy pattern (less preferred)          │
│  │ (jump box)       │   One VM with public IP, SSH to others     │
│  └──────────────────┘                                            │
└──────────────────────────────────────────────────────────────────┘
```

### Component Comparison

| Component              | Purpose                                    | Linux Analogy                    |
|------------------------|--------------------------------------------|----------------------------------|
| **IAP Tunnel**         | Authenticated SSH without public IP        | SSH bastion + LDAP auth          |
| **Cloud NAT**          | Outbound internet for VMs without pub IP   | `iptables -t nat MASQUERADE`     |
| **Private Google Access** | Access Google APIs from private VMs     | DNS redirect to internal proxy   |
| **VPC Service Controls** | Prevent data exfiltration from VPC       | Network-level DLP perimeter      |
| **Bastion Host**       | Jump box with public IP                    | SSH ProxyJump                    |

### IAP (Identity-Aware Proxy) for SSH

```
Traditional SSH:                    IAP SSH:
┌──────┐  SSH (port 22)  ┌────┐   ┌──────┐  HTTPS  ┌─────┐  SSH  ┌────┐
│ User │ ──────────────→  │ VM │   │ User │ ──────→ │ IAP │ ────→ │ VM │
└──────┘ (direct, risky)  └────┘   └──────┘         └─────┘       └────┘
                                   │                 │
                                   ├─ Google Login   ├─ Checks IAM
                                   ├─ MFA            │  permissions
                                   └─ Any network    ├─ Logs all
                                                     │  sessions
                                                     └─ Source IP:
                                                        35.235.240.0/20
```

### Cloud NAT vs Public IP

| Feature         | Public IP                    | Cloud NAT                         |
|-----------------|------------------------------|-----------------------------------|
| Inbound access  | Yes (attack surface)         | No (NAT is outbound-only)         |
| Outbound access | Yes                          | Yes (via NAT gateway)             |
| Cost            | Ephemeral IP is free         | NAT gateway charges per GB + hour |
| Security        | Directly reachable           | Not reachable from internet       |
| Linux analogy   | eth0 with public IP          | eth0 behind NAT router            |

### Private Google Access (PGA)

```
Without PGA:                         With PGA:
VM (no pub IP)                       VM (no pub IP)
│                                    │
├── curl googleapis.com              ├── curl googleapis.com
│   → FAILS (no internet)           │   → WORKS (routed internally)
│                                    │
└── apt-get update                   └── apt-get update
    → FAILS                              → Still needs Cloud NAT
```

PGA allows VMs **without external IPs** to reach Google APIs (Cloud Storage, BigQuery, etc.) through Google's internal network. It does NOT provide general internet access — you still need Cloud NAT for `apt-get`.

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Build a complete no-public-IP architecture: private VM, IAP SSH, Cloud NAT for outbound, and Private Google Access.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Step 2 — Create VPC with Private Subnet

```bash
# Create custom VPC
gcloud compute networks create secure-vpc \
    --subnet-mode=custom

# Create subnet with Private Google Access enabled
gcloud compute networks subnets create secure-subnet \
    --network=secure-vpc \
    --region=$REGION \
    --range=10.10.0.0/24 \
    --enable-private-ip-google-access
```

### Step 3 — Create Firewall Rules

```bash
# Allow IAP SSH only
gcloud compute firewall-rules create secure-allow-iap-ssh \
    --network=secure-vpc \
    --action=allow \
    --direction=ingress \
    --source-ranges=35.235.240.0/20 \
    --rules=tcp:22 \
    --target-tags=secure-vm

# Allow internal communication
gcloud compute firewall-rules create secure-allow-internal \
    --network=secure-vpc \
    --action=allow \
    --direction=ingress \
    --source-ranges=10.10.0.0/24 \
    --rules=all
```

### Step 4 — Create Cloud NAT

```bash
# Create Cloud Router (required for NAT)
gcloud compute routers create secure-router \
    --network=secure-vpc \
    --region=$REGION

# Create Cloud NAT
gcloud compute routers nats create secure-nat \
    --router=secure-router \
    --region=$REGION \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges \
    --enable-logging
```

### Step 5 — Create Private VM (No External IP)

```bash
gcloud compute instances create private-vm \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --network=secure-vpc \
    --subnet=secure-subnet \
    --no-address \
    --tags=secure-vm \
    --metadata=startup-script='#!/bin/bash
echo "Private VM started at $(date)" >> /var/log/startup.log'
```

### Step 6 — Verify No External IP

```bash
gcloud compute instances describe private-vm \
    --zone=$ZONE \
    --format="yaml(networkInterfaces[0].networkIP, networkInterfaces[0].accessConfigs)"
# Should show internal IP only, no accessConfigs (no external IP)
```

### Step 7 — SSH via IAP

```bash
# SSH through IAP tunnel (no public IP needed)
gcloud compute ssh private-vm \
    --zone=$ZONE \
    --tunnel-through-iap

# Inside the VM, verify no external IP
curl -sf -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/
# Should be empty or error

# Test outbound internet (via Cloud NAT)
curl -s ifconfig.me
# Should show Cloud NAT's external IP

# Test apt-get (via Cloud NAT)
sudo apt-get update

# Test Google API access (via Private Google Access)
gsutil ls gs://gcp-public-data-landsat/ 2>&1 | head -3

# Exit
exit
```

### Step 8 — Verify Cloud NAT Logging

```bash
gcloud logging read \
    'resource.type="nat_gateway" AND resource.labels.router_id="secure-router"' \
    --limit=5 \
    --format="table(timestamp, jsonPayload.connection.src_ip, jsonPayload.connection.dest_ip)"
```

### Step 9 — Test Private Google Access

```bash
# Temporarily disable PGA
gcloud compute networks subnets update secure-subnet \
    --region=$REGION \
    --no-enable-private-ip-google-access

# SSH in and test — Google API access should fail (if Cloud NAT is removed)
# Re-enable PGA
gcloud compute networks subnets update secure-subnet \
    --region=$REGION \
    --enable-private-ip-google-access
```

### Step 10 — Compare: Bastion Host Pattern

```bash
# For reference: this is the older bastion pattern (less secure than IAP)
# Create bastion with public IP in the same VPC
gcloud compute instances create bastion-vm \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --network=secure-vpc \
    --subnet=secure-subnet \
    --tags=bastion

# Would need a firewall rule allowing SSH from your IP to bastion
# Then SSH: laptop → bastion → private-vm (ProxyJump)
# IAP is preferred: no bastion needed, better audit trail
```

### Cleanup

```bash
gcloud compute instances delete private-vm --zone=$ZONE --quiet
gcloud compute instances delete bastion-vm --zone=$ZONE --quiet 2>/dev/null
gcloud compute routers nats delete secure-nat --router=secure-router --region=$REGION --quiet
gcloud compute routers delete secure-router --region=$REGION --quiet
gcloud compute firewall-rules delete secure-allow-iap-ssh secure-allow-internal --quiet
gcloud compute networks subnets delete secure-subnet --region=$REGION --quiet
gcloud compute networks delete secure-vpc --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **No public IP** removes the largest attack surface — VMs unreachable from internet
- **IAP SSH** replaces direct SSH — authenticates via Google identity, logs all sessions
- **Cloud NAT** provides outbound internet (apt-get, pip) without a public IP
- **Private Google Access** lets private VMs reach Google APIs (Storage, BigQuery)
- **VPC Service Controls** adds data exfiltration protection (Day 65+)
- IAP source range: `35.235.240.0/20` — allow in firewall for SSH
- Cloud NAT needs a **Cloud Router** in the same region
- Bastion host is the legacy pattern — IAP is preferred (no VM to manage)

### Essential Commands

```bash
# VM without public IP
gcloud compute instances create NAME --no-address --network=VPC --subnet=SUBNET

# SSH via IAP
gcloud compute ssh VM --zone=ZONE --tunnel-through-iap

# Cloud NAT
gcloud compute routers create ROUTER --network=VPC --region=REGION
gcloud compute routers nats create NAT --router=ROUTER --auto-allocate-nat-external-ips

# Private Google Access
gcloud compute networks subnets update SUBNET --region=REGION --enable-private-ip-google-access

# IAP firewall
gcloud compute firewall-rules create allow-iap --source-ranges=35.235.240.0/20 --rules=tcp:22
```

---

## Part 4 — Quiz (15 min)

**Question 1: A private VM (no external IP) needs to run `apt-get update`. What do you need?**

<details>
<summary>Show Answer</summary>

**Cloud NAT.** Private Google Access only covers Google APIs (e.g., `storage.googleapis.com`, `bigquery.googleapis.com`), not general internet like Debian package repositories.

Setup:
1. Create a Cloud Router in the VM's region
2. Create a Cloud NAT gateway attached to the router
3. Configure it to NAT all subnets (or specific ones)

The VM's outbound traffic will be NAT'd to the Cloud NAT's external IP, allowing `apt-get update` to work. Inbound traffic from the internet is still blocked.

</details>

**Question 2: What's the advantage of IAP SSH over a bastion host?**

<details>
<summary>Show Answer</summary>

| Aspect           | IAP SSH                        | Bastion Host                   |
|------------------|--------------------------------|--------------------------------|
| Infrastructure   | No VM needed (managed by GCP)  | Must maintain a bastion VM     |
| Patching         | Google manages                 | You must patch the bastion OS  |
| Authentication   | Google identity + IAM          | SSH keys on bastion            |
| Audit trail      | Full audit log in Cloud Logging| Manual SSH logging needed      |
| Attack surface   | No public-facing VM            | Bastion has a public IP        |
| MFA              | Google 2FA built-in            | Must configure separately      |
| Cost             | No extra VM cost               | Bastion VM costs money         |

IAP is strictly better in nearly every dimension. Bastion hosts are a legacy pattern.

</details>

**Question 3: You enable Private Google Access on a subnet. Can VMs in that subnet now access `https://github.com`?**

<details>
<summary>Show Answer</summary>

**No.** Private Google Access only provides access to **Google APIs and services** (e.g., `*.googleapis.com`, `*.gcr.io`). It does NOT provide general internet access.

For `github.com` or any non-Google internet destination, you need **Cloud NAT**. PGA is specifically for situations where VMs need to interact with GCP services (Cloud Storage, BigQuery, Container Registry) without a public IP.

</details>

**Question 4: Your org policy blocks external IPs on all VMs. How do you still expose a web application to the internet?**

<details>
<summary>Show Answer</summary>

Use a **Global HTTP(S) Load Balancer** with backend VMs that have **no external IPs**.

The LB architecture:
1. VMs have internal IPs only (compliant with org policy)
2. The **Load Balancer** has a public IP (LB is not a VM, so the policy doesn't apply)
3. Health check probes from `130.211.0.0/22` and `35.191.0.0/16` reach VMs internally
4. The LB proxies external traffic to internal VMs

This is the standard production pattern: **no VM has a public IP**, but the application is still internet-accessible through the LB.

</details>

---

*Next: [Day 65 — Security Checklist for VMs](DAY_65_SECURITY_CHECKLIST.md)*
