# Day 13 — Cloud Logging: Logs Explorer, Queries & Sinks

> **Week 3 · Monitoring & Logging** | Region: `europe-west2` | Study time: 2 hours

---

## Part 1 — Concept (30 min)

### 1.1 What Is Cloud Logging?

Cloud Logging is GCP's centralised log management service — think of it as a **managed `rsyslog` + `journald` + ELK stack** all rolled into one. Every GCP service automatically ships logs here.

| Linux Analogy | GCP Equivalent |
|---|---|
| `/var/log/syslog` | Cloud Logging – Platform logs |
| `/var/log/auth.log` | Cloud Audit Logs – Admin Activity |
| `journalctl -u nginx` | Logs Explorer filtered by resource |
| `logrotate` | Log retention policies |
| `rsyslog` forwarding | Log sinks (route to GCS/BigQuery/Pub/Sub) |

### 1.2 Log Types

```
┌─────────────────────────────────────────────────┐
│                 CLOUD LOGGING                    │
├──────────────┬──────────────┬───────────────────┤
│  Platform    │   Audit      │   User / Agent    │
│  Logs        │   Logs       │   Logs            │
├──────────────┼──────────────┼───────────────────┤
│ GCE serial   │ Admin        │ Application logs  │
│ VPC flow     │ Activity     │ written via Ops   │
│ GKE system   │ Data Access  │ Agent or API      │
│ LB request   │ System Event │                   │
│ Cloud SQL    │ Policy Denied│                   │
└──────────────┴──────────────┴───────────────────┘
```

| Log Type | Default Retention | Enabled By Default | Cost |
|---|---|---|---|
| Admin Activity audit | 400 days | Yes | Free |
| Data Access audit | 30 days | No (most services) | Charged |
| Platform logs | 30 days | Yes | Charged |
| User-written logs | 30 days | N/A | Charged |

### 1.3 Logs Explorer Overview

Logs Explorer is the web UI for querying logs — like `grep` and `awk` on steroids.

```
┌─────────────────────────────────────────────────────────┐
│  LOGS EXPLORER                                          │
│                                                         │
│  ┌─────────────────────────────────────────────┐        │
│  │  Query Box (logging query language)         │        │
│  │  resource.type="gce_instance"               │        │
│  │  severity>=WARNING                          │        │
│  │  timestamp>="2026-04-08T00:00:00Z"          │        │
│  └─────────────────────────────────────────────┘        │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐          │
│  │ Resource │  │ Severity │  │  Time Range  │          │
│  │ Filter   │  │ Filter   │  │  Selector    │          │
│  └──────────┘  └──────────┘  └──────────────┘          │
│                                                         │
│  ┌─────────────────────────────────────────────┐        │
│  │  Log Entry 1  [EXPAND]                      │        │
│  │  Log Entry 2  [EXPAND]                      │        │
│  │  Log Entry 3  [EXPAND]                      │        │
│  └─────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────┘
```

### 1.4 Logging Query Language

The query language uses field paths — like `jq` for structured log JSON.

| Query Pattern | Example | Linux Equivalent |
|---|---|---|
| By resource | `resource.type="gce_instance"` | `grep` in specific log file |
| By severity | `severity>=ERROR` | `journalctl -p err` |
| By text | `textPayload:"disk full"` | `grep "disk full" /var/log/*` |
| By label | `resource.labels.instance_id="123"` | filtering by hostname |
| By time | `timestamp>="2026-04-08T00:00:00Z"` | `journalctl --since` |
| Combined | `resource.type="gce_instance" AND severity=ERROR` | piping grep |

### 1.5 Log Sinks (Log Router)

Sinks route copies of logs to storage destinations — like `rsyslog` forwarding rules.

```
                        ┌──────────────────┐
                        │   LOG ROUTER     │
   Incoming Logs ──────>│                  │
                        │  ┌────────────┐  │
                        │  │  _Default  │──┼──> Cloud Logging buckets
                        │  │   sink     │  │     (30-day retention)
                        │  └────────────┘  │
                        │                  │
                        │  ┌────────────┐  │
                        │  │ Custom     │──┼──> GCS Bucket (archive)
                        │  │  Sink A    │  │
                        │  └────────────┘  │
                        │                  │
                        │  ┌────────────┐  │
                        │  │ Custom     │──┼──> BigQuery (analytics)
                        │  │  Sink B    │  │
                        │  └────────────┘  │
                        │                  │
                        │  ┌────────────┐  │
                        │  │ Custom     │──┼──> Pub/Sub (streaming)
                        │  │  Sink C    │  │
                        │  └────────────┘  │
                        └──────────────────┘
```

| Sink Destination | Use Case | Linux Analogy |
|---|---|---|
| Cloud Storage (GCS) | Long-term archive, compliance | `logrotate` → compressed archive |
| BigQuery | Ad-hoc SQL analytics on logs | shipping to a database |
| Pub/Sub | Real-time streaming to SIEM | syslog TCP forward |
| Logging bucket | Custom retention periods | separate log partition |

### 1.6 Retention & Pricing

- **_Default** bucket: 30 days, free for first 50 GiB/month ingestion
- **_Required** bucket: 400 days (Admin Activity, System Event), always free
- Custom buckets: configurable 1–3650 days
- Beyond free tier: ~$0.50 / GiB ingested

### 1.7 Exclusion Filters

You can **exclude** logs from being ingested to save cost — like dropping debug-level logs in `rsyslog`:

```
# Exclusion filter example — drop DEBUG logs from a noisy service
resource.type="gce_instance"
severity=DEBUG
resource.labels.instance_id="1234567890"
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Goal

Create a VM, generate syslog entries, query them in Logs Explorer, and create a sink to export logs to GCS.

### Prerequisites

```bash
# Set project
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-b
```

### Step 1 — Create a Test VM

```bash
gcloud compute instances create log-test-vm \
    --zone=europe-west2-b \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=log-test
```

### Step 2 — Generate Log Entries

SSH into the VM and produce some syslog-style entries:

```bash
# SSH into the VM
gcloud compute ssh log-test-vm --zone=europe-west2-b

# --- Run these INSIDE the VM ---

# Generate syslog entries (like you would on any Linux box)
logger -p user.info "DAY13-LAB: Application started successfully"
logger -p user.warning "DAY13-LAB: Disk usage approaching threshold"
logger -p user.err "DAY13-LAB: Failed to connect to database"
logger -p user.crit "DAY13-LAB: Critical failure in payment service"

# Generate some repeated entries to test query counting
for i in $(seq 1 10); do
    logger -p user.info "DAY13-LAB: Heartbeat check $i OK"
done

# Write a custom application log
echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR custom-app: Connection refused" | \
    sudo tee -a /var/log/custom-app.log

# Exit the VM
exit
```

### Step 3 — Query Logs in Logs Explorer (Console)

Open **Console → Logging → Logs Explorer**, then try these queries:

**Query 1 — Find all our lab entries:**
```
resource.type="gce_instance"
textPayload:"DAY13-LAB"
```

**Query 2 — Errors only:**
```
resource.type="gce_instance"
textPayload:"DAY13-LAB"
severity>=ERROR
```

**Query 3 — Count heartbeats:**
```
resource.type="gce_instance"
textPayload:"DAY13-LAB: Heartbeat"
```

**Query 4 — Time-bounded (last hour):**
```
resource.type="gce_instance"
textPayload:"DAY13-LAB"
timestamp>="2026-04-08T00:00:00Z"
```

### Step 4 — Query Logs via gcloud CLI

```bash
# Read recent logs for the VM (like tail -f /var/log/syslog)
gcloud logging read \
    'resource.type="gce_instance" AND textPayload:"DAY13-LAB"' \
    --limit=20 \
    --format="table(timestamp,severity,textPayload)"

# Errors only
gcloud logging read \
    'resource.type="gce_instance" AND textPayload:"DAY13-LAB" AND severity>=ERROR' \
    --limit=10 \
    --format="table(timestamp,severity,textPayload)"

# Write a custom log entry from CLI (like logger on Linux)
gcloud logging write my-custom-log "DAY13-LAB: Custom entry from gcloud CLI" \
    --severity=INFO
```

### Step 5 — Create a GCS Bucket for Log Export

```bash
# Create a GCS bucket to receive logs
gcloud storage buckets create gs://YOUR_PROJECT_ID-log-sink \
    --location=europe-west2 \
    --uniform-bucket-level-access

# Verify
gcloud storage buckets describe gs://YOUR_PROJECT_ID-log-sink --format="value(name)"
```

### Step 6 — Create a Log Sink to GCS

```bash
# Create sink — routes matching logs to GCS
gcloud logging sinks create gce-error-sink \
    storage.googleapis.com/YOUR_PROJECT_ID-log-sink \
    --log-filter='resource.type="gce_instance" AND severity>=ERROR'

# The sink creation outputs a service account — grant it write access
# Copy the writer identity from the output, e.g.:
# serviceAccount:p123456789-123456@gcp-sa-logging.iam.gserviceaccount.com

SINK_SA=$(gcloud logging sinks describe gce-error-sink \
    --format="value(writerIdentity)")

gcloud storage buckets add-iam-policy-binding \
    gs://YOUR_PROJECT_ID-log-sink \
    --member="$SINK_SA" \
    --role="roles/storage.objectCreator"
```

### Step 7 — Verify the Sink

```bash
# List sinks
gcloud logging sinks list --format="table(name,destination,filter)"

# Describe our sink
gcloud logging sinks describe gce-error-sink

# Generate an error to trigger the sink
gcloud compute ssh log-test-vm --zone=europe-west2-b \
    --command="logger -p user.err 'DAY13-LAB: Sink test error entry'"

# Wait ~5 min, then check the GCS bucket
gcloud storage ls gs://YOUR_PROJECT_ID-log-sink/ --recursive
```

### Step 8 — Explore Log Entry Structure

```bash
# Get a single log entry in full JSON to understand structure
gcloud logging read \
    'resource.type="gce_instance" AND textPayload:"DAY13-LAB"' \
    --limit=1 \
    --format=json
```

Key fields to note:

| Field | Description | Linux Analogy |
|---|---|---|
| `insertId` | Unique log entry ID | — |
| `logName` | Log stream name | log file path |
| `resource.type` | Resource type (gce_instance) | hostname in syslog |
| `severity` | Log level | syslog priority |
| `textPayload` | Plain text message | the log line itself |
| `jsonPayload` | Structured log data | — |
| `timestamp` | When the event occurred | syslog timestamp |

### Cleanup

```bash
# Delete the sink
gcloud logging sinks delete gce-error-sink --quiet

# Delete the GCS bucket
gcloud storage rm -r gs://YOUR_PROJECT_ID-log-sink/
gcloud storage buckets delete gs://YOUR_PROJECT_ID-log-sink

# Delete the VM
gcloud compute instances delete log-test-vm --zone=europe-west2-b --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- Cloud Logging = centralised managed log service; think `rsyslog` + ELK in one
- **Log types**: Platform (auto), Audit (admin/data-access), User-written (app/agent)
- **Logs Explorer** = web UI for queries; **gcloud logging read** = CLI equivalent
- **Query language** uses field paths: `resource.type`, `severity`, `textPayload`, `timestamp`
- **Sinks** route log copies to GCS / BigQuery / Pub/Sub / custom bucket
- **_Default** bucket = 30 days; **_Required** bucket = 400 days (free, audit logs)
- **Exclusion filters** = drop logs before ingestion to save cost
- Sink writer identity needs IAM permissions on the destination
- First 50 GiB/month ingestion is free; ~$0.50/GiB after that

### Essential Commands

```bash
# Read logs
gcloud logging read 'FILTER' --limit=N --format=json

# Write a custom log
gcloud logging write LOG_NAME "message" --severity=INFO

# List/create/delete sinks
gcloud logging sinks list
gcloud logging sinks create SINK_NAME DESTINATION --log-filter='FILTER'
gcloud logging sinks delete SINK_NAME

# Get sink writer identity
gcloud logging sinks describe SINK_NAME --format="value(writerIdentity)"
```

---

## Part 4 — Quiz (15 min)

**Question 1: Which log bucket has a fixed 400-day retention and cannot be deleted?**

<details>
<summary>Show Answer</summary>

**`_Required`** bucket. It stores Admin Activity and System Event audit logs. These are always free and cannot be excluded, modified, or deleted. The `_Default` bucket stores everything else with a default 30-day retention that can be customised.

</details>

---

**Question 2: You created a log sink to export ERROR logs to a GCS bucket, but no files appear after 30 minutes. What is the most likely cause?**

<details>
<summary>Show Answer</summary>

The **sink's writer identity** (service account) does not have permission to write to the GCS bucket. After creating a sink, you must grant the `roles/storage.objectCreator` role (or equivalent) to the service account returned in `writerIdentity`. This is the most common sink troubleshooting issue.

Other possible causes: the filter is wrong (no matching logs), or logs haven't been generated yet.

</details>

---

**Question 3: What is the difference between `textPayload` and `jsonPayload` in a log entry?**

<details>
<summary>Show Answer</summary>

- **`textPayload`**: Plain unstructured text (like a raw syslog line). Example: `"Connection refused from 10.0.0.1"`
- **`jsonPayload`**: Structured JSON data with named fields. Example: `{"status": 500, "method": "GET", "url": "/api/health"}`

Only one payload type is present per log entry. Structured logs (`jsonPayload`) are easier to query because you can filter on individual fields: `jsonPayload.status=500`.

</details>

---

**Question 4: You want to stop ingesting DEBUG-level logs from a noisy service to reduce costs, but still keep ERROR and above. What GCP feature do you use?**

<details>
<summary>Show Answer</summary>

Use an **exclusion filter** on the Log Router. Create a filter that matches the DEBUG logs you want to drop:

```
resource.type="gce_instance"
resource.labels.instance_id="NOISY_VM_ID"
severity=DEBUG
```

Excluded logs are never ingested (and never charged). They cannot be recovered. This is like configuring `rsyslog` to drop messages below a certain priority before writing them.

</details>

---

*End of Day 13 — Tomorrow: Cloud Monitoring, metrics, and dashboards.*
