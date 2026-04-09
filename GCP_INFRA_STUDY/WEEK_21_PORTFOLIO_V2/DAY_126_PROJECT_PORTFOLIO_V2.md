# Day 126 — PROJECT: Portfolio v2 Published

> **Week 21 · Portfolio v2** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Complete final polish on all 3 portfolio projects and verify everything is published, professional, and recruiter-ready. This is your capstone for the portfolio phase.

---

## Part 1 — Concept: The Portfolio Quality Bar (30 min)

### What "Done" Looks Like

Your portfolio is **done** when a hiring manager can:
1. Visit your GitHub profile and understand who you are in 10 seconds
2. Click on any pinned project and understand what it does in 30 seconds
3. Read the README and understand your architecture and decisions in 2 minutes
4. See screenshots proving the project actually works
5. Find troubleshooting docs showing you ran into and solved real problems
6. See a tagged release showing the project is complete and versioned

### Final Quality Checklist

| Area | Check | Status |
|---|---|---|
| **GitHub Profile** | | |
| Profile README exists and renders correctly | | ☐ |
| Photo/avatar is professional | | ☐ |
| Bio mentions Cloud/Infra Engineer + ACE cert | | ☐ |
| Top 3 projects are pinned | | ☐ |
| **Per Project (×3)** | | |
| Repository has description + topics | | ☐ |
| README has title + one-liner + badges | | ☐ |
| Architecture diagram (Mermaid) renders | | ☐ |
| Problem statement is clear and relatable | | ☐ |
| Tech stack table is complete | | ☐ |
| Prerequisites are specific with versions | | ☐ |
| Quick Start has numbered steps with commands | | ☐ |
| Screenshots exist in `docs/images/` | | ☐ |
| At least 1 screenshot is annotated | | ☐ |
| Troubleshooting section has 3+ entries | | ☐ |
| At least 1 debugging narrative written | | ☐ |
| `.gitignore` prevents secret commits | | ☐ |
| `LICENSE` file exists | | ☐ |
| `.tfvars.example` (not real `.tfvars`) committed | | ☐ |
| v1.0.0 release created with changelog | | ☐ |
| Commit messages are conventional format | | ☐ |
| No secrets in any file or commit history | | ☐ |
| **Narrative Arc** | | |
| Project 1 = Foundation (single service) | | ☐ |
| Project 2 = Integration (multi-service + IaC) | | ☐ |
| Project 3 = Production-ready (monitoring + security) | | ☐ |
| Three projects cover 4+ JD requirement areas | | ☐ |

### Portfolio Narrative Summary

Prepare a short paragraph that connects your 3 projects into a story. You'll use this in cover letters, LinkedIn, and interviews.

**Template:**

> "My portfolio demonstrates a progression from [foundational infrastructure] to [integrated cloud architecture] to [production-readiness]. In [Project 1], I [what you did and learned]. Building on that, [Project 2] [what you did and how it was more complex]. Finally, [Project 3] [what you did and how it shows production thinking]. Together, these projects cover [list of skills] — reflecting my journey from Linux infrastructure specialist to cloud engineer."

**Example:**

> "My portfolio demonstrates a progression from secure VM provisioning to multi-service VPC architecture to full observability. In my Secure VM Baseline project, I built hardened Compute Engine instances with CIS-aligned configurations using Terraform. Building on that, my VPC Architecture project designed a production-grade network with public/private segregation, Cloud NAT, and IAP access — all as reusable Terraform modules. Finally, my SRE Monitoring Pack implemented custom dashboards, alerting policies, and SLO tracking for a simulated production environment. Together, these projects cover Compute, Networking, IAM, IaC, and Monitoring — reflecting my 6-year Linux infrastructure background combined with hands-on GCP cloud engineering skills."

### Common Mistakes to Avoid

| Mistake | Why It Hurts | Fix |
|---|---|---|
| "This is a lab exercise" in description | Sounds like coursework, not real work | Frame as solving a real problem |
| Generic repo names like "project1" | No context, looks lazy | Use descriptive names: `gcp-vpc-terraform-module` |
| Empty or default README | Biggest red flag possible | Use the template from Day 122 |
| Screenshots with sensitive data visible | Security red flag | Redact before committing |
| All projects are identical in scope | Shows no growth | Ensure narrative arc |
| No `.gitignore` | State files or secrets visible | Add before first commit |
| Commit messages: "fix", "update", "done" | Looks unprofessional | Use conventional commits |

---

## Part 2 — Hands-On Activity: Final Polish & Verification (60 min)

### Exercise 1 — Complete the Master Checklist (20 min)

Go through the quality checklist above for **each of your 3 projects**. For every ☐ that isn't checked:

1. Open the project on GitHub
2. Make the fix (edit README, add missing file, update description)
3. Commit with a meaningful message: `docs: add troubleshooting section` or `chore: add .gitignore`
4. Push to main

**Priority order if short on time:**
1. README completeness (title, diagram, problem, setup)
2. Screenshots present
3. Troubleshooting section
4. Release created
5. Profile README

### Exercise 2 — Peer Review Simulation (20 min)

Review your own portfolio as if you were a hiring manager seeing it for the first time:

**Step 1: The 10-Second Test**
- Open your GitHub profile
- Can you tell who this person is and what they do in 10 seconds?
- Are the pinned repositories clearly labelled?

**Step 2: The 30-Second Test (per project)**
- Click on a pinned repository
- Read only the first screen of the README (no scrolling)
- Do you understand what this project does and why?
- Is there a visual (diagram or screenshot)?

**Step 3: The 2-Minute Deep Dive (per project)**
- Scroll through the full README
- Are the setup instructions clear enough to follow?
- Is there a troubleshooting section?
- Does the project feel complete and professional?

**Note any issues and fix them immediately.**

### Exercise 3 — Write Your Portfolio Narrative (10 min)

Using the template from Part 1, write your portfolio narrative paragraph:

1. What progression do your 3 projects show?
2. What did you build and learn in each?
3. What skills do they collectively demonstrate?
4. How does this connect to your 6-year Linux background?

Write this paragraph and save it — you'll use it in:
- LinkedIn "About" section (Week 22)
- Cover letter template (Week 22)
- Interview "tell me about your projects" answer (Week 23)

### Exercise 4 — Final Verification (10 min)

**Security scan:**
```bash
# Check for common secrets in your repos
# Run locally for each project
grep -rn "PRIVATE KEY" .
grep -rn "password" . --include="*.tf" --include="*.sh"
grep -rn "secret" . --include="*.tf" --include="*.sh"
```

**Link verification:**
- Click every link in every README — do they work?
- Do Mermaid diagrams render on GitHub?
- Do image links in README show the screenshots?

**Final push:**
```bash
git status  # Nothing unexpected
git log --oneline -10  # History looks clean
```

---

## Part 3 — Revision: Key Takeaways (15 min)

- **Portfolio v2 is complete** when all 3 projects pass the full quality checklist
- **The quality bar:** profile README + pinned repos + README with diagrams + screenshots + troubleshooting + releases
- **Narrative arc matters:** foundation → integration → production-ready tells a growth story
- **Write a portfolio narrative paragraph** — you'll reuse it across cover letters, LinkedIn, and interviews
- **Self-review as a hiring manager** — the 10-second, 30-second, and 2-minute tests reveal what needs fixing
- **Security scan before publishing** — grep for secrets, private keys, passwords in all committed files
- **Common mistakes:** generic repo names, empty READMEs, no `.gitignore`, messy commit history
- **Three polished projects >> ten mediocre ones** — quality is the differentiator
- **Everything from this week connects to the next 3 weeks:** resume (Week 22), interviews (Week 23), applications (Week 24)
- **Celebrate this milestone** — you've built a professional cloud engineering portfolio from scratch

---

## Part 4 — Quiz (15 min)

**Q1.** You've published your portfolio and a recruiter messages you saying they looked at your GitHub. What three things would you want them to have seen?

<details><summary>Answer</summary>

1. **Profile README** — immediately shows you're a Cloud Infrastructure Engineer with ACE certification and 6 years of Linux experience. Sets the context for everything else.
2. **Pinned project with architecture diagram** — the Mermaid diagram in the README gives them a visual understanding of your technical skills in under 10 seconds. Shows you can design, not just configure.
3. **Troubleshooting section or debugging narrative** — this is what separates you from tutorial-followers. It proves you've actually built and operated infrastructure, hit real problems, and solved them. This is what makes them want to interview you.

Bonus: A tagged release shows project maturity; screenshots prove it works on real GCP.
</details>

**Q2.** Your portfolio has 3 projects: Terraform VPC, Terraform VPC with modules, and Terraform VPC with different CIDR ranges. What's wrong with this portfolio and how would you fix it?

<details><summary>Answer</summary>

All three projects are **variations of the same thing** — there's no breadth or narrative arc. A hiring manager sees "this person can only do VPC in Terraform." 

**Fix:** Keep the best VPC project (probably the modular one) and replace the other two with projects covering different domains:
- **Project 2:** Monitoring + SRE (dashboards, alerting, SLO) — shows observability skills
- **Project 3:** IAM + security architecture — shows security thinking

The portfolio should demonstrate you can work across the **full infrastructure stack**: Compute, Networking, IAM, Monitoring, and IaC. Three VPC projects, no matter how good, fail the breadth test.
</details>

**Q3.** What is a "portfolio narrative arc" and why does the order of your projects matter?

<details><summary>Answer</summary>

A narrative arc is the **story your portfolio tells** about your growth as an engineer. The recommended arc is:

1. **Foundation** — a simpler project showing core skills (e.g., secure VM setup)
2. **Integration** — a more complex project combining multiple services (e.g., VPC + Terraform modules + CI/CD)
3. **Production-ready** — the most mature project showing operational thinking (e.g., monitoring, alerting, SLO, incident response)

Order matters because it mirrors **how engineers grow in real roles**: start with individual components, learn to integrate systems, then think about production concerns. It tells hiring managers: "This person has gone through a learning journey and is now thinking at a production/operations level." A random collection of projects doesn't tell this story.
</details>

**Q4.** You're about to push your portfolio to GitHub. List 5 things you should check for security before making the repositories public.

<details><summary>Answer</summary>

1. **No service account keys or API keys** in any file — grep for "PRIVATE KEY", "api_key", "secret"
2. **No real `.tfvars` files** — only `.tfvars.example` with placeholder values; real `.tfvars` in `.gitignore`
3. **No passwords or tokens** in scripts, variables, or config files
4. **No sensitive data in screenshots** — billing details, personal email addresses, internal hostnames redacted
5. **No secrets in Git history** — even if removed from current files, they persist in commit history. Use `git log --all -S "password"` to check. If found, use BFG Repo Cleaner or `git filter-branch` to purge.

Also check: `.gitignore` includes `.tfstate`, `.terraform/`, `*.pem`, `*.key`; and that no real GCP credentials or OAuth tokens are stored anywhere in the repo.
</details>
