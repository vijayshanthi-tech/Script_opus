# Week 2, Day 8 (Tue) — Firewall Rules (Ingress/Egress) + Tags

> **Study time:** 2 hours | **Prereqs:** Day 7 (VPC, Subnets, CIDR)  
> **Region:** `europe-west2` (London)

---

## Part 1: Concept (30 min)

### GCP Firewall Rules vs iptables

If you've configured `iptables` or `nftables` on Linux, GCP firewall rules will feel familiar — but with key differences.

| Feature | Linux iptables | GCP Firewall Rules |
|---|---|---|
| **Where applied** | On the VM itself | At the VPC level (before traffic hits the VM) |
| **Stateful?** | Depends on conntrack | Always stateful |
| **Default policy** | Configurable (ACCEPT/DROP) | Implied deny ingress, implied allow egress |
| **Rule matching** | Sequential (first match wins) | Priority-based (lowest number = highest priority) |
| **Targets** | Chains (INPUT/OUTPUT/FORWARD) | All instances, tags, or service accounts |
| **Persistence** | Lost on reboot without save | Persistent (API-managed) |

**Linux analogy:** Think of GCP firewall rules as a managed `iptables` in front of every VM, where Google handles the conntrack and rule persistence for you.

### Firewall Rule Anatomy

```
┌──────────────────────────────────────────────────────────────┐
│                    GCP FIREWALL RULE                          │
│                                                              │
│  Direction:    INGRESS (incoming) or EGRESS (outgoing)       │
│  Priority:     0-65535 (lower = higher priority)             │
│  Action:       ALLOW or DENY                                 │
│  Target:       All instances | Target tags | Service account │
│  Source/Dest:  IP ranges, tags, or service accounts          │
│  Protocols:    tcp, udp, icmp, esp, ah, sctp, or all         │
│  Ports:        Specific ports or ranges (e.g., 80, 443,     │
│                8000-9000)                                     │
│  Enforcement:  Enabled or Disabled                           │
└──────────────────────────────────────────────────────────────┘
```

### Traffic Flow Decision

```
                    Incoming Packet
                         │
                         ▼
              ┌─────────────────────┐
              │ Match highest-priority│
              │ rule (lowest number) │
              └──────────┬──────────┘
                         │
              ┌──────────┴──────────┐
              │                      │
         Rule Found              No Rule Found
              │                      │
         ┌────┴────┐           ┌─────┴─────┐
         │         │           │            │
       ALLOW     DENY      Ingress?     Egress?
         │         │           │            │
      ✅ Pass   ❌ Drop    ❌ Drop     ✅ Pass
                           (implied     (implied
                            deny)       allow)
```

### Implied Rules (Cannot Be Deleted)

| Rule | Direction | Priority | Action | Description |
|---|---|---|---|---|
| Implied deny ingress | Ingress | 65535 | Deny | Blocks all incoming traffic by default |
| Implied allow egress | Egress | 65535 | Allow | Allows all outgoing traffic by default |

> These are the lowest-priority rules. Any rule you create with a lower priority number will override them.

### Default Network Firewall Rules

When you use the `default` VPC (auto-mode), GCP creates these rules:

| Rule Name | Direction | Priority | Allows | Source |
|---|---|---|---|---|
| `default-allow-internal` | Ingress | 65534 | tcp, udp, icmp (all internal) | `10.128.0.0/9` |
| `default-allow-ssh` | Ingress | 65534 | tcp:22 | `0.0.0.0/0` |
| `default-allow-rdp` | Ingress | 65534 | tcp:3389 | `0.0.0.0/0` |
| `default-allow-icmp` | Ingress | 65534 | icmp | `0.0.0.0/0` |

> ⚠️ **Security concern:** The default rules allow SSH and RDP from anywhere (`0.0.0.0/0`). In production, always use custom firewall rules with restricted source ranges.

### Target Tags vs Service Accounts

**Target Tags** are labels you attach to VMs to control which firewall rules apply:

```
┌─────────────────────────────────────────────────────────┐
│  Firewall Rule: allow-http                               │
│  Target: tag "web-server"                                │
│  Allow: tcp:80                                           │
│                                                          │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐            │
│  │  VM-1    │   │  VM-2    │   │  VM-3    │            │
│  │ tag:     │   │ tag:     │   │ tag:     │            │
│  │ web-     │   │ app-     │   │ web-     │            │
│  │ server   │   │ server   │   │ server   │            │
│  │ ✅ HTTP  │   │ ❌ HTTP  │   │ ✅ HTTP  │            │
│  └──────────┘   └──────────┘   └──────────┘            │
└─────────────────────────────────────────────────────────┘
```

| Method | Pros | Cons |
|---|---|---|
| **Target Tags** | Simple, quick to set up | Any project editor can change tags on a VM |
| **Service Accounts** | IAM-controlled, more secure | Requires SA management |

**Linux analogy:** Target tags are like `iptables` chain names — you group rules under a label. Service accounts are like using Linux user/group-based firewall rules (`-m owner --uid-owner`).

### Priority Best Practice

```
Priority Range    Use Case
───────────────   ─────────────────────────────────
0-999             Emergency overrides (deny malicious IPs)
1000              Standard allow rules
2000              Standard deny rules  
65534             Default network rules
65535             Implied rules (cannot be changed)
```

---

## Part 2: Hands-On Lab (60 min)

### Lab Objective
Create custom firewall rules: allow SSH from a specific IP, allow HTTP with tags, deny all egress then selectively allow. Test connectivity at each stage.

### Step 0: Set Up VPC and Subnet

```bash
export VPC_NAME="fw-lab-vpc"
export SUBNET_NAME="fw-lab-subnet"
export REGION="europe-west2"
export ZONE="europe-west2-a"

# Create VPC
gcloud compute networks create ${VPC_NAME} \
    --subnet-mode=custom

# Create subnet
gcloud compute networks subnets create ${SUBNET_NAME} \
    --network=${VPC_NAME} \
    --region=${REGION} \
    --range=10.10.0.0/24
```

### Step 1: Create VM with Tags

```bash
# Web server VM (tagged)
gcloud compute instances create web-vm \
    --zone=${ZONE} \
    --machine-type=e2-micro \
    --network=${VPC_NAME} \
    --subnet=${SUBNET_NAME} \
    --tags=web-server,ssh-allowed \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx
systemctl start nginx'

# App server VM (different tags)
gcloud compute instances create app-vm \
    --zone=${ZONE} \
    --machine-type=e2-micro \
    --network=${VPC_NAME} \
    --subnet=${SUBNET_NAME} \
    --tags=app-server \
    --image-family=debian-12 \
    --image-project=debian-cloud
```

### Step 2: Test — No Firewall Rules Yet

```bash
# Try to SSH — this will FAIL (implied deny ingress blocks SSH)
gcloud compute ssh web-vm --zone=${ZONE}
# ERROR: Connection timed out
```

> This proves the implied deny ingress rule is working. No traffic gets in without explicit allow rules.

### Step 3: Allow SSH via IAP (Restricted Source)

```bash
gcloud compute firewall-rules create ${VPC_NAME}-allow-ssh-iap \
    --network=${VPC_NAME} \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=35.235.240.0/20 \
    --target-tags=ssh-allowed \
    --priority=1000 \
    --description="Allow SSH only via IAP tunnel"
```

> `35.235.240.0/20` is Google's IAP range. Only VMs with the `ssh-allowed` tag can be reached.

```bash
# Test SSH to web-vm (has ssh-allowed tag) — WORKS
gcloud compute ssh web-vm --zone=${ZONE} --tunnel-through-iap --command="hostname"
# Output: web-vm

# Test SSH to app-vm (no ssh-allowed tag) — FAILS
gcloud compute ssh app-vm --zone=${ZONE} --tunnel-through-iap --command="hostname"
# ERROR: Connection timed out
```

### Step 4: Allow HTTP to web-server Tag Only

```bash
gcloud compute firewall-rules create ${VPC_NAME}-allow-http \
    --network=${VPC_NAME} \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=web-server \
    --priority=1000 \
    --description="Allow HTTP to web-server tagged VMs"
```

```bash
# Get external IP of web-vm
WEB_IP=$(gcloud compute instances describe web-vm \
    --zone=${ZONE} \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

echo "Web VM IP: ${WEB_IP}"

# Test HTTP access (from Cloud Shell or local machine)
curl -s -o /dev/null -w "%{http_code}" http://${WEB_IP}
# Output: 200
```

### Step 5: Allow Internal ICMP Between VMs

```bash
gcloud compute firewall-rules create ${VPC_NAME}-allow-internal-icmp \
    --network=${VPC_NAME} \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=icmp \
    --source-ranges=10.10.0.0/24 \
    --priority=1000 \
    --description="Allow ICMP within subnet"
```

```bash
# Add ssh-allowed tag to app-vm temporarily
gcloud compute instances add-tags app-vm --zone=${ZONE} --tags=ssh-allowed

# SSH to web-vm and ping app-vm
APP_IP=$(gcloud compute instances describe app-vm \
    --zone=${ZONE} \
    --format="get(networkInterfaces[0].networkIP)")

gcloud compute ssh web-vm --zone=${ZONE} --tunnel-through-iap \
    --command="ping -c 3 ${APP_IP}"
```

### Step 6: Deny All Egress, Then Allow Specific

```bash
# Deny ALL egress (overrides implied allow egress)
gcloud compute firewall-rules create ${VPC_NAME}-deny-all-egress \
    --network=${VPC_NAME} \
    --direction=EGRESS \
    --action=DENY \
    --rules=all \
    --destination-ranges=0.0.0.0/0 \
    --priority=1000 \
    --description="Deny all outbound traffic"
```

```bash
# Test — internet access should be blocked
gcloud compute ssh web-vm --zone=${ZONE} --tunnel-through-iap \
    --command="curl -s --max-time 5 http://example.com || echo 'BLOCKED'"
# Output: BLOCKED
```

```bash
# Allow DNS (required for name resolution)
gcloud compute firewall-rules create ${VPC_NAME}-allow-dns-egress \
    --network=${VPC_NAME} \
    --direction=EGRESS \
    --action=ALLOW \
    --rules=udp:53,tcp:53 \
    --destination-ranges=0.0.0.0/0 \
    --priority=900 \
    --description="Allow DNS egress"

# Allow HTTPS egress (for apt, APIs, etc.)
gcloud compute firewall-rules create ${VPC_NAME}-allow-https-egress \
    --network=${VPC_NAME} \
    --direction=EGRESS \
    --action=ALLOW \
    --rules=tcp:443 \
    --destination-ranges=0.0.0.0/0 \
    --priority=900 \
    --description="Allow HTTPS egress"
```

```bash
# Test — HTTPS should work now
gcloud compute ssh web-vm --zone=${ZONE} --tunnel-through-iap \
    --command="curl -s --max-time 5 https://example.com | head -5"
```

### Step 7: List All Firewall Rules

```bash
gcloud compute firewall-rules list \
    --filter="network=${VPC_NAME}" \
    --format="table(name, direction, priority, allowed[].map().firewall_rule().list():label=ALLOWED, denied[].map().firewall_rule().list():label=DENIED, sourceRanges.list():label=SRC_RANGES, targetTags.list():label=TARGET_TAGS)"
```

**Expected output:**
```
NAME                            DIRECTION  PRIORITY  ALLOWED     DENIED  SRC_RANGES         TARGET_TAGS
fw-lab-vpc-allow-dns-egress     EGRESS     900       udp:53,tcp:53       0.0.0.0/0
fw-lab-vpc-allow-https-egress   EGRESS     900       tcp:443             0.0.0.0/0
fw-lab-vpc-allow-http           INGRESS    1000      tcp:80              0.0.0.0/0          web-server
fw-lab-vpc-allow-internal-icmp  INGRESS    1000      icmp                10.10.0.0/24
fw-lab-vpc-allow-ssh-iap        INGRESS    1000      tcp:22              35.235.240.0/20    ssh-allowed
fw-lab-vpc-deny-all-egress      EGRESS     1000              all         0.0.0.0/0
```

### Cleanup

```bash
# Delete VMs
gcloud compute instances delete web-vm --zone=${ZONE} --quiet
gcloud compute instances delete app-vm --zone=${ZONE} --quiet

# Delete all firewall rules for the VPC
for RULE in $(gcloud compute firewall-rules list --filter="network=${VPC_NAME}" --format="value(name)"); do
    gcloud compute firewall-rules delete ${RULE} --quiet
done

# Delete subnet and VPC
gcloud compute networks subnets delete ${SUBNET_NAME} --region=${REGION} --quiet
gcloud compute networks delete ${VPC_NAME} --quiet
```

---

## Part 3: Revision (15 min)

### Key Concepts

- GCP firewall rules are **stateful** — return traffic is automatically allowed
- **Implied rules**: deny all ingress (65535), allow all egress (65535) — cannot be deleted
- Rules are matched by **priority** (lowest number wins), not order of creation
- **Target tags** control which VMs a rule applies to — any project editor can modify tags
- **Service accounts** as targets are more secure (IAM-controlled)
- For **ingress**: specify `--source-ranges` (who can send traffic)
- For **egress**: specify `--destination-ranges` (where traffic can go)
- `35.235.240.0/20` is the IAP source range — use this instead of `0.0.0.0/0` for SSH
- To restrict outbound: deny all egress at priority 1000, then allow specific at priority 900
- Firewall rules apply to the **VPC**, not to individual subnets

### Key Commands

```bash
# Create ingress rule with tags
gcloud compute firewall-rules create NAME \
    --network=VPC --direction=INGRESS --action=ALLOW \
    --rules=tcp:80 --source-ranges=0.0.0.0/0 --target-tags=TAG

# Create egress deny rule
gcloud compute firewall-rules create NAME \
    --network=VPC --direction=EGRESS --action=DENY \
    --rules=all --destination-ranges=0.0.0.0/0

# List firewall rules
gcloud compute firewall-rules list --filter="network=VPC"

# Describe a rule
gcloud compute firewall-rules describe RULE_NAME

# Update a rule
gcloud compute firewall-rules update RULE_NAME --priority=500

# Add tags to a VM
gcloud compute instances add-tags VM_NAME --zone=ZONE --tags=TAG1,TAG2

# Remove tags from a VM
gcloud compute instances remove-tags VM_NAME --zone=ZONE --tags=TAG1
```

---

## Part 4: Quiz (15 min)

**Question 1:** You create two firewall rules for the same VPC: Rule A (priority 1000, allow tcp:80) and Rule B (priority 500, deny tcp:80). What happens to incoming HTTP traffic?

<details>
<summary>Click to reveal answer</summary>

**HTTP traffic is DENIED.**

Rule B has priority 500 (lower number = higher priority), so it is evaluated first. Since Rule B denies tcp:80, the traffic is blocked. Rule A (priority 1000) is never reached.

In GCP, the highest-priority matching rule wins — it's not like iptables where rules are processed sequentially in a chain.

</details>

---

**Question 2:** A VM has the tag `app-server`. You create a firewall rule targeting `web-server` that allows tcp:443. Can the VM receive HTTPS traffic?

<details>
<summary>Click to reveal answer</summary>

**No.** The firewall rule targets VMs with the tag `web-server`. Since the VM only has the tag `app-server`, the rule does not apply to it.

The VM would need either:
- The `web-server` tag added to it, OR
- A separate firewall rule targeting `app-server` or all instances

</details>

---

**Question 3:** You want VMs to reach the internet for `apt update` but block everything else outbound. What's the minimum set of egress rules?

<details>
<summary>Click to reveal answer</summary>

You need three rules:

1. **Deny all egress** (priority 1000):
   ```bash
   --direction=EGRESS --action=DENY --rules=all --destination-ranges=0.0.0.0/0
   ```

2. **Allow DNS egress** (priority 900):
   ```bash
   --direction=EGRESS --action=ALLOW --rules=udp:53,tcp:53 --destination-ranges=0.0.0.0/0
   ```

3. **Allow HTTP/HTTPS egress** (priority 900):
   ```bash
   --direction=EGRESS --action=ALLOW --rules=tcp:80,tcp:443 --destination-ranges=0.0.0.0/0
   ```

DNS is needed for name resolution. HTTP (80) and HTTPS (443) are needed for Debian/Ubuntu apt repositories. The allow rules have priority 900 (higher than the deny at 1000), so they are matched first.

</details>

---

**Question 4:** What is the difference between the implied deny ingress rule and a custom deny rule you create?

<details>
<summary>Click to reveal answer</summary>

| Aspect | Implied Deny Ingress | Custom Deny Rule |
|---|---|---|
| **Priority** | 65535 (lowest possible) | You choose (e.g., 500, 1000) |
| **Deletable** | No — cannot be removed | Yes — can be deleted/modified |
| **Visible** | Not shown in `firewall-rules list` | Shown in `firewall-rules list` |
| **Logging** | Cannot enable logging | Can enable `--enable-logging` |
| **Scope** | Applies to all instances | Can target specific tags/SAs |

The implied deny is a safety net — it catches everything that no other rule matched. A custom deny rule gives you explicit control with logging, specific targeting, and configurable priority.

</details>

---

**End of Day 8** — Tomorrow: Private vs Public IP, Internal Connectivity
