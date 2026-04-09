# Day 130 — Tailor Resume to Job Descriptions

> **Week 22 · Resume & CV** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Learn ATS optimisation, keyword matching, and how to create multiple tailored resume versions that pass automated screening and speak directly to specific job descriptions.

---

## Part 1 — Concept: ATS Optimisation & Resume Tailoring (30 min)

### How ATS (Applicant Tracking Systems) Work

75% of resumes are rejected by ATS before a human sees them. ATS systems:

| What ATS Does | Implication for You |
|---|---|
| **Parses** your resume into structured fields | Use clean formatting — no tables, graphics, or columns |
| **Extracts keywords** from content | Include exact phrases from the JD |
| **Scores relevance** against job description | Higher keyword match = higher ranking |
| **Ranks candidates** for recruiter review | Top 10-20% get human eyes |
| **Filters by requirements** | Missing a "required" skill = automatic rejection |

### ATS-Friendly Formatting Rules

| Do | Don't |
|---|---|
| Use standard section headings (Experience, Projects, Skills) | Use creative headers ("My Journey", "Toolbox") |
| Plain text or simple formatting (bold, bullets) | Complex tables, columns, or graphics |
| Standard fonts (Arial, Calibri, Times New Roman) | Decorative fonts or tiny sizes |
| .docx or .pdf format (check which the ATS accepts) | .png, .jpeg, or heavily designed PDFs |
| Put your name as the file name | `resume_final_v3_FINAL.docx` |
| One column layout | Two-column or sidebar layouts |
| Spell out acronyms at least once: "Infrastructure as Code (IaC)" | Only use acronyms the first time |

### Keyword Matching Strategy

**Step 1: Extract keywords from the JD**

Read the job description and highlight:
- Required skills (appear in "Requirements" or "Must have")
- Preferred skills (appear in "Nice to have" or "Preferred")
- Repeated words/phrases (if it appears 3+ times, it's important)
- Action words the company uses (automate, design, implement, troubleshoot)

**Step 2: Map keywords to your resume**

| JD Keyword | Where on My Resume | Exact Phrase |
|---|---|---|
| "Terraform" | Projects: VPC Architecture | "Terraform Modules" ✓ |
| "Cloud networking" | Projects: VPC Architecture | "VPC with Cloud NAT" ✓ |
| "Incident response" | Work Experience: bullet 5 | "Led incident response" ✓ |
| "Kubernetes" | NOT on resume | Gap — add to Skills if any exposure, or omit |
| "Linux" | Summary + Experience | "RHEL 7/8 production servers" ✓ |

**Step 3: Incorporate missing keywords naturally**

Don't keyword-stuff. Integrate naturally:
- In project descriptions
- In experience bullets
- In skills section
- In summary (most impactful placement)

### Common Cloud Engineer JD Keywords

| Category | Frequent Keywords |
|---|---|
| **Cloud Platforms** | GCP, AWS, Azure, multi-cloud, hybrid cloud |
| **IaC** | Terraform, Ansible, CloudFormation, Infrastructure as Code |
| **Containers** | Docker, Kubernetes, GKE, container orchestration |
| **CI/CD** | Cloud Build, Jenkins, GitHub Actions, GitLab CI, pipelines |
| **Networking** | VPC, DNS, load balancing, CDN, VPN, interconnect, firewall |
| **Security** | IAM, least privilege, encryption, compliance, CIS, hardening |
| **Monitoring** | Cloud Monitoring, Prometheus, Grafana, SLO, SLI, alerting |
| **OS** | Linux, RHEL, Ubuntu, shell scripting, Bash |
| **Methodology** | SRE, DevOps, agile, incident management, on-call, RCA |
| **Soft Skills** | Collaboration, communication, documentation, mentoring |

### Maintaining Multiple Resume Versions

| Version | Target | Key Emphasis |
|---|---|---|
| **Base Resume** | Your complete resume with all content | Reference document, not sent directly |
| **Cloud Infra v1** | Roles emphasising networking + security | Lead with VPC project, security bullets |
| **Cloud Infra v2** | Roles emphasising automation + monitoring | Lead with SRE project, automation bullets |
| **Hybrid v1** | Roles wanting both on-prem + cloud | Balance Linux experience with GCP projects |

**Management tip:** Keep a spreadsheet tracking which version you sent to which company.

### Tailoring Workflow

```
1. Read JD thoroughly (5 min)
2. Highlight keywords and requirements (3 min)
3. Copy your base resume (1 min)
4. Adjust summary to match JD language (5 min)
5. Reorder projects by JD relevance (3 min)
6. Adjust 2-3 experience bullets to match keywords (5 min)
7. Update Skills section to match JD order (2 min)
8. Name file: "FirstName_LastName_CompanyName_Role.pdf" (1 min)
```

Total: ~25 minutes per application. Gets faster with practice.

---

## Part 2 — Hands-On Activity: Tailor to 2 Job Descriptions (60 min)

### Exercise 1 — Find 2 Target Job Descriptions (10 min)

Find 2 real Cloud Infrastructure Engineer (or similar) job descriptions. Good sources:
- LinkedIn Jobs: search "Cloud Infrastructure Engineer UK"
- Google Careers: cloud roles
- Indeed: "GCP Engineer" or "Cloud Engineer"
- CWJobs, Totaljobs (UK-specific)

Save both JDs in full. You'll reference them throughout this exercise.

### Exercise 2 — Keyword Extraction (15 min)

For each JD, create a keyword map:

**JD 1: [Company Name] — [Role Title]**

| Category | Keywords Found | On My Resume? | Action |
|---|---|---|---|
| Required Skills | | | |
| | | | |
| | | | |
| Preferred Skills | | | |
| | | | |
| Repeated Phrases | | | |
| | | | |

**JD 2: [Company Name] — [Role Title]**

| Category | Keywords Found | On My Resume? | Action |
|---|---|---|---|
| Required Skills | | | |
| | | | |
| | | | |
| Preferred Skills | | | |
| | | | |
| Repeated Phrases | | | |
| | | | |

### Exercise 3 — Create 2 Tailored Versions (25 min)

For each JD, create a tailored resume:

1. **Copy your base resume**
2. **Adjust the summary** — use language from the JD. If they say "design and implement cloud infrastructure," use "design and implement" in your summary
3. **Reorder projects** — put the most relevant project first
4. **Adjust 2-3 experience bullets** — swap generic bullets for ones matching JD keywords
5. **Update Skills section** — reorder to put JD-matching skills first

**Quick tailoring checklist:**

| Element | JD 1 Version | JD 2 Version |
|---|---|---|
| Summary uses JD language | ☐ | ☐ |
| Most relevant project first | ☐ | ☐ |
| Keywords from "Required" section present | ☐ | ☐ |
| At least 3 "Preferred" keywords present | ☐ | ☐ |
| Skills section matches JD priority | ☐ | ☐ |

### Exercise 4 — ATS Compatibility Test (10 min)

Test your resume's ATS compatibility:

1. Copy your resume text into a plain text file — does it read coherently?
2. Check that section headings are standard (Experience, Projects, Skills, Education)
3. Verify no important content is in headers/footers (ATS often ignores these)
4. Ensure the file is saved as .docx or .pdf
5. Name it properly: `FirstName_LastName_CompanyName.pdf`

**Keyword density check:** For each "Required" skill in the JD, your resume should mention it at least 2-3 times across different sections (summary, projects, experience, skills).

---

## Part 3 — Revision: Key Takeaways (15 min)

- **75% of resumes are rejected by ATS** before a human sees them — keyword matching is critical
- **Extract keywords from JDs** — highlight required skills, preferred skills, and repeated phrases
- **Use exact JD phrasing** where possible — "design and implement" not "create and set up"
- **ATS-friendly formatting:** single column, standard headings, no graphics, .docx or .pdf
- **Maintain a base resume** and create tailored versions per application (~25 min each)
- **Spell out acronyms once:** "Infrastructure as Code (IaC)" helps both ATS and human readers
- **Reorder sections per JD** — most relevant project first, most relevant skills first
- **Track versions** with a spreadsheet: company, role, version sent, date applied
- **Name files professionally:** `FirstName_LastName_CompanyName.pdf`
- **Keyword density:** each required skill should appear 2-3 times across your resume

---

## Part 4 — Quiz (15 min)

**Q1.** A job description lists "Terraform, Kubernetes, and CI/CD pipelines" as required skills. You have strong Terraform experience and some CI/CD knowledge, but no Kubernetes. What should you do?

<details><summary>Answer</summary>

1. **Terraform:** Feature prominently — this is your strength. Mention in summary, projects, and skills.
2. **CI/CD:** Include what you have — Cloud Build, GitHub Actions, any pipeline experience. Even "Terraform CI/CD with Cloud Build" counts.
3. **Kubernetes:** Be honest. Options: (a) If you have **any** exposure (even a tutorial), add it to Skills with an honest level indicator, (b) If truly zero experience, **don't fabricate it**. Instead, mention container-adjacent skills: "Familiar with containerisation concepts; hands-on with Docker for local development." (c) In your cover letter, acknowledge it: "Currently expanding skills into container orchestration with GKE."

**Never claim skills you can't discuss in an interview.** Missing one "required" skill doesn't automatically disqualify you — many companies list aspirational requirements. Apply if you match 70%+ of the requirements.
</details>

**Q2.** What's the risk of using a two-column or sidebar resume layout?

<details><summary>Answer</summary>

**ATS parsing failure.** Two-column layouts, sidebars, and text boxes cause ATS systems to:
1. **Scramble content** — reading across columns instead of within them
2. **Miss entire sections** — sidebar content may not be parsed at all
3. **Merge text incorrectly** — "Python Experience" becomes "Python managed 200 Experience servers"

The result: your resume scores 0% keyword match even though it contains all the right content. ATS sees garbled text, not your carefully crafted bullets.

**Solution:** Always use a **single-column layout** with standard headings. If you want visual appeal, use clean formatting (bold headings, carefully spaces bullet points, consistent font) within a single column. Save design flourishes for a personal website, not your ATS-submitted resume.
</details>

**Q3.** How much time should you spend tailoring a resume per job application, and what's the minimum you should change?

<details><summary>Answer</summary>

**Target: 20-30 minutes per application.** The minimum changes:

1. **Summary (5 min):** Adjust 1-2 phrases to match JD language
2. **Projects order (2 min):** Put the most relevant project first
3. **1-2 experience bullets (5 min):** Swap bullets to match JD emphasis
4. **Skills order (2 min):** Reorder to match JD priorities
5. **File name (1 min):** `Name_Company_Role.pdf`

**Diminishing returns:** Beyond 30 minutes, you're over-tailoring. The goal is 80% match, not 100% — a suspicious 100% match can actually flag as "keyword stuffed." Spend the extra time writing a short, personalised cover letter instead.

If you're spending less than 10 minutes, you're probably sending a generic resume that won't pass ATS filters.
</details>

**Q4.** You're maintaining 3 resume versions. How should you track which version was sent where?

<details><summary>Answer</summary>

Create a **job application tracker** (spreadsheet or Notion doc):

| Date | Company | Role | Resume Version | Cover Letter? | Applied Via | Status | Follow-up Date |
|---|---|---|---|---|---|---|---|
| 2026-04-08 | Company A | Cloud Infra Eng | Cloud Infra v1 | Yes | LinkedIn | Applied | 2026-04-22 |
| 2026-04-09 | Company B | Platform Eng | Cloud Infra v2 | Yes | Careers Page | Applied | 2026-04-23 |

This prevents: (1) **Sending the wrong version** to a company, (2) **Forgetting which narrative** you used (important for interview prep), (3) **Missing follow-ups** — always follow up 2 weeks after applying, (4) **Losing track** of where you are in each process. It also helps you spot patterns: if version 1 gets more callbacks than version 2, that tells you something about your positioning.
</details>
