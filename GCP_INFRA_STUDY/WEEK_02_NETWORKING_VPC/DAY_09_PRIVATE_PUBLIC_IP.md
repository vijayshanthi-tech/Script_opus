# Week 2, Day 9 (Wed) — Private vs Public IP, Internal Connectivity

> **Study time:** 2 hours | **Prereqs:** Day 7–8 (VPC, Firewall Rules)  
> **Region:** `europe-west2` (London)

---

## Part 1: Concept (30 min)

### IP Address Types in GCP

Every VM gets an **internal (private) IP** automatically. An **external (public) IP** is optional.

```
┌─────────────────────────────────────────────────────────────┐
│                         INTERNET                             │
│                            │                                 │
│                     ┌──────┴──────┐                         │
│                     │ External IP  │                         │
│                     │ 34.89.x.x   │ (optional)              │
│                     └──────┬──────┘                         │
│                            │                                 │
│  ┌─────────────────────────┼───────────────────────────┐    │
│  │                    VPC  │                             │    │
│  │              ┌──────────┴──────────┐                 │    │
│  │              │      VM Instance     │                 │    │
│  │              │                      │                 │    │
│  │              │  Internal IP:        │                 │    │
│  │              │  10.10.0.2           │                 │    │
│  │              │  (always assigned)   │                 │    │
│  │              │                      │                 │    │
│  │              │  External IP:        │                 │    │
│  │              │  34.89.12.34         │                 │    │
│  │              │  (optional)          │                 │    │
│  │              └─────────────────────┘                 │    │
│  └──────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Internal IP (Private)

| Property | Detail |
|---|---|
| **Assignment** | Automatic from subnet CIDR range |
| **Scope** | Within the VPC |
| **Persistence** | Stays the same until VM is deleted |
| **Can be static?** | Yes — reserve an internal static IP |
| **DNS** | Auto-registered: `VM_NAME.ZONE.c.PROJECT_ID.internal` |
| **Cost** | Free |

**Linux analogy:** Like the IP assigned to `eth0` on a private LAN. Equivalent to `ip addr show eth0`.

### External IP (Public)

| Property | Ephemeral | Static |
|---|---|---|
| **Assignment** | Auto-assigned at boot | You reserve and assign |
| **Persistence** | Changes on stop/start | Stays until you release |
| **Cost** | Free while VM runs | Charged when NOT attached to a running VM |
| **Use case** | Dev/test | Production, DNS records |

**Linux analogy:** Ephemeral external IP is like a DHCP lease on a public interface — you get a new IP each time. Static is like a dedicated public IP from your ISP.

### When Does a VM Need an External IP?

```
  ┌─────────────────────────────────────────────────────┐
  │          Does the VM need internet access?           │
  └────────────────────────┬────────────────────────────┘
                           │
                    ┌──────┴──────┐
                    │             │
                   YES           NO
                    │             │
           ┌────────┴────────┐   └─── Internal only ✅
           │                 │
    Inbound from        Outbound to
    internet?            internet?
           │                 │
      ┌────┴────┐      ┌────┴────┐
      │         │      │         │
     YES       NO     YES       NO
      │         │      │         │
  External   Use     Cloud    Internal
  IP needed  Load    NAT      only ✅
  (or LB)    Bal     (no ext
              +      IP needed)
            backend
```

### Private Google Access

VMs **without external IPs** cannot reach Google APIs (like Cloud Storage, BigQuery) by default. **Private Google Access** fixes this.

```
WITHOUT Private Google Access:
  ┌──────────┐                    ┌──────────────┐
  │ VM       │───── X ──────────► │ Google APIs   │
  │ (no ext  │  Can't reach      │ (storage,     │
  │  IP)     │                    │  bigquery)    │
  └──────────┘                    └──────────────┘

WITH Private Google Access:
  ┌──────────┐                    ┌──────────────┐
  │ VM       │─── ✅ ───────────► │ Google APIs   │
  │ (no ext  │  Via internal      │ (storage,     │
  │  IP)     │  routing           │  bigquery)    │
  └──────────┘                    └──────────────┘
```

**Key point:** Private Google Access is enabled **per subnet**, not per VM.

### Cloud NAT Overview

**Cloud NAT** allows VMs without external IPs to reach the internet for outbound connections (e.g., `apt update`, downloading packages).

```
  ┌──────────┐     ┌───────────┐     ┌───────────┐
  │ VM       │────►│ Cloud NAT  │────►│ Internet   │
  │ (no ext  │     │ Gateway    │     │            │
  │  IP)     │     │            │     │            │
  └──────────┘     │ Translates │     └───────────┘
                   │ internal IP│
                   │ to NAT IP  │
                   └───────────┘
```

**Linux analogy:** Exactly like `iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE`. Cloud NAT does SNAT (Source NAT) for outbound traffic.

> Cloud NAT is covered in depth on Day 11.

### Internal DNS

GCP automatically creates DNS entries for VMs:

```
Format:  VM_NAME.ZONE.c.PROJECT_ID.internal

Example: web-vm.europe-west2-a.c.my-project-123.internal
```

VMs in the same VPC can resolve each other by hostname. This is like having a local `/etc/hosts` or `dnsmasq` auto-configured.

### Summary Table

| Feature | Internal IP | Ephemeral External | Static External |
|---|---|---|---|
| **Assigned** | Always | On create (optional) | You reserve |
| **Changes** | On delete only | On stop/start | Never (until released) |
| **Internet access** | No (need NAT/ext IP) | Yes, both ways | Yes, both ways |
| **Google API access** | Need Private Google Access | Yes | Yes |
| **Cost** | Free | Free (running VM) | Charged if unattached |

---

## Part 2: Hands-On Lab (60 min)

### Lab Objective
Create 2 VMs (one with external IP, one without). Test connectivity between them, test internet access, and enable Private Google Access.

### Step 0: Set Up VPC

```bash
export VPC_NAME="ip-lab-vpc"
export SUBNET_NAME="ip-lab-subnet"
export REGION="europe-west2"
export ZONE="europe-west2-a"

gcloud compute networks create ${VPC_NAME} --subnet-mode=custom

gcloud compute networks subnets create ${SUBNET_NAME} \
    --network=${VPC_NAME} \
    --region=${REGION} \
    --range=10.20.0.0/24

# Allow SSH via IAP
gcloud compute firewall-rules create ${VPC_NAME}-allow-ssh-iap \
    --network=${VPC_NAME} \
    --allow=tcp:22 \
    --source-ranges=35.235.240.0/20

# Allow internal ICMP
gcloud compute firewall-rules create ${VPC_NAME}-allow-internal \
    --network=${VPC_NAME} \
    --allow=icmp,tcp,udp \
    --source-ranges=10.20.0.0/24
```

### Step 1: Create VM WITH External IP

```bash
gcloud compute instances create vm-public \
    --zone=${ZONE} \
    --machine-type=e2-micro \
    --network=${VPC_NAME} \
    --subnet=${SUBNET_NAME} \
    --image-family=debian-12 \
    --image-project=debian-cloud
```

> By default, a VM gets an ephemeral external IP.

### Step 2: Create VM WITHOUT External IP

```bash
gcloud compute instances create vm-private \
    --zone=${ZONE} \
    --machine-type=e2-micro \
    --network=${VPC_NAME} \
    --subnet=${SUBNET_NAME} \
    --no-address \
    --image-family=debian-12 \
    --image-project=debian-cloud
```

### Step 3: Verify IP Assignments

```bash
gcloud compute instances list \
    --filter="name:(vm-public OR vm-private)" \
    --format="table(name, networkInterfaces[0].networkIP:label=INTERNAL_IP, networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)"
```

**Expected output:**
```
NAME        INTERNAL_IP  EXTERNAL_IP
vm-private  10.20.0.3
vm-public   10.20.0.2    34.89.XX.XX
```

> Notice `vm-private` has no external IP.

### Step 4: Test Internal Connectivity (Ping Between VMs)

```bash
# Get internal IP of vm-private
PRIVATE_IP=$(gcloud compute instances describe vm-private \
    --zone=${ZONE} \
    --format="get(networkInterfaces[0].networkIP)")

# SSH to vm-public and ping vm-private
gcloud compute ssh vm-public --zone=${ZONE} --tunnel-through-iap \
    --command="ping -c 3 ${PRIVATE_IP}"
```

**Expected output:**
```
PING 10.20.0.3 (10.20.0.3) 56(84) bytes of data.
64 bytes from 10.20.0.3: icmp_seq=1 ttl=64 time=0.8 ms
64 bytes from 10.20.0.3: icmp_seq=2 ttl=64 time=0.3 ms
64 bytes from 10.20.0.3: icmp_seq=3 ttl=64 time=0.3 ms
```

> Internal connectivity works regardless of external IP assignment.

### Step 5: Test Internet Access

```bash
# From vm-public (HAS external IP) — WORKS
gcloud compute ssh vm-public --zone=${ZONE} --tunnel-through-iap \
    --command="curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://example.com"
# Output: 200

# From vm-private (NO external IP) — FAILS
gcloud compute ssh vm-private --zone=${ZONE} --tunnel-through-iap \
    --command="curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://example.com || echo 'FAILED: No internet'"
# Output: FAILED: No internet
```

### Step 6: Test Google API Access (Without Private Google Access)

```bash
# From vm-private — try to access Cloud Storage API
gcloud compute ssh vm-private --zone=${ZONE} --tunnel-through-iap \
    --command="curl -s --max-time 5 https://storage.googleapis.com || echo 'FAILED: Cannot reach Google APIs'"
# Output: FAILED: Cannot reach Google APIs
```

### Step 7: Enable Private Google Access

```bash
gcloud compute networks subnets update ${SUBNET_NAME} \
    --region=${REGION} \
    --enable-private-ip-google-access
```

```bash
# Verify it's enabled
gcloud compute networks subnets describe ${SUBNET_NAME} \
    --region=${REGION} \
    --format="get(privateIpGoogleAccess)"
# Output: True
```

### Step 8: Test Google API Access (With Private Google Access)

```bash
# From vm-private — try Google APIs again
gcloud compute ssh vm-private --zone=${ZONE} --tunnel-through-iap \
    --command="curl -s --max-time 10 -o /dev/null -w '%{http_code}' https://storage.googleapis.com"
# Output: 200 (or valid response)
```

> Private Google Access allows `vm-private` to reach Google APIs via internal routing, but it still **cannot** reach the general internet (e.g., `example.com`).

### Step 9: Reserve a Static External IP

```bash
# Reserve a static external IP
gcloud compute addresses create my-static-ip \
    --region=${REGION}

# View the reserved IP
gcloud compute addresses describe my-static-ip \
    --region=${REGION} \
    --format="get(address)"
```

```bash
# Assign to a new VM (or existing via instance stop/set/start)
STATIC_IP=$(gcloud compute addresses describe my-static-ip \
    --region=${REGION} --format="get(address)")

echo "Reserved static IP: ${STATIC_IP}"
```

### Step 10: Verify DNS Resolution

```bash
# From vm-public, resolve vm-private by internal DNS name
gcloud compute ssh vm-public --zone=${ZONE} --tunnel-through-iap \
    --command="ping -c 2 vm-private.${ZONE}.c.$(gcloud config get-value project).internal"
```

### Cleanup

```bash
# Delete VMs
gcloud compute instances delete vm-public --zone=${ZONE} --quiet
gcloud compute instances delete vm-private --zone=${ZONE} --quiet

# Release static IP
gcloud compute addresses delete my-static-ip --region=${REGION} --quiet

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

- Every VM gets an **internal (private) IP** automatically from its subnet's CIDR
- **External IP** is optional — ephemeral (changes on stop/start) or static (persists)
- VMs in the **same VPC** can communicate via internal IPs regardless of external IP
- VMs **without external IPs** cannot reach the internet (need Cloud NAT)
- **Private Google Access** (per subnet) allows no-external-IP VMs to reach Google APIs
- Private Google Access does **NOT** give general internet access
- **Static external IPs** cost money when not attached to a running VM
- Internal DNS: `VM_NAME.ZONE.c.PROJECT_ID.internal`
- Use **`--no-address`** flag to create a VM without an external IP
- **Best practice:** Minimize external IPs; use IAP for SSH, Cloud NAT for outbound

### Key Commands

```bash
# Create VM without external IP
gcloud compute instances create NAME --no-address

# Reserve static external IP
gcloud compute addresses create NAME --region=REGION

# List reserved IPs
gcloud compute addresses list

# Enable Private Google Access on a subnet
gcloud compute networks subnets update NAME --region=REGION --enable-private-ip-google-access

# Check if Private Google Access is enabled
gcloud compute networks subnets describe NAME --region=REGION --format="get(privateIpGoogleAccess)"

# View VM IP addresses
gcloud compute instances describe NAME --zone=ZONE \
    --format="get(networkInterfaces[0].networkIP, networkInterfaces[0].accessConfigs[0].natIP)"
```

---

## Part 4: Quiz (15 min)

**Question 1:** A VM has no external IP. Can it communicate with another VM in the same VPC that does have an external IP?

<details>
<summary>Click to reveal answer</summary>

**Yes.** Internal communication within the same VPC uses internal (private) IPs and the VPC's internal routing. The external IP of the other VM is irrelevant for this communication.

The traffic path is: `vm-private (10.20.0.3)` → VPC route table → subnet route → `vm-public (10.20.0.2)`. External IPs are only used for internet-facing traffic.

</details>

---

**Question 2:** You enable Private Google Access on a subnet. Can VMs in that subnet now run `apt update` to download packages from the Debian repositories?

<details>
<summary>Click to reveal answer</summary>

**No.** Private Google Access only enables access to **Google APIs and services** (Cloud Storage, BigQuery, Container Registry, etc.). It does NOT provide general internet access.

To reach external sites like Debian repositories, the VM needs either:
- An external IP, OR
- Cloud NAT configured on the subnet's region

However, if you configure your VM to use Google's apt mirror (`packages.cloud.google.com`), those would work via Private Google Access.

</details>

---

**Question 3:** What is the cost difference between an ephemeral and static external IP?

<details>
<summary>Click to reveal answer</summary>

| Scenario | Ephemeral | Static |
|---|---|---|
| Attached to running VM | Free | Free |
| Attached to stopped VM | N/A (released on stop) | **Charged** |
| Not attached to any VM | N/A | **Charged** |

The key difference: ephemeral IPs are released when the VM stops (you get a new one on restart). Static IPs are reserved for you — and **you pay for them when they're idle** (not attached to a running VM).

This is why you should release static IPs when not in use:
```bash
gcloud compute addresses delete my-static-ip --region=REGION --quiet
```

</details>

---

**Question 4:** A colleague creates a VM without an external IP and complains they can't SSH into it from Cloud Shell. What's the recommended solution?

<details>
<summary>Click to reveal answer</summary>

Use **Identity-Aware Proxy (IAP) TCP forwarding**:

```bash
gcloud compute ssh vm-name --zone=ZONE --tunnel-through-iap
```

IAP tunnels the SSH connection through Google's infrastructure to the VM's internal IP. Requirements:
1. Firewall rule allowing tcp:22 from `35.235.240.0/20` (IAP range)
2. The user must have the `iap.tunnelResourceAccessor` IAM role
3. The IAP API must be enabled on the project

This is the **recommended** approach for SSH — it eliminates the need for external IPs and provides auditable, identity-based access.

</details>

---

**End of Day 9** — Tomorrow: Routes Deep Dive
