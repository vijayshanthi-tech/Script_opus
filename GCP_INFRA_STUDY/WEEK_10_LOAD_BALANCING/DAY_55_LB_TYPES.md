# Day 55 — Load Balancer Types Overview

> **Week 10 · Load Balancing**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Week 9 MIG & Autoscaling completed

---

## Part 1 — Concept (30 min)

### What Is Load Balancing?

A load balancer distributes incoming traffic across multiple backend instances. Think of it as a reverse proxy (`nginx upstream` or `HAProxy`) but as a fully managed, globally distributed GCP service.

```
Linux Analogy
─────────────
  nginx.conf:
    upstream backend {
        server 10.0.0.1:80 weight=1;
        server 10.0.0.2:80 weight=1;
        server 10.0.0.3:80 weight=1;
        health_check interval=10 fails=3;
    }
    server {
        listen 80;
        location / {
            proxy_pass http://backend;
        }
    }

  GCP Load Balancer:
    forwarding_rule → target_proxy → url_map → backend_service → instance_group
    + health_check (auto-removes unhealthy backends)
```

### GCP Load Balancer Types

```
┌──────────────────────────────────────────────────────────────┐
│                  GCP LOAD BALANCER FAMILY                      │
│                                                               │
│  EXTERNAL (Internet-facing)                                   │
│  ├── Global HTTP(S) LB          ← L7, global, CDN-ready      │
│  ├── Global SSL Proxy LB        ← L4 SSL, global             │
│  ├── Global TCP Proxy LB        ← L4 TCP, global             │
│  ├── Regional External HTTP(S)  ← L7, single region          │
│  └── Regional TCP/UDP Network LB← L4, single region, passthru│
│                                                               │
│  INTERNAL (VPC-only)                                          │
│  ├── Regional Internal HTTP(S)  ← L7, single region          │
│  └── Regional Internal TCP/UDP  ← L4, single region          │
│                                                               │
│  L7 = Application layer (HTTP headers, URL paths)             │
│  L4 = Transport layer (TCP/UDP port forwarding)               │
└──────────────────────────────────────────────────────────────┘
```

### Decision Matrix

| Scenario                                    | Recommended LB                    | Why                                    |
|---------------------------------------------|-----------------------------------|----------------------------------------|
| Public website with global users            | Global External HTTP(S)           | Global anycast, CDN, SSL offload       |
| Public API with path-based routing          | Global External HTTP(S)           | URL map routes /api/v1 vs /api/v2      |
| Public TCP service (non-HTTP)               | Global TCP Proxy                  | TCP-level, global distribution         |
| Public SSL termination (non-HTTP)           | Global SSL Proxy                  | SSL offload for TCP services           |
| Regional game server (UDP)                  | Regional External TCP/UDP Network | Pass-through, preserves client IP      |
| Internal microservice communication         | Regional Internal HTTP(S)         | L7 routing within VPC, service mesh    |
| Internal database proxy                     | Regional Internal TCP/UDP         | L4 TCP within VPC, no external access  |
| Simple TCP pass-through (preserve src IP)   | Regional External TCP/UDP Network | Network LB preserves original client IP|

### Component Architecture (HTTP(S) LB)

```
┌─────────────────────────────────────────────────────────────┐
│          GLOBAL EXTERNAL HTTP(S) LOAD BALANCER               │
│                                                              │
│  Internet                                                    │
│     │                                                        │
│     ▼                                                        │
│  ┌──────────────────┐                                       │
│  │ Global Forwarding │  ← Reserved IP, port 80/443          │
│  │ Rule              │    (like nginx listen directive)      │
│  └────────┬─────────┘                                       │
│           │                                                  │
│           ▼                                                  │
│  ┌──────────────────┐                                       │
│  │ Target HTTP(S)   │  ← SSL termination (HTTPS only)       │
│  │ Proxy            │    (like nginx ssl_certificate)        │
│  └────────┬─────────┘                                       │
│           │                                                  │
│           ▼                                                  │
│  ┌──────────────────┐                                       │
│  │ URL Map          │  ← Path-based routing                 │
│  │ /api → backend A │    (like nginx location blocks)       │
│  │ /web → backend B │                                       │
│  │ /*   → default   │                                       │
│  └────────┬─────────┘                                       │
│           │                                                  │
│           ▼                                                  │
│  ┌──────────────────┐   ┌──────────────────┐               │
│  │ Backend Service  │   │ Backend Service   │               │
│  │ (API backends)   │   │ (Web backends)    │               │
│  │                  │   │                   │               │
│  │ ┌─────┐ ┌─────┐ │   │ ┌─────┐ ┌─────┐  │               │
│  │ │ MIG │ │ MIG │ │   │ │ MIG │ │ MIG │  │               │
│  │ │ a   │ │ b   │ │   │ │ c   │ │ d   │  │               │
│  │ └─────┘ └─────┘ │   │ └─────┘ └─────┘  │               │
│  └──────────────────┘   └──────────────────┘               │
│           │                      │                          │
│           ▼                      ▼                          │
│  ┌──────────────────────────────────────────┐              │
│  │ Health Check (per backend service)        │              │
│  │ HTTP :80/health  check_interval=5s        │              │
│  └──────────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────────┘
```

### Key Differences: L4 vs L7

| Feature              | L4 (Network/TCP/SSL Proxy)   | L7 (HTTP(S))                   |
|----------------------|------------------------------|--------------------------------|
| OSI Layer            | Transport (TCP/UDP)          | Application (HTTP)             |
| Routing              | IP + Port only               | URL path, host, headers        |
| SSL termination      | At proxy (SSL Proxy) or passthru | At proxy (offloaded)       |
| Client IP            | Preserved (Network LB)       | Via X-Forwarded-For header     |
| CDN / Cloud Armor    | Limited                      | Full support                   |
| WebSocket            | Supported                    | Supported                      |
| Linux analogy        | `iptables DNAT`              | `nginx proxy_pass`             |

### Premium vs Standard Tier

| Feature          | Premium Tier                     | Standard Tier                     |
|------------------|----------------------------------|-----------------------------------|
| Routing          | Google global backbone (anycast) | Public internet (regional)        |
| Scope            | Global                           | Regional                          |
| Latency          | Lower (Google network)           | Higher (internet routing)         |
| Cost             | Higher                           | Lower (~35% cheaper)              |
| Failover         | Cross-region automatic           | No cross-region failover          |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Explore load balancer types using gcloud, understand the component relationships, and set up a basic TCP Network LB for comparison before building HTTP LB on Day 56.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE_A=europe-west2-a
export ZONE_B=europe-west2-b
```

### Step 2 — Create Backend VMs

```bash
# Create two VMs serving different content (simulating backends)
for i in 1 2; do
  gcloud compute instances create web-backend-$i \
      --zone=$ZONE_A \
      --machine-type=e2-micro \
      --image-family=debian-12 \
      --image-project=debian-cloud \
      --tags=web-backend \
      --metadata=startup-script="#!/bin/bash
apt-get update && apt-get install -y nginx
echo '<h1>Backend $i</h1>' > /var/www/html/index.html
echo 'OK' > /var/www/html/health
systemctl start nginx"
done
```

### Step 3 — Create Firewall Rules

```bash
gcloud compute firewall-rules create allow-http-lb-lab \
    --network=default \
    --action=allow \
    --direction=ingress \
    --source-ranges=0.0.0.0/0 \
    --target-tags=web-backend \
    --rules=tcp:80

gcloud compute firewall-rules create allow-hc-lb-lab \
    --network=default \
    --action=allow \
    --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=web-backend \
    --rules=tcp:80
```

### Step 4 — Create Unmanaged Instance Group

```bash
gcloud compute instance-groups unmanaged create web-ig \
    --zone=$ZONE_A

gcloud compute instance-groups unmanaged add-instances web-ig \
    --zone=$ZONE_A \
    --instances=web-backend-1,web-backend-2

gcloud compute instance-groups unmanaged set-named-ports web-ig \
    --zone=$ZONE_A \
    --named-ports=http:80
```

### Step 5 — Create Regional TCP/UDP Network LB

```bash
# Health check for Network LB
gcloud compute health-checks create http network-lb-hc \
    --port=80 \
    --request-path=/health

# Backend service (regional, external)
gcloud compute backend-services create network-lb-backend \
    --protocol=TCP \
    --health-checks=network-lb-hc \
    --region=$REGION

# Add instance group to backend
gcloud compute backend-services add-backend network-lb-backend \
    --instance-group=web-ig \
    --instance-group-zone=$ZONE_A \
    --region=$REGION

# Forwarding rule
gcloud compute forwarding-rules create network-lb-rule \
    --region=$REGION \
    --ports=80 \
    --backend-service=network-lb-backend
```

### Step 6 — Test the Network LB

```bash
# Get the LB IP
LB_IP=$(gcloud compute forwarding-rules describe network-lb-rule \
    --region=$REGION --format="value(IPAddress)")

echo "Network LB IP: $LB_IP"

# Test — should alternate between Backend 1 and Backend 2
for i in $(seq 1 6); do
  curl -s http://$LB_IP/
done
```

### Step 7 — List All LB Components

```bash
# See what was created
gcloud compute forwarding-rules list
gcloud compute backend-services list
gcloud compute health-checks list
gcloud compute instance-groups list
```

### Cleanup

```bash
gcloud compute forwarding-rules delete network-lb-rule --region=$REGION --quiet
gcloud compute backend-services delete network-lb-backend --region=$REGION --quiet
gcloud compute health-checks delete network-lb-hc --quiet
gcloud compute instance-groups unmanaged delete web-ig --zone=$ZONE_A --quiet
gcloud compute instances delete web-backend-1 web-backend-2 --zone=$ZONE_A --quiet
gcloud compute firewall-rules delete allow-http-lb-lab allow-hc-lb-lab --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- GCP has **7 load balancer types** — choice depends on traffic type, scope, and layer
- **Global External HTTP(S) LB**: most common; L7, CDN, Cloud Armor, URL routing
- **Regional TCP/UDP Network LB**: L4 pass-through, preserves client IP
- **Internal LB**: for VPC-internal communication only
- HTTP(S) LB components: forwarding rule → target proxy → URL map → backend service → instance group
- **Premium tier**: uses Google backbone (global anycast); **Standard**: internet routing
- L7 provides URL/host routing; L4 provides port-level forwarding
- Health checks are **per backend service**, not per LB

### Essential Commands

```bash
# List LB components
gcloud compute forwarding-rules list
gcloud compute backend-services list
gcloud compute target-http-proxies list
gcloud compute url-maps list

# Describe
gcloud compute forwarding-rules describe NAME --global
gcloud compute backend-services describe NAME --global
```

---

## Part 4 — Quiz (15 min)

**Question 1: You need to route `/api/*` to one set of VMs and `/static/*` to another. Which LB type do you need?**

<details>
<summary>Show Answer</summary>

**Global External HTTP(S) Load Balancer** (or Regional External/Internal HTTP(S) LB). Only L7 load balancers support **URL map** path-based routing. L4 LBs (Network LB, TCP/SSL Proxy) cannot inspect HTTP paths — they only see IP addresses and ports.

</details>

**Question 2: Your game server uses UDP and needs to see the real client IP. Which LB type should you use?**

<details>
<summary>Show Answer</summary>

**Regional External TCP/UDP Network LB**. It's the only LB type that:
1. Supports **UDP** traffic
2. Is a **pass-through** LB — doesn't proxy the connection, so the real client IP is preserved in the packet
3. Works at L4 (transport layer)

HTTP(S) LBs and Proxy LBs replace the source IP with the proxy's IP (client IP available only via `X-Forwarded-For` header, which doesn't apply to UDP).

</details>

**Question 3: What's the difference between a backend service and an instance group in LB terminology?**

<details>
<summary>Show Answer</summary>

- **Instance group**: A collection of VM instances (managed or unmanaged) — the actual compute resources
- **Backend service**: A logical grouping that contains one or more instance groups + configuration (health check, session affinity, timeout, CDN settings, balancing mode)

A backend service is like an nginx `upstream` block — it defines how traffic is distributed across instance groups. An instance group is like the list of `server` entries within that upstream.

</details>

**Question 4: You're choosing between Premium and Standard network tier for a regional London-only application. Which tier saves money?**

<details>
<summary>Show Answer</summary>

**Standard tier** saves ~35% on networking costs. Since the application is regional (London only, `europe-west2`), you don't benefit from Premium tier's global anycast routing or cross-region failover. Standard tier routes traffic through the public internet to the region, which is perfectly fine for single-region deployments. Premium tier's Google backbone is most valuable for global, multi-region applications.

</details>

---

*Next: [Day 56 — Create HTTP Load Balancer](DAY_56_HTTP_LB.md)*
