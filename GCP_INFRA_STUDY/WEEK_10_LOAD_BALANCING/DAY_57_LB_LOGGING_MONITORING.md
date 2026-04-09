# Day 57 — LB Logging & Monitoring

> **Week 10 · Load Balancing**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 56 HTTP LB completed

---

## Part 1 — Concept (30 min)

### LB Observability Stack

```
┌──────────────────────────────────────────────────────────────┐
│              LB OBSERVABILITY ARCHITECTURE                     │
│                                                               │
│  ┌────────────────────────────────────────────┐              │
│  │          HTTP(S) LOAD BALANCER              │              │
│  │                                             │              │
│  │  Request → GFE → Backend                    │              │
│  │               │                             │              │
│  │          ┌────┴────┐                        │              │
│  │          │ Log Entry│                        │              │
│  │          └────┬────┘                        │              │
│  └───────────────┼─────────────────────────────┘              │
│                  │                                             │
│         ┌────────┴────────┐                                   │
│         ▼                 ▼                                    │
│  ┌─────────────┐  ┌──────────────────┐                       │
│  │ Cloud        │  │ Cloud            │                       │
│  │ Logging      │  │ Monitoring       │                       │
│  │              │  │                  │                       │
│  │ - Access logs│  │ - Request count  │                       │
│  │ - Error logs │  │ - Latency (p50,  │                       │
│  │ - Latency    │  │   p95, p99)      │                       │
│  │ - Status code│  │ - Error rate     │                       │
│  │ - Client IP  │  │ - Backend usage  │                       │
│  └──────┬──────┘  │ - CDN hit ratio  │                       │
│         │         └────────┬─────────┘                       │
│         │                  │                                  │
│         ▼                  ▼                                  │
│  ┌─────────────┐  ┌──────────────────┐                       │
│  │ Log-Based   │  │ Alerting         │                       │
│  │ Metrics     │  │ Policies         │                       │
│  │ (custom)    │  │ - 5xx > 1%       │                       │
│  └─────────────┘  │ - Latency > 2s   │                       │
│                   │ - Backend down    │                       │
│                   └──────────────────┘                       │
└──────────────────────────────────────────────────────────────┘
```

### LB Log Entry Structure

```
Linux Analogy: nginx access log
─────────────
  access_log format:
    $remote_addr - $request - $status - $request_time - $upstream_addr

GCP LB Log Entry:
┌─────────────────────────────────────────────┐
│ httpRequest:                                 │
│   requestMethod: GET                         │
│   requestUrl: http://34.xx.xx.xx/api/v1     │
│   status: 200                                │
│   requestSize: 256                           │
│   responseSize: 1024                         │
│   latency: "0.045s"                          │
│   remoteIp: 86.xx.xx.xx                     │
│   serverIp: 10.128.0.5                      │
│   userAgent: "Mozilla/5.0..."               │
│                                              │
│ resource:                                    │
│   type: http_load_balancer                   │
│   labels:                                    │
│     backend_service_name: my-backend-svc     │
│     forwarding_rule_name: my-fw-rule         │
│     url_map_name: my-url-map                 │
│                                              │
│ jsonPayload:                                 │
│   statusDetails: "response_sent_by_backend"  │
│   backendTargetProjectNumber: "123456"       │
│   cacheHit: false                            │
│   cacheLookup: true                          │
└─────────────────────────────────────────────┘
```

### Key LB Metrics

| Metric                                          | Description                       | Alert Threshold           |
|-------------------------------------------------|-----------------------------------|---------------------------|
| `loadbalancing.googleapis.com/https/request_count` | Total requests                  | Baseline deviation        |
| `loadbalancing.googleapis.com/https/total_latencies` | End-to-end latency (ms)      | p99 > 2000ms              |
| `loadbalancing.googleapis.com/https/backend_latencies` | Backend processing time     | p99 > 1000ms              |
| `loadbalancing.googleapis.com/https/request_bytes_count` | Inbound bytes             | Spike detection           |
| `loadbalancing.googleapis.com/https/response_bytes_count` | Outbound bytes           | Spike detection           |
| `loadbalancing.googleapis.com/https/backend_request_count` | Requests per backend    | Uneven distribution       |
| Error rate (derived)                            | 5xx / total requests              | > 1%                      |

### CDN Cache Metrics

| Metric               | Meaning                                   | Target        |
|----------------------|-------------------------------------------|---------------|
| Cache Hit Ratio      | % of requests served from CDN cache       | > 80%         |
| Cache Fill Bytes     | Bytes fetched from origin to fill cache   | Low = good    |
| Cache Lookup         | Whether CDN attempted to serve from cache | Should be true|

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Enable LB logging, query access logs, explore LB metrics in Cloud Monitoring, and create a simple dashboard.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
```

### Step 2 — Create Quick LB Setup (Minimal)

```bash
# Instance template
gcloud compute instance-templates create log-lb-tpl \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=log-lb-backend \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx
echo "<h1>$(hostname)</h1>" > /var/www/html/index.html
echo "OK" > /var/www/html/health
systemctl start nginx'

# MIG
gcloud compute instance-groups managed create log-lb-mig \
    --template=log-lb-tpl --size=2 --region=$REGION
gcloud compute instance-groups managed set-named-ports log-lb-mig \
    --region=$REGION --named-ports=http:80

# Firewall
gcloud compute firewall-rules create allow-hc-log-lb \
    --network=default --action=allow --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=log-lb-backend --rules=tcp:80

# Health check
gcloud compute health-checks create http log-lb-hc \
    --port=80 --request-path=/health

# Backend service with logging ENABLED
gcloud compute backend-services create log-lb-backend \
    --protocol=HTTP \
    --port-name=http \
    --health-checks=log-lb-hc \
    --global \
    --enable-logging \
    --logging-sample-rate=1.0

gcloud compute backend-services add-backend log-lb-backend \
    --instance-group=log-lb-mig \
    --instance-group-region=$REGION \
    --global

# URL map, proxy, forwarding rule
gcloud compute url-maps create log-lb-urlmap --default-service=log-lb-backend
gcloud compute target-http-proxies create log-lb-proxy --url-map=log-lb-urlmap
gcloud compute forwarding-rules create log-lb-fwd --global \
    --target-http-proxy=log-lb-proxy --ports=80
```

### Step 3 — Generate Traffic

```bash
LB_IP=$(gcloud compute forwarding-rules describe log-lb-fwd \
    --global --format="value(IPAddress)")
echo "LB IP: $LB_IP"

# Wait for LB to become active
echo "Waiting for LB..."
for i in $(seq 1 30); do
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://$LB_IP/ 2>/dev/null)
    [ "$STATUS" = "200" ] && echo "Active!" && break
    sleep 10
done

# Generate some traffic (100 requests)
for i in $(seq 1 100); do
    curl -s -o /dev/null http://$LB_IP/
    curl -s -o /dev/null http://$LB_IP/nonexistent  # 404
done
echo "Traffic generated."
```

### Step 4 — Query LB Access Logs

```bash
# View recent LB logs
gcloud logging read \
    'resource.type="http_load_balancer" AND resource.labels.forwarding_rule_name="log-lb-fwd"' \
    --limit=10 \
    --format="table(timestamp, httpRequest.status, httpRequest.requestUrl, httpRequest.latency)"

# Filter for errors only (4xx + 5xx)
gcloud logging read \
    'resource.type="http_load_balancer"
     AND resource.labels.forwarding_rule_name="log-lb-fwd"
     AND httpRequest.status>=400' \
    --limit=10 \
    --format="table(timestamp, httpRequest.status, httpRequest.requestUrl)"

# Check latency distribution
gcloud logging read \
    'resource.type="http_load_balancer"
     AND resource.labels.forwarding_rule_name="log-lb-fwd"' \
    --limit=50 \
    --format="value(httpRequest.latency)" | sort -n
```

### Step 5 — Create a Log-Based Metric

```bash
# Count 5xx errors from the LB
gcloud logging metrics create lb-5xx-errors \
    --description="Count of 5xx responses from HTTP LB" \
    --log-filter='resource.type="http_load_balancer"
        AND resource.labels.forwarding_rule_name="log-lb-fwd"
        AND httpRequest.status>=500'
```

### Step 6 — Explore Monitoring Metrics (gcloud)

```bash
# List available LB metrics
gcloud monitoring metrics list \
    --filter="metric.type = starts_with(\"loadbalancing.googleapis.com/https\")" \
    --format="table(name, description)" \
    --limit=20

# Query request count over last hour
gcloud monitoring time-series list \
    --filter='metric.type="loadbalancing.googleapis.com/https/request_count"' \
    --interval-start-time=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --format="table(metric.labels, points[0].value)"
```

### Step 7 — Create Alerting Policy

```bash
# Alert if 5xx error rate exceeds threshold
gcloud alpha monitoring policies create \
    --display-name="LB 5xx Error Alert" \
    --condition-display-name="5xx errors > 5 in 5 min" \
    --condition-filter='resource.type="http_load_balancer" AND metric.type="loadbalancing.googleapis.com/https/request_count" AND metric.labels.response_code_class=500' \
    --condition-threshold-value=5 \
    --condition-threshold-comparison=COMPARISON_GT \
    --duration=300s
```

### Step 8 — Check Logging Configuration

```bash
# Verify logging is enabled on backend service
gcloud compute backend-services describe log-lb-backend \
    --global \
    --format="yaml(logConfig)"

# Adjust sample rate (reduce to 50% for high-traffic prod)
gcloud compute backend-services update log-lb-backend \
    --global \
    --logging-sample-rate=0.5
```

### Cleanup

```bash
gcloud compute forwarding-rules delete log-lb-fwd --global --quiet
gcloud compute target-http-proxies delete log-lb-proxy --quiet
gcloud compute url-maps delete log-lb-urlmap --quiet
gcloud compute backend-services delete log-lb-backend --global --quiet
gcloud compute health-checks delete log-lb-hc --quiet
gcloud compute instance-groups managed delete log-lb-mig --region=$REGION --quiet
gcloud compute instance-templates delete log-lb-tpl --quiet
gcloud compute firewall-rules delete allow-hc-log-lb --quiet
gcloud logging metrics delete lb-5xx-errors --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- LB logging is **per backend service** — enable with `--enable-logging --logging-sample-rate=1.0`
- Log entries include: request URL, status, latency, client IP, backend, cache status
- **Sample rate**: 1.0 = 100% of requests logged; reduce for high-traffic (0.1 = 10%)
- Key metrics: request_count, total_latencies, backend_latencies, error rate
- **Log-based metrics** convert log filters into numeric metrics for alerting
- CDN metrics: cache hit ratio, cache fill bytes
- Log query filter: `resource.type="http_load_balancer"`
- Always monitor: 5xx rate, p99 latency, backend health state

### Essential Commands

```bash
# Enable logging on backend service
gcloud compute backend-services update NAME --global --enable-logging --logging-sample-rate=1.0

# Query LB logs
gcloud logging read 'resource.type="http_load_balancer"' --limit=20

# Create log-based metric
gcloud logging metrics create NAME --log-filter='...'

# List LB monitoring metrics
gcloud monitoring metrics list --filter='metric.type=starts_with("loadbalancing.googleapis.com")'
```

---

## Part 4 — Quiz (15 min)

**Question 1: Your LB handles 10,000 requests/second. You have `logging-sample-rate=1.0`. What is the impact and what should you do?**

<details>
<summary>Show Answer</summary>

At 1.0 (100%), you're generating **10,000 log entries per second** ≈ 864 million per day. Impact:
- **Cost**: Cloud Logging charges per GB ingested (~$0.50/GB). At ~1KB per entry, that's ~850 GB/day ≈ **$425/day**
- **Storage**: Massive log volume to store and query

**Fix**: Reduce sample rate to 0.01-0.1 (1-10%) for production:
```bash
gcloud compute backend-services update NAME --global --logging-sample-rate=0.05
```
At 5%, you still get statistically representative data (500 logs/sec) at 1/20th the cost.

</details>

**Question 2: How do you distinguish between LB-level latency and backend processing latency?**

<details>
<summary>Show Answer</summary>

GCP provides two separate latency metrics:
- **`total_latencies`**: End-to-end time from when the GFE receives the request to when the response is sent to the client. Includes backend processing + GFE overhead.
- **`backend_latencies`**: Time from when the GFE forwards the request to the backend until the backend responds.

The difference (`total - backend`) is the **GFE overhead** (typically 1-5ms). If `total_latencies` is high but `backend_latencies` is low, the issue is network/GFE-related, not your application.

</details>

**Question 3: You see `statusDetails: "failed_to_pick_backend"` in LB logs. What does this mean?**

<details>
<summary>Show Answer</summary>

This means the LB could not find a healthy backend to route the request to. Common causes:

1. **All backends are unhealthy** — health checks failing on every instance
2. **No backends configured** — backend service has no instance groups
3. **Capacity limit reached** — all backends at max utilization/rate cap

Check backend health:
```bash
gcloud compute backend-services get-health BACKEND_SVC --global
```

Common fix: ensure firewall allows health check probes from `130.211.0.0/22` and `35.191.0.0/16`.

</details>

**Question 4: You want to alert when more than 1% of LB requests return 5xx over a 5-minute window. How would you set this up?**

<details>
<summary>Show Answer</summary>

Two approaches:

**Approach 1 — MQL (Monitoring Query Language):**
Create an alerting policy with a ratio metric:
- Numerator: request_count where response_code_class=500
- Denominator: total request_count
- Alert when ratio > 0.01 for 5 minutes

**Approach 2 — Log-based metric:**
1. Create a log-based metric counting 5xx logs
2. Create a second metric counting all logs
3. Use a ratio alert on the two metrics

Approach 1 is preferred because GCP provides request_count broken down by response_code_class natively — no custom metrics needed.

</details>

---

*Next: [Day 58 — Terraform Load Balancer](DAY_58_TERRAFORM_LB.md)*
