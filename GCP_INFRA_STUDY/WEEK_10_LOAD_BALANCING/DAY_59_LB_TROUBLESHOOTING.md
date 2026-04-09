# Day 59 — LB Troubleshooting

> **Week 10 · Load Balancing**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Days 55-58 completed

---

## Part 1 — Concept (30 min)

### Troubleshooting Decision Tree

```
┌────────────────────────────────────────────────────────────┐
│              LB TROUBLESHOOTING FLOWCHART                   │
│                                                             │
│  User reports: "Site is down / errors"                      │
│       │                                                     │
│       ▼                                                     │
│  What HTTP status?                                          │
│       │                                                     │
│  ┌────┼────────┬──────────┬──────────┬──────────┐          │
│  │   502       │   503    │   504    │  Connection│         │
│  │ Bad Gateway │ Service  │ Gateway  │  Refused   │         │
│  │             │ Unavail. │ Timeout  │            │         │
│  └────┬────────┴────┬─────┴────┬─────┴─────┬─────┘         │
│       │             │          │            │               │
│       ▼             ▼          ▼            ▼               │
│  Backends       All backends  Backend    LB not yet        │
│  returning      unhealthy    too slow   propagated or      │
│  errors         or no        to respond forwarding rule    │
│                 backends                 misconfigured      │
└────────────────────────────────────────────────────────────┘
```

### Common LB Errors & Root Causes

| Error Code | statusDetails                        | Root Cause                              | Fix                                  |
|------------|--------------------------------------|-----------------------------------------|--------------------------------------|
| **502**    | `backend_connection_closed_...`      | Backend closed connection prematurely   | Check app crashes, increase timeout  |
| **502**    | `failed_to_pick_backend`             | No healthy backends available           | Fix health checks / firewall         |
| **502**    | `response_sent_by_backend`           | Backend itself returned 502             | Fix application errors               |
| **503**    | `backend_early_response_with_503`    | Backend returned 503                    | Backend overloaded or misconfigured  |
| **504**    | `backend_timeout`                    | Backend didn't respond within timeout   | Increase timeout, fix slow queries   |
| **404**    | `url_map_mismatch`                   | No URL map rule matched the request     | Update URL map path rules            |

### Health Check Failures — The #1 Issue

```
Most Common LB Problem:
ALL BACKENDS UNHEALTHY

Diagnosis Steps:
─────────────────────────────────────────────────
1. Firewall?
   Are 130.211.0.0/22 and 35.191.0.0/16
   allowed to reach backend port?
   ┌──────┐     ┌──────────┐     ┌────────┐
   │ HC   │ ──► │ Firewall │ ──► │ Backend│
   │ Probe│     │ BLOCKED? │     │ :80    │
   └──────┘     └──────────┘     └────────┘

2. Application running?
   SSH into VM → curl localhost:80/health
   Is the response 200 OK?

3. Port mismatch?
   Health check port ≠ application listen port?

4. Path mismatch?
   Health check path: /health
   But app serves: /healthz or /status

5. Named port mismatch?
   Backend service: port_name = "http"
   Instance group named_port: "http" → 80
   Must match!
─────────────────────────────────────────────────
```

### 502 Error Troubleshooting

```
502 Bad Gateway
│
├── statusDetails = "failed_to_pick_backend"
│   └── All backends unhealthy → Fix health checks
│
├── statusDetails = "backend_connection_closed_before_data_sent_to_client"
│   └── Backend crashed / closed TCP connection
│       - Check application logs on backend VM
│       - Check if backend has enough resources (CPU/RAM)
│       - Check keep-alive timeout mismatch
│
├── statusDetails = "response_sent_by_backend" with 502
│   └── Backend application returned 502
│       - Upstream proxy on backend failing
│       - Application error
│
└── statusDetails = "failed_to_connect_to_backend"
    └── Backend VM exists but can't connect
        - Firewall blocking LB → backend
        - App not listening on expected port
        - App bound to 127.0.0.1 instead of 0.0.0.0
```

### Firewall Checklist

| Rule Needed                  | Source Ranges                          | Port    | Purpose                    |
|------------------------------|---------------------------------------|---------|----------------------------|
| Allow health check probes    | `130.211.0.0/22`, `35.191.0.0/16`   | App port| Health checks reach backend |
| Allow LB traffic to backend  | `130.211.0.0/22`, `35.191.0.0/16`   | App port| GFE proxy reaches backend  |
| Allow IAP SSH (optional)     | `35.235.240.0/20`                    | 22      | SSH for debugging          |

> **Key insight**: For HTTP(S) LB, the GFE (Google Front End) proxies traffic. The source IP at the backend is from Google's ranges, NOT the client's IP.

### Timeout Chain

```
Client ──── Forwarding Rule ──── Target Proxy ──── Backend Service ──── Backend VM
                                                       │
                                                  timeout_sec = 30
                                                  (default: 30s)
                                                       │
                                                  If backend doesn't
                                                  respond within 30s
                                                       │
                                                       ▼
                                                  504 Gateway Timeout

Linux Analogy:
  nginx proxy_read_timeout 30s;
  nginx proxy_connect_timeout 5s;
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Deliberately break an LB in different ways, observe the errors, and fix them.

### Step 1 — Deploy a Working LB

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a

# Quick setup — template, MIG, health check, full LB
gcloud compute instance-templates create debug-tpl \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=debug-lb \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx
echo "<h1>$(hostname)</h1>" > /var/www/html/index.html
echo "OK" > /var/www/html/health
systemctl start nginx'

gcloud compute instance-groups managed create debug-mig \
    --template=debug-tpl --size=2 --zone=$ZONE
gcloud compute instance-groups managed set-named-ports debug-mig \
    --zone=$ZONE --named-ports=http:80

gcloud compute firewall-rules create debug-allow-hc \
    --network=default --action=allow --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=debug-lb --rules=tcp:80

gcloud compute health-checks create http debug-hc \
    --port=80 --request-path=/health

gcloud compute backend-services create debug-backend \
    --protocol=HTTP --port-name=http --health-checks=debug-hc \
    --global --enable-logging --logging-sample-rate=1.0
gcloud compute backend-services add-backend debug-backend \
    --instance-group=debug-mig --instance-group-zone=$ZONE --global

gcloud compute url-maps create debug-urlmap --default-service=debug-backend
gcloud compute target-http-proxies create debug-proxy --url-map=debug-urlmap
gcloud compute forwarding-rules create debug-fwd --global \
    --target-http-proxy=debug-proxy --ports=80

# Wait for LB
LB_IP=$(gcloud compute forwarding-rules describe debug-fwd --global --format="value(IPAddress)")
echo "LB IP: $LB_IP — waiting for it to go live..."
for i in $(seq 1 30); do
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://$LB_IP/ 2>/dev/null)
    [ "$STATUS" = "200" ] && echo "LB active!" && break
    sleep 10
done
```

### Step 2 — Break It: Delete Firewall Rule

```bash
# Simulate: someone removes the health check firewall rule
gcloud compute firewall-rules delete debug-allow-hc --quiet

# Wait 1-2 minutes, then check backend health
echo "Waiting 90 seconds for health checks to fail..."
sleep 90

gcloud compute backend-services get-health debug-backend --global
# Expected: all backends UNHEALTHY

# Try to access LB
curl -sv http://$LB_IP/ 2>&1 | grep "< HTTP"
# Expected: 502

# Check LB logs for the error
gcloud logging read \
    'resource.type="http_load_balancer" AND resource.labels.forwarding_rule_name="debug-fwd"' \
    --limit=5 --format="table(timestamp, httpRequest.status, jsonPayload.statusDetails)"
# Expected: statusDetails = "failed_to_pick_backend"
```

### Step 3 — Fix It: Restore Firewall Rule

```bash
gcloud compute firewall-rules create debug-allow-hc \
    --network=default --action=allow --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=debug-lb --rules=tcp:80

# Wait for health checks to pass
echo "Waiting for backends to become healthy..."
sleep 30
gcloud compute backend-services get-health debug-backend --global
```

### Step 4 — Break It: Stop Application on All Backends

```bash
# Stop nginx on both backends
for INST in $(gcloud compute instance-groups managed list-instances debug-mig \
    --zone=$ZONE --format="value(instance)"); do
    gcloud compute ssh $INST --zone=$ZONE -- "sudo systemctl stop nginx" &
done
wait

# Check health
sleep 60
gcloud compute backend-services get-health debug-backend --global

# Access LB — expect 502
curl -sv http://$LB_IP/ 2>&1 | grep "< HTTP"
```

### Step 5 — Fix It: Restart Application

```bash
for INST in $(gcloud compute instance-groups managed list-instances debug-mig \
    --zone=$ZONE --format="value(instance)"); do
    gcloud compute ssh $INST --zone=$ZONE -- "sudo systemctl start nginx" &
done
wait

sleep 30
curl -s http://$LB_IP/
```

### Step 6 — Break It: Wrong Health Check Path

```bash
# Update health check to wrong path
gcloud compute health-checks update http debug-hc \
    --request-path=/nonexistent

# Wait and check
sleep 60
gcloud compute backend-services get-health debug-backend --global
# Backend returns 404 for /nonexistent → marked UNHEALTHY
```

### Step 7 — Fix It: Correct Health Check Path

```bash
gcloud compute health-checks update http debug-hc \
    --request-path=/health

sleep 30
gcloud compute backend-services get-health debug-backend --global
```

### Step 8 — Investigate Backend Timeout (504)

```bash
# Set very short timeout on backend service
gcloud compute backend-services update debug-backend \
    --global --timeout=1

# If your backend takes >1s, you'll see 504
curl -sv http://$LB_IP/ 2>&1 | grep "< HTTP"

# Fix: restore reasonable timeout
gcloud compute backend-services update debug-backend \
    --global --timeout=30
```

### Cleanup

```bash
gcloud compute forwarding-rules delete debug-fwd --global --quiet
gcloud compute target-http-proxies delete debug-proxy --quiet
gcloud compute url-maps delete debug-urlmap --quiet
gcloud compute backend-services delete debug-backend --global --quiet
gcloud compute health-checks delete debug-hc --quiet
gcloud compute instance-groups managed delete debug-mig --zone=$ZONE --quiet
gcloud compute instance-templates delete debug-tpl --quiet
gcloud compute firewall-rules delete debug-allow-hc --quiet 2>/dev/null
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **502 `failed_to_pick_backend`**: No healthy backends — check firewall + health check
- **502 `backend_connection_closed`**: App crashed or closed connection — check app logs
- **504 `backend_timeout`**: Backend too slow — increase `timeout_sec` or fix app performance
- Health check firewall → **#1 most common LB misconfiguration**
- Required source ranges: `130.211.0.0/22` and `35.191.0.0/16`
- **Named ports** must match between backend service (`port_name`) and instance group
- Backend timeout default is 30s — increase for slow APIs
- LB logs contain `statusDetails` field — essential for diagnosis
- Debug path: check health → check firewall → check app → check timeout

### Essential Debug Commands

```bash
# Check backend health (most important command)
gcloud compute backend-services get-health BACKEND --global

# Read LB logs with error details
gcloud logging read 'resource.type="http_load_balancer" AND httpRequest.status>=400' --limit=10

# Verify firewall rules
gcloud compute firewall-rules list --filter="targetTags:TAG"

# SSH into backend and test locally
gcloud compute ssh INSTANCE --zone=ZONE -- "curl -v localhost:80/health"

# Check health check config
gcloud compute health-checks describe HC_NAME
```

---

## Part 4 — Quiz (15 min)

**Question 1: You get 502 with `statusDetails: "failed_to_pick_backend"`. All VMs are running. What's wrong?**

<details>
<summary>Show Answer</summary>

All backends are marked **UNHEALTHY** by the health check, even though VMs are running. Most likely cause: **firewall rule missing** for health check probes.

Verify:
```bash
gcloud compute backend-services get-health BACKEND --global
gcloud compute firewall-rules list --filter="targetTags:YOUR_TAG"
```

Fix:
```bash
gcloud compute firewall-rules create allow-hc \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=YOUR_TAG --rules=tcp:80
```

</details>

**Question 2: Your backend VMs listen on port 8080, but the LB returns 502. The health check is configured for port 80. What's wrong?**

<details>
<summary>Show Answer</summary>

**Port mismatch.** Three things need to align:

1. **Health check port** must match the app port: change to `--port=8080`
2. **Named port** on instance group must map to 8080: `--named-ports=http:8080`
3. **Backend service** `port_name` must match the named port name: `--port-name=http`

Fix all three:
```bash
gcloud compute health-checks update http HC --port=8080
gcloud compute instance-groups managed set-named-ports MIG --named-ports=http:8080
# Backend service port_name=http already matches
```

</details>

**Question 3: Your API endpoint takes 45 seconds to process large reports. Users see 504 errors. How do you fix it?**

<details>
<summary>Show Answer</summary>

The default backend service **timeout is 30 seconds**. Since your API takes 45s, the LB gives up and returns 504 before the backend responds.

Fix: Increase the timeout:
```bash
gcloud compute backend-services update BACKEND --global --timeout=60
```

Also consider:
- Optimizing the API to be faster
- Returning 202 Accepted immediately and processing asynchronously
- Using WebSocket or streaming for long-running operations

</details>

**Question 4: After creating an HTTP LB, you immediately curl the IP and get "Connection refused". Is the LB broken?**

<details>
<summary>Show Answer</summary>

**No, it's not broken.** The Global HTTP(S) LB takes **3-5 minutes** to propagate configuration to Google Front End (GFE) servers worldwide. During this time:

1. The forwarding rule exists but GFE isn't serving yet
2. You'll get "Connection refused" or timeouts
3. This is normal and expected

Wait 5 minutes and retry. If still failing after 10 minutes, check:
- Forwarding rule exists: `gcloud compute forwarding-rules describe NAME --global`
- Target proxy references correct URL map
- Backend service has healthy backends

</details>

---

*Next: [Day 60 — PROJECT: App Behind LB](DAY_60_PROJECT_APP_BEHIND_LB.md)*
