# Day 56 — Create External HTTP(S) Load Balancer

> **Week 10 · Load Balancing**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 55 LB Types completed

---

## Part 1 — Concept (30 min)

### HTTP(S) LB Component Deep Dive

```
┌──────────────────────────────────────────────────────────────┐
│       EXTERNAL HTTP(S) LOAD BALANCER — COMPONENT CHAIN        │
│                                                               │
│  Client Request                                               │
│       │                                                       │
│       ▼                                                       │
│  ┌─────────────────────────┐                                 │
│  │  GLOBAL FORWARDING RULE │  ← Public IP + Port (80/443)    │
│  │  "Front door"           │    Like: nginx listen 80;       │
│  └───────────┬─────────────┘                                 │
│              │                                                │
│              ▼                                                │
│  ┌─────────────────────────┐                                 │
│  │  TARGET HTTP PROXY      │  ← Links forwarding rule to     │
│  │  (or HTTPS w/ SSL cert) │    URL map. SSL termination     │
│  │  "Protocol handler"     │    Like: nginx ssl_certificate  │
│  └───────────┬─────────────┘                                 │
│              │                                                │
│              ▼                                                │
│  ┌─────────────────────────┐                                 │
│  │  URL MAP                │  ← Routes by host/path          │
│  │  "Traffic router"       │    Like: nginx location blocks  │
│  │                         │                                  │
│  │  /api/*  → api-backend  │                                 │
│  │  /web/*  → web-backend  │                                 │
│  │  /*      → default      │                                 │
│  └───────────┬─────────────┘                                 │
│              │                                                │
│              ▼                                                │
│  ┌─────────────────────────┐                                 │
│  │  BACKEND SERVICE        │  ← Config: health check, CDN,   │
│  │  "Backend pool"         │    session affinity, timeout     │
│  │                         │    Like: nginx upstream block    │
│  │  ┌──────────┐          │                                  │
│  │  │ MIG or   │          │                                  │
│  │  │ Instance │          │                                  │
│  │  │ Group    │          │                                  │
│  │  └────┬─────┘          │                                  │
│  └───────┼────────────────┘                                  │
│          │                                                    │
│          ▼                                                    │
│  ┌─────────────────────────┐                                 │
│  │  HEALTH CHECK           │  ← Probes backends, removes     │
│  │  "Liveness probe"       │    unhealthy ones from rotation  │
│  └─────────────────────────┘                                 │
└──────────────────────────────────────────────────────────────┘
```

### Creation Order

| Step | Resource                    | Depends On        | gcloud command prefix                  |
|------|-----------------------------|-------------------|----------------------------------------|
| 1    | Health Check                | Nothing           | `gcloud compute health-checks create`  |
| 2    | Instance Group / MIG        | Nothing           | `gcloud compute instance-groups ...`   |
| 3    | Backend Service             | HC + IG           | `gcloud compute backend-services create`|
| 4    | URL Map                     | Backend Service   | `gcloud compute url-maps create`       |
| 5    | Target HTTP Proxy           | URL Map           | `gcloud compute target-http-proxies create`|
| 6    | Global Forwarding Rule      | Target Proxy      | `gcloud compute forwarding-rules create`|

### Session Affinity Options

| Mode                  | Description                          | Use Case                    |
|-----------------------|--------------------------------------|-----------------------------|
| NONE                  | Round-robin (default)                | Stateless apps              |
| CLIENT_IP             | Same client → same backend           | Sticky sessions by IP       |
| CLIENT_IP_PROTO       | Client IP + protocol                | Protocol-specific affinity  |
| GENERATED_COOKIE      | LB sets a cookie to track session   | HTTP session persistence    |
| HEADER_FIELD          | Route by specific HTTP header       | Tenant-based routing        |

### Balancing Modes

| Mode         | Description                                    | When to Use                    |
|--------------|------------------------------------------------|--------------------------------|
| UTILIZATION  | Distribute by backend CPU utilization          | Default; general workloads     |
| RATE         | Distribute by requests per second per instance | When rate-limiting is needed   |
| CONNECTION   | Distribute by active connections               | Long-lived connections         |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Deploy 2 nginx VMs across 2 zones, create a Global External HTTP(S) Load Balancer, and test traffic distribution.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE_A=europe-west2-a
export ZONE_B=europe-west2-b
```

### Step 2 — Create Instance Template

```bash
gcloud compute instance-templates create http-lb-template \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=http-lb-backend \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx
HOSTNAME=$(hostname)
ZONE=$(curl -sf -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)
cat > /var/www/html/index.html <<EOF
<h1>Hello from HTTP LB Backend</h1>
<p>Hostname: $HOSTNAME</p>
<p>Zone: $ZONE</p>
EOF
echo "OK" > /var/www/html/health
systemctl enable nginx && systemctl start nginx'
```

### Step 3 — Create MIG (Regional)

```bash
gcloud compute instance-groups managed create http-lb-mig \
    --template=http-lb-template \
    --size=2 \
    --region=$REGION

# Set named port (required by backend service)
gcloud compute instance-groups managed set-named-ports http-lb-mig \
    --region=$REGION \
    --named-ports=http:80
```

### Step 4 — Create Firewall Rules

```bash
# Allow health check probes
gcloud compute firewall-rules create allow-hc-http-lb \
    --network=default \
    --action=allow \
    --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=http-lb-backend \
    --rules=tcp:80

# Allow HTTP from LB (GFE proxy range)
gcloud compute firewall-rules create allow-http-from-lb \
    --network=default \
    --action=allow \
    --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=http-lb-backend \
    --rules=tcp:80
```

### Step 5 — Create Health Check

```bash
gcloud compute health-checks create http http-lb-hc \
    --port=80 \
    --request-path=/health \
    --check-interval=10s \
    --timeout=5s \
    --healthy-threshold=2 \
    --unhealthy-threshold=3
```

### Step 6 — Create Backend Service

```bash
gcloud compute backend-services create http-lb-backend-svc \
    --protocol=HTTP \
    --port-name=http \
    --health-checks=http-lb-hc \
    --global \
    --enable-logging \
    --logging-sample-rate=1.0

# Add MIG as backend
gcloud compute backend-services add-backend http-lb-backend-svc \
    --instance-group=http-lb-mig \
    --instance-group-region=$REGION \
    --balancing-mode=UTILIZATION \
    --max-utilization=0.8 \
    --global
```

### Step 7 — Create URL Map

```bash
gcloud compute url-maps create http-lb-url-map \
    --default-service=http-lb-backend-svc
```

### Step 8 — Create Target HTTP Proxy

```bash
gcloud compute target-http-proxies create http-lb-proxy \
    --url-map=http-lb-url-map
```

### Step 9 — Create Global Forwarding Rule

```bash
gcloud compute forwarding-rules create http-lb-forwarding-rule \
    --global \
    --target-http-proxy=http-lb-proxy \
    --ports=80
```

### Step 10 — Test the Load Balancer

```bash
# Get the LB IP (may take 3-5 minutes to become active)
LB_IP=$(gcloud compute forwarding-rules describe http-lb-forwarding-rule \
    --global --format="value(IPAddress)")
echo "HTTP LB IP: $LB_IP"

# Wait for the LB to start serving (retry until 200)
echo "Waiting for LB to become active (up to 5 min)..."
for i in $(seq 1 30); do
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://$LB_IP/ 2>/dev/null)
    if [ "$STATUS" = "200" ]; then
        echo "LB is active!"
        break
    fi
    echo "  Attempt $i: HTTP $STATUS — waiting 10s..."
    sleep 10
done

# Send multiple requests — see different backends
for i in $(seq 1 6); do
    echo "--- Request $i ---"
    curl -s http://$LB_IP/
    echo ""
done
```

### Step 11 — Inspect LB Components

```bash
# Full component listing
echo "=== Forwarding Rule ==="
gcloud compute forwarding-rules describe http-lb-forwarding-rule --global

echo "=== URL Map ==="
gcloud compute url-maps describe http-lb-url-map

echo "=== Backend Service ==="
gcloud compute backend-services describe http-lb-backend-svc --global

echo "=== Backend Health ==="
gcloud compute backend-services get-health http-lb-backend-svc --global
```

### Cleanup

```bash
gcloud compute forwarding-rules delete http-lb-forwarding-rule --global --quiet
gcloud compute target-http-proxies delete http-lb-proxy --quiet
gcloud compute url-maps delete http-lb-url-map --quiet
gcloud compute backend-services delete http-lb-backend-svc --global --quiet
gcloud compute health-checks delete http-lb-hc --quiet
gcloud compute instance-groups managed delete http-lb-mig --region=$REGION --quiet
gcloud compute instance-templates delete http-lb-template --quiet
gcloud compute firewall-rules delete allow-hc-http-lb allow-http-from-lb --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- HTTP(S) LB has 6 components: forwarding rule → proxy → URL map → backend service → instance group → health check
- Create **bottom-up**: health check + IG first, then backend service, URL map, proxy, forwarding rule
- Delete **top-down**: forwarding rule first, then proxy, URL map, backend service
- **Named ports** on instance groups map port names (e.g., "http") to port numbers (80)
- Backend service **balancing modes**: UTILIZATION, RATE, CONNECTION
- **`--enable-logging`** on backend service captures access logs in Cloud Logging
- Health checks source IPs: `130.211.0.0/22`, `35.191.0.0/16` — must be allowed
- LB takes **3-5 minutes** to become fully active after creation

### Essential Commands

```bash
# Health check
gcloud compute health-checks create http NAME --port=80 --request-path=/health

# Backend service
gcloud compute backend-services create NAME --protocol=HTTP --port-name=http --health-checks=HC --global
gcloud compute backend-services add-backend NAME --instance-group=IG --instance-group-region=REGION --global

# URL map
gcloud compute url-maps create NAME --default-service=BACKEND

# Target proxy
gcloud compute target-http-proxies create NAME --url-map=URLMAP

# Forwarding rule
gcloud compute forwarding-rules create NAME --global --target-http-proxy=PROXY --ports=80

# Check backend health
gcloud compute backend-services get-health NAME --global
```

---

## Part 4 — Quiz (15 min)

**Question 1: You create an HTTP LB but all backends show as UNHEALTHY. What are the top 3 things to check?**

<details>
<summary>Show Answer</summary>

1. **Firewall rules**: Ensure `130.211.0.0/22` and `35.191.0.0/16` can reach the backend port (80). The health check probes come from these IP ranges.
2. **Health check path**: Does the backend actually serve a response at the configured path (e.g., `/health`)? SSH into a VM and test: `curl localhost/health`
3. **Named port**: The backend service's `--port-name` must match the instance group's named port. If backend service uses `http`, the IG must have `http:80` as a named port.

Also check: Is the application running? Is it listening on the correct port?

</details>

**Question 2: What is the purpose of the URL map? When would you use multiple backend services?**

<details>
<summary>Show Answer</summary>

The URL map routes incoming requests to different backend services based on **URL path** and/or **host header**. Use multiple backend services when:

- `/api/*` should go to API servers (different machine types, autoscaling)
- `/static/*` should go to storage backends (or Cloud CDN)
- `admin.example.com` should go to admin servers
- Different paths need different health checks, timeouts, or CDN settings

Without a URL map, all traffic goes to a single default backend service.

</details>

**Question 3: Why does the HTTP LB take several minutes to become active after creation?**

<details>
<summary>Show Answer</summary>

The Global HTTP(S) LB uses **Google Front End (GFE)** servers distributed worldwide. When you create an LB:

1. Configuration propagates to GFE servers globally (takes 1-3 min)
2. Health checks must pass for backends to enter rotation (takes 10-30s × threshold)
3. DNS and routing tables update

Total time: typically **3-5 minutes** for HTTP, up to **15 minutes** for HTTPS (SSL certificate provisioning adds time).

</details>

**Question 4: You need to preserve the original client IP address. How does the HTTP(S) LB expose it?**

<details>
<summary>Show Answer</summary>

The HTTP(S) LB is a **proxy** — it terminates the TCP connection and creates a new one to the backend. The original client IP is **not** in the TCP source address. Instead, the LB adds:

- **`X-Forwarded-For`** header: contains the client IP (and any intermediate proxies)
- **`X-Forwarded-Proto`**: original protocol (http/https)

In nginx, you'd read it with:
```nginx
set_real_ip_from 130.211.0.0/22;
set_real_ip_from 35.191.0.0/16;
real_ip_header X-Forwarded-For;
```

If you need the original source IP preserved in the TCP packet (not just headers), use a **Network LB** (L4 pass-through) instead.

</details>

---

*Next: [Day 57 — LB Logging & Monitoring](DAY_57_LB_LOGGING_MONITORING.md)*
