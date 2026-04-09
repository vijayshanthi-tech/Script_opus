# Day 121 — Select Top 3 Portfolio Projects

> **Week 21 · Portfolio v2** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Evaluate all projects completed during Weeks 1-20, select the top 3 that best demonstrate your cloud engineering capabilities, and craft a narrative arc that tells a compelling story to hiring managers.

---

## Part 1 — Concept: Project Selection Strategy (30 min)

### Why Project Selection Matters

Recruiters spend 6-10 seconds on an initial portfolio scan. Three polished, strategically chosen projects outperform ten mediocre ones. Your goal is to show **breadth, depth, and progression**.

### Project Evaluation Matrix

| Criteria | Weight | Score 1-5 | What It Demonstrates |
|---|---|---|---|
| **Technical Complexity** | 25% | | Multi-service integration, IaC, automation |
| **GCP Service Coverage** | 20% | | Breadth across Compute, Networking, IAM, Monitoring |
| **Job Relevance** | 25% | | Direct mapping to Cloud/Infra Engineer JD requirements |
| **Real-World Applicability** | 15% | | Solves problems employers actually face |
| **Storytelling Potential** | 15% | | Clear problem → solution → outcome arc |

### Mapping Projects to Job Requirements

| Common JD Requirement | Project That Demonstrates It | Evidence |
|---|---|---|
| Infrastructure as Code | Terraform VPC/VM project | Modules, state management, CI/CD |
| Linux administration | Secure VM Baseline project | Hardening, SSH, firewall, patching |
| Monitoring & alerting | SRE Monitoring Pack | Dashboards, alerting policies, SLO/SLI |
| Networking & security | VPC design with firewall rules | Subnets, NAT, Private Google Access |
| IAM & access control | IAM architecture project | Least privilege, service accounts, Workload Identity |
| Automation & scripting | Shell script migrations, automation | Bash/Python, cron, Cloud Functions |
| Incident response | Incident response runbook | RCA template, escalation, post-mortem |
| Cost optimisation | Any project with committed use / right-sizing | Budget alerts, labels, recommendations |

### The Portfolio Narrative Arc

Your three projects should tell a story of **progression**:

```
Project 1: Foundation          Project 2: Integration         Project 3: Production-Ready
─────────────────────────    ──────────────────────────     ──────────────────────────
Single service                Multi-service                  Full stack
Basic config                  IaC + automation               Monitoring + security + IaC
"I can build"                 "I can architect"              "I can operate"
```

### Writing Project Descriptions That Sell

**Weak Description:**
> "Created a VPC with subnets and firewall rules using Terraform."

**Strong Description:**
> "Designed and deployed a production-grade VPC architecture in europe-west2 with public/private subnet segregation, NAT gateway for egress control, and IAP-based SSH access — eliminating the need for bastion hosts. Implemented as reusable Terraform modules with remote state in GCS and CI/CD via Cloud Build."

**Formula:** `[Action verb] + [What you built] + [How/Technology] + [Business value/outcome]`

### Project Description Framework

| Element | Purpose | Example |
|---|---|---|
| **Problem Statement** | Why this project exists | "Production VMs had no standardised monitoring" |
| **Architecture Decision** | Show you made choices | "Chose Cloud Monitoring over Datadog for native integration" |
| **Technical Implementation** | What you built | "Terraform modules, alerting policies, custom dashboards" |
| **Outcome/Impact** | Quantified result | "Reduced MTTD from unknown to <5 minutes" |
| **What I Learned** | Growth mindset signal | "Learned alert tuning to reduce noise by 60%" |

---

## Part 2 — Hands-On Activity: Select & Document Your Top 3 (60 min)

### Exercise 1 — Inventory All Projects (15 min)

List every project/lab you completed during Weeks 1-20. Score each using the evaluation matrix.

**Create a scoring spreadsheet or table:**

```markdown
| # | Project Name | Complexity /5 | Coverage /5 | Relevance /5 | Real-World /5 | Story /5 | Weighted Total |
|---|---|---|---|---|---|---|---|
| 1 | Secure VM Baseline | | | | | | |
| 2 | VPC + Firewall Rules | | | | | | |
| 3 | Terraform VPC Modules | | | | | | |
| 4 | Monitoring Dashboard | | | | | | |
| 5 | IAM Least Privilege | | | | | | |
| 6 | Load Balancer Setup | | | | | | |
| 7 | Autoscaling MIG | | | | | | |
| 8 | Incident Response Pack | | | | | | |
| 9 | SRE Monitoring Pack | | | | | | |
| ... | ... | | | | | | |
```

### Exercise 2 — Select Top 3 & Validate (15 min)

1. Rank projects by weighted total score
2. Check the top 3 against the narrative arc — do they show progression?
3. Check coverage — do they collectively cover Compute, Networking, IAM, Monitoring, IaC?
4. If there's a gap, swap the weakest project for one that fills it

**Validation checklist:**

- [ ] Project 1 is accessible to someone reviewing quickly (foundation level)
- [ ] Project 2 shows multi-service integration and IaC skills
- [ ] Project 3 demonstrates production-readiness thinking (monitoring, security, automation)
- [ ] All three together cover at least 4 of the 6 core JD requirements
- [ ] Each project has a clear "before → after" story

### Exercise 3 — Write Compelling Descriptions (30 min)

For each of your top 3 projects, write:

**Project 1 — [Name]:**
1. **One-liner** (for GitHub repo description, max 100 chars)
2. **Short description** (3-4 sentences for resume/LinkedIn)
3. **Full description** (1-2 paragraphs for the README)

Use this template for the full description:

```markdown
## [Project Name]

**Problem:** [What real-world problem does this solve?]

**Solution:** [What did you build? Which GCP services?]

**Architecture:** [High-level design — subnets, services, data flow]

**Key Technical Decisions:**
- [Decision 1 and why]
- [Decision 2 and why]

**Outcome:**
- [Metric or result 1]
- [Metric or result 2]

**Technologies:** GCP Compute Engine · VPC · Cloud IAM · Terraform · Bash
```

Repeat for Projects 2 and 3.

---

## Part 3 — Revision: Key Takeaways (15 min)

- **Three polished projects > ten incomplete ones** — quality over quantity
- **Score projects objectively** using weighted criteria: complexity, coverage, relevance, real-world applicability, storytelling potential
- **Narrative arc matters** — show progression from foundation → integration → production-ready
- **Map projects to JD requirements** — every project should tick boxes on a job description
- **Strong descriptions use the formula:** action verb + what you built + how + business value
- **Include problem, architecture, decisions, outcome, and learnings** in every project writeup
- **Validate collectively** — your top 3 should cover Compute, Networking, IAM, Monitoring, and IaC
- **One-liner, short, and full descriptions** serve different purposes (GitHub, resume, README)
- **Quantify outcomes** wherever possible (uptime %, time saved, reduction in X)
- **Show decision-making** — "I chose X over Y because Z" signals senior thinking

---

## Part 4 — Quiz (15 min)

**Q1.** When selecting portfolio projects, why is "narrative arc" important?

<details><summary>Answer</summary>

A narrative arc (foundation → integration → production-ready) tells a story of **growth and progression**. It demonstrates to hiring managers that you didn't just follow tutorials — you built increasingly complex systems. This arc mirrors how engineers grow in real roles: start with single components, learn to integrate services, then think about production concerns like monitoring, security, and reliability.
</details>

**Q2.** A job description asks for "experience with infrastructure as code, monitoring, and networking." You have 5 projects but can only showcase 3. One is a Terraform VPC project, one is a monitoring dashboard, and one is a basic VM setup. The other two are an IAM deep-dive and a load balancer project. Which 3 should you pick and why?

<details><summary>Answer</summary>

Pick the **Terraform VPC project** (covers IaC + networking), the **monitoring dashboard** (covers monitoring), and the **load balancer project** (covers networking depth + production-readiness). Drop the basic VM setup (too simple, covered by other projects) and the IAM deep-dive (not explicitly asked for in this JD). The three selected projects directly map to all three JD requirements while showing breadth.
</details>

**Q3.** What makes a project description "strong" versus "weak" on a portfolio?

<details><summary>Answer</summary>

A **strong** description includes: (1) a clear problem statement, (2) specific technologies and architecture decisions, (3) quantified outcomes, and (4) what you learned. A **weak** description merely states what was done ("Created a VPC with Terraform") without context, decisions, or impact. Strong descriptions show **engineering thinking** — why you made choices, what trade-offs you considered, and what measurable results you achieved.
</details>

**Q4.** You scored your projects and the top 3 all focus on networking (VPC, firewall rules, load balancer). Should you go with these three? Why or why not?

<details><summary>Answer</summary>

**No.** Even if they scored highest individually, three networking-only projects show **depth without breadth**. Swap one networking project for a project covering a different domain (monitoring, IaC, IAM, or automation). Hiring managers want to see you can work across the infrastructure stack, not just one area. A portfolio should demonstrate you can handle the **full scope** of a Cloud/Infra Engineer role. Exception: if you're applying for a pure network engineer role, then networking depth is appropriate.
</details>
