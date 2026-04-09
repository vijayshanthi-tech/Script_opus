# Week 2, Day 11 (Fri) — NAT Concept (High-Level)

> **Study time:** 2 hours | **Prereqs:** Day 7–10 (VPC, Firewall, IP, Routes)  
> **Region:** `europe-west2` (London)

---

## Part 1: Concept (30 min)

### Why Cloud NAT Exists

Many production VMs should **not** have external IPs (security principle of least privilege). But they still need to:
- Download packages (`apt update`, `yum install`)
- Pull container images
- Call third-party APIs
- Send logs to external services

**Cloud NAT** solves this: outbound internet access without external IPs.

### How Cloud NAT Works

```
┌───────────────────────────────────────────────────────────────┐
│                        VPC                                     │
│                                                                │
│  ┌──────────┐                                                  │
│  │ VM-A     │─┐                                                │
│  │ 10.1.0.5 │ │                                                │
│  │ no ext IP│ │    ┌──────────────────┐    ┌──────────────┐   │
│  └──────────┘ ├───►│   Cloud Router    │───►│  Cloud NAT    │──┼──► Internet
│               │    │  (control plane)  │    │  Gateway      │  │
│  ┌──────────┐ │    │                   │    │               │  │
│  │ VM-B     │─┘    │  - Learns routes  │    │ NAT IP:       │  │
│  │ 10.1.0.6 │      │  - No data plane  │    │ 34.89.X.X    │  │
│  │ no ext IP│      │    forwarding     │    │               │  │
│  └──────────┘      └──────────────────┘    │ Translates:   │  │
│                                             │ 10.1.0.5 →   │  │
│                                             │ 34.89.X.X    │  │
│                                             └──────────────┘  │
│                                                                │
│  ◄──── RETURN TRAFFIC ────                                     │
│  34.89.X.X:src_port → 10.1.0.5:orig_port (de-NAT)            │
└───────────────────────────────────────────────────────────────┘
```

### Cloud NAT Architecture Components

| Component | Purpose |
|---|---|
| **Cloud Router** | Required. Manages NAT configuration. Does NOT forward data. |
| **Cloud NAT Gateway** | Performs the actual NAT translation (SNAT) |
| **NAT IP Address** | The public IP(s) used for outbound traffic |
| **Subnet mapping** | Which subnets use this NAT gateway |

### Cloud NAT vs Traditional NAT

| Feature | Traditional Linux NAT | GCP Cloud NAT |
|---|---|---|
| **Implementation** | iptables MASQUERADE on a VM | Google-managed, distributed |
| **Single point of failure?** | Yes (the NAT VM) | No — fully managed, HA |
| **Throughput** | Limited by VM size | Scales automatically |
| **Maintenance** | You manage, patch, monitor | Google manages everything |
| **Cost** | VM cost + network | Per-GB processed + NAT IP cost |
| **IP forwarding** | Must enable `ip_forward` | Not needed |
| **Data plane** | Through the VM | NOT through Cloud Router |

**Linux analogy:**
```bash
# Traditional Linux NAT (what Cloud NAT replaces):
iptables -t nat -A POSTROUTING -s 10.1.0.0/24 -o eth0 -j MASQUERADE
echo 1 > /proc/sys/net/ipv4/ip_forward

# Cloud NAT does this at the infrastructure level — no VM needed
```

### Key Behaviour

1. Cloud NAT is **outbound only** — it does NOT allow inbound connections from the internet
2. Cloud NAT applies to VMs **without external IPs** only (VMs with external IPs bypass NAT)
3. Cloud NAT is **regional** — one NAT gateway per region per Cloud Router
4. Return traffic (responses to outbound requests) is automatically handled (stateful)
5. Cloud NAT does NOT work for GKE nodes with external IPs

### When to Use Cloud NAT vs External IP

```
┌─────────────────────────────────────────────────────────┐
│           Decision: Internet Access Method               │
│                                                          │
│  Need inbound FROM internet?                             │
│  ├── YES → External IP or Load Balancer                  │
│  └── NO                                                  │
│       │                                                  │
│       Need outbound TO internet?                         │
│       ├── YES → Cloud NAT                                │
│       └── NO                                             │
│            │                                             │
│            Need Google APIs only?                        │
│            ├── YES → Private Google Access                │
│            └── NO  → Fully isolated (no internet)        │
└─────────────────────────────────────────────────────────┘
```

### NAT IP Address Allocation

| Mode | Description |
|---|---|
| **Automatic** | Google allocates NAT IPs as needed |
| **Manual** | You specify which static IPs to use |

> Use **manual** when you need to whitelist specific outbound IPs with third-party services.

### Cloud NAT Logging

Cloud NAT can log translations for troubleshooting and auditing:

| Log Type | What It Records |
|---|---|
| **ERRORS_ONLY** | Only NAT errors (e.g., port exhaustion) |
| **TRANSLATIONS_ONLY** | Successful translations |
| **ALL** | Both errors and translations |

Logs go to Cloud Logging and include:
- Source VM IP and port
- NAT IP and translated port
- Destination IP and port
- Protocol

### Port Allocation

Each NAT IP supports **~64,000 ports**. Each VM is allocated a minimum number of ports:

| Setting | Default | Description |
|---|---|---|
| `min-ports-per-vm` | 64 | Minimum ports reserved per VM |
| Dynamic port allocation | Enabled by default | Scales up as needed |

> If a VM makes many concurrent connections (e.g., a web scraper), it may exhaust its port allocation. Increase `min-ports-per-vm` or add more NAT IPs.

---

## Part 2: Hands-On Lab (60 min)

### Lab Objective
Create a VM without an external IP, verify it has no internet access, set up Cloud NAT, verify internet works, and examine NAT logs.

### Step 0: Create Lab Environment

```bash
export VPC_NAME="nat-lab-vpc"
export SUBNET_NAME="nat-lab-subnet"
export REGION="europe-west2"
export ZONE="europe-west2-a"
export ROUTER_NAME="nat-lab-router"
export NAT_NAME="nat-lab-gateway"

# Create VPC and subnet
gcloud compute networks create ${VPC_NAME} --subnet-mode=custom

gcloud compute networks subnets create ${SUBNET_NAME} \
    --network=${VPC_NAME} \
    --region=${REGION} \
    --range=10.40.0.0/24

# Firewall: SSH via IAP
gcloud compute firewall-rules create ${VPC_NAME}-allow-ssh-iap \
    --network=${VPC_NAME} \
    --allow=tcp:22 \
    --source-ranges=35.235.240.0/20
```

### Step 1: Create VM Without External IP

```bash
gcloud compute instances create nat-test-vm \
    --zone=${ZONE} \
    --machine-type=e2-micro \
    --network=${VPC_NAME} \
    --subnet=${SUBNET_NAME} \
    --no-address \
    --image-family=debian-12 \
    --image-project=debian-cloud
```

### Step 2: Verify No Internet Access

```bash
gcloud compute ssh nat-test-vm --zone=${ZONE} --tunnel-through-iap \
    --command="curl -s --max-time 5 http://ifconfig.me || echo 'NO INTERNET ACCESS'"
```

**Expected output:**
```
NO INTERNET ACCESS
```

```bash
# Also try DNS resolution
gcloud compute ssh nat-test-vm --zone=${ZONE} --tunnel-through-iap \
    --command="host google.com || echo 'DNS FAILED TOO'"
```

> Without external IP and no Cloud NAT, the VM has zero internet connectivity (not even DNS).

### Step 3: Create Cloud Router

```bash
gcloud compute routers create ${ROUTER_NAME} \
    --network=${VPC_NAME} \
    --region=${REGION} \
    --description="Cloud Router for NAT lab"
```

**Expected output:**
```
Creating router [nat-lab-router]...done.
NAME              REGION         NETWORK
nat-lab-router    europe-west2   nat-lab-vpc
```

### Step 4: Create Cloud NAT Gateway

```bash
gcloud compute routers nats create ${NAT_NAME} \
    --router=${ROUTER_NAME} \
    --region=${REGION} \
    --nat-all-subnet-ip-ranges \
    --auto-allocate-nat-external-ips \
    --enable-logging \
    --log-filter=ALL \
    --min-ports-per-vm=64
```

**Expected output:**
```
Creating NAT [nat-lab-gateway] in router [nat-lab-router]...done.
```

> **Flags explained:**
> - `--nat-all-subnet-ip-ranges`: Apply NAT to all subnets in the VPC
> - `--auto-allocate-nat-external-ips`: Let Google manage NAT IPs
> - `--enable-logging`: Turn on NAT logging
> - `--log-filter=ALL`: Log both translations and errors

### Step 5: Wait for NAT to Propagate (1-2 minutes)

```bash
# Verify NAT configuration
gcloud compute routers nats describe ${NAT_NAME} \
    --router=${ROUTER_NAME} \
    --region=${REGION} \
    --format="yaml(name, natIpAllocateOption, sourceSubnetworkIpRangesToNat, logConfig)"
```

**Expected output:**
```yaml
logConfig:
  enable: true
  filter: ALL
name: nat-lab-gateway
natIpAllocateOption: AUTO_ONLY
sourceSubnetworkIpRangesToNat: ALL_SUBNETWORKS_ALL_IP_RANGES
```

### Step 6: Test Internet Access (Should Work Now!)

```bash
gcloud compute ssh nat-test-vm --zone=${ZONE} --tunnel-through-iap \
    --command="curl -s --max-time 10 http://ifconfig.me"
```

**Expected output:**
```
34.89.XX.XX
```

> This is the Cloud NAT's external IP, NOT the VM's IP. The VM still has no external IP.

```bash
# Test DNS resolution
gcloud compute ssh nat-test-vm --zone=${ZONE} --tunnel-through-iap \
    --command="host google.com"
```

**Expected output:**
```
google.com has address 142.250.XX.XX
```

```bash
# Test package download
gcloud compute ssh nat-test-vm --zone=${ZONE} --tunnel-through-iap \
    --command="sudo apt-get update -qq && echo 'APT UPDATE SUCCESSFUL'"
```

**Expected output:**
```
APT UPDATE SUCCESSFUL
```

### Step 7: Verify VM Still Has No External IP

```bash
gcloud compute instances describe nat-test-vm \
    --zone=${ZONE} \
    --format="table(name, networkInterfaces[0].networkIP:label=INTERNAL_IP, networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)"
```

**Expected output:**
```
NAME          INTERNAL_IP  EXTERNAL_IP
nat-test-vm   10.40.0.2
```

> EXTERNAL_IP is blank — the VM is reaching the internet purely through Cloud NAT.

### Step 8: View the NAT IP Addresses

```bash
gcloud compute routers get-nat-ip-info ${ROUTER_NAME} \
    --region=${REGION}
```

Or check the auto-allocated addresses:
```bash
gcloud compute routers get-status ${ROUTER_NAME} \
    --region=${REGION} \
    --format="yaml(result.natStatus)"
```

### Step 9: Check NAT Logs

```bash
# View NAT logs in Cloud Logging (wait a few minutes after traffic)
gcloud logging read \
    "resource.type=nat_gateway AND resource.labels.router_id=${ROUTER_NAME}" \
    --limit=5 \
    --format="table(timestamp, jsonPayload.connection.src_ip, jsonPayload.connection.dest_ip, jsonPayload.allocation_status)"
```

> Logs show the source VM IP, destination, and whether NAT allocation succeeded.

### Step 10: Test — Inbound Connection Should FAIL

```bash
# Get the NAT IP
NAT_IP=$(gcloud compute ssh nat-test-vm --zone=${ZONE} --tunnel-through-iap \
    --command="curl -s http://ifconfig.me")

echo "NAT IP: ${NAT_IP}"

# Try to SSH to the NAT IP from outside — FAILS
# (Don't actually run this, just understand the concept)
# ssh user@${NAT_IP}  # Connection refused — Cloud NAT is outbound ONLY
```

### Step 11: Configure NAT for Specific Subnets Only (Optional)

```bash
# Update NAT to apply only to specific subnets
gcloud compute routers nats update ${NAT_NAME} \
    --router=${ROUTER_NAME} \
    --region=${REGION} \
    --nat-custom-subnet-ip-ranges="${SUBNET_NAME}"
```

### Cleanup

```bash
# Delete VM
gcloud compute instances delete nat-test-vm --zone=${ZONE} --quiet

# Delete Cloud NAT
gcloud compute routers nats delete ${NAT_NAME} \
    --router=${ROUTER_NAME} \
    --region=${REGION} --quiet

# Delete Cloud Router
gcloud compute routers delete ${ROUTER_NAME} \
    --region=${REGION} --quiet

# Delete firewall rules
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

- **Cloud NAT** = outbound internet for VMs without external IPs (no inbound)
- Requires a **Cloud Router** (control plane only — no data forwarding)
- Cloud NAT is **regional** — one per region per router
- **Fully managed** — no VM to maintain, auto-scales, HA by default
- VMs with external IPs **bypass** Cloud NAT (they use their own IP)
- **NAT IP allocation**: automatic (Google manages) or manual (you specify IPs)
- **Logging** can be enabled: errors only, translations only, or all
- Each NAT IP supports ~64,000 ports; default 64 ports per VM
- Cloud NAT is **stateful** — return traffic is automatically handled
- Use Cloud NAT when VMs need `apt update`, API calls, or outbound connectivity
- Use **Private Google Access** for Google APIs only (doesn't need Cloud NAT)

### Key Commands

```bash
# Create Cloud Router
gcloud compute routers create NAME --network=VPC --region=REGION

# Create Cloud NAT
gcloud compute routers nats create NAME \
    --router=ROUTER --region=REGION \
    --nat-all-subnet-ip-ranges \
    --auto-allocate-nat-external-ips

# Describe NAT configuration
gcloud compute routers nats describe NAME --router=ROUTER --region=REGION

# Update NAT (e.g., change min ports)
gcloud compute routers nats update NAME --router=ROUTER --region=REGION --min-ports-per-vm=128

# View NAT status
gcloud compute routers get-status ROUTER --region=REGION

# View NAT logs
gcloud logging read "resource.type=nat_gateway" --limit=10

# Delete NAT
gcloud compute routers nats delete NAME --router=ROUTER --region=REGION
```

---

## Part 4: Quiz (15 min)

**Question 1:** A VM has no external IP and Cloud NAT is configured. Can an external client initiate a connection to this VM via the NAT IP?

<details>
<summary>Click to reveal answer</summary>

**No.** Cloud NAT is **outbound only**. It performs Source NAT (SNAT) for outgoing connections and handles the return traffic (stateful), but it does NOT create inbound NAT rules (DNAT).

To allow inbound connections, the VM needs either:
- An external IP, OR
- A Load Balancer in front of it, OR
- IAP for SSH/RDP access

This is actually a security benefit — VMs behind Cloud NAT are unreachable from the internet.

</details>

---

**Question 2:** You set up Cloud NAT but your VM still can't reach the internet. What are two things to check?

<details>
<summary>Click to reveal answer</summary>

1. **Check if the VM has an external IP**: Cloud NAT only applies to VMs **without** external IPs. If the VM has an external IP, it bypasses Cloud NAT entirely (and uses its own IP for outbound).

2. **Check egress firewall rules**: If you have a deny-all egress rule (from Day 8), it blocks traffic **before** it reaches Cloud NAT. Ensure egress is allowed for the required ports/destinations.

Other things to check:
- NAT propagation delay (can take 1-2 minutes after creation)
- NAT is configured for the correct subnet (`--nat-all-subnet-ip-ranges` or specific subnet)
- The Cloud Router and NAT are in the **same region** as the subnet/VM
- Port exhaustion (increase `min-ports-per-vm` if making many concurrent connections)

</details>

---

**Question 3:** What is the role of the Cloud Router in Cloud NAT? Does traffic flow through it?

<details>
<summary>Click to reveal answer</summary>

The Cloud Router serves as the **control plane** for Cloud NAT. It manages the NAT configuration, IP allocation, and port mapping.

**Traffic does NOT flow through the Cloud Router.** The actual NAT translation happens at the infrastructure level (Google's network fabric). The Cloud Router just coordinates the configuration.

Think of it this way:
- **Cloud Router** = the brains (decides how NAT works)
- **Google's network** = the muscle (actually does the NAT translation)

This is different from a traditional Linux NAT box where the same machine handles both configuration and packet forwarding.

</details>

---

**Question 4:** You need third-party services to whitelist your VM's outbound IP. How do you ensure a predictable IP with Cloud NAT?

<details>
<summary>Click to reveal answer</summary>

Use **manual NAT IP allocation** instead of automatic:

```bash
# Reserve a static IP
gcloud compute addresses create nat-static-ip --region=europe-west2

# Create/update NAT with manual IP
gcloud compute routers nats create my-nat \
    --router=my-router \
    --region=europe-west2 \
    --nat-all-subnet-ip-ranges \
    --nat-external-ip-pool=nat-static-ip
```

With manual allocation, you control exactly which IP(s) Cloud NAT uses. You can then share this IP with the third-party service for whitelisting.

If you need more than ~64,000 concurrent connections, add multiple NAT IPs:
```bash
--nat-external-ip-pool=nat-ip-1,nat-ip-2
```

</details>

---

**End of Day 11** — Tomorrow: PROJECT — Secure VPC + 2-Tier VM Setup
