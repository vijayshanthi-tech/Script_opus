# Week 2, Day 10 (Thu) — Routes Deep Dive

> **Study time:** 2 hours | **Prereqs:** Day 7–9 (VPC, Firewall, IP addressing)  
> **Region:** `europe-west2` (London)

---

## Part 1: Concept (30 min)

### What Are Routes?

Routes tell the VPC **where to send packets** based on their destination IP. Every packet leaving a VM is matched against the route table to determine the next hop.

**Linux analogy:** Exactly like `ip route show` or the kernel routing table. GCP routes work the same way — longest prefix match, priority-based, with a default gateway.

```bash
# Linux equivalent
$ ip route show
10.1.0.0/24 dev eth0 proto kernel scope link src 10.1.0.2    # Subnet route
10.2.0.0/24 via 10.1.0.1 dev eth0                             # Static route
default via 10.1.0.1 dev eth0                                  # Default route
```

### Route Types Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    VPC ROUTE TABLE                            │
│                                                              │
│  ┌───────────────────────────────────────────────────┐      │
│  │  SYSTEM-GENERATED ROUTES (auto-created by GCP)     │      │
│  │                                                     │      │
│  │  1. Default Route     0.0.0.0/0 → Internet GW     │      │
│  │     (priority 1000)                                 │      │
│  │                                                     │      │
│  │  2. Subnet Routes     10.1.0.0/24 → subnet-eu     │      │
│  │     (priority 0)      10.2.0.0/24 → subnet-us     │      │
│  └───────────────────────────────────────────────────┘      │
│                                                              │
│  ┌───────────────────────────────────────────────────┐      │
│  │  CUSTOM ROUTES (created by you)                    │      │
│  │                                                     │      │
│  │  3. Static Routes     172.16.0.0/16 → VPN tunnel  │      │
│  │     (priority: you set)                             │      │
│  │                                                     │      │
│  │  4. Policy-Based       For advanced routing        │      │
│  │     Routes             (src + dest based)          │      │
│  └───────────────────────────────────────────────────┘      │
│                                                              │
│  ┌───────────────────────────────────────────────────┐      │
│  │  DYNAMIC ROUTES (from Cloud Router / BGP)          │      │
│  │                                                     │      │
│  │  5. BGP-learned        192.168.0.0/16 → on-prem   │      │
│  │     routes              (via Cloud VPN/Interconnect)│      │
│  └───────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### System-Generated Routes

#### 1. Default Route

| Property | Value |
|---|---|
| **Destination** | `0.0.0.0/0` |
| **Next hop** | Default internet gateway |
| **Priority** | 1000 |
| **Created when** | VPC is created |
| **Can delete?** | Yes — but VMs lose internet access |
| **Purpose** | Provides path to the internet |

#### 2. Subnet Routes

| Property | Value |
|---|---|
| **Destination** | Subnet's CIDR (e.g., `10.1.0.0/24`) |
| **Next hop** | The subnet itself |
| **Priority** | 0 (highest — cannot be overridden) |
| **Created when** | Subnet is created |
| **Can delete?** | No — only by deleting the subnet |
| **Purpose** | Routes traffic to VMs within the subnet |

### Custom Static Routes

You create these to direct traffic through specific next hops.

```
┌──────────────┐     Custom Route:              ┌──────────────┐
│   VM-A       │     172.16.0.0/16 →            │   VM-NAT     │
│  10.1.0.5    │────────────────────────────────►│  10.1.0.10   │
│              │     next-hop: 10.1.0.10        │  (appliance)  │
└──────────────┘                                 └──────┬───────┘
                                                        │
                                                        ▼
                                                 ┌──────────────┐
                                                 │  On-premises  │
                                                 │  172.16.x.x  │
                                                 └──────────────┘
```

### Next-Hop Types

| Next-Hop Type | Description | Use Case |
|---|---|---|
| **Default internet gateway** | Routes to the internet | Default route |
| **Instance** | Specific VM (by name) | Network appliance, NAT instance |
| **IP address** | Internal IP of a VM | When VM name might change |
| **VPN tunnel** | Cloud VPN tunnel | Routing to on-premises |
| **Internal Load Balancer (ILB)** | ILB forwarding rule | HA routing through LB |

**Linux analogy:**
```bash
# Next-hop gateway (like default internet gateway)
ip route add default via 10.1.0.1 dev eth0

# Next-hop IP (like next-hop instance)
ip route add 172.16.0.0/16 via 10.1.0.10

# Next-hop interface (like subnet route)
ip route add 10.1.0.0/24 dev eth0
```

### Routing Order (How GCP Picks a Route)

```
         Incoming Packet (dest: 172.16.1.50)
                    │
                    ▼
    ┌───────────────────────────────────┐
    │  Step 1: LONGEST PREFIX MATCH     │
    │                                   │
    │  172.16.1.0/24  ← matches (24)   │  ◄── Most specific wins
    │  172.16.0.0/16  ← matches (16)   │
    │  0.0.0.0/0      ← matches (0)    │
    │                                   │
    │  Winner: 172.16.1.0/24            │
    └───────────────┬───────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────┐
    │  Step 2: If multiple routes with  │
    │  same prefix length → PRIORITY    │
    │                                   │
    │  Route A: priority 100            │  ◄── Lowest wins
    │  Route B: priority 500            │
    │                                   │
    │  Winner: Route A                  │
    └───────────────┬───────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────┐
    │  Step 3: If same prefix + same    │
    │  priority → ECMP (load balance)   │
    │  (only for next-hop instances     │
    │   in same zone)                   │
    └───────────────────────────────────┘
```

### Route Priorities

| Priority | Meaning |
|---|---|
| 0 | Highest (subnet routes — cannot be overridden) |
| 100-999 | High priority custom routes |
| 1000 | Default (system default route) |
| 1001-65534 | Lower priority custom routes |
| 65535 | Lowest (reserved) |

### Policy-Based Routes (Advanced)

Policy-based routes match on **both source and destination**, unlike regular routes which match only on destination.

| Feature | Regular Route | Policy-Based Route |
|---|---|---|
| **Match on** | Destination IP only | Source + Destination IP |
| **Use case** | Standard routing | Steering specific traffic |
| **Complexity** | Simple | Advanced |
| **Example** | All traffic to `172.16.0.0/16` → VPN | Only traffic FROM `10.1.0.0/24` TO `172.16.0.0/16` → VPN |

---

## Part 2: Hands-On Lab (60 min)

### Lab Objective
Inspect default routes, create custom static routes, observe route behaviour, and understand next-hops.

### Step 0: Create Lab VPC

```bash
export VPC_NAME="route-lab-vpc"
export SUBNET_A="route-subnet-a"
export SUBNET_B="route-subnet-b"
export REGION="europe-west2"
export ZONE="europe-west2-a"

gcloud compute networks create ${VPC_NAME} --subnet-mode=custom

gcloud compute networks subnets create ${SUBNET_A} \
    --network=${VPC_NAME} \
    --region=${REGION} \
    --range=10.30.1.0/24

gcloud compute networks subnets create ${SUBNET_B} \
    --network=${VPC_NAME} \
    --region=${REGION} \
    --range=10.30.2.0/24

# Allow SSH and ICMP
gcloud compute firewall-rules create ${VPC_NAME}-allow-ssh-iap \
    --network=${VPC_NAME} \
    --allow=tcp:22 \
    --source-ranges=35.235.240.0/20

gcloud compute firewall-rules create ${VPC_NAME}-allow-internal \
    --network=${VPC_NAME} \
    --allow=icmp,tcp,udp \
    --source-ranges=10.30.0.0/16
```

### Step 1: Inspect System-Generated Routes

```bash
gcloud compute routes list \
    --filter="network=${VPC_NAME}" \
    --format="table(name, destRange, nextHopGateway.basename(), nextHopNetwork.basename(), priority, routeType)"
```

**Expected output:**
```
NAME                                    DEST_RANGE      NEXT_HOP                   PRIORITY
default-route-xxxxxxxxx                 0.0.0.0/0       default-internet-gateway    1000
default-route-xxxxxxxxx                 10.30.1.0/24                                0
default-route-xxxxxxxxx                 10.30.2.0/24                                0
```

> Three routes: one default internet route (priority 1000) and two subnet routes (priority 0).

### Step 2: Create VMs

```bash
gcloud compute instances create vm-a \
    --zone=${ZONE} \
    --machine-type=e2-micro \
    --network=${VPC_NAME} \
    --subnet=${SUBNET_A} \
    --no-address \
    --image-family=debian-12 \
    --image-project=debian-cloud

gcloud compute instances create vm-b \
    --zone=${ZONE} \
    --machine-type=e2-micro \
    --network=${VPC_NAME} \
    --subnet=${SUBNET_B} \
    --no-address \
    --image-family=debian-12 \
    --image-project=debian-cloud
```

### Step 3: Verify Internal Routing Works

```bash
VM_B_IP=$(gcloud compute instances describe vm-b \
    --zone=${ZONE} \
    --format="get(networkInterfaces[0].networkIP)")

gcloud compute ssh vm-a --zone=${ZONE} --tunnel-through-iap \
    --command="ping -c 3 ${VM_B_IP}"
```

**Expected output:**
```
PING 10.30.2.2 (10.30.2.2) 56(84) bytes of data.
64 bytes from 10.30.2.2: icmp_seq=1 ttl=64 time=0.6 ms
```

> This works because of the subnet route for `10.30.2.0/24` (priority 0).

### Step 4: View Routes from Inside the VM

```bash
gcloud compute ssh vm-a --zone=${ZONE} --tunnel-through-iap \
    --command="ip route show"
```

**Expected output:**
```
default via 10.30.1.1 dev ens4
10.30.1.0/24 via 10.30.1.1 dev ens4
10.30.1.1 dev ens4 scope link
```

> Inside the VM, you see the Linux routing table. The GCP VPC routes are handled at the infrastructure level (above the VM).

### Step 5: Create a Custom Static Route

Let's create a blackhole route — traffic to `192.168.100.0/24` gets dropped:

```bash
# Create a route that drops traffic (no valid next-hop)
gcloud compute routes create drop-test-traffic \
    --network=${VPC_NAME} \
    --destination-range=198.51.100.0/24 \
    --priority=500 \
    --next-hop-gateway=default-internet-gateway \
    --description="Test route - traffic to TEST-NET-2 via internet gateway" \
    --tags=route-test
```

> We use `198.51.100.0/24` (TEST-NET-2) which is a documentation-reserved range.

### Step 6: Verify the Custom Route

```bash
gcloud compute routes list \
    --filter="network=${VPC_NAME}" \
    --format="table(name, destRange, nextHopGateway.basename(), priority, tags.list():label=TAGS)" \
    --sort-by=priority
```

**Expected output:**
```
NAME                         DEST_RANGE         NEXT_HOP                  PRIORITY  TAGS
default-route-xxxxxxxx       10.30.1.0/24                                  0
default-route-xxxxxxxx       10.30.2.0/24                                  0
drop-test-traffic            198.51.100.0/24    default-internet-gateway   500       route-test
default-route-xxxxxxxx       0.0.0.0/0          default-internet-gateway   1000
```

### Step 7: Create a Route via Instance (Next-Hop Instance)

Create a "router" VM that could act as a network appliance:

```bash
gcloud compute instances create router-vm \
    --zone=${ZONE} \
    --machine-type=e2-micro \
    --network=${VPC_NAME} \
    --subnet=${SUBNET_A} \
    --no-address \
    --can-ip-forward \
    --image-family=debian-12 \
    --image-project=debian-cloud
```

> `--can-ip-forward` is **critical** — without it, GCP drops packets not destined for the VM's own IP. This is like enabling `net.ipv4.ip_forward=1` in Linux.

```bash
# Create route via the router VM
ROUTER_IP=$(gcloud compute instances describe router-vm \
    --zone=${ZONE} \
    --format="get(networkInterfaces[0].networkIP)")

gcloud compute routes create via-router-test \
    --network=${VPC_NAME} \
    --destination-range=203.0.113.0/24 \
    --next-hop-address=${ROUTER_IP} \
    --priority=800 \
    --description="Route TEST-NET-3 via router VM"
```

### Step 8: Verify IP Forwarding on Router VM

```bash
gcloud compute instances describe router-vm \
    --zone=${ZONE} \
    --format="get(canIpForward)"
# Output: True
```

```bash
# Inside the router VM, verify Linux-level forwarding
gcloud compute ssh router-vm --zone=${ZONE} --tunnel-through-iap \
    --command="sysctl net.ipv4.ip_forward"
# Output: net.ipv4.ip_forward = 1
```

### Step 9: Describe a Specific Route

```bash
gcloud compute routes describe via-router-test \
    --format="yaml(name, destRange, nextHopIp, priority, network)"
```

**Expected output:**
```yaml
destRange: 203.0.113.0/24
name: via-router-test
network: https://www.googleapis.com/compute/v1/projects/PROJECT/global/networks/route-lab-vpc
nextHopIp: 10.30.1.X
priority: 800
```

### Step 10: Test Route Priority

```bash
# Create another route to the same destination but lower priority
gcloud compute routes create via-router-test-low \
    --network=${VPC_NAME} \
    --destination-range=203.0.113.0/24 \
    --next-hop-gateway=default-internet-gateway \
    --priority=1200 \
    --description="Lower priority route for TEST-NET-3"

# List both routes
gcloud compute routes list \
    --filter="network=${VPC_NAME} AND destRange=203.0.113.0/24" \
    --format="table(name, destRange, nextHopIp, nextHopGateway.basename(), priority)"
```

**Expected output:**
```
NAME                    DEST_RANGE         NEXT_HOP_IP   NEXT_HOP_GATEWAY             PRIORITY
via-router-test         203.0.113.0/24     10.30.1.X                                  800
via-router-test-low     203.0.113.0/24                   default-internet-gateway      1200
```

> Traffic to `203.0.113.0/24` goes through `router-vm` (priority 800) because it has higher priority than the internet gateway route (priority 1200).

### Cleanup

```bash
# Delete custom routes
gcloud compute routes delete drop-test-traffic --quiet
gcloud compute routes delete via-router-test --quiet
gcloud compute routes delete via-router-test-low --quiet

# Delete VMs
gcloud compute instances delete vm-a --zone=${ZONE} --quiet
gcloud compute instances delete vm-b --zone=${ZONE} --quiet
gcloud compute instances delete router-vm --zone=${ZONE} --quiet

# Delete firewall rules
for RULE in $(gcloud compute firewall-rules list --filter="network=${VPC_NAME}" --format="value(name)"); do
    gcloud compute firewall-rules delete ${RULE} --quiet
done

# Delete subnets and VPC
gcloud compute networks subnets delete ${SUBNET_A} --region=${REGION} --quiet
gcloud compute networks subnets delete ${SUBNET_B} --region=${REGION} --quiet
gcloud compute networks delete ${VPC_NAME} --quiet
```

---

## Part 3: Revision (15 min)

### Key Concepts

- **Subnet routes** (priority 0) are auto-created and cannot be overridden or deleted
- **Default route** (`0.0.0.0/0`, priority 1000) provides internet access — can be deleted
- **Longest prefix match** wins first, then **lowest priority number** wins
- **`--can-ip-forward`** must be enabled on VMs acting as routers/NAT (like `sysctl net.ipv4.ip_forward=1`)
- Next-hops: internet gateway, instance, IP address, VPN tunnel, ILB
- **Policy-based routes** match on source + destination (advanced)
- Routes can be **tagged** to apply only to VMs with matching network tags
- **Dynamic routes** come from Cloud Router via BGP (used with VPN/Interconnect)
- When two routes have the same destination and priority, GCP uses ECMP (Equal-Cost Multi-Path)
- Deleting the default route isolates VMs from the internet (useful for high-security environments)

### Key Commands

```bash
# List all routes for a VPC
gcloud compute routes list --filter="network=VPC_NAME"

# Create custom static route
gcloud compute routes create NAME \
    --network=VPC --destination-range=CIDR --next-hop-address=IP --priority=N

# Create route via instance
gcloud compute routes create NAME \
    --network=VPC --destination-range=CIDR --next-hop-instance=VM --next-hop-instance-zone=ZONE

# Describe a route
gcloud compute routes describe ROUTE_NAME

# Delete a route
gcloud compute routes delete ROUTE_NAME

# Enable IP forwarding on a VM (at creation)
gcloud compute instances create NAME --can-ip-forward

# Check route table inside a VM
ip route show
```

---

## Part 4: Quiz (15 min)

**Question 1:** You have two routes: Route A (`10.1.0.0/24`, priority 500) and Route B (`10.1.0.0/16`, priority 100). A packet is destined for `10.1.0.50`. Which route is used?

<details>
<summary>Click to reveal answer</summary>

**Route A** (`10.1.0.0/24`, priority 500) is used.

GCP uses **longest prefix match first**, then priority. `/24` is more specific than `/16`, so Route A wins regardless of priority. Priority only breaks ties when two routes have the **same prefix length**.

This is the same behaviour as the Linux kernel routing table.

</details>

---

**Question 2:** You create a VM to act as a NAT gateway for other VMs. Traffic reaches the VM but gets dropped. What did you forget?

<details>
<summary>Click to reveal answer</summary>

You forgot to enable **IP forwarding** on the VM.

```bash
gcloud compute instances create nat-vm --can-ip-forward
```

By default, GCP drops packets that are not destined for the VM's own IP address. The `--can-ip-forward` flag tells GCP to allow the VM to forward packets (like setting `sysctl net.ipv4.ip_forward=1` in Linux).

If the VM already exists, you must stop it, enable IP forwarding, and restart:
```bash
gcloud compute instances stop nat-vm --zone=ZONE
# Use Console or API to update canIpForward
gcloud compute instances start nat-vm --zone=ZONE
```

</details>

---

**Question 3:** Can you create a custom route that overrides a subnet route?

<details>
<summary>Click to reveal answer</summary>

**No.** Subnet routes have priority `0` — the highest possible. You cannot create a route with priority 0, and you cannot create a route with the same destination as a subnet route.

The only way to remove a subnet route is to delete the subnet itself.

This is a safety mechanism — it ensures VMs in a subnet can always reach each other via the subnet's internal routing.

</details>

---

**Question 4:** You delete the default route (`0.0.0.0/0`) from your VPC. What happens to your VMs?

<details>
<summary>Click to reveal answer</summary>

VMs **lose all internet access** — they can no longer reach external IPs. However:

- **Internal communication** still works (subnet routes are unaffected)
- **IAP SSH** still works (IAP uses Google's internal infrastructure)
- **Private Google Access** still works (if enabled on the subnet)

This is actually a **security best practice** for sensitive workloads. You can delete the default route and use Cloud NAT or VPN for controlled outbound access.

To restore:
```bash
gcloud compute routes create restore-default \
    --network=VPC_NAME \
    --destination-range=0.0.0.0/0 \
    --next-hop-gateway=default-internet-gateway \
    --priority=1000
```

</details>

---

**End of Day 10** — Tomorrow: Cloud NAT
