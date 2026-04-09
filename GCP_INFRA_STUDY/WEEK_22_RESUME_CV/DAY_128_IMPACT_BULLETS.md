# Day 128 — Impact Bullets with Metrics

> **Week 22 · Resume & CV** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Transform job duty descriptions into impact-driven bullet points with quantified results using the STAR-lite format, and translate Linux admin experience into cloud-relevant achievements.

---

## Part 1 — Concept: Writing Impact Bullets (30 min)

### Why Metrics Matter on a Resume

Hiring managers see hundreds of resumes saying "managed servers" and "configured networks." What makes yours different? **Numbers.** A bullet with a metric gets 40% more attention than a duty description.

| Duty Description (Weak) | Impact Bullet (Strong) |
|---|---|
| Managed Linux servers | Managed 200+ RHEL 7/8 production servers across 3 datacentres, maintaining 99.9% uptime over 4 years |
| Configured user accounts | Provisioned and managed RHDS/LDAP directory serving 5,000+ users with automated group policy enforcement |
| Wrote scripts | Automated server provisioning with Bash scripts, reducing build time from 4 hours to 30 minutes (87% reduction) |
| Resolved incidents | Led resolution of P1 incidents affecting 10,000+ users, achieving average MTTR of 45 minutes |
| Set up monitoring | Implemented Nagios monitoring across 200+ servers, reducing undetected outages by 70% |
| Did patching | Orchestrated monthly patching cycles for 200+ servers with zero unplanned downtime over 18 months |

### The STAR-Lite Format for Resume Bullets

Full STAR is for interviews. For resume bullets, use **STAR-Lite**:

```
[Action Verb] + [What You Did] + [Scale/Scope] + [Result/Impact]
```

| Component | What It Is | Example |
|---|---|---|
| **Action Verb** | Strong, specific verb | Automated, Architected, Reduced, Led |
| **What** | The specific thing you did | Server provisioning, monitoring setup, LDAP migration |
| **Scale** | Numbers showing scope | 200+ servers, 5K users, 3 datacentres |
| **Result** | Quantified impact | 87% time reduction, 99.9% uptime, £50K saved |

### Types of Metrics to Use

| Metric Type | Examples | How to Estimate |
|---|---|---|
| **Volume/Scale** | 200+ servers, 5,000 users, 50 VMs | Count what you managed |
| **Time Saved** | 4hrs → 30min (87% reduction) | Compare manual vs automated time |
| **Uptime/Reliability** | 99.9% uptime, zero downtime | Check SLA reports or estimate |
| **Speed** | MTTR 45min, deployment in 5min | Time your incident resolution |
| **Cost** | £50K annual savings, 30% cost reduction | Estimate labour/resource savings |
| **Percentage** | 70% fewer incidents, 90% automation | Before/after comparison |
| **Frequency** | Daily, monthly, per quarter | How often you did it |

### Translating Linux Admin to Cloud-Relevant Bullets

| Linux Admin Task | Cloud-Relevant Reframe |
|---|---|
| Managed physical servers | "Managed production compute infrastructure" — same skill, hardware-agnostic language |
| Configured firewalls (iptables) | "Implemented network security policies" — maps to GCP firewall rules |
| Set up LDAP | "Designed enterprise identity and access management" — maps to GCP IAM |
| Wrote cron jobs | "Automated operational tasks" — maps to Cloud Scheduler, Cloud Functions |
| Installed monitoring tools | "Implemented observability infrastructure" — maps to Cloud Monitoring |
| Did capacity planning | "Performed capacity planning and right-sizing" — direct cloud skill |
| Responded to incidents | "Led incident response and root cause analysis" — SRE skill |
| Patched servers | "Managed vulnerability remediation across production fleet" — security skill |

### Before/After Examples

**Before:** "Responsible for LDAP administration"

**After:** "Managed RHDS/LDAP directory infrastructure serving 5,000+ users across 3 organisational units, implementing automated provisioning that reduced account creation from 2 hours to 15 minutes"

**Before:** "Set up and configured new servers"

**After:** "Engineered standardised server build process using Kickstart and Bash automation, reducing provisioning time from 4 hours to 30 minutes and ensuring CIS benchmark compliance across 200+ RHEL servers"

**Before:** "Troubleshot network issues"

**After:** "Diagnosed and resolved network connectivity issues across multi-site infrastructure, reducing average resolution time by 60% through systematic debugging playbooks"

---

## Part 2 — Hands-On Activity: Write Your Bullets (60 min)

### Exercise 1 — Achievement Mining (20 min)

List every significant thing you've done in your career. Don't worry about wording yet — just capture the raw material.

**For each role you've held, answer these questions:**

| Question | Your Answer |
|---|---|
| How many servers/systems did you manage? | |
| How many users did you support? | |
| What did you automate? What was the time saving? | |
| What was the uptime/SLA you maintained? | |
| What was your biggest incident? How fast did you resolve it? | |
| What process did you improve? By how much? | |
| What did you build from scratch? | |
| What cost savings did you achieve? | |
| What tools did you implement? | |
| What did you mentor others on? | |

**GCP project achievements:**

| Project | What You Built | Metric/Outcome |
|---|---|---|
| Terraform VPC | Production-grade VPC architecture | Reusable modules, <5min deployment |
| Monitoring | Custom dashboards + alerting | <5min MTTD, 0 alert noise |
| IAM | Least privilege access design | X service accounts, Y policies |
| SRE Pack | SLO/SLI implementation | Target: 99.9% availability |

### Exercise 2 — Write 10-12 Bullet Points (25 min)

Using STAR-Lite format, write 10-12 bullet points covering:
- 4-5 bullets from your Linux admin experience (reframed for cloud relevance)
- 2-3 bullets from your RHDS/LDAP experience (reframed as IAM)
- 3-4 bullets from your GCP project work

**Template for each bullet:**
```
• [Action verb] [what you did] [covering/across/for] [scale], [resulting in/achieving] [metric]
```

**Examples to model yours after:**

```
• Architected GCP VPC network with public/private subnet segregation, Cloud NAT, and IAP 
  access using Terraform modules — deployed in europe-west2 with <5 minute provisioning

• Implemented Cloud Monitoring observability stack with custom dashboards, CPU/memory/disk 
  alerting policies, and SLO tracking for compute infrastructure

• Managed 200+ RHEL 7/8 production servers across 3 datacentres, maintaining 99.9% uptime 
  through proactive monitoring, automated patching, and capacity planning

• Designed and operated RHDS/LDAP directory infrastructure serving 5,000+ users, implementing 
  automated provisioning that reduced account setup from 2 hours to 15 minutes

• Automated server hardening using Bash scripts aligned with CIS benchmarks, achieving 
  consistent security baselines across the entire production fleet

• Led P1 incident response for infrastructure outages affecting 10,000+ users, achieving 
  average MTTR of 45 minutes with documented root cause analysis
```

### Exercise 3 — Refine and Order (15 min)

1. **Cut any bullet without a metric** — add one or remove the bullet
2. **Order by impact** — strongest achievements first within each role
3. **Check verb variety** — don't start 5 bullets with "Managed"
4. **Verify truth** — every number should be defensible in an interview
5. **Check length** — each bullet should be 1-2 lines, never 3+

| Bullet # | Has Action Verb? | Has Scale? | Has Metric? | Cloud-Relevant? |
|---|---|---|---|---|
| 1 | ☐ | ☐ | ☐ | ☐ |
| 2 | ☐ | ☐ | ☐ | ☐ |
| ... | | | | |

---

## Part 3 — Revision: Key Takeaways (15 min)

- **STAR-Lite formula:** Action Verb + What + Scale + Result/Metric
- **Every bullet needs a number** — if you can't quantify it, estimate it (then be ready to explain)
- **Translate Linux to cloud language:** "servers" → "compute infrastructure", firewall → "network security", LDAP → "identity and access management"
- **Types of metrics:** volume/scale, time saved, uptime, speed, cost, percentage improvement
- **Before/after format** is the clearest way to show impact: X → Y (Z% improvement)
- **Order bullets by impact** — strongest first within each role/section
- **Vary your action verbs** — don't start every bullet the same way
- **1-2 lines per bullet** — if it's 3 lines, split or cut
- **Every number must be defensible** — you WILL be asked about them in interviews
- **Your Linux experience IS cloud experience** — frame it as such

---

## Part 4 — Quiz (15 min)

**Q1.** Transform this duty description into an impact bullet: "Responsible for server patching and updates."

<details><summary>Answer</summary>

**Impact bullet:** "Orchestrated monthly vulnerability patching cycles across 200+ RHEL production servers, maintaining zero unplanned downtime over 18 months while achieving 100% compliance with security SLAs."

**What changed:** (1) "Responsible for" → active verb "Orchestrated", (2) Added **scale** (200+ servers), (3) Added **frequency** (monthly), (4) Added **result** (zero downtime, 100% compliance), (5) Added **duration** (18 months), (6) Reframed "patching" as "vulnerability patching cycles" — more professional and security-relevant.
</details>

**Q2.** You can't remember the exact number of servers you managed. It was "a lot — maybe 150-250." What should you put on your resume?

<details><summary>Answer</summary>

Use **"200+"** — it's within your reasonable estimate range and the "+" acknowledges it's approximate. In interviews, if asked, say "approximately 200, though it varied between 150 and 250 depending on project cycles." 

**Rules for estimating:**
- Round to a clean number (200, not 187)
- Use "+" to indicate "at least this many"
- Be able to explain your estimate if asked
- Never inflate significantly — hiring managers can tell
- "100+" is better than no number at all
- If truly uncertain, use ranges sparingly: "150-250 servers"
</details>

**Q3.** Why should you reframe "LDAP administration" as "identity and access management" on your resume?

<details><summary>Answer</summary>

Three reasons: (1) **ATS keyword matching** — job descriptions say "IAM" not "LDAP", so "identity and access management" will match ATS filters while "LDAP" won't, (2) **Conceptual mapping** — LDAP is a specific technology, but the skills (user provisioning, group policies, access control, directory hierarchy) map directly to GCP IAM, Azure AD, and other cloud identity systems. Using the broader term shows you understand the **concept**, not just one tool, (3) **Forward-looking positioning** — "LDAP administration" sounds legacy; "identity and access management infrastructure" sounds current and relevant to cloud engineering roles. You still mention RHDS/LDAP as the specific technology — the reframe is in the **category**, not eliminating the detail.
</details>

**Q4.** Your resume has 15 bullet points and none have metrics. You only have time to add metrics to 5. Which 5 bullets should you prioritise?

<details><summary>Answer</summary>

Prioritise metrics for the bullets that are **most relevant to your target role** (Cloud Infrastructure Engineer):

1. **Server/infrastructure scale** — "Managed [X]+ servers" — establishes scope credibility
2. **Automation achievement** — "Reduced [process] from X to Y" — core cloud skill, shows impact
3. **Uptime/reliability** — "Maintained [X]% uptime" — SRE/operations credibility
4. **Cloud/GCP project scope** — "Deployed [X] using Terraform" — directly job-relevant
5. **Incident response** — "Resolved P1 incidents in [X] minutes MTTR" — operational maturity

These five cover the main pillars employers evaluate: **scale, automation, reliability, cloud skills, and incident handling**. The remaining 10 bullets should still use strong action verbs even without specific metrics.
</details>
