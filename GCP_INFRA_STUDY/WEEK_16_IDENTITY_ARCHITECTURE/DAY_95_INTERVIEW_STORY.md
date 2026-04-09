# Day 95 — Interview Story: RHDS Experience Mapped to Cloud Identity

> **Week 16 — Identity Architecture** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 The STAR Method for Technical Interviews

```
  STAR METHOD — STRUCTURE YOUR ANSWERS
  ═════════════════════════════════════

  ┌─────────────────────────────────────────────────┐
  │  S — SITUATION                                   │
  │  "In my role as Linux/LDAP admin at..."          │
  │  Context: what was the environment?              │
  │  Scale: how many users, servers, replicas?       │
  ├─────────────────────────────────────────────────┤
  │  T — TASK                                        │
  │  "I was responsible for..."                      │
  │  What was the challenge or requirement?          │
  │  What were the constraints?                      │
  ├─────────────────────────────────────────────────┤
  │  A — ACTION                                      │
  │  "I designed and implemented..."                 │
  │  What specifically did YOU do?                   │
  │  Technical details: tools, commands, decisions   │
  ├─────────────────────────────────────────────────┤
  │  R — RESULT                                      │
  │  "This resulted in..."                           │
  │  Measurable outcomes: uptime, time saved,        │
  │  security posture improved                       │
  └─────────────────────────────────────────────────┘
```

### 1.2 Your RHDS Stories → Cloud Relevance

| RHDS Experience | Cloud Interview Topic | How to Frame It |
|----------------|----------------------|-----------------|
| Managing RHDS multi-master replication | High Availability / DR | "I understand HA at the identity layer" |
| Writing ACIs for access control | IAM / least privilege | "I've done fine-grained access control" |
| TLS certificate management for LDAPS | Encryption / PKI | "I manage certificate lifecycle" |
| RHDS performance tuning (indexes/cache) | Cloud optimization | "I tune systems for scale" |
| Password policy implementation | Security compliance | "I implement authentication policies" |
| JML process (ldapadd/modify/delete) | Identity lifecycle | "I automate identity management" |
| Troubleshooting replication conflicts | Distributed systems | "I debug distributed state issues" |
| LDAP schema extensions | Data modeling | "I design identity schemas" |

### 1.3 STAR Story 1: Access Control Migration

```
  STORY 1: MIGRATING FROM OPEN ACIS TO LEAST PRIVILEGE
  ════════════════════════════════════════════════════

  SITUATION:
  ┌─────────────────────────────────────────────────────────┐
  │ Our RHDS directory served 3,000 users across 5 OUs.     │
  │ Over 3 years, ACIs had accumulated — some granting      │
  │ (targetattr="*")(allow all) to broad groups.            │
  │ Security audit flagged 47 over-permissive ACIs.         │
  └─────────────────────────────────────────────────────────┘

  TASK:
  ┌─────────────────────────────────────────────────────────┐
  │ Reduce ACI scope without breaking 12 applications       │
  │ that depended on LDAP reads/writes.                     │
  │ Timeline: 8 weeks. No downtime allowed.                 │
  └─────────────────────────────────────────────────────────┘

  ACTION:
  ┌─────────────────────────────────────────────────────────┐
  │ 1. Exported all ACIs: ldapsearch "(aci=*)" aci          │
  │ 2. Mapped each ACI to its dependent application          │
  │ 3. Used access log analysis to find actual attributes    │
  │    each app needed (grep + awk on access-log)            │
  │ 4. Wrote narrowed ACIs: (targetattr="cn||sn||mail")     │
  │    instead of (targetattr="*")                           │
  │ 5. Tested on replica first, then promoted to production  │
  │ 6. Monitored for "insufficient access rights" errors     │
  └─────────────────────────────────────────────────────────┘

  RESULT:
  ┌─────────────────────────────────────────────────────────┐
  │ • Reduced over-permissive ACIs from 47 to 0             │
  │ • Zero application outages during migration              │
  │ • Passed security audit                                  │
  │ • Documented ACI review process for future use           │
  └─────────────────────────────────────────────────────────┘

  CLOUD MAPPING:
  ACI audit → IAM Recommender
  (targetattr="*") → roles/editor (over-permissive)
  Narrowed ACIs → specific predefined roles
  Access log analysis → Cloud Audit Log analysis
  Test on replica → test in dev project, promote to prod
```

### 1.4 STAR Story 2: Identity Automation

```
  STORY 2: AUTOMATING THE JML (JOINER-MOVER-LEAVER) PROCESS
  ═════════════════════════════════════════════════════════

  SITUATION:
  ┌─────────────────────────────────────────────────────────┐
  │ HR submitted user changes via email. IT team manually    │
  │ ran ldapadd/ldapmodify. Average turnaround: 2 days.     │
  │ 15% of leavers had active accounts 30+ days after exit. │
  └─────────────────────────────────────────────────────────┘

  TASK:
  ┌─────────────────────────────────────────────────────────┐
  │ Automate JML to reduce turnaround to <4 hours.          │
  │ Ensure 100% leaver account disable on exit date.        │
  └─────────────────────────────────────────────────────────┘

  ACTION:
  ┌─────────────────────────────────────────────────────────┐
  │ 1. Built CSV export from HR system (daily at 6 AM)      │
  │ 2. Wrote Python script to:                              │
  │    - Parse CSV for new/changed/terminated records        │
  │    - Generate LDIF for each change                       │
  │    - Apply via ldapmodify with error handling             │
  │ 3. Joiner: auto-generate uid, set passwordPolicy,       │
  │    add to department group                               │
  │ 4. Leaver: nsAccountLock=true, remove from all groups,  │
  │    schedule ldapdelete after 30 days                     │
  │ 5. Added logging and email notifications                 │
  └─────────────────────────────────────────────────────────┘

  RESULT:
  ┌─────────────────────────────────────────────────────────┐
  │ • Turnaround: 2 days → 4 hours (same-day processing)   │
  │ • Stale leaver accounts: 15% → 0%                      │
  │ • Saved IT team ~8 hours/week of manual work            │
  │ • Zero errors in 6 months (vs ~5/month manual)          │
  └─────────────────────────────────────────────────────────┘

  CLOUD MAPPING:
  CSV export → HR webhook to Pub/Sub
  Python script → Cloud Function
  ldapmodify → Cloud Identity Admin SDK + IAM API
  nsAccountLock → suspend user / disable SA
  Cron schedule → Cloud Scheduler
  Email notifications → Slack/email via notification channels
```

### 1.5 STAR Story 3: High Availability

```
  STORY 3: RHDS MULTI-MASTER REPLICATION FOR HA
  ═══════════════════════════════════════════════

  SITUATION:
  ┌─────────────────────────────────────────────────────────┐
  │ Single RHDS instance serving authentication for 3,000   │
  │ users. Annual downtime: ~6 hours (patching, crashes).   │
  │ Each hour of LDAP downtime = no SSH, no app logins.     │
  └─────────────────────────────────────────────────────────┘

  TASK:
  ┌─────────────────────────────────────────────────────────┐
  │ Design and implement HA for RHDS. Target: 99.9% uptime. │
  └─────────────────────────────────────────────────────────┘

  ACTION:
  ┌─────────────────────────────────────────────────────────┐
  │ 1. Deployed 2 additional RHDS instances (3 total)        │
  │ 2. Configured multi-master replication agreements:       │
  │    - TLS between all replicas (port 636)                 │
  │    - nsDS5ReplicaChangelogMaxAge: 7d                     │
  │    - nsDS5ReplicaReleaseTimeout: 60s                     │
  │ 3. Set up HAProxy for LDAP load balancing:               │
  │    - Health check: ldapsearch base="" "(objectclass=*)"  │
  │    - Failover: 3s timeout, 2 retries                     │
  │ 4. Updated all clients: point to HAProxy VIP             │
  │ 5. Tested: kill one node → verify automatic failover     │
  └─────────────────────────────────────────────────────────┘

  RESULT:
  ┌─────────────────────────────────────────────────────────┐
  │ • Uptime: improved from ~99.93% to 99.99%               │
  │ • Zero-downtime patching (rolling updates)               │
  │ • Replication lag: <2 seconds between nodes              │
  │ • Successfully survived a DC power outage                │
  └─────────────────────────────────────────────────────────┘

  CLOUD MAPPING:
  Multi-master RHDS → Cloud Identity is globally distributed (managed HA)
  HAProxy LDAP LB → Cloud Load Balancer
  Replication agreements → GCP handles this transparently
  Rolling updates → managed service, no patching needed
  DC failover → multi-region by default
  Key insight: "I understand WHY HA matters, even though
  Cloud Identity provides it as a managed service."
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab 2.1 — Practice STAR Story Delivery

```bash
echo "=== INTERVIEW PRACTICE EXERCISE ==="
echo ""
echo "Practice these responses OUT LOUD (not just reading)."
echo "Time yourself: each STAR story should take 2-3 minutes."
echo ""

cat << 'EXERCISE'
EXERCISE 1: "Tell me about a time you implemented least privilege access."
───────────────────────────────────────────────────────────────────────────
Use STAR Story 1 (ACI Migration). Key phrases:
- "I audited all ACIs in our RHDS directory..."
- "This is directly analogous to reviewing IAM bindings in GCP..."
- "Just like using IAM Recommender to right-size roles..."
- "I used access log analysis, which maps to Cloud Audit Log analysis..."

EXERCISE 2: "How would you automate identity management in the cloud?"
───────────────────────────────────────────────────────────────────────────
Use STAR Story 2 (JML Automation). Key phrases:
- "I've automated identity lifecycle in RHDS..."
- "The same pattern applies to cloud: event-driven architecture..."
- "HR event → Pub/Sub → Cloud Function → Cloud Identity API..."
- "I reduced stale accounts from 15% to zero..."

EXERCISE 3: "What's your experience with high-availability systems?"
───────────────────────────────────────────────────────────────────────────
Use STAR Story 3 (RHDS HA). Key phrases:
- "I designed and implemented multi-master RHDS replication..."
- "This gives me deep understanding of distributed identity systems..."
- "In GCP, Cloud Identity provides this as a managed service..."
- "My experience means I understand the failure modes even when managed..."

EXERCISE 4: "Why are you transitioning from Linux infra to cloud?"
───────────────────────────────────────────────────────────────────────────
Frame: "Cloud is the natural evolution of infrastructure."
- "The concepts I've mastered — identity, access control, HA,
   automation — are the SAME concepts in cloud."
- "I'm not leaving my skills behind; I'm applying them at a new scale."
- "6 years of Linux gave me the foundation. ACE certification proves
   I can translate it to GCP."
EXERCISE
```

### Lab 2.2 — Build Your Skills Translation Matrix

```bash
echo "=== YOUR SKILLS TRANSLATION MATRIX ==="
echo ""

cat << 'MATRIX'
┌──────────────────────────────────────────────────────────────────────┐
│ YOUR EXPERIENCE                 │ GCP EQUIVALENT            │ LEVEL │
├─────────────────────────────────┼───────────────────────────┼───────┤
│ RHDS administration (3 yrs)     │ Cloud Identity admin      │ ★★★★★ │
│ LDAP ACIs                       │ IAM policies & bindings   │ ★★★★★ │
│ LDAP replication                │ Managed HA / DR           │ ★★★★☆ │
│ TLS/certificate management      │ Certificate Manager       │ ★★★★☆ │
│ Shell scripting automation      │ Cloud Functions / Bash    │ ★★★★★ │
│ Linux security (SELinux, PAM)   │ Org policies, SCC         │ ★★★★☆ │
│ iptables / firewalld            │ VPC firewall rules        │ ★★★★★ │
│ Cron job scheduling             │ Cloud Scheduler           │ ★★★★★ │
│ rsyslog / auditd                │ Cloud Logging             │ ★★★★☆ │
│ HAProxy / nginx LB              │ Cloud Load Balancing      │ ★★★☆☆ │
│ Ansible / scripted provisioning │ Terraform                 │ ★★★★☆ │
│ Nagios / Zabbix monitoring      │ Cloud Monitoring          │ ★★★★☆ │
│ Package management (yum/dnf)    │ Container Registry / AR   │ ★★★☆☆ │
│ LVM / disk management           │ Persistent Disks          │ ★★★★★ │
│ SSH key management              │ OS Login / IAP            │ ★★★★★ │
├─────────────────────────────────┼───────────────────────────┼───────┤
│ CERTIFICATION                   │                           │       │
│ ACE (Associate Cloud Engineer)  │ Validates GCP competence  │ ✓     │
└──────────────────────────────────────────────────────────────────────┘
MATRIX
```

### Lab 2.3 — Common Interview Questions + Cloud Answers

```bash
echo "=== INTERVIEW Q&A BANK ==="
echo ""

cat << 'QA'
Q: "How do you implement least privilege in GCP?"
A: "Same approach as RHDS ACIs — start broad, observe actual usage via audit
   logs, then narrow. In GCP, IAM Recommender automates this by analysing
   90 days of API usage. I've done this manually in RHDS with access-log
   analysis, so I understand both the manual and automated approaches."

Q: "How do you handle a security incident in the cloud?"
A: "Same incident response framework as on-prem:
   1. Detect (Cloud Audit Logs + alerting, like RHDS audit-log + nagios)
   2. Contain (disable SA/account, like nsAccountLock=true)
   3. Investigate (query logs in BigQuery, like grep access-log)
   4. Remediate (fix IAM, rotate credentials)
   5. Review (post-incident, update policies + alerts)"

Q: "What's the difference between authentication and authorisation?"
A: "Authentication = proving who you are (RHDS ldapbind, GCP OAuth login).
   Authorisation = what you're allowed to do (RHDS ACI, GCP IAM binding).
   In RHDS, both happen at the directory server. In GCP, authentication is
   Cloud Identity/IdP, authorisation is IAM — they're separate systems."

Q: "How would you migrate on-prem identity to GCP?"
A: "Three-phase approach:
   Phase 1: GCDS sync — read from RHDS, create Cloud Identity accounts
   Phase 2: SAML SSO — keep auth on-prem via Keycloak + RHDS
   Phase 3: Decision point — full migration to Cloud Identity or keep hybrid
   I've managed RHDS replication agreements, which is the same concept as
   one-way sync to a different directory technology."

Q: "What's your experience with Terraform for IAM?"
A: "I use google_project_iam_member for additive bindings (safe, won't
   remove existing access) and google_project_iam_binding only when I need
   authoritative control over a role. This is like managing RHDS ACIs —
   additive = adding a new ACI, authoritative = replacing all ACIs for a
   target. Getting this wrong can lock people out, so I always use
   plan + review."
QA
```

### Lab 2.4 — Build Your 60-Second Elevator Pitch

```bash
echo "=== YOUR ELEVATOR PITCH ==="
echo ""

cat << 'PITCH'
TEMPLATE (adapt to each role):
══════════════════════════════

"I'm a Linux infrastructure engineer with 6 years of experience
and 3 years specialising in Red Hat Directory Server — the identity
backbone for thousands of users.

I've built access control systems, automated identity lifecycle
management, and designed high-availability directory architectures.

I recognised that these same challenges — identity, access, security,
automation — are now solved at cloud scale. So I earned my GCP
Associate Cloud Engineer certification and have been building
hands-on projects in IAM, networking, Terraform, and monitoring.

What excites me about this role is applying my deep infrastructure
knowledge to cloud-native patterns. I don't just know HOW to
configure IAM — I understand WHY it works, because I've built
the on-prem equivalent from scratch."

KEY PHRASES TO INCLUDE:
• "identity management at scale"
• "access control and least privilege"
• "automation of security operations"
• "ACE certified"
• "infrastructure as code"
• "deep understanding of distributed systems"
PITCH
```

### Lab 2.5 — Technical Scenario Practice

```bash
echo "=== TECHNICAL SCENARIO PRACTICE ==="
echo ""

cat << 'SCENARIO'
SCENARIO: "A developer reports they can't access a GCS bucket. Walk me
through your troubleshooting process."

YOUR ANSWER (map to RHDS experience):
═══════════════════════════════════════

1. IDENTIFY THE ERROR
   "First, what's the exact error? 403 Forbidden → IAM issue.
   404 Not Found → wrong bucket name. 401 → auth issue."
   RHDS: "Is it 'insufficient access rights' (ACI) or 'invalid credentials' (bind fail)?"

2. CHECK IDENTITY
   "Who is the developer authenticating as? gcloud auth list.
   Are they using their user account or a service account?"
   RHDS: "Which bind DN are they using? Check conn= in access-log."

3. CHECK IAM BINDINGS
   "gcloud projects get-iam-policy --filter='members:user@'
   Do they have roles/storage.objectViewer or similar?"
   RHDS: "ldapsearch for ACIs targeting their group or uid."

4. CHECK RESOURCE LEVEL
   "gsutil iam get gs://bucket — maybe IAM is on the bucket, not project."
   RHDS: "ACI might be on a subtree, not the root."

5. USE POLICY TROUBLESHOOTER
   "gcloud policy-troubleshoot iam — shows exactly why access is denied."
   RHDS: "There's no equivalent — you'd manually trace ACI evaluation."

6. FIX AND VERIFY
   "Add the minimum required role. Test. Document."
   RHDS: "Add targeted ACI. Test with ldapsearch as that user. Document."
SCENARIO
```

### 🧹 Cleanup

```bash
echo "No resources created in this lab (interview preparation exercise)."
echo "No cleanup needed."
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **STAR method:** Situation, Task, Action, Result — structure every interview answer
- **Always bridge** from RHDS experience to cloud: "I did X in RHDS, which maps to Y in GCP"
- **Three prepared stories:** Least privilege (ACI audit), Automation (JML), HA (replication)
- **Skills translation:** Every Linux/RHDS skill has a GCP equivalent — know the mapping
- **Elevator pitch:** 60 seconds, covers experience + certification + motivation
- **Technical scenarios:** Same troubleshooting methodology in cloud as on-prem
- **Key message:** "I understand the fundamentals, not just the tools"

### Interview Cheat Sheet
```
Before any answer, ask yourself:
1. Can I reference my RHDS/Linux experience? (YES → mention it)
2. Can I name the GCP service/tool? (YES → name it)
3. Can I give a specific example? (YES → use STAR format)
4. Can I mention a measurable result? (YES → include numbers)

Red flags to avoid:
✗ "I don't have cloud experience" (you DO — ACE + hands-on)
✗ "I just read about it" (you've BUILT it in labs)
✗ Long-winded answers without structure (use STAR)
✗ Memorised definitions without context (always add your experience)
```

---

## Part 4 — Quiz (15 min)

**Q1.** An interviewer asks: "What's the biggest security risk in cloud IAM?" Give a STAR-formatted answer using your RHDS experience.

<details><summary>Answer</summary>

**S:** "In my RHDS environment, I discovered that 47 ACIs had `(targetattr="*")(allow all)` — essentially giving broad groups full access to all attributes."

**T:** "I needed to reduce these to least privilege without breaking 12 dependent applications."

**A:** "I analysed 30 days of LDAP access logs to identify which attributes each app actually used, rewrote ACIs to target only those attributes, tested on a replica, and rolled out incrementally."

**R:** "Reduced over-permissive ACIs to zero, no outages, passed the security audit."

**Bridge to cloud:** "The same risk exists in GCP — `roles/editor` is the cloud equivalent of `(targetattr=*)(allow all)`. I'd use IAM Recommender (automated version of my log analysis) to identify and replace Editor with specific predefined roles. The methodology is identical; GCP just has better tooling."

</details>

**Q2.** An interviewer asks: "How do you ensure 100% compliance with the leaver process?" Answer with your JML automation story.

<details><summary>Answer</summary>

**S:** "We had 15% of leavers with active RHDS accounts 30+ days after exit — a significant security risk."

**T:** "Automate the leaver process to achieve 0% stale accounts."

**A:** "Built a daily automated pipeline: HR CSV export → Python parser → LDIF generation → `ldapmodify` to set `nsAccountLock: true` and remove group memberships. Added cron job for 30-day deletion. Built monitoring to alert if the pipeline failed."

**R:** "Stale accounts: 15% → 0%. IT team saved 8 hours/week."

**Cloud equivalent:** "In GCP, the same architecture would use: HR webhook → Pub/Sub → Cloud Function → Cloud Identity Admin SDK (suspend user) + IAM API (remove all bindings) → Cloud Scheduler for delayed deletion. I'd add Cloud Monitoring alerts if the function fails. The pattern is identical — event-driven automation with fail-safe monitoring."

</details>

**Q3.** An interviewer asks: "Why should we hire someone from an on-prem LDAP background for a cloud role?"

<details><summary>Answer</summary>

"Three reasons:

1. **Deep fundamentals:** I understand identity, authentication, authorisation, and access control at the protocol level — not just clicking buttons in a console. When something breaks in Cloud IAM, I can reason about WHY because I've built the equivalent from scratch.

2. **Security mindset:** 3 years of managing ACIs, password policies, and replication security means I think about access control by default. I audited 47 over-permissive ACIs and reduced them to zero — that same discipline applies to IAM bindings.

3. **Automation culture:** I automated the JML lifecycle from 2-day manual turnaround to 4-hour automated processing. Cloud infrastructure demands automation — I already think this way.

Plus, I have my ACE certification, which validates I can translate these skills to GCP. I'm not learning from zero; I'm applying 6 years of infrastructure experience to a new platform."

</details>

**Q4.** Practice the 60-second elevator pitch. Time yourself and say it out loud.

<details><summary>Answer</summary>

**Scoring rubric (self-assess):**

| Criteria | Points |
|---------|--------|
| Under 60 seconds? | /10 |
| Mentioned years of experience? | /10 |
| Mentioned RHDS/LDAP specifically? | /10 |
| Named a concrete achievement? | /10 |
| Mentioned ACE certification? | /10 |
| Connected on-prem to cloud? | /10 |
| Expressed enthusiasm for the role? | /10 |
| Spoke clearly without filler words? | /10 |
| Made eye contact (practice with mirror)? | /10 |
| Ended with a forward-looking statement? | /10 |

**Target: 80+/100.** Practice 5 times until it sounds natural, not rehearsed.

</details>
