# Day 133 — Compute + Linux Deep Interview Questions

> **Week 23 · Interview Prep** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Prepare model answers for the top 20 Compute Engine and Linux interview questions, leveraging your 6 years of Linux experience to give authoritative, experience-backed responses.

---

## Part 1 — Concept: Compute & Linux Interview Strategy (30 min)

### Your Advantage

With 6 years of Linux administration, you have **real-world depth** most cloud certification holders lack. The key is to **bridge your on-prem knowledge to GCP context** in every answer.

**Framework for answering:** `On-prem experience → GCP equivalent → How I'd handle it`

### Top 20 Compute + Linux Interview Questions

| # | Question | Category | Difficulty |
|---|---|---|---|
| 1 | How do you choose the right VM machine type? | Compute | Medium |
| 2 | Explain the difference between preemptible, spot, and on-demand VMs | Compute | Easy |
| 3 | How would you troubleshoot a VM that won't start? | Compute | Medium |
| 4 | What's the difference between a boot disk and an attached disk? | Compute | Easy |
| 5 | How do you SSH into a VM with no external IP? | Networking/Compute | Medium |
| 6 | Explain OS Login vs metadata-based SSH keys | Security | Medium |
| 7 | What is a managed instance group and when would you use one? | Compute | Medium |
| 8 | How do you handle VM patching at scale? | Operations | Hard |
| 9 | A VM is running but has high CPU. How do you diagnose? | Linux/Troubleshooting | Medium |
| 10 | How do you check if a disk is full on Linux? | Linux | Easy |
| 11 | Explain the Linux boot process | Linux | Hard |
| 12 | How would you harden a Linux VM in GCP? | Security | Hard |
| 13 | What's the difference between systemd and init? | Linux | Medium |
| 14 | How do you manage processes on Linux? | Linux | Easy |
| 15 | Explain startup scripts in GCP | Compute | Medium |
| 16 | How do you migrate on-prem VMs to GCP? | Migration | Hard |
| 17 | What are custom images and when would you use them? | Compute | Medium |
| 18 | How do you set up a VM for production workloads? | Architecture | Hard |
| 19 | Explain sole-tenant nodes | Compute | Medium |
| 20 | How do you troubleshoot network connectivity from a VM? | Networking | Hard |

### Model Answer Framework

For every technical question, structure your answer in 3 layers:

```
Layer 1: Direct Answer (10-15 seconds)
"The answer is X. Specifically..."

Layer 2: Detail/How (30-45 seconds)
"In practice, this means... The steps are..."

Layer 3: Experience/Context (15-30 seconds)
"In my experience managing 200+ Linux servers, I found that..."
```

### Model Answers — Key Questions

**Q1: How do you choose the right VM machine type?**

> "I start with the workload requirements — CPU, memory, and disk I/O profile. GCP offers general-purpose (E2, N2), compute-optimised (C2), and memory-optimised (M2) families. For most web servers and applications, E2 or N2 covers the need. For CPU-intensive work like data processing, C2 is better.
>
> In practice, I'd start with an E2-medium for testing, monitor with Cloud Monitoring to see actual usage, then right-size. From my Linux admin background, I know that capacity planning is iterative — you provision based on estimates, then adjust based on real data. GCP's recommender engine also suggests right-sizing after a few days of usage data."

**Q9: A VM is running but has high CPU. How do you diagnose?**

> "First, I'd SSH in and run `top` or `htop` to identify which process is consuming CPU. Then I'd check:
> 1. `ps aux --sort=-%cpu | head -20` — top CPU consumers
> 2. `dmesg` — kernel messages for hardware/driver issues
> 3. `journalctl -xe` — recent systemd logs
> 4. For cloud-specific: check Cloud Monitoring metrics for historical CPU trends — is this a spike or sustained?
>
> Common causes I've seen in 6 years: runaway logging, zombie processes, misconfigured cron jobs running concurrently, or memory pressure causing swap thrashing which manifests as high CPU wait. On GCP specifically, also check if the Ops Agent itself is consuming resources due to misconfigured collection intervals."

**Q12: How would you harden a Linux VM in GCP?**

> "I'd apply both OS-level and GCP-level hardening:
>
> **GCP level:** Use OS Login instead of metadata SSH keys, apply IAP for SSH access (no external IP needed), use Shielded VM features (Secure Boot, vTPM), apply a restrictive firewall with deny-all default, use a service account with minimum necessary roles.
>
> **OS level:** Disable root login, enforce SSH key-only auth, disable password auth, configure fail2ban, enable SELinux/AppArmor, remove unnecessary packages, set up unattended security updates, configure audit logging with auditd, restrict file permissions.
>
> From my experience hardening 200+ RHEL servers, the most overlooked item is audit logging — you need to know what happened when something goes wrong. I'd export these to Cloud Logging for centralised analysis."

---

## Part 2 — Hands-On Activity: Practice Answers (60 min)

### Exercise 1 — Write Model Answers for 10 Questions (40 min)

Pick 10 questions from the list that are most likely for your target roles. Write model answers using the 3-layer framework. Allocate 4 minutes per question.

For each answer, ensure you:
- [ ] Give a direct answer in the first sentence
- [ ] Include specific commands, services, or steps
- [ ] Reference your Linux experience where relevant
- [ ] Bridge to GCP context
- [ ] Keep total speaking time under 90 seconds

**High-priority questions to answer first:**

1. Q1 (VM sizing) — asked in almost every cloud interview
2. Q5 (SSH with no external IP) — tests networking + security awareness
3. Q9 (high CPU diagnosis) — your Linux expertise shines here
4. Q12 (VM hardening) — combines OS and cloud knowledge
5. Q8 (patching at scale) — operational maturity question

### Exercise 2 — Practice Aloud (15 min)

Pick your 3 strongest answers and practice them aloud:

1. Set a timer for 90 seconds
2. Answer as if in an interview — no reading
3. Record yourself (phone voice memo)
4. Listen back — are you concise? Confident? Specific?
5. Note any areas where you rambled or hesitated

**Common mistakes to avoid:**
- Starting with "Um, so basically..." — start with the direct answer
- Giving a 3-minute answer — keep to 60-90 seconds
- Being too theoretical — always include practical examples
- Forgetting to mention your experience — this is your differentiator

### Exercise 3 — Gap Analysis (5 min)

Review all 20 questions. For any you **can't answer confidently**, mark them and note what you need to review:

| Question # | Confidence (1-5) | What to Review |
|---|---|---|
| | | |
| | | |
| | | |

Spend your next study session focused on the lowest-confidence topics.

---

## Part 3 — Revision: Key Takeaways (15 min)

- **Answer framework:** Direct answer → Detail/How → Experience/Context (60-90 seconds total)
- **Bridge on-prem to cloud** in every answer: "In my Linux experience... In GCP, this translates to..."
- **High CPU diagnosis:** `top`, `ps aux`, `dmesg`, `journalctl`, Cloud Monitoring history
- **SSH without external IP:** IAP tunnel (`--tunnel-through-iap`) — always mention this
- **VM hardening = GCP level + OS level** — don't forget IAP, Shielded VM, OS Login
- **Machine type selection:** Start with E2, monitor with Cloud Monitoring, right-size based on data
- **Patching at scale:** OS Patch Management, maintenance windows, staged rollouts
- **Custom images:** Golden images with hardening + agents pre-installed — faster provisioning
- **Your 6 years of Linux experience is your superpower** — reference it in every answer
- **Practice aloud** — reading answers and speaking them are completely different skills

---

## Part 4 — Quiz (15 min)

**Q1.** An interviewer asks: "How would you SSH into a GCP VM that has no external IP address?" Give your answer.

<details><summary>Answer</summary>

"I'd use **Identity-Aware Proxy (IAP) tunnelling**. The command is:

```bash
gcloud compute ssh vm-name --zone=europe-west2-a --tunnel-through-iap
```

This works because IAP creates an authenticated tunnel from your workstation to the VM through Google's infrastructure — no external IP or VPN needed. The VM needs a firewall rule allowing TCP port 22 from the IAP IP range `35.235.240.0/20`.

This is actually more secure than using external IPs because: (1) no public attack surface, (2) IAP enforces identity-based access (tied to IAM), (3) all sessions are logged in Cloud Audit Logs. In my Linux admin background, we used bastion hosts for similar isolation — IAP is the cloud-native replacement that eliminates managing bastion infrastructure entirely."
</details>

**Q2.** "A VM is running but application logs show 'disk full' errors. Walk me through your troubleshooting." What's your answer?

<details><summary>Answer</summary>

"First, I'd SSH into the VM and check disk usage:

```bash
df -h                    # Overall disk usage per filesystem
du -sh /* 2>/dev/null    # Which directories are consuming space
du -sh /var/log/*        # Logs are the most common culprit
```

Common causes I've seen in 6 years of Linux admin:
1. **Log rotation not configured** — application or system logs growing unbounded
2. **Deleted files held open** — `lsof +L1` shows files deleted but still held by a process
3. **Temp files accumulating** — `/tmp` or application temp dirs not cleaned
4. **Core dumps** — check for large core files
5. **Docker/container images** — if running containers, `docker system prune`

**Immediate fix:** Identify and remove the largest unnecessary files, or truncate logs:
```bash
# Find files over 100MB
find / -type f -size +100M -exec ls -lh {} \;
# Truncate a log without deleting the file (safe for open file handles)
> /var/log/large-file.log
```

**Long-term fix:** Set up log rotation (`logrotate`), configure Cloud Monitoring disk alerts at 80% threshold, consider resizing the boot disk or attaching additional persistent disk. On GCP, you can resize a disk without downtime: `gcloud compute disks resize`."
</details>

**Q3.** "What's the difference between preemptible/spot VMs and on-demand VMs? When would you use each?"

<details><summary>Answer</summary>

"**On-demand VMs** run until you stop them — guaranteed availability, full price. Use for production workloads, databases, anything requiring uptime SLAs.

**Preemptible/Spot VMs** are 60-91% cheaper but GCP can terminate them with 30 seconds notice, and they're automatically deleted after 24 hours (preemptible) or at any time (spot). Use for:
- Batch processing jobs that can be restarted
- CI/CD build runners
- Data processing pipelines with checkpointing
- Non-critical development/testing

In practice, the workload must be **fault-tolerant and restartable**. I'd use managed instance groups with spot VMs and configure a shutdown script to save state. From my Linux background, this is similar to designing batch jobs that checkpoint progress — if the process dies, it resumes from the last checkpoint, not from zero.

Spot VMs replaced preemptible VMs and have the same pricing model without the 24-hour limit, but with the same no-guarantee of availability."
</details>

**Q4.** "How would you set up a VM for a production workload on GCP? Walk me through your checklist."

<details><summary>Answer</summary>

"My production VM checklist, drawing from 6 years of production Linux management:

**1. Compute:**
- Right-sized machine type (E2/N2 based on workload profiling)
- Non-preemptible (on-demand) for availability
- Automatic restart enabled, host maintenance set to migrate

**2. Storage:**
- SSD persistent disk for performance-sensitive workloads
- Separate data disk from boot disk (easier backups, resizing)
- Snapshot schedule configured for backup

**3. Networking:**
- No external IP (use IAP or load balancer for access)
- Placed in a private subnet with Cloud NAT for egress
- Targeted firewall rules (not default-allow)

**4. Security:**
- Shielded VM (Secure Boot, vTPM, integrity monitoring)
- OS Login enabled (no metadata SSH keys)
- Dedicated service account with minimum roles (not default compute SA)
- CIS-hardened OS image

**5. Monitoring:**
- Ops Agent installed for CPU, memory, disk, network metrics
- Alerting policies for CPU >80%, disk >85%, memory >90%
- Uptime check configured

**6. Operations:**
- Startup script for consistent configuration
- Labels for cost allocation and environment tagging
- Defined in Terraform for reproducibility

This checklist is essentially what I did on-prem but mapped to GCP services — the production principles are the same."
</details>
