# Day 129 — Projects Section with Links

> **Week 22 · Resume & CV** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Create a compelling Projects section on your resume that links to your GitHub portfolio, maps each project to job requirements, and uses the right technical keywords.

---

## Part 1 — Concept: The Projects Section (30 min)

### Where Projects Go on Your Resume

For a career transitioner, the Projects section is **critical** — it bridges the gap between your Linux admin experience and the cloud role you're targeting.

| Resume Section Order | For Career Transitioner |
|---|---|
| 1. Header (name, contact, links) | Include GitHub link prominently |
| 2. Professional Summary | Bridge statement (Day 127) |
| 3. **Projects / Portfolio** ← | **Move this ABOVE work experience** |
| 4. Work Experience | Reframed with cloud-relevant bullets (Day 128) |
| 5. Certifications | ACE cert + planned certs |
| 6. Skills | Technical skills list |
| 7. Education | Degree/relevant courses |

**Key insight:** Placing Projects before Work Experience draws attention to your **cloud capabilities** before the recruiter sees your "Linux Admin" job title and potentially pigeonholes you.

### How to Present Projects on a Resume

**Format per project (3-4 lines):**

```
PROJECT NAME | github.com/username/repo-name
Technologies: Terraform, GCP Compute Engine, VPC, Cloud Monitoring, Bash
• One-line description of what you built and why
• Key technical achievement or metric (e.g., "Deployed in <5 min via Terraform modules")
```

### Project Description Framework

| Element | Purpose | Word Count |
|---|---|---|
| **Project name** | Memorable, descriptive | 2-4 words |
| **GitHub link** | Proof of work | URL |
| **Tech stack** | ATS keywords + skill match | 4-6 technologies |
| **What + Why** | Shows problem-solving | 1 line |
| **Key achievement** | Differentiator | 1 line |

### Mapping Projects to Job Requirements

| JD Requirement | Project to Reference | Bullet to Write |
|---|---|---|
| "Infrastructure as Code" | Terraform VPC project | "Designed VPC architecture as reusable Terraform modules with GCS remote state" |
| "Cloud networking" | VPC + Firewall project | "Built production VPC with public/private subnets, Cloud NAT, and IAP SSH access" |
| "Monitoring/observability" | SRE Monitoring Pack | "Implemented Cloud Monitoring dashboards, alerting policies, and SLO tracking" |
| "Linux administration" | Secure VM Baseline | "Hardened Compute Engine VMs with CIS-aligned configurations and Ops Agent" |
| "IAM/security" | IAM Architecture | "Designed least-privilege IAM with custom roles and Workload Identity Federation" |
| "Automation" | Any scripted project | "Automated infrastructure deployment reducing build time from hours to minutes" |

### Technical Keywords for ATS

ATS (Applicant Tracking Systems) scan for keywords. Your projects section should naturally include these:

| Category | Keywords to Include |
|---|---|
| **GCP Services** | Compute Engine, VPC, Cloud NAT, IAM, Cloud Monitoring, Cloud Build, GCS |
| **IaC** | Terraform, modules, state management, HCL, plan/apply |
| **Networking** | VPC, subnets, firewall rules, CIDR, Private Google Access, load balancing |
| **Security** | IAM, least privilege, service accounts, Workload Identity, CIS benchmarks |
| **Monitoring** | Cloud Monitoring, Ops Agent, dashboards, alerting, SLO/SLI, uptime checks |
| **OS** | RHEL, CentOS, Linux, SSH, systemd, hardening |
| **Scripting** | Bash, Python, automation, CI/CD |
| **Methodology** | SRE, incident response, RCA, capacity planning, cost optimisation |

### Strong vs Weak Project Names

| Weak | Strong | Why |
|---|---|---|
| "Project 1" | "Production VPC Architecture" | Descriptive, sounds professional |
| "Terraform Lab" | "Terraform VPC Modules" | Specific, keywords included |
| "Monitoring Setup" | "SRE Monitoring & Alerting Pack" | Shows SRE thinking, scope |
| "GCP Stuff" | "Secure VM Baseline — CIS Hardened" | Specific, security-focused |

---

## Part 2 — Hands-On Activity: Build Your Projects Section (60 min)

### Exercise 1 — Draft Project Entries (30 min)

Write the resume entry for each of your top 3 projects using this template:

```markdown
**[PROJECT NAME]** | github.com/yourusername/repo-name
Technologies: [Tech 1], [Tech 2], [Tech 3], [Tech 4], [Tech 5]
• [What you built and the problem it solves — 1 line]  
• [Key technical achievement or metric — 1 line]
```

**Project 1 — Foundation:**

```
SECURE VM BASELINE | github.com/yourusername/gcp-secure-vm-baseline
Technologies: Terraform, GCP Compute Engine, Cloud IAM, Ops Agent, Bash
• Built CIS-hardened Compute Engine instances with automated security 
  configuration, SSH hardening, and monitoring agent deployment
• Reduced VM provisioning from manual 2-hour process to 5-minute 
  Terraform deployment with consistent security compliance
```

**Project 2 — Integration:**

```
PRODUCTION VPC ARCHITECTURE | github.com/yourusername/gcp-vpc-terraform
Technologies: Terraform Modules, GCP VPC, Cloud NAT, IAP, Firewall Rules
• Designed multi-tier VPC in europe-west2 with public/private subnet segregation, 
  Cloud NAT for egress, and IAP-based SSH access eliminating bastion hosts
• Implemented as reusable Terraform modules with GCS remote state and 
  parameterised deployment across environments
```

**Project 3 — Production-Ready:**

```
SRE MONITORING & ALERTING PACK | github.com/yourusername/gcp-sre-monitoring
Technologies: GCP Cloud Monitoring, Ops Agent, Terraform, SLO/SLI, Alerting
• Implemented comprehensive observability for compute infrastructure with custom 
  dashboards, multi-signal alerting policies, and SLO-based monitoring
• Achieved <5 minute mean-time-to-detect (MTTD) for CPU, memory, and disk 
  anomalies with tuned alert thresholds reducing noise by 60%
```

### Exercise 2 — Map to Job Descriptions (15 min)

Find 2 Cloud Infrastructure Engineer job descriptions online (LinkedIn, Google Careers, Indeed). For each:

1. List the top 5 requirements from the JD
2. Map each requirement to one of your projects
3. Verify your project descriptions use matching keywords

| JD Requirement | My Project | Keywords Matched? |
|---|---|---|
| | | ☐ |
| | | ☐ |
| | | ☐ |
| | | ☐ |
| | | ☐ |

If a requirement isn't covered by any project, note it as a gap to address in your Work Experience bullets or Skills section.

### Exercise 3 — Format and Position (15 min)

1. **Position the Projects section** on your resume draft — immediately after Professional Summary, before Work Experience
2. **Format consistently** — same structure for all 3 projects
3. **Check total length** — Projects section should be 12-18 lines (about 1/3 of a page)
4. **Verify GitHub links** — click every link to confirm they work
5. **ATS test** — copy your resume text into a plain text editor. Do the keywords survive? (No images, no columns that break in text)

**Section header options:**
- "Projects" — simple, standard
- "Cloud Infrastructure Projects" — more specific
- "Portfolio Projects" — signals intentional portfolio building
- "Technical Projects" — common format

---

## Part 3 — Revision: Key Takeaways (15 min)

- **Projects section goes ABOVE Work Experience** for career transitioners — lead with cloud skills
- **Format:** Project Name | GitHub Link, Technologies line, 2 bullet points (what + metric)
- **Each project entry = 3-4 lines** — concise, not full README content
- **Use strong project names** — "Production VPC Architecture" not "Project 1"
- **Include GitHub links** — they serve as proof of work and let reviewers dive deeper
- **Technology line doubles as ATS keywords** — list 4-6 relevant technologies
- **Map projects to JD requirements** — every project should tick at least one job requirement box
- **Two bullets per project:** one for what/why, one for the key metric/achievement
- **Total Projects section: 12-18 lines** — impactful but not overwhelming
- **Test for ATS compatibility** — paste resume as plain text, check keywords survive

---

## Part 4 — Quiz (15 min)

**Q1.** Why should a career transitioner place the Projects section above Work Experience on their resume?

<details><summary>Answer</summary>

Because your Work Experience section has job titles like "Linux Systems Administrator" which can cause recruiters to **pigeonhole** you before they see your cloud skills. By placing Projects first, you lead with **cloud engineering evidence** — Terraform, GCP, monitoring, VPC architecture — which directly matches the Cloud Infrastructure Engineer role they're hiring for. Once they've seen your cloud capabilities, they'll read your Work Experience with a more favourable lens, seeing "Linux admin with 6 years experience" as an **asset** rather than a mismatch. Resume order controls **narrative flow** — tell the story you want them to hear first.
</details>

**Q2.** A project entry reads: "Built a VPC in GCP using Terraform." How would you improve this for a resume?

<details><summary>Answer</summary>

**Improved:**

```
PRODUCTION VPC ARCHITECTURE | github.com/user/gcp-vpc-terraform
Technologies: Terraform Modules, GCP VPC, Cloud NAT, IAP, Firewall Rules
• Designed multi-tier VPC in europe-west2 with public/private segregation, 
  Cloud NAT, and IAP SSH access — deployed as reusable Terraform modules
• Eliminated bastion host requirement, reducing attack surface while 
  maintaining full SSH access via Identity-Aware Proxy
```

**What improved:** (1) Added a **GitHub link** for proof, (2) Listed specific **technologies** for ATS matching, (3) Added **architecture details** (multi-tier, public/private, region), (4) Included a **security benefit** (eliminated bastion host), (5) Framed as a **reusable module** showing production thinking, (6) Used active verbs "Designed" and "Eliminated" instead of generic "Built."
</details>

**Q3.** How many technologies should you list per project on a resume, and how do you choose which ones?

<details><summary>Answer</summary>

List **4-6 technologies** per project. Choosing criteria:
1. **Job relevance** — prioritise technologies mentioned in the JDs you're targeting
2. **Specificity** — "Terraform Modules" is better than just "Terraform"; "GCP VPC" is better than just "GCP"
3. **Avoid duplication** — if all 3 projects list "Terraform, GCP", add project-specific tech instead
4. **Core + supporting** — lead with the main technology, add supporting tools

Example prioritisation for a VPC project: `Terraform Modules` (primary tool), `GCP VPC` (primary service), `Cloud NAT` (specific service), `IAP` (specific service), `Firewall Rules` (security), `GCS` (state backend). This gives 6 **specific, searchable** keywords rather than generic terms.
</details>

**Q4.** You're applying to two different roles — one emphasises "networking and security" and the other emphasises "automation and monitoring." Should your Projects section be the same for both applications?

<details><summary>Answer</summary>

**No.** While the same 3 projects can work for both, you should **reorder them and adjust emphasis**:

**For "networking and security" role:**
- Lead with VPC Architecture project (networking focus)
- Emphasise security aspects in each project (IAM, firewall rules, CIS hardening)
- Use security keywords: "least privilege", "network segmentation", "CIS benchmarks"

**For "automation and monitoring" role:**
- Lead with SRE Monitoring Pack (monitoring focus)
- Emphasise automation in each project (Terraform automation, scripted deployment)
- Use automation keywords: "automated deployment", "CI/CD", "SLO/SLI"

The projects are the same, but the **order, emphasis, and keywords** change per JD. This is ATS optimisation and tailoring — covered in detail on Day 130.
</details>
