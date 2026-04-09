# Week 2, Day 12 (Sat) — PROJECT: Secure VPC + 2-Tier VM Setup

> **Study time:** 2+ hours | **Prereqs:** Days 7–11 (all Week 2 topics)  
> **Region:** `europe-west2` (London)  
> **Type:** End-of-week hands-on project — combines VPC, subnets, firewall rules, IP addressing, routes, and Cloud NAT

---

## Architecture Diagram

```
                          INTERNET
                             │
                   ┌─────────┴─────────┐
                   │   Cloud NAT        │ (outbound only for app-tier)
                   │   nat-project-gw   │
                   └─────────┬─────────┘
                             │
                   ┌─────────┴─────────┐
                   │   Cloud Router     │ project-router
                   └─────────┬─────────┘
                             │
┌────────────────────────────┼────────────────────────────────────┐
│                    project-vpc (Custom VPC)                      │
│                                                                  │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                                                          │  │
│   │   ┌─────────────────────┐   ┌────────────────────────┐  │  │
│   │   │   WEB-TIER SUBNET   │   │   APP-TIER SUBNET      │  │  │
│   │   │   10.50.1.0/24      │   │   10.50.2.0/24         │  │  │
│   │   │   europe-west2      │   │   europe-west2         │  │  │
│   │   │                     │   │                        │  │  │
│   │   │   ┌─────────────┐   │   │   ┌─────────────┐     │  │  │
│   │   │   │  web-server  │   │   │   │  app-server  │     │  │  │
│   │   │   │  nginx       │   │   │   │  no ext IP   │     │  │  │
│   │   │   │  ext IP      │   │   │   │  Cloud NAT   │     │  │  │
│   │   │   │  :80 open    │   │   │   │  for outbound│     │  │  │
│   │   │   └──────┬──────┘   │   │   └──────┬───────┘     │  │  │
│   │   │          │          │   │          │             │  │  │
│   │   └──────────┼──────────┘   └──────────┼─────────────┘  │  │
│   │              │                          │                │  │
│   │              └──────────────────────────┘                │  │
│   │                 Internal communication                   │  │
│   │                 (tcp, udp, icmp allowed)                 │  │
│   └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│   FIREWALL RULES:                                                │
│   ┌────────────────────────────────────────────────────────┐    │
│   │ 1. SSH via IAP only (35.235.240.0/20 → tcp:22)        │    │
│   │ 2. HTTP to web-tier (0.0.0.0/0 → tcp:80, tag:web)     │    │
│   │ 3. Internal between tiers (10.50.0.0/16 → all)        │    │
│   │ 4. Deny all other ingress (implied, priority 65535)    │    │
│   └────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Build

### Phase 1: Network Foundation

#### 1.1 Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export VPC_NAME="project-vpc"
export SUBNET_WEB="web-tier"
export SUBNET_APP="app-tier"
export REGION="europe-west2"
export ZONE="europe-west2-a"
export ROUTER_NAME="project-router"
export NAT_NAME="nat-project-gw"
```

#### 1.2 Create Custom VPC

```bash
gcloud compute networks create ${VPC_NAME} \
    --subnet-mode=custom \
    --description="Week 2 Project - Secure 2-tier VPC"
```

**Expected output:**
```
Created [https://www.googleapis.com/compute/v1/projects/PROJECT_ID/global/networks/project-vpc].
NAME         SUBNET_MODE  BGP_ROUTING_MODE  IPV4_RANGE  GATEWAY_IPV4
project-vpc  CUSTOM       REGIONAL
```

#### 1.3 Create Web-Tier Subnet

```bash
gcloud compute networks subnets create ${SUBNET_WEB} \
    --network=${VPC_NAME} \
    --region=${REGION} \
    --range=10.50.1.0/24 \
    --description="Web tier - public-facing servers" \
    --enable-private-ip-google-access
```

#### 1.4 Create App-Tier Subnet

```bash
gcloud compute networks subnets create ${SUBNET_APP} \
    --network=${VPC_NAME} \
    --region=${REGION} \
    --range=10.50.2.0/24 \
    --description="App tier - backend servers, no external IPs" \
    --enable-private-ip-google-access
```

#### 1.5 Verify Network

```bash
gcloud compute networks subnets list \
    --network=${VPC_NAME} \
    --format="table(name, region, ipCidrRange, privateIpGoogleAccess)"
```

**Expected output:**
```
NAME      REGION         IP_CIDR_RANGE  PRIVATE_IP_GOOGLE_ACCESS
app-tier  europe-west2   10.50.2.0/24   True
web-tier  europe-west2   10.50.1.0/24   True
```

---

### Phase 2: Firewall Rules

#### 2.1 Allow SSH via IAP Only

```bash
gcloud compute firewall-rules create ${VPC_NAME}-allow-ssh-iap \
    --network=${VPC_NAME} \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=35.235.240.0/20 \
    --priority=1000 \
    --description="Allow SSH ONLY via Identity-Aware Proxy"
```

> **Security:** No SSH from `0.0.0.0/0`. Only IAP-tunneled connections (authenticated via Google IAM) can reach port 22.

#### 2.2 Allow HTTP to Web-Tier Only

```bash
gcloud compute firewall-rules create ${VPC_NAME}-allow-http-web \
    --network=${VPC_NAME} \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=web-server \
    --priority=1000 \
    --description="Allow HTTP to web-server tagged VMs only"
```

> Only VMs with the `web-server` tag receive HTTP traffic. The app-tier VMs are NOT exposed.

#### 2.3 Allow Internal Communication Between Tiers

```bash
gcloud compute firewall-rules create ${VPC_NAME}-allow-internal \
    --network=${VPC_NAME} \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp,udp,icmp \
    --source-ranges=10.50.0.0/16 \
    --priority=1000 \
    --description="Allow all internal traffic between web and app tiers"
```

#### 2.4 Allow Health Checks (For Future Load Balancer)

```bash
gcloud compute firewall-rules create ${VPC_NAME}-allow-health-check \
    --network=${VPC_NAME} \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=web-server \
    --priority=1000 \
    --description="Allow GCP health check probes"
```

> `130.211.0.0/22` and `35.191.0.0/16` are Google's health check probe ranges.

#### 2.5 Verify Firewall Rules

```bash
gcloud compute firewall-rules list \
    --filter="network=${VPC_NAME}" \
    --format="table(name, direction, priority, allowed[].map().firewall_rule().list():label=ALLOWED, sourceRanges.list():label=SRC, targetTags.list():label=TARGETS)" \
    --sort-by=priority
```

**Expected output:**
```
NAME                               DIRECTION  PRIORITY  ALLOWED              SRC                          TARGETS
project-vpc-allow-health-check     INGRESS    1000      tcp:80               130.211.0.0/22,35.191.0.0/16 web-server
project-vpc-allow-http-web         INGRESS    1000      tcp:80               0.0.0.0/0                    web-server
project-vpc-allow-internal         INGRESS    1000      tcp,udp,icmp         10.50.0.0/16
project-vpc-allow-ssh-iap          INGRESS    1000      tcp:22               35.235.240.0/20
```

---

### Phase 3: Compute Instances

#### 3.1 Create Web Server (with nginx)

```bash
gcloud compute instances create web-server \
    --zone=${ZONE} \
    --machine-type=e2-micro \
    --network=${VPC_NAME} \
    --subnet=${SUBNET_WEB} \
    --tags=web-server \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head><title>Web Tier</title></head>
<body>
<h1>Web Server - project-vpc</h1>
<p>Hostname: $(hostname)</p>
<p>Internal IP: $(hostname -I | awk "{print \$1}")</p>
<p>Tier: WEB</p>
<p>Timestamp: $(date)</p>
</body>
</html>
EOF
systemctl restart nginx'
```

> This VM gets an external IP (default) and the `web-server` tag for HTTP firewall rule.

#### 3.2 Create App Server (no external IP)

```bash
gcloud compute instances create app-server \
    --zone=${ZONE} \
    --machine-type=e2-micro \
    --network=${VPC_NAME} \
    --subnet=${SUBNET_APP} \
    --no-address \
    --tags=app-server \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y python3'
```

> This VM has **no external IP** and the `app-server` tag. It cannot reach the internet yet.

#### 3.3 Verify Instances

```bash
gcloud compute instances list \
    --filter="name:(web-server OR app-server)" \
    --format="table(name, zone, machineType.basename(), networkInterfaces[0].networkIP:label=INTERNAL_IP, networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP, tags.items.list():label=TAGS)"
```

**Expected output:**
```
NAME         ZONE             MACHINE_TYPE  INTERNAL_IP  EXTERNAL_IP   TAGS
app-server   europe-west2-a   e2-micro      10.50.2.2                  app-server
web-server   europe-west2-a   e2-micro      10.50.1.2    34.89.XX.XX   web-server
```

---

### Phase 4: Cloud NAT for App-Tier

#### 4.1 Create Cloud Router

```bash
gcloud compute routers create ${ROUTER_NAME} \
    --network=${VPC_NAME} \
    --region=${REGION}
```

#### 4.2 Create Cloud NAT (App-Tier Subnet Only)

```bash
gcloud compute routers nats create ${NAT_NAME} \
    --router=${ROUTER_NAME} \
    --region=${REGION} \
    --nat-custom-subnet-ip-ranges="${SUBNET_APP}" \
    --auto-allocate-nat-external-ips \
    --enable-logging \
    --log-filter=ALL \
    --min-ports-per-vm=128
```

> We use `--nat-custom-subnet-ip-ranges` to apply NAT **only to the app-tier subnet**. The web-tier has its own external IP and doesn't need NAT.

#### 4.3 Verify NAT

```bash
gcloud compute routers nats describe ${NAT_NAME} \
    --router=${ROUTER_NAME} \
    --region=${REGION} \
    --format="yaml(name, natIpAllocateOption, subnetworks, logConfig)"
```

**Expected output:**
```yaml
logConfig:
  enable: true
  filter: ALL
name: nat-project-gw
natIpAllocateOption: AUTO_ONLY
subnetworks:
- name: https://www.googleapis.com/compute/v1/projects/PROJECT/regions/europe-west2/subnetworks/app-tier
  sourceIpRangesToNat:
  - ALL_IP_RANGES
```

---

### Phase 5: Verification

#### 5.1 Test HTTP Access to Web Server

```bash
WEB_IP=$(gcloud compute instances describe web-server \
    --zone=${ZONE} \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

echo "Web server external IP: ${WEB_IP}"
curl -s http://${WEB_IP}
```

**Expected output:**
```html
<!DOCTYPE html>
<html>
<head><title>Web Tier</title></head>
<body>
<h1>Web Server - project-vpc</h1>
<p>Hostname: web-server</p>
<p>Internal IP: 10.50.1.2</p>
<p>Tier: WEB</p>
...
</body>
</html>
```

#### 5.2 Test SSH via IAP to Both VMs

```bash
# SSH to web-server
gcloud compute ssh web-server --zone=${ZONE} --tunnel-through-iap \
    --command="echo 'SSH to web-server: OK'"

# SSH to app-server
gcloud compute ssh app-server --zone=${ZONE} --tunnel-through-iap \
    --command="echo 'SSH to app-server: OK'"
```

#### 5.3 Test Internal Connectivity (Web → App)

```bash
APP_IP=$(gcloud compute instances describe app-server \
    --zone=${ZONE} \
    --format="get(networkInterfaces[0].networkIP)")

gcloud compute ssh web-server --zone=${ZONE} --tunnel-through-iap \
    --command="ping -c 3 ${APP_IP}"
```

**Expected output:**
```
PING 10.50.2.2 (10.50.2.2) 56(84) bytes of data.
64 bytes from 10.50.2.2: icmp_seq=1 ttl=64 time=0.8 ms
```

#### 5.4 Test Internal Connectivity (App → Web)

```bash
WEB_INTERNAL_IP=$(gcloud compute instances describe web-server \
    --zone=${ZONE} \
    --format="get(networkInterfaces[0].networkIP)")

gcloud compute ssh app-server --zone=${ZONE} --tunnel-through-iap \
    --command="ping -c 3 ${WEB_INTERNAL_IP}"
```

#### 5.5 Test Cloud NAT on App Server

```bash
# App server can reach the internet via Cloud NAT
gcloud compute ssh app-server --zone=${ZONE} --tunnel-through-iap \
    --command="curl -s --max-time 10 http://ifconfig.me"
```

**Expected output:** A Google-owned IP (the Cloud NAT IP, not the VM's IP).

```bash
# Test apt update works
gcloud compute ssh app-server --zone=${ZONE} --tunnel-through-iap \
    --command="sudo apt-get update -qq && echo 'APT UPDATE: OK'"
```

#### 5.6 Verify HTTP is NOT Accessible on App Server

```bash
# App server doesn't have an external IP, and the HTTP firewall rule
# targets web-server tag only. The app server is NOT reachable from outside.
# This is by design — the app tier is internal only.
echo "App server has no external IP — cannot be reached from internet ✓"
```

---

### Phase 6: Verification Script

Save this as a verification script to confirm everything works:

```bash
#!/bin/bash
# verify-project.sh — Run from Cloud Shell or local terminal with gcloud

ZONE="europe-west2-a"
REGION="europe-west2"
VPC_NAME="project-vpc"
PASS=0
FAIL=0

check() {
    local desc="$1"
    local result="$2"
    if [ "$result" = "PASS" ]; then
        echo "[PASS] $desc"
        ((PASS++))
    else
        echo "[FAIL] $desc"
        ((FAIL++))
    fi
}

echo "========================================="
echo " Project Verification: Secure VPC"
echo "========================================="

# Check 1: VPC exists
VPC=$(gcloud compute networks describe ${VPC_NAME} --format="get(name)" 2>/dev/null)
check "VPC '${VPC_NAME}' exists" "$([ "$VPC" = "${VPC_NAME}" ] && echo PASS || echo FAIL)"

# Check 2: Web subnet exists
WEB_SUB=$(gcloud compute networks subnets describe web-tier --region=${REGION} --format="get(ipCidrRange)" 2>/dev/null)
check "Web-tier subnet (10.50.1.0/24)" "$([ "$WEB_SUB" = "10.50.1.0/24" ] && echo PASS || echo FAIL)"

# Check 3: App subnet exists
APP_SUB=$(gcloud compute networks subnets describe app-tier --region=${REGION} --format="get(ipCidrRange)" 2>/dev/null)
check "App-tier subnet (10.50.2.0/24)" "$([ "$APP_SUB" = "10.50.2.0/24" ] && echo PASS || echo FAIL)"

# Check 4: Web server has external IP
WEB_EXT=$(gcloud compute instances describe web-server --zone=${ZONE} --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)
check "Web-server has external IP" "$([ -n "$WEB_EXT" ] && echo PASS || echo FAIL)"

# Check 5: App server has NO external IP
APP_EXT=$(gcloud compute instances describe app-server --zone=${ZONE} --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)
check "App-server has NO external IP" "$([ -z "$APP_EXT" ] && echo PASS || echo FAIL)"

# Check 6: Web server tag
WEB_TAGS=$(gcloud compute instances describe web-server --zone=${ZONE} --format="get(tags.items)" 2>/dev/null)
check "Web-server has 'web-server' tag" "$(echo $WEB_TAGS | grep -q web-server && echo PASS || echo FAIL)"

# Check 7: Firewall rules count
FW_COUNT=$(gcloud compute firewall-rules list --filter="network=${VPC_NAME}" --format="value(name)" 2>/dev/null | wc -l)
check "At least 4 firewall rules" "$([ "$FW_COUNT" -ge 4 ] && echo PASS || echo FAIL)"

# Check 8: Cloud NAT exists
NAT=$(gcloud compute routers nats describe nat-project-gw --router=project-router --region=${REGION} --format="get(name)" 2>/dev/null)
check "Cloud NAT gateway exists" "$([ "$NAT" = "nat-project-gw" ] && echo PASS || echo FAIL)"

# Check 9: Private Google Access on both subnets
PGA_WEB=$(gcloud compute networks subnets describe web-tier --region=${REGION} --format="get(privateIpGoogleAccess)" 2>/dev/null)
PGA_APP=$(gcloud compute networks subnets describe app-tier --region=${REGION} --format="get(privateIpGoogleAccess)" 2>/dev/null)
check "Private Google Access enabled (both subnets)" "$([ "$PGA_WEB" = "True" ] && [ "$PGA_APP" = "True" ] && echo PASS || echo FAIL)"

# Check 10: HTTP accessible on web server
HTTP_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" http://${WEB_EXT} 2>/dev/null)
check "HTTP (port 80) accessible on web-server" "$([ "$HTTP_CODE" = "200" ] && echo PASS || echo FAIL)"

echo ""
echo "========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "========================================="
```

---

## Checklist

Use this to verify you've completed everything:

- [ ] Custom VPC created (`project-vpc`, custom mode)
- [ ] Web-tier subnet (`10.50.1.0/24`, europe-west2)
- [ ] App-tier subnet (`10.50.2.0/24`, europe-west2)
- [ ] Private Google Access enabled on both subnets
- [ ] Firewall: SSH via IAP only (`35.235.240.0/20 → tcp:22`)
- [ ] Firewall: HTTP to web-server tag only (`0.0.0.0/0 → tcp:80`)
- [ ] Firewall: Internal communication (`10.50.0.0/16 → tcp,udp,icmp`)
- [ ] Firewall: Health check probe ranges allowed
- [ ] Web-server VM: nginx, external IP, `web-server` tag
- [ ] App-server VM: no external IP, `app-server` tag
- [ ] Cloud Router created
- [ ] Cloud NAT configured for app-tier subnet only
- [ ] Web server reachable via HTTP from internet
- [ ] App server NOT reachable from internet
- [ ] Both VMs reachable via IAP SSH
- [ ] Internal ping between web and app works
- [ ] App server can reach internet via Cloud NAT
- [ ] Verification script runs with all checks passing

---

## What You Practised Today

| Day | Topic | How It Was Used |
|---|---|---|
| Day 7 | VPC & Subnets | Custom VPC with 2 subnets, CIDR planning |
| Day 8 | Firewall Rules | IAP-only SSH, tag-based HTTP, internal allow |
| Day 9 | Private/Public IP | Web server with ext IP, app server without |
| Day 10 | Routes | System-generated subnet routes, default route |
| Day 11 | Cloud NAT | NAT for app-tier outbound internet access |

---

## Cleanup Commands

> ⚠️ Run these **only** when you're finished and ready to tear everything down.

```bash
echo "=== Cleaning up Week 2 Project ==="

# Phase 1: Delete VMs
gcloud compute instances delete web-server --zone=${ZONE} --quiet
gcloud compute instances delete app-server --zone=${ZONE} --quiet

# Phase 2: Delete Cloud NAT and Router
gcloud compute routers nats delete ${NAT_NAME} \
    --router=${ROUTER_NAME} \
    --region=${REGION} --quiet

gcloud compute routers delete ${ROUTER_NAME} \
    --region=${REGION} --quiet

# Phase 3: Delete Firewall Rules
for RULE in $(gcloud compute firewall-rules list --filter="network=${VPC_NAME}" --format="value(name)"); do
    echo "Deleting firewall rule: ${RULE}"
    gcloud compute firewall-rules delete ${RULE} --quiet
done

# Phase 4: Delete Subnets
gcloud compute networks subnets delete ${SUBNET_WEB} --region=${REGION} --quiet
gcloud compute networks subnets delete ${SUBNET_APP} --region=${REGION} --quiet

# Phase 5: Delete VPC
gcloud compute networks delete ${VPC_NAME} --quiet

echo "=== Cleanup Complete ==="
```

### Verify Cleanup

```bash
# Confirm VPC is gone
gcloud compute networks describe ${VPC_NAME} 2>&1 | grep -q "NOT_FOUND" && echo "VPC deleted ✓" || echo "VPC still exists!"

# Confirm no orphaned resources
gcloud compute instances list --filter="zone:${ZONE}" --format="table(name)" 2>/dev/null
gcloud compute addresses list --filter="region:${REGION}" --format="table(name, status)" 2>/dev/null
```

---

**End of Week 2** — Next week: Load Balancing & CDN
