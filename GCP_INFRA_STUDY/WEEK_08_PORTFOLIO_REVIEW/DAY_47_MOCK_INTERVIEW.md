# Day 47 — Mock Interview: Explain Your Projects

> **Week 8 — Portfolio & Review** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### Interview Communication Framework

Technical interviews test **communication** as much as knowledge. You need to explain complex infrastructure in a structured, concise way.

### The STAR-T Method for Infrastructure

```
┌──────────────────────────────────────────────────────────┐
│              STAR-T Framework                             │
│                                                          │
│  S — SITUATION                                           │
│      "The project needed..."                             │
│      (30 seconds — set the context)                      │
│                                                          │
│  T — TASK                                                │
│      "My job was to..."                                  │
│      (15 seconds — your specific responsibility)         │
│                                                          │
│  A — ACTION                                              │
│      "I built X using Y because Z"                       │
│      (60 seconds — what you did and why)                 │
│                                                          │
│  R — RESULT                                              │
│      "This achieved..."                                  │
│      (15 seconds — measurable outcome)                   │
│                                                          │
│  T — TECHNOLOGY                                          │
│      "Key technologies: Terraform, GCP VPC, Cloud NAT"   │
│      (10 seconds — keyword dropping for the JD match)    │
│                                                          │
│  Total: ~2 minutes                                       │
└──────────────────────────────────────────────────────────┘
```

### "Walk Me Through Your Architecture"

This is the most common technical interview question. Here's the structure:

```
┌──────────────────────────────────────────────────────────┐
│         Architecture Walkthrough Structure                │
│                                                          │
│  1. START from the user/entry point                      │
│     "Traffic comes in from the internet..."              │
│                                                          │
│  2. FOLLOW the data/request flow                         │
│     "... hits the load balancer, which routes to..."     │
│                                                          │
│  3. HIGHLIGHT security at each layer                     │
│     "... the firewall only allows port 80/443..."        │
│                                                          │
│  4. MENTION automation                                   │
│     "... all deployed via Terraform, so it's..."         │
│                                                          │
│  5. END with operational aspects                         │
│     "... monitoring via Ops Agent, daily snapshots..."   │
│                                                          │
│  KEY: Use the diagram as a visual guide                  │
│  Point to components as you explain them                 │
└──────────────────────────────────────────────────────────┘
```

### Common Interview Questions Map

```
┌──────────────────────────────────────────────────────────┐
│        Questions by Category                             │
│                                                          │
│  ARCHITECTURE:                                           │
│  • "Walk me through your architecture"                   │
│  • "Why did you choose this design?"                     │
│  • "What would you change for production?"               │
│                                                          │
│  SECURITY:                                               │
│  • "How did you secure SSH access?"                      │
│  • "Explain your network security model"                 │
│  • "How do you handle secrets?"                          │
│                                                          │
│  OPERATIONS:                                             │
│  • "How do you monitor this?"                            │
│  • "What's your backup strategy?"                        │
│  • "Explain your incident response process"              │
│                                                          │
│  TERRAFORM:                                              │
│  • "How do you manage Terraform state?"                  │
│  • "How do you handle environment differences?"          │
│  • "What's your module strategy?"                        │
│                                                          │
│  TROUBLESHOOTING:                                        │
│  • "A VM can't reach the internet. Debug it."            │
│  • "Terraform plan shows unexpected changes. Why?"       │
│  • "Your startup script isn't running. What do you do?"  │
│                                                          │
│  GROWTH:                                                 │
│  • "How would you scale this to 100 VMs?"                │
│  • "What would you add if you had more time?"            │
│  • "What was the hardest part?"                          │
└──────────────────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Goal: Prepare 2-Minute Explanations for Each Project, Plus Model Answers

### Project 1: Secure VPC (Week 2)

**2-Minute Explanation:**

> "The goal was to create a production-ready network on GCP that follows security best practices.
>
> I built a custom VPC in europe-west2 with a /24 subnet, so I have full control over the IP addressing — no auto-created subnets. For security, I implemented IAP-only SSH access — there are no public SSH ports on any VM. All VMs get private IPs only, and Cloud NAT handles outbound internet access for package updates.
>
> Firewall rules follow least privilege: SSH only from IAP's IP range, HTTP only to tagged web servers, and everything else is denied by default. VPC Flow Logs are enabled for audit trails.
>
> I deployed everything with Terraform modules — VPC in one module, compute in another — so the same modules are reused across dev and prod environments. The key design decision was using IAP instead of a bastion host, which reduces the attack surface and leverages Google's identity-aware infrastructure.
>
> Technologies: Terraform, VPC, Cloud NAT, Cloud Router, IAP, Firewall Rules."

### Project 2: Monitoring Pack (Week 3)

**2-Minute Explanation:**

> "This project sets up full observability for a Compute Engine fleet — metrics, logs, and alerting.
>
> Each VM runs the Ops Agent for standard metrics — CPU, memory, disk, network — plus a custom monitoring script I wrote that checks application-specific health metrics. The script runs via cron every 5 minutes and pushes custom metrics to the Cloud Monitoring API.
>
> I configured alert policies with escalating thresholds: CPU over 80% triggers a warning, disk over 85% triggers an alert, memory over 90% is critical. Notifications go to both email and a Slack webhook for redundancy.
>
> There's also a pre-built dashboard showing fleet-wide metrics at a glance — useful for daily standups and incident investigation. The monitoring setup is baked into the VM's startup script, so every new VM automatically gets full monitoring from boot.
>
> Technologies: Cloud Monitoring, Ops Agent, Custom Metrics API, Cloud Logging, Bash, cron."

### Project 3: Terraform Landing Zone (Week 5)

**2-Minute Explanation:**

> "I built an automated landing zone — a repeatable foundation for new GCP workloads — using Terraform modules.
>
> The structure separates reusable modules from environment-specific configuration. There's a VPC module, a compute module, and a storage module. Each environment — dev and prod — calls the same modules with different parameters: dev gets e2-micro VMs on the default network, prod gets e2-standard-2 on a hardened network with snapshot schedules.
>
> State is stored remotely in a GCS bucket with prefix-based separation per environment, preventing state conflicts in a team setting. I wrote a .gitignore that excludes state files and credentials, and every module has its own README with input/output documentation.
>
> The key learning was separating what changes per environment (machine type, CIDR, labels) from what stays constant (hardening, monitoring, firewall patterns).
>
> Technologies: Terraform (modules, remote state, workspaces), GCS, VPC, Compute Engine."

### Project 4: Backup & Restore (Week 6)

**2-Minute Explanation:**

> "This project implements a complete backup strategy for Compute Engine VMs with documented restore procedures.
>
> VM disks have automated snapshot schedules: web servers get daily snapshots with 7-day retention, databases get hourly with 24-hour retention. Application data in Cloud Storage uses lifecycle policies to auto-transition from Standard to Nearline to Coldline, and versioning is enabled for accidental deletion recovery.
>
> I created a custom image pipeline — a golden image with the base OS, packages, and hardening — so any destroyed VM can be rebuilt identically. For the backup strategy, I documented RPO and RTO targets: 24 hours RPO for web servers, 1 hour for databases, and 15 minutes RTO for both.
>
> The key deliverable is a backup/restore runbook with exact commands, verification steps, a troubleshooting table, and a test log. I validated the runbook by simulating data corruption and timing the full restore procedure.
>
> Technologies: Snapshots, Resource Policies, GCS Lifecycle, Object Versioning, Custom Images."

### Project 5: Golden VM Automation (Week 7)

**2-Minute Explanation:**

> "This automates the entire VM baseline — from bare Debian 12 to a production-ready, hardened, monitored server — using a single idempotent startup script.
>
> The script lives in GCS and is referenced via startup-script-url. When a VM boots, it downloads and runs the script, which installs packages, hardens SSH and kernel parameters, configures fail2ban and auditd, sets up a monitoring script with cron, and configures log rotation.
>
> The script uses a guard file pattern for idempotency — if the marker file exists, it skips all setup. This is important because startup scripts run on every boot, not just the first boot. I also wrote a verification script that checks all 20+ configuration points automatically.
>
> The setup is deployed via Terraform with an instance template, so spinning up 50 identical VMs is one command. Operational scripts — monitoring, disk cleanup — run automatically from day one.
>
> Technologies: Startup Scripts, GCS, Terraform Instance Templates, Bash, cron, logrotate, fail2ban, auditd."

---

### Common Questions & Model Answers

**Q: "How did you secure SSH access?"**

> "I use IAP (Identity-Aware Proxy) for SSH — no public SSH ports are exposed. The firewall only allows TCP/22 from Google's IAP IP range (35.235.240.0/20), and only to VMs tagged 'ssh'. On the VM itself, SSH is hardened: root login is disabled, password authentication is off, max auth tries is 3, and X11 forwarding is disabled. I also run fail2ban for additional brute-force protection."

**Q: "How do you manage Terraform state in a team?"**

> "State is stored in a GCS bucket with object versioning enabled — so we can recover if state gets corrupted. Each environment gets its own state prefix, preventing conflicts. We use the Terraform GCS backend with locking, so only one person can modify state at a time. The bucket has IAM restricted to the Terraform service account, and state files are never committed to Git — they're in .gitignore."

**Q: "A VM can't reach the internet. Walk me through debugging it."**

> "First, I check if the VM has an external IP: `gcloud compute instances describe VM`. If no external IP, I check for Cloud NAT: `gcloud compute routers nats list`. If NAT exists, I verify it's attached to the right router and subnet. If NAT is missing, that's the fix. On the VM, I check routes with `ip route show` and DNS with `nslookup google.com`. If routes are fine but traffic doesn't flow, I check egress firewall rules. The most common cause is missing Cloud NAT or a restricted egress firewall."

**Q: "What would you change for a real production environment?"**

> "Several things: First, I'd add a load balancer for high availability instead of single VMs. Second, I'd implement a CI/CD pipeline for Terraform — PRs trigger plan, merge triggers apply. Third, I'd use service accounts with minimal roles instead of default scopes. Fourth, SSL certificates via Certificate Manager. Fifth, proper secrets management with Secret Manager instead of metadata. And sixth, I'd add health checks and auto-healing managed instance groups instead of standalone VMs."

**Q: "What was the hardest part of these projects?"**

> "Making startup scripts truly idempotent was tricky. The first version worked on a fresh VM but broke on reboot because it appended to config files instead of overwriting them. I learned to use guard files, full file overwrites instead of appends, and sed for in-place edits. The debugging process — serial output, journalctl, re-running the script manually — taught me more than the initial build."

---

## Part 3 — Revision (15 min)

### Interview Preparation Checklist

```
FOR EACH PROJECT:
  [ ] 2-minute explanation practiced (with timer)
  [ ] Architecture diagram ready to draw/show
  [ ] Key decision + WHY ready to explain
  [ ] One "hardest part" or "lesson learned" story
  [ ] Cleanup process known

GENERAL:
  [ ] Can draw VPC architecture on whiteboard
  [ ] Can explain Terraform state management
  [ ] Can debug common issues verbally (SSH, network, startup)
  [ ] Can explain IAP, Cloud NAT, firewall rules
  [ ] Can discuss security hardening approach
  [ ] Know the difference between snapshot/image/machine image
  [ ] Can explain how to scale beyond single VMs (MIG, LB)
```

### Phrases That Impress

| Concept | Say This |
|---|---|
| Security | "Defence in depth — firewall + IAP + OS hardening" |
| Automation | "Idempotent startup scripts — safe to re-run on every boot" |
| Operations | "Monitoring from day one — not an afterthought" |
| IaC | "Modules separate reusable logic from environment-specific config" |
| Backups | "We measure RPO and RTO, not just 'we have backups'" |
| Testing | "I tested the restore procedure — an untested backup is no backup" |

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: Practice: Explain your VPC project in under 2 minutes. What are the key points you must hit?</strong></summary>

**Answer:** Key points (in order):

1. **Purpose:** "Production-ready network with security best practices"
2. **Architecture:** Custom VPC → private subnet → firewall rules → Cloud NAT
3. **Security highlights:** IAP-only SSH, no public IPs, deny-all default, flow logs
4. **Automation:** "Deployed via Terraform modules, reusable across environments"
5. **Key decision:** "IAP over bastion — reduces attack surface, identity-aware access"
6. **Tech stack:** "Terraform, VPC, Cloud NAT, Cloud Router, IAP"

**Practice tip:** Set a 2-minute timer and practice out loud. If you can't finish, trim the details — keep the structure.
</details>

<details>
<summary><strong>Q2: An interviewer asks: "Why Terraform instead of just gcloud commands?" How do you answer?</strong></summary>

**Answer:**

> "gcloud commands are great for one-off tasks and debugging, but Terraform provides three things essential for production:
>
> **1. State management** — Terraform tracks what exists, so it can detect drift and plan changes precisely.
>
> **2. Reproducibility** — I can destroy and recreate the entire environment identically, in any project or region, with one command.
>
> **3. Code review** — infrastructure changes go through the same PR review process as application code, catching mistakes before they reach production.
>
> In my projects, I use gcloud for ad-hoc debugging and Terraform for anything that needs to be persistent and repeatable."
</details>

<details>
<summary><strong>Q3: "What would you do differently if you were starting these projects again?" (This is a growth mindset question)</strong></summary>

**Answer:**

> "Three things:
>
> **1. CI/CD from the start** — I'd set up Cloud Build to run `terraform plan` on PRs from day one, rather than applying locally. Even for personal projects, it builds the right habit.
>
> **2. Remote state from the start** — I started with local state and migrated later. Starting with a GCS backend would have been cleaner.
>
> **3. Testing** — I'd add automated infrastructure tests (Terratest or `terraform validate` in CI) to catch issues before apply. My current testing is manual verification scripts, which work but don't scale.
>
> These gaps reflect the difference between a learning portfolio and a production system — I know what needs to be added, which is the point."
</details>

<details>
<summary><strong>Q4: The interviewer says: "We use AWS, not GCP. Is your experience transferable?" How do you respond?</strong></summary>

**Answer:**

> "Absolutely. The concepts are directly transferable — the tooling differs but the architecture patterns are the same.
>
> GCP VPC maps to AWS VPC. Cloud NAT maps to NAT Gateway. IAP maps to Systems Manager Session Manager. GCS maps to S3 with lifecycle and versioning. Compute Engine maps to EC2 with AMIs and launch templates.
>
> More importantly, the skills that matter most are cloud-agnostic: Infrastructure as Code (Terraform works on both), network security design (defence in depth), operational automation (startup scripts = user data), and monitoring/observability patterns.
>
> I chose GCP for my study because I hold the ACE certification, but I've built my projects with portability in mind — my Terraform modules could be adapted to the AWS provider with variable changes, not architectural changes."
</details>
