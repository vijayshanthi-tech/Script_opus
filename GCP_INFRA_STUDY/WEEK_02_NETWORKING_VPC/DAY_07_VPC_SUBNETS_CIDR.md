# Week 2, Day 7 (Mon) — VPC, Subnets, CIDR, Routes

> **Study time:** 2 hours | **Prereqs:** Week 1 complete, ACE-level GCP familiarity  
> **Region:** `europe-west2` (London) | **Secondary:** `us-central1` (Iowa)

---

## Part 1: Concept (30 min)

### What Is a VPC?

A **Virtual Private Cloud (VPC)** is a software-defined network that spans all GCP regions globally. Unlike AWS VPCs (which are regional), a single GCP VPC is a **global resource**.

**Linux analogy:** Think of a VPC as your entire network namespace (`ip netns`). Just as a network namespace isolates routing tables, iptables rules, and interfaces, a VPC isolates your cloud network from other projects.

```
┌──────────────────────────────────────────────────────────────────┐
│                        GCP PROJECT                               │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                    VPC (Global)                             │  │
│  │                                                            │  │
│  │  ┌─────────────────┐          ┌─────────────────┐         │  │
│  │  │  Subnet A        │          │  Subnet B        │         │  │
│  │  │  europe-west2    │          │  us-central1     │         │  │
│  │  │  10.1.0.0/24     │          │  10.2.0.0/24     │         │  │
│  │  │                  │          │                  │         │  │
│  │  │  ┌────┐ ┌────┐  │          │  ┌────┐ ┌────┐  │         │  │
│  │  │  │VM-1│ │VM-2│  │◄────────►│  │VM-3│ │VM-4│  │         │  │
│  │  │  └────┘ └────┘  │  Routes  │  └────┘ └────┘  │         │  │
│  │  └─────────────────┘          └─────────────────┘         │  │
│  │                                                            │  │
│  │           Firewall Rules (Applied at VPC level)            │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### Key VPC Properties

| Property | Detail |
|---|---|
| **Scope** | Global (spans all regions) |
| **Subnets** | Regional (one region each) |
| **Firewall rules** | Applied at VPC level, filter per-VM |
| **Routes** | Applied at VPC level |
| **IP ranges** | Defined per subnet (CIDR) |
| **MTU** | 1460 bytes default (can be 1500) |

### Auto-Mode vs Custom-Mode VPC

| Feature | Auto-Mode VPC | Custom-Mode VPC |
|---|---|---|
| **Subnet creation** | One subnet per region automatically | You create subnets manually |
| **CIDR range** | `10.128.0.0/20` per region (predefined) | You choose the CIDR |
| **Use case** | Quick prototyping, dev/test | Production, controlled IP planning |
| **Flexibility** | Low — can't change ranges | High — full control |
| **Default VPC** | Yes, every project gets one | No, must be created |
| **Can convert?** | Auto → Custom (one-way) | N/A |

**Linux analogy:** Auto-mode is like running `dhclient` and getting whatever IP the DHCP server gives you. Custom-mode is like manually configuring `/etc/network/interfaces` with your own static IP plan.

> **Best Practice:** Always use **custom-mode VPC** in production. Auto-mode ranges can overlap with on-premises networks and you cannot delete auto-created subnets.

### CIDR Notation Refresher

CIDR (Classless Inter-Domain Routing) defines IP ranges using a prefix length.

```
   IP Address:   10.1.0.0
   Subnet Mask:  /24 = 255.255.255.0
   
   Binary:  10.1.0.  00000000
                     ^^^^^^^^
                     Host bits (8 bits = 256 addresses)
                     
   Usable:  10.1.0.0  → Network address (reserved by GCP)
            10.1.0.1  → Default gateway (reserved by GCP)
            10.1.0.2  → 10.1.0.253 (usable)
            10.1.0.254 → reserved
            10.1.0.255 → Broadcast (reserved)
```

### RFC 1918 Private IP Ranges

| Range | CIDR | Total IPs | Common Use |
|---|---|---|---|
| `10.0.0.0/8` | 10.0.0.0 – 10.255.255.255 | 16,777,216 | Large enterprises |
| `172.16.0.0/12` | 172.16.0.0 – 172.31.255.255 | 1,048,576 | Medium networks |
| `192.168.0.0/16` | 192.168.0.0 – 192.168.255.255 | 65,536 | Home/small networks |

### GCP Subnet Rules

- Minimum subnet size: `/29` (8 IPs, 4 usable)
- Maximum subnet size: `/8`
- GCP reserves **4 IPs** per subnet (first two + last two)
- Subnets **cannot overlap** within a VPC
- Subnets **can be expanded** (increase range) but **never shrunk**

### Quick CIDR Cheat Sheet

| CIDR | Hosts | Usable (GCP) | Use Case |
|---|---|---|---|
| `/28` | 16 | 12 | Tiny test subnet |
| `/24` | 256 | 252 | Standard workload |
| `/20` | 4,096 | 4,092 | Large workload |
| `/16` | 65,536 | 65,532 | Very large environment |

### Routes in a VPC

When you create a VPC and subnets, GCP automatically creates:

1. **Default route** (`0.0.0.0/0`) → Internet gateway (if subnet has external IPs)
2. **Subnet routes** → One per subnet, for internal communication

```
┌─────────────────────────────────────────────────┐
│              VPC Route Table                      │
│                                                   │
│  Destination       Next-Hop          Type         │
│  ─────────────     ────────────      ──────────   │
│  10.1.0.0/24       Subnet A          System       │
│  10.2.0.0/24       Subnet B          System       │
│  0.0.0.0/0         Internet GW       System       │
└─────────────────────────────────────────────────┘
```

**Linux analogy:** This is exactly like `ip route show`:
```bash
# Linux equivalent
10.1.0.0/24 dev eth0 proto kernel scope link src 10.1.0.2
default via 10.1.0.1 dev eth0
```

---

## Part 2: Hands-On Lab (60 min)

### Lab Objective
Create a custom-mode VPC with 2 subnets in different regions, verify routes, and launch a VM in each subnet.

### Step 0: Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export VPC_NAME="lab-vpc-week2"
export SUBNET_EU="subnet-eu-west2"
export SUBNET_US="subnet-us-central1"
export REGION_EU="europe-west2"
export REGION_US="us-central1"
export ZONE_EU="europe-west2-a"
export ZONE_US="us-central1-a"
```

### Step 1: Create Custom-Mode VPC

```bash
gcloud compute networks create ${VPC_NAME} \
    --subnet-mode=custom \
    --bgp-routing-mode=regional \
    --description="Week 2 Lab - Custom VPC"
```

**Expected output:**
```
Created [https://www.googleapis.com/compute/v1/projects/PROJECT_ID/global/networks/lab-vpc-week2].
NAME            SUBNET_MODE  BGP_ROUTING_MODE  IPV4_RANGE  GATEWAY_IPV4
lab-vpc-week2   CUSTOM       REGIONAL
```

### Step 2: Create Subnet in europe-west2

```bash
gcloud compute networks subnets create ${SUBNET_EU} \
    --network=${VPC_NAME} \
    --region=${REGION_EU} \
    --range=10.1.0.0/24 \
    --description="EU West2 subnet"
```

**Expected output:**
```
Created [https://www.googleapis.com/compute/v1/projects/PROJECT_ID/regions/europe-west2/subnetworks/subnet-eu-west2].
NAME              REGION         NETWORK        RANGE        STACK_TYPE
subnet-eu-west2   europe-west2   lab-vpc-week2  10.1.0.0/24  IPV4_ONLY
```

### Step 3: Create Subnet in us-central1

```bash
gcloud compute networks subnets create ${SUBNET_US} \
    --network=${VPC_NAME} \
    --region=${REGION_US} \
    --range=10.2.0.0/24 \
    --description="US Central1 subnet"
```

### Step 4: Verify the VPC and Subnets

```bash
# List subnets in the VPC
gcloud compute networks subnets list \
    --network=${VPC_NAME} \
    --format="table(name, region, ipCidrRange)"
```

**Expected output:**
```
NAME                 REGION         IP_CIDR_RANGE
subnet-eu-west2      europe-west2   10.1.0.0/24
subnet-us-central1   us-central1    10.2.0.0/24
```

### Step 5: Inspect Routes

```bash
gcloud compute routes list \
    --filter="network=${VPC_NAME}" \
    --format="table(name, destRange, nextHopGateway.basename(), priority)"
```

**Expected output:**
```
NAME                                    DEST_RANGE     NEXT_HOP       PRIORITY
default-route-xxxxxxxx                  0.0.0.0/0      default-internet-gateway  1000
default-route-xxxxxxxx                  10.1.0.0/24                              0
default-route-xxxxxxxx                  10.2.0.0/24                              0
```

> Notice: Subnet routes have priority `0` (highest). The default internet route has priority `1000`.

### Step 6: Create Firewall Rules (Allow ICMP + SSH)

```bash
# Allow ICMP (ping) within the VPC
gcloud compute firewall-rules create ${VPC_NAME}-allow-icmp \
    --network=${VPC_NAME} \
    --allow=icmp \
    --source-ranges=10.0.0.0/8 \
    --description="Allow ICMP internally"

# Allow SSH from IAP (Identity-Aware Proxy)
gcloud compute firewall-rules create ${VPC_NAME}-allow-ssh-iap \
    --network=${VPC_NAME} \
    --allow=tcp:22 \
    --source-ranges=35.235.240.0/20 \
    --description="Allow SSH via IAP"
```

### Step 7: Create VM in EU Subnet

```bash
gcloud compute instances create vm-eu \
    --zone=${ZONE_EU} \
    --machine-type=e2-micro \
    --network=${VPC_NAME} \
    --subnet=${SUBNET_EU} \
    --no-address \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y iputils-ping'
```

### Step 8: Create VM in US Subnet

```bash
gcloud compute instances create vm-us \
    --zone=${ZONE_US} \
    --machine-type=e2-micro \
    --network=${VPC_NAME} \
    --subnet=${SUBNET_US} \
    --no-address \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y iputils-ping'
```

### Step 9: Verify Internal Connectivity

```bash
# Get the internal IP of vm-us
VM_US_IP=$(gcloud compute instances describe vm-us \
    --zone=${ZONE_US} \
    --format="get(networkInterfaces[0].networkIP)")

echo "VM-US internal IP: ${VM_US_IP}"

# SSH into vm-eu and ping vm-us
gcloud compute ssh vm-eu --zone=${ZONE_EU} --tunnel-through-iap \
    --command="ping -c 3 ${VM_US_IP}"
```

**Expected output:**
```
PING 10.2.0.2 (10.2.0.2) 56(84) bytes of data.
64 bytes from 10.2.0.2: icmp_seq=1 ttl=64 time=98.2 ms
64 bytes from 10.2.0.2: icmp_seq=2 ttl=64 time=97.8 ms
64 bytes from 10.2.0.2: icmp_seq=3 ttl=64 time=97.5 ms
```

> Cross-region ping works because both subnets are in the same VPC. GCP handles routing automatically via subnet routes.

### Step 10: Draw Your Network Diagram

Document what you built:

```
┌──────────────────────────────────────────────────────────────┐
│                    lab-vpc-week2 (Custom VPC)                 │
│                                                              │
│   europe-west2                      us-central1              │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │ subnet-eu-west2   │           │ subnet-us-central1│        │
│  │ 10.1.0.0/24       │           │ 10.2.0.0/24      │        │
│  │                    │           │                   │        │
│  │   ┌──────────┐    │  Route    │   ┌──────────┐   │        │
│  │   │  vm-eu   │    │◄────────►│   │  vm-us   │   │        │
│  │   │ 10.1.0.X │    │  (auto)  │   │ 10.2.0.X │   │        │
│  │   │ no ext IP│    │           │   │ no ext IP│   │        │
│  │   └──────────┘    │           │   └──────────┘   │        │
│  └──────────────────┘           └──────────────────┘        │
│                                                              │
│  Firewall: allow-icmp (10.0.0.0/8), allow-ssh-iap           │
└──────────────────────────────────────────────────────────────┘
```

### Cleanup

```bash
# Delete VMs
gcloud compute instances delete vm-eu --zone=${ZONE_EU} --quiet
gcloud compute instances delete vm-us --zone=${ZONE_US} --quiet

# Delete firewall rules
gcloud compute firewall-rules delete ${VPC_NAME}-allow-icmp --quiet
gcloud compute firewall-rules delete ${VPC_NAME}-allow-ssh-iap --quiet

# Delete subnets
gcloud compute networks subnets delete ${SUBNET_EU} --region=${REGION_EU} --quiet
gcloud compute networks subnets delete ${SUBNET_US} --region=${REGION_US} --quiet

# Delete VPC
gcloud compute networks delete ${VPC_NAME} --quiet
```

---

## Part 3: Revision (15 min)

### Key Concepts

- A **VPC** is a global resource; subnets are regional
- **Auto-mode VPC**: one subnet per region with predefined `10.128.x.x/20` ranges — avoid in production
- **Custom-mode VPC**: you define subnets and CIDR ranges — always use this
- **CIDR** defines IP ranges: `/24` = 256 IPs, `/20` = 4,096 IPs
- GCP **reserves 4 IPs** per subnet (first 2 + last 2)
- **Subnet routes** are auto-created (priority 0) — one per subnet
- **Default route** (`0.0.0.0/0`) points to internet gateway (priority 1000)
- VMs in the **same VPC** can communicate across regions via internal IPs
- Subnets can be **expanded** (larger CIDR) but never shrunk
- **No cost** for cross-region traffic within the same VPC using internal IPs (ingress is free, egress is charged)

### Key Commands

```bash
# Create custom VPC
gcloud compute networks create NAME --subnet-mode=custom

# Create subnet
gcloud compute networks subnets create NAME --network=VPC --region=REGION --range=CIDR

# List subnets
gcloud compute networks subnets list --network=VPC

# List routes
gcloud compute routes list --filter="network=VPC"

# Describe a subnet
gcloud compute networks subnets describe NAME --region=REGION

# Expand subnet (increase CIDR)
gcloud compute networks subnets expand-ip-range NAME --region=REGION --prefix-length=NEW_PREFIX
```

---

## Part 4: Quiz (15 min)

**Question 1:** You create a custom VPC with a `/24` subnet. How many usable IP addresses do VMs get?

<details>
<summary>Click to reveal answer</summary>

**252 usable IPs.**

A `/24` has 256 total addresses. GCP reserves 4:
- First address (network): `x.x.x.0`
- Second address (gateway): `x.x.x.1`
- Second-to-last: `x.x.x.254` (reserved)
- Last address (broadcast): `x.x.x.255`

256 - 4 = **252 usable**.

</details>

---

**Question 2:** What is the key difference between an auto-mode and custom-mode VPC?

<details>
<summary>Click to reveal answer</summary>

**Auto-mode VPC** automatically creates one subnet in every region with predefined IP ranges (`10.128.0.0/20` pattern). You cannot control the CIDR ranges.

**Custom-mode VPC** starts with no subnets. You manually create subnets with your own CIDR ranges in the regions you choose.

Auto-mode can be converted to custom-mode (one-way), but custom cannot be converted to auto. Always use custom-mode in production to maintain IP planning control and avoid overlaps with on-premises networks.

</details>

---

**Question 3:** A VM in `europe-west2` (10.1.0.5) wants to reach a VM in `us-central1` (10.2.0.10). Both are in the same VPC. What route makes this work?

<details>
<summary>Click to reveal answer</summary>

The **system-generated subnet route** for `10.2.0.0/24` (priority 0) handles this automatically.

When you create a subnet, GCP creates a corresponding route that directs traffic for that CIDR to the subnet. Since both subnets are in the same VPC, the route table knows how to forward packets between them — no additional configuration needed.

The routing path: `vm-eu` → VPC route table → subnet route for `10.2.0.0/24` → `vm-us`.

This is different from AWS, where you'd need VPC peering for cross-region communication. In GCP, a single VPC is global.

</details>

---

**Question 4:** You need to add more IPs to an existing `/24` subnet. What command do you use, and what is the limitation?

<details>
<summary>Click to reveal answer</summary>

Use `gcloud compute networks subnets expand-ip-range`:

```bash
gcloud compute networks subnets expand-ip-range subnet-eu-west2 \
    --region=europe-west2 \
    --prefix-length=20
```

This expands from `/24` (256 IPs) to `/20` (4,096 IPs).

**Limitation:** You can only **expand** (make the prefix shorter, e.g., `/24` → `/20`). You can **never shrink** a subnet. The new range must not overlap with other subnets in the VPC.

</details>

---

**End of Day 7** — Tomorrow: Firewall Rules (Ingress/Egress) + Tags
