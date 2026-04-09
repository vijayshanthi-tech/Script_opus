# Day 46 — Rebuild From Scratch (Timebox)

> **Week 8 — Portfolio & Review** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### Why Rebuild From Scratch?

Rebuilding from memory is the **ultimate test** of understanding. Following a tutorial vs building from memory are completely different skill levels.

```
┌──────────────────────────────────────────────────────────┐
│          The Competence Ladder                            │
│                                                          │
│  Level 1: FOLLOW                                         │
│  "I can build it following the guide step by step"       │
│  → Copy-paste gcloud commands from tutorial               │
│                                                          │
│  Level 2: ADAPT                                          │
│  "I can modify the guide for my needs"                   │
│  → Change region, machine type, add a firewall rule      │
│                                                          │
│  Level 3: RECALL                                         │
│  "I can build it from memory with occasional lookups"    │
│  → Remember the architecture, look up syntax              │
│                                                          │
│  Level 4: TEACH                                          │
│  "I can explain it to someone else and help them build"  │
│  → Interview answer quality, blog post quality            │
│                                                          │
│  Today's goal: Reach Level 3                             │
└──────────────────────────────────────────────────────────┘
```

**Linux analogy:** You can set up a LAMP stack from memory because you've done it 100 times. Today you prove you can do the same with a GCP VPC + VM + monitoring stack.

### The Rebuild Process

```
┌──────────────────────────────────────────────────────────┐
│              Rebuild Process                              │
│                                                          │
│  BEFORE (5 min):                                         │
│  ├── Choose the project to rebuild                       │
│  ├── Close all notes and tutorials                       │
│  ├── Open only: gcloud CLI + editor + timer              │
│  └── Allowed: gcloud --help, terraform docs              │
│                                                          │
│  DURING (60 min):                                        │
│  ├── Start timer                                         │
│  ├── Build from memory                                   │
│  ├── Note gaps: "I had to look this up"                  │
│  ├── Don't look at previous solutions                    │
│  └── Stop at 60 min regardless of completion             │
│                                                          │
│  AFTER (15 min):                                         │
│  ├── Compare with original solution                      │
│  ├── Note what you forgot                                │
│  ├── Note what you got right                             │
│  └── Create a "gaps" list for focused review             │
│                                                          │
│  KEY RULE: It's OK to not finish!                        │
│  The value is in discovering your gaps.                  │
└──────────────────────────────────────────────────────────┘
```

### What to Rebuild

Choose ONE project based on your target role:

| Project | From | Best If Targeting |
|---|---|---|
| **Secure VPC** | Week 2 | Network/security roles |
| **Monitoring Pack** | Week 3 | SRE/DevOps roles |
| **Terraform Landing Zone** | Week 5 | Cloud/Platform engineer roles |
| **Backup & Restore** | Week 6 | Infrastructure/ops roles |
| **Golden VM** | Week 7 | Automation/DevOps roles |

---

## Part 2 — Hands-On Lab (60 min)

### Instructions

1. Close all study notes
2. Set a timer for 60 minutes
3. Only use: `gcloud --help`, `terraform docs`, `man` pages
4. Note every time you get stuck

### Rebuild Option A: Secure VPC Project

**Goal from memory:** Build a VPC with a subnet, firewall rules (SSH via IAP, HTTP), Cloud NAT, and deploy a VM that can reach the internet but has no public IP.

**Architecture to build from memory:**

```
Internet → Cloud NAT (egress only)
                ↓
VPC: rebuild-vpc (europe-west2)
  Subnet: rebuild-subnet (10.0.1.0/24)
    VM: rebuild-web (no public IP, tags: ssh, http-server)
  
Firewall:
  - allow-ssh-iap: tcp/22 from 35.235.240.0/20 → tag:ssh
  - allow-http: tcp/80 from 0.0.0.0/0 → tag:http-server
  - (implicit deny all)

NAT:
  Cloud Router → Cloud NAT → subnet
```

**Start building! (Timer: 60 minutes)**

```bash
# ── YOUR WORKSPACE ──
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=europe-west2-a
export REGION=europe-west2

# ── STEP 1: VPC + Subnet ──
# Build from memory...

# ── STEP 2: Firewall Rules ──
# Build from memory...

# ── STEP 3: Cloud Router + NAT ──
# Build from memory...

# ── STEP 4: VM (no public IP) ──
# Build from memory...

# ── STEP 5: Verify ──
# SSH via IAP, test internet access, test HTTP
```

### Rebuild Option B: Golden VM with Monitoring

**Goal from memory:** Create a VM with a startup script that installs packages, hardens SSH, sets up monitoring via cron, and configures log rotation.

**Architecture to build from memory:**

```
GCS Bucket → startup-script-url → VM
  
VM setup:
  - Packages: nginx, fail2ban, htop, curl
  - SSH: PermitRootLogin no, PasswordAuth no
  - Kernel: ip_forward 0, syncookies 1
  - Monitoring: script in /opt/, cron every 5 min
  - Log rotation: logrotate config for custom logs
```

**Start building! (Timer: 60 minutes)**

```bash
# ── YOUR WORKSPACE ──
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=europe-west2-a
export REGION=europe-west2

# ── STEP 1: Write startup script from memory ──
# Build from memory...

# ── STEP 2: Upload to GCS ──
# Build from memory...

# ── STEP 3: Create VM with startup-script-url ──
# Build from memory...

# ── STEP 4: Verify all components ──
# SSH in, check services, check hardening, check cron
```

### Gap Tracking Template

As you build, fill this in:

```
REBUILD GAP TRACKER
Project: _______________
Date:    _______________
Time:    _____ / 60 min

COMPLETED (from memory):
  [ ] ______________________
  [ ] ______________________
  [ ] ______________________
  [ ] ______________________
  [ ] ______________________

HAD TO LOOK UP:
  - ___________________________ (where I found it: _______)
  - ___________________________ (where I found it: _______)
  - ___________________________ (where I found it: _______)

FORGOT ENTIRELY:
  - ___________________________
  - ___________________________

DID NOT REACH:
  - ___________________________
  - ___________________________

CONFIDENCE RATING: __ / 10

PRIORITY REVIEW TOPICS:
  1. ___________________________
  2. ___________________________
  3. ___________________________
```

---

### After The Timer (15 min)

### Compare with Original

Go back to your original solution and check:

```
COMPARISON CHECKLIST:

ARCHITECTURE:
  [ ] Same components? (VPC, subnet, firewall, NAT/VM...)
  [ ] Anything you added that wasn't needed?
  [ ] Anything you missed?

COMMANDS:
  [ ] gcloud commands correct?
  [ ] Flags correct? (--zone, --region, --network)
  [ ] Resource names follow convention?

SECURITY:
  [ ] All hardening applied?
  [ ] Firewall rules complete?
  [ ] IAM/scopes correct?

OPERATIONAL:
  [ ] Monitoring set up?
  [ ] Backup/snapshots configured?
  [ ] Cleanup commands ready?
```

---

## Part 3 — Revision (15 min)

### The Rebuild Technique

- **Timeboxing** prevents perfectionism — 60 min max, then review
- **Gap tracking** identifies exactly what to study next
- **No notes rule** tests real recall, not search-and-copy skills
- **Comparison** after the build shows blind spots objectively
- Do this exercise again in 2 weeks — you'll see dramatic improvement

### Common Gaps (What Most People Forget)

```
TOP 10 FORGOTTEN ITEMS:
1. IAP source range for SSH (35.235.240.0/20)
2. Cloud NAT requires a Cloud Router first
3. VM scopes for GCS/monitoring access
4. startup-script-url (not startup-script-URL)
5. sysctl -p to apply kernel params
6. chmod 644 for cron.d files
7. --tunnel-through-iap flag for SSH
8. gsutil mb requires -b on for uniform access
9. Snapshot schedule requires resource policy + attach
10. logrotate delaycompress purpose
```

### Study Priority After Rebuild

| Gap Type | Action |
|---|---|
| Forgot the concept | Re-read the day's concept section |
| Remembered concept, forgot syntax | Practice the commands 3 times |
| Never reached it (time ran out) | Wasn't priority — review if time allows |
| Got it wrong | Re-do that specific step from the original solution |

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: You're rebuilding a VPC from scratch and you can't remember the IAP source range for the SSH firewall rule. What's your strategy?</strong></summary>

**Answer:** This is exactly the kind of detail to look up rather than memorize:

```bash
# Quick lookup method:
gcloud compute firewall-rules list \
  --filter="name~iap" \
  --format="table(name,sourceRanges)"

# Or check documentation:
# IAP source range: 35.235.240.0/20
```

**The important thing is knowing:**
1. SSH should go through IAP (not direct public access)
2. IAP uses specific source IP ranges for the tunnel
3. Where to find the range: GCP docs → IAP → TCP forwarding

**Memorize the concept (IAP for SSH), look up the number (35.235.240.0/20).**
</details>

<details>
<summary><strong>Q2: During the rebuild, you realised you forgot to create a Cloud Router before Cloud NAT. Why can't NAT work without a router?</strong></summary>

**Answer:** Cloud NAT is a **configuration on a Cloud Router**, not a standalone service. The architecture is:

```
VPC → Cloud Router → Cloud NAT config → handles NAT for subnet
```

**Why a router?**
- Cloud Router manages BGP sessions and routing advertisements
- Cloud NAT is implemented as a NAT gateway function ON the router
- The router knows which subnets and IP ranges to NAT
- Without the router, there's no control plane to process NAT rules

**Analogy:** On Linux, you need `iptables` (the framework) before you can add NAT rules. Cloud Router is the framework; Cloud NAT is the NAT rule set.

```bash
# Correct order:
gcloud compute routers create ROUTER --region=REGION --network=VPC
gcloud compute routers nats create NAT --router=ROUTER --region=REGION \
  --auto-allocate-nat-external-ips --nat-all-subnet-ip-ranges
```
</details>

<details>
<summary><strong>Q3: Your rebuilt VM can't download the startup script from GCS. What did you probably forget?</strong></summary>

**Answer:** Most likely forgot the **VM scopes** or **IAM permissions:**

1. **Scopes:** The VM needs `--scopes=storage-ro` (or `cloud-platform`) to access GCS
   ```bash
   gcloud compute instances create VM --scopes=storage-ro ...
   ```

2. **Service account:** The VM's default SA needs `roles/storage.objectViewer` on the bucket
   ```bash
   gsutil iam ch serviceAccount:SA@PROJECT.iam.gserviceaccount.com:objectViewer gs://BUCKET
   ```

3. **Bucket exists and script is in it:**
   ```bash
   gsutil ls gs://BUCKET/startup.sh  # Verify
   ```

4. **Metadata key is correct:** Must be `startup-script-url` (not `startup-script-URL` or `startupScript`)

**Quick debug:**
```bash
gcloud compute instances get-serial-port-output VM --zone=ZONE | grep -i "startup\|download\|error"
```
</details>

<details>
<summary><strong>Q4: After rebuilding, you compare your solution with the original and notice you forgot log rotation entirely. How do you prioritise this gap?</strong></summary>

**Answer:** Rate the gap on two axes:

| Axis | Log Rotation |
|---|---|
| **Interview likelihood** | Medium — might come up in "how do you manage a fleet?" |
| **Production importance** | HIGH — missing log rotation = disk fills = outage |

**Priority: Study this week.** Even though it's not the most interview-glamorous topic, log rotation is:
1. A fundamental ops skill (validates your 6 years of Linux experience)
2. Easy to forget because it's "boring" admin work
3. The kind of thing that separates "I can build" from "I can operate"

**Action:** Practice writing a logrotate config from memory:
```
/var/log/myapp/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```
Repeat until you can write it without looking. Should take 3 repetitions.
</details>
