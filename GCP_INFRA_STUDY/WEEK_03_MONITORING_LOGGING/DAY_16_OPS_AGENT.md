# Day 16 — Ops Agent: Unified Logging & Monitoring Agent

> **Week 3 · Monitoring & Logging** | Region: `europe-west2` | Study time: 2 hours

---

## Part 1 — Concept (30 min)

### 1.1 What Is the Ops Agent?

The Ops Agent is Google's **unified agent** that runs on VMs to collect detailed metrics and logs — things the hypervisor can't see. Think of it as `collectd` + `fluentd` bundled into one managed agent.

| Linux Analogy | GCP Equivalent |
|---|---|
| `collectd` (metrics collector) | Ops Agent — metrics pipeline |
| `fluentd` / `rsyslog` forwarding | Ops Agent — logging pipeline |
| `node_exporter` (Prometheus) | Ops Agent system metrics |
| `top` / `free` / `df` data | Ops Agent exposes memory, disk %, processes |
| systemd service | `google-cloud-ops-agent.service` |

### 1.2 Why Do You Need It?

GCE auto-collected metrics come from the **hypervisor** (outside the VM). They're limited:

```
     WITHOUT Ops Agent                  WITH Ops Agent
  ┌───────────────────┐            ┌───────────────────────┐
  │ Hypervisor sees:  │            │ Hypervisor           │
  │ ✓ CPU utilization │            │ + Agent sees:         │
  │ ✓ Network bytes   │            │ ✓ CPU utilization     │
  │ ✓ Disk IO bytes   │            │ ✓ Network bytes       │
  │ ✗ Memory usage    │            │ ✓ Disk IO bytes       │
  │ ✗ Disk space %    │            │ ✓ Memory usage ✓ NEW  │
  │ ✗ Process list    │            │ ✓ Disk space %  ✓ NEW │
  │ ✗ Swap usage      │            │ ✓ Process count ✓ NEW │
  │ ✗ App logs        │            │ ✓ Swap usage    ✓ NEW │
  │ ✗ syslog/journal  │            │ ✓ App logs      ✓ NEW │
  │                   │            │ ✓ syslog/journal ✓ NEW│
  └───────────────────┘            └───────────────────────┘
```

### 1.3 Agent Architecture

```
┌──────────────── VM Instance ──────────────────────┐
│                                                    │
│  ┌─────────────────────────────────────────────┐   │
│  │          GOOGLE CLOUD OPS AGENT             │   │
│  │                                             │   │
│  │  ┌─────────────────┐  ┌──────────────────┐  │   │
│  │  │ METRICS PIPELINE │  │ LOGGING PIPELINE │  │   │
│  │  │ (OpenTelemetry)  │  │ (Fluent Bit)     │  │   │
│  │  │                 │  │                  │  │   │
│  │  │ ● CPU           │  │ ● /var/log/syslog│  │   │
│  │  │ ● Memory        │  │ ● /var/log/auth  │  │   │
│  │  │ ● Disk          │  │ ● journald       │  │   │
│  │  │ ● Network       │  │ ● Custom files   │  │   │
│  │  │ ● Swap          │  │ ●                │  │   │
│  │  │ ● Process       │  │                  │  │   │
│  │  └────────┬────────┘  └────────┬─────────┘  │   │
│  │           │                    │             │   │
│  └───────────┼────────────────────┼─────────────┘   │
│              │                    │                  │
└──────────────┼────────────────────┼──────────────────┘
               │                    │
               ▼                    ▼
        Cloud Monitoring      Cloud Logging
```

### 1.4 Metrics Comparison: Before vs After

| Metric | Without Agent | With Agent |
|---|---|---|
| CPU utilization | `compute.googleapis.com/instance/cpu/utilization` | Same + `agent.googleapis.com/cpu/*` |
| Memory used % | **Not available** | `agent.googleapis.com/memory/percent_used` |
| Disk space % | **Not available** | `agent.googleapis.com/disk/percent_used` |
| Swap used | **Not available** | `agent.googleapis.com/swap/percent_used` |
| Process count | **Not available** | `agent.googleapis.com/processes/count_by_state` |
| Network (detailed) | Bytes in/out only | + packets, errors, drops |

### 1.5 Configuration

The Ops Agent reads config from `/etc/google-cloud-ops-agent/config.yaml`:

```yaml
# /etc/google-cloud-ops-agent/config.yaml
logging:
  receivers:
    syslog:
      type: files
      include_paths:
        - /var/log/messages
        - /var/log/syslog
    custom_app:
      type: files
      include_paths:
        - /var/log/myapp/*.log
  service:
    pipelines:
      default_pipeline:
        receivers: [syslog]
      custom_pipeline:
        receivers: [custom_app]

metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
      collection_interval: 60s
  service:
    pipelines:
      default_pipeline:
        receivers: [hostmetrics]
```

| Config Section | Purpose | Linux Analogy |
|---|---|---|
| `logging.receivers` | Define log sources | rsyslog input modules |
| `logging.service.pipelines` | Route logs through receivers | rsyslog rules |
| `metrics.receivers` | Define metric sources | collectd plugins |
| `metrics.service.pipelines` | Route metrics through receivers | collectd chain rules |

### 1.6 VM Manager & OS Policies (Fleet Install)

For fleets of VMs, use **OS policies** instead of SSH-ing into each one:

```
  ┌──────────────────────────────────────────┐
  │          OS POLICY ASSIGNMENT            │
  │                                          │
  │  "Install Ops Agent on all VMs           │
  │   with label env=production              │
  │   in zone europe-west2-b"               │
  │                                          │
  │  Scope: zones, labels, OS type           │
  └──────────┬───────────┬──────────┬────────┘
             │           │          │
             ▼           ▼          ▼
         [VM-1]      [VM-2]     [VM-3]
         agent ✓     agent ✓    agent ✓
```

### 1.7 Supported Operating Systems

| OS | Supported |
|---|---|
| Debian 10/11/12 | Yes |
| Ubuntu 18.04/20.04/22.04 | Yes |
| CentOS 7/8, RHEL 7/8/9 | Yes |
| SLES 12/15 | Yes |
| Windows Server 2016/2019/2022 | Yes |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Goal

Create two VMs (one without agent, one with agent), compare available metrics, then install the Ops Agent and verify new metrics and logs appear.

### Prerequisites

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-b
```

### Step 1 — Create a VM Without the Agent

```bash
gcloud compute instances create ops-no-agent \
    --zone=europe-west2-b \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --labels=agent=none
```

### Step 2 — Check Available Metrics (Before Agent)

Wait 2–3 minutes for metrics to start flowing, then:

```bash
INSTANCE_ID_NO=$(gcloud compute instances describe ops-no-agent \
    --zone=europe-west2-b --format="value(id)")

# Check CPU — should WORK
gcloud monitoring time-series list \
    --filter="metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.labels.instance_id=\"$INSTANCE_ID_NO\"" \
    --interval-start-time=$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%SZ') \
    --limit=3

# Check memory — should return NOTHING (no agent)
gcloud monitoring time-series list \
    --filter="metric.type=\"agent.googleapis.com/memory/percent_used\" AND resource.labels.instance_id=\"$INSTANCE_ID_NO\"" \
    --interval-start-time=$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%SZ') \
    --limit=3

echo "CPU: available. Memory: nothing — because there's no agent."
```

### Step 3 — Create a VM and Install the Ops Agent

```bash
# Create a second VM
gcloud compute instances create ops-with-agent \
    --zone=europe-west2-b \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --labels=agent=opsagent

# SSH into it
gcloud compute ssh ops-with-agent --zone=europe-west2-b
```

**Inside the VM:**

```bash
# Install the Ops Agent (official Google installer script)
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install

# Check agent status (like checking any systemd service)
sudo systemctl status google-cloud-ops-agent
sudo systemctl status google-cloud-ops-agent-opentelemetry-collector
sudo systemctl status google-cloud-ops-agent-fluent-bit

# Verify it's running
sudo systemctl is-active google-cloud-ops-agent

# Check agent version
dpkg -l google-cloud-ops-agent | grep -i ops
```

### Step 4 — Verify Agent Configuration

```bash
# Still inside the VM

# View default config
cat /etc/google-cloud-ops-agent/config.yaml

# Check what logs the agent is tailing
sudo journalctl -u google-cloud-ops-agent-fluent-bit --no-pager -n 20

# Check what metrics the collector is gathering
sudo journalctl -u google-cloud-ops-agent-opentelemetry-collector --no-pager -n 20

# View the built-in log paths being collected
ls -la /var/log/syslog /var/log/auth.log /var/log/messages 2>/dev/null

# Generate some test data
logger "DAY16-LAB: Ops Agent test entry from $(hostname)"
dd if=/dev/zero of=/tmp/testfile bs=1M count=100 2>/dev/null  # disk activity
free -m  # check memory for reference

exit
```

### Step 5 — Compare Metrics (After Agent)

```bash
INSTANCE_ID_WITH=$(gcloud compute instances describe ops-with-agent \
    --zone=europe-west2-b --format="value(id)")

# Wait 2-3 minutes for agent metrics to flow

# Memory — should now WORK
gcloud monitoring time-series list \
    --filter="metric.type=\"agent.googleapis.com/memory/percent_used\" AND resource.labels.instance_id=\"$INSTANCE_ID_WITH\"" \
    --interval-start-time=$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%SZ') \
    --limit=3

# Disk space percentage — should now WORK
gcloud monitoring time-series list \
    --filter="metric.type=\"agent.googleapis.com/disk/percent_used\" AND resource.labels.instance_id=\"$INSTANCE_ID_WITH\"" \
    --interval-start-time=$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%SZ') \
    --limit=3

# Swap usage
gcloud monitoring time-series list \
    --filter="metric.type=\"agent.googleapis.com/swap/percent_used\" AND resource.labels.instance_id=\"$INSTANCE_ID_WITH\"" \
    --interval-start-time=$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%SZ') \
    --limit=3

echo "Memory, disk, and swap metrics now available with the Ops Agent!"
```

### Step 6 — Verify Logs Are Flowing

```bash
# Check if syslog entries from the VM appear in Cloud Logging
gcloud logging read \
    "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_ID_WITH\" AND textPayload:\"DAY16-LAB\"" \
    --limit=5 \
    --format="table(timestamp,severity,textPayload)"

# Compare: check if the no-agent VM has syslog entries
# (It might have serial port logs but not syslog)
gcloud logging read \
    "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_ID_NO\"" \
    --limit=5 \
    --format="table(timestamp,logName,severity)"
```

### Step 7 — Add Custom Log Collection

```bash
# SSH back into the agent VM
gcloud compute ssh ops-with-agent --zone=europe-west2-b

# Create a custom application log
sudo mkdir -p /var/log/myapp
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO myapp: Application started" | \
    sudo tee /var/log/myapp/app.log
echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR myapp: Database connection failed" | \
    sudo tee -a /var/log/myapp/app.log

# Configure the Ops Agent to collect this custom log
sudo tee /etc/google-cloud-ops-agent/config.yaml > /dev/null << 'EOF'
logging:
  receivers:
    syslog:
      type: files
      include_paths:
        - /var/log/messages
        - /var/log/syslog
    myapp_logs:
      type: files
      include_paths:
        - /var/log/myapp/*.log
  service:
    pipelines:
      default_pipeline:
        receivers: [syslog]
      myapp_pipeline:
        receivers: [myapp_logs]

metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
      collection_interval: 60s
  service:
    pipelines:
      default_pipeline:
        receivers: [hostmetrics]
EOF

# Restart the agent to pick up new config
sudo systemctl restart google-cloud-ops-agent

# Verify restart
sudo systemctl status google-cloud-ops-agent --no-pager

# Generate more custom log entries
for i in $(seq 1 5); do
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO myapp: Request processed #$i" | \
        sudo tee -a /var/log/myapp/app.log
done

exit
```

### Step 8 — Verify Custom Logs in Explorer

```bash
# Query for the custom application logs
gcloud logging read \
    "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_ID_WITH\" AND logName:\"myapp_logs\"" \
    --limit=10 \
    --format="table(timestamp,severity,textPayload)"
```

Also check in **Console → Logging → Logs Explorer**:
```
resource.type="gce_instance"
logName:"myapp_logs"
```

### Step 9 — Explore VM Insights (Console)

Navigate to **Console → Monitoring → VM Insights**:

1. Click **Enable** if prompted
2. Compare `ops-no-agent` vs `ops-with-agent`
3. Note that agent-equipped VMs show memory, disk space, and running processes
4. This is the quickest way to audit which VMs have the agent installed

### Cleanup

```bash
# Delete both VMs
gcloud compute instances delete ops-no-agent --zone=europe-west2-b --quiet
gcloud compute instances delete ops-with-agent --zone=europe-west2-b --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- Ops Agent = unified `collectd` + `fluentd` replacement; collects detailed metrics + logs from inside the VM
- Without agent: only hypervisor metrics (CPU, network, disk IO). No memory, disk space %, swap, process info
- With agent: full OS-level metrics under `agent.googleapis.com/` + syslog/journald/custom log collection
- Config file: `/etc/google-cloud-ops-agent/config.yaml` — define receivers and pipelines
- Two sub-services: `opentelemetry-collector` (metrics) + `fluent-bit` (logs)
- **Fleet install**: use OS policies via VM Manager for many VMs
- **VM Insights**: Console dashboard showing agent status across all VMs
- Custom log collection: add `receivers` with `include_paths` pointing to your log files

### Essential Commands

```bash
# Install Ops Agent
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install

# Manage agent service
sudo systemctl status google-cloud-ops-agent
sudo systemctl restart google-cloud-ops-agent
sudo systemctl stop google-cloud-ops-agent

# Check sub-services
sudo systemctl status google-cloud-ops-agent-opentelemetry-collector
sudo systemctl status google-cloud-ops-agent-fluent-bit

# View agent logs
sudo journalctl -u google-cloud-ops-agent --no-pager -n 50

# Edit config
sudo vim /etc/google-cloud-ops-agent/config.yaml
sudo systemctl restart google-cloud-ops-agent
```

---

## Part 4 — Quiz (15 min)

**Question 1: You need to monitor memory utilization on your GCE VMs. What must you install?**

<details>
<summary>Show Answer</summary>

Install the **Ops Agent** (`google-cloud-ops-agent`). GCE auto-collected metrics come from the hypervisor and do **not** include memory utilization. The Ops Agent runs inside the VM and collects OS-level metrics including:
- `agent.googleapis.com/memory/percent_used`
- `agent.googleapis.com/memory/bytes_used`

This is analogous to how you need `node_exporter` on a Linux box for Prometheus to see `/proc/meminfo` data — the monitoring server can't read the VM's memory stats from outside.

</details>

---

**Question 2: After installing the Ops Agent, you modify `/etc/google-cloud-ops-agent/config.yaml` to add a custom log path. New log entries are not appearing in Cloud Logging. What did you forget?**

<details>
<summary>Show Answer</summary>

You need to **restart the agent** after editing the config:

```bash
sudo systemctl restart google-cloud-ops-agent
```

The Ops Agent does not hot-reload configuration changes. Just like editing `/etc/rsyslog.conf` requires `systemctl restart rsyslog`, the Ops Agent needs a restart.

Also verify:
- The log file path in `include_paths` is correct and exists
- The agent user has read permission on the log file
- The pipeline references the new receiver
- Check agent logs: `sudo journalctl -u google-cloud-ops-agent-fluent-bit`

</details>

---

**Question 3: You have 50 production VMs and need to install the Ops Agent on all of them. What is the recommended approach?**

<details>
<summary>Show Answer</summary>

Use **VM Manager OS policies** to install the Ops Agent at fleet scale. Create an OS policy assignment that:
1. Targets VMs by zone, labels, or OS type
2. Ensures the `google-cloud-ops-agent` package is installed
3. Continuously enforces the desired state (if the agent is removed, it gets reinstalled)

This is declarative and self-healing — much better than SSH-ing into 50 VMs manually or even using a shell loop. It's the GCP equivalent of Ansible/Puppet for agent management.

Alternative: use `gcloud compute ssh` in a loop for a quick one-off, but this doesn't ensure ongoing compliance.

</details>

---

**Question 4: What are the two sub-services that make up the Ops Agent, and what does each do?**

<details>
<summary>Show Answer</summary>

1. **`google-cloud-ops-agent-opentelemetry-collector`**: The **metrics pipeline**. Based on OpenTelemetry Collector. Collects CPU, memory, disk, network, swap, and process metrics. Sends to Cloud Monitoring.

2. **`google-cloud-ops-agent-fluent-bit`**: The **logging pipeline**. Based on Fluent Bit. Tails log files (`/var/log/syslog`, custom paths) and reads from journald. Sends to Cloud Logging.

Both run as separate systemd services under the umbrella `google-cloud-ops-agent` service. If one fails, the other continues running.

Linux analogy: it's like running `collectd` (metrics) and `fluentd` (logs) as two separate daemons managed by a single wrapper.

</details>

---

*End of Day 16 — Tomorrow: Health check scripting with bash.*
