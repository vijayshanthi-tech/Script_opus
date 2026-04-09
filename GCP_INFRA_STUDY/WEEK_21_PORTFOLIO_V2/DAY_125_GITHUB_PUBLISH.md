# Day 125 — Push to GitHub + Tag Releases

> **Week 21 · Portfolio v2** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Set up a professional GitHub presence — push polished projects with meaningful commit history, create tagged releases, build a profile README, and optimise discoverability.

---

## Part 1 — Concept: GitHub as Your Professional Showcase (30 min)

### Your GitHub Profile = Your Technical CV

Recruiters and hiring managers visit GitHub profiles. What they look for:

| Element | What They Check | Time Spent |
|---|---|---|
| **Profile README** | Who you are, what you do, what you're learning | 5-10 seconds |
| **Pinned Repositories** | Your best work, front and centre | 10-20 seconds |
| **Repository READMEs** | Quality of documentation, architecture | 30-60 seconds |
| **Commit History** | Consistency, meaningful messages | Quick glance |
| **Topics/Tags** | Discoverability, technology alignment | Quick glance |
| **Contribution Graph** | Activity level (green squares) | Quick glance |

### Git Workflow for Portfolio Projects

**Branch Strategy (Simple):**

```
main (default)          — Always deployable, clean code
├── feature/add-monitoring   — Feature branches for new work
├── fix/firewall-rule        — Bug fix branches
└── docs/improve-readme      — Documentation improvements
```

**For portfolio projects, keep it simple:** work on `main` or use short-lived feature branches. Don't over-engineer with develop/staging branches for solo projects.

### Meaningful Commit Messages

**Format:** `type: concise description of what changed`

| Type | When to Use | Example |
|---|---|---|
| `feat:` | New feature or functionality | `feat: add Cloud NAT for private subnet egress` |
| `fix:` | Bug fix | `fix: correct firewall rule source range for IAP` |
| `docs:` | Documentation changes | `docs: add architecture diagram to README` |
| `refactor:` | Code restructuring | `refactor: extract VPC into reusable module` |
| `test:` | Adding tests | `test: add validation for subnet CIDR ranges` |
| `chore:` | Maintenance | `chore: update Terraform provider to 5.0` |

**Bad commits:**
```
- "update"
- "fix stuff"
- "wip"
- "final version"
- "asdfgh"
```

**Good commits:**
```
- "feat: add alerting policy for CPU > 80% threshold"
- "fix: resolve state lock issue by adding GCS backend"
- "docs: add troubleshooting section for common IAM errors"
```

### Creating Releases with Changelogs

Releases show your project is **mature and versioned** — not just a dumping ground of files.

**Version Strategy (Semantic Versioning Lite):**

| Version | Meaning | Example |
|---|---|---|
| `v1.0.0` | Initial complete release | Project fully functional with docs |
| `v1.1.0` | Added feature | Added monitoring dashboard |
| `v1.1.1` | Bug fix | Fixed firewall rule typo |
| `v2.0.0` | Major change | Restructured to use Terraform modules |

**Release Notes Template:**

```markdown
## v1.0.0 — Initial Release

### What's Included
- VPC with public/private subnets in europe-west2
- Firewall rules for SSH (IAP) and HTTP
- Cloud NAT for private subnet internet access
- Terraform modules with remote GCS backend

### Architecture
[Link to architecture diagram in README]

### Quick Start
See [README.md](README.md#quick-start) for setup instructions.

### Known Limitations
- Single-region deployment only
- No auto-scaling configured (see v2.0 roadmap)
```

### GitHub Profile README

A profile README appears at the top of your GitHub profile page. Create it by making a repository with the **same name as your GitHub username**.

**Profile README Template:**

```markdown
# Hi, I'm [Your Name] 👋

**Cloud Infrastructure Engineer** | ACE Certified | 6 Years Linux Infrastructure

## 🔧 What I Work With

- **Cloud:** GCP (Compute Engine, VPC, IAM, Cloud Monitoring, Cloud Build)
- **IaC:** Terraform (modules, remote state, CI/CD pipelines)
- **OS:** RHEL, CentOS, Ubuntu — hardening, patching, automation
- **Identity:** RHDS/LDAP (3 years), GCP IAM, Workload Identity
- **Monitoring:** Cloud Monitoring, Ops Agent, SLO/SLI, alerting
- **Scripting:** Bash, Python (automation, migration tools)

## 📂 Featured Projects

| Project | Description | Tech |
|---|---|---|
| [Project 1](link) | One-line description | Terraform, GCP, Bash |
| [Project 2](link) | One-line description | Terraform, VPC, IAM |
| [Project 3](link) | One-line description | Monitoring, SRE, Ops Agent |

## 📜 Certifications

- Google Cloud Associate Cloud Engineer (ACE)
- [Next certification you're pursuing]

## 📫 Connect

- LinkedIn: [your-linkedin-url]
- Email: [your-email]

---
*Currently deepening GCP infrastructure skills — targeting Professional Cloud Architect.*
```

### Pinned Repositories

GitHub allows you to pin up to 6 repositories to your profile. Pin strategy:

| Pin Slot | What to Pin | Why |
|---|---|---|
| 1 | Your best infrastructure project | Lead with your strongest work |
| 2 | Your most complex project | Show depth |
| 3 | Your most unique project | Stand out |
| 4-6 | Other relevant work or contributions | Fill with supporting evidence |

### Topics and Tags for Discoverability

Add topics to each repository for searchability:

**Good topics for your projects:**
- `gcp` `google-cloud-platform` `terraform` `infrastructure-as-code`
- `vpc` `networking` `firewall` `iam`
- `cloud-monitoring` `sre` `observability`
- `linux` `bash` `automation`
- `cloud-engineer` `devops` `infrastructure`

---

## Part 2 — Hands-On Activity: Publish to GitHub (60 min)

### Exercise 1 — Prepare Repositories (15 min)

For each of your top 3 projects:

1. **Create a `.gitignore`** appropriate for Terraform/GCP projects:

```gitignore
# Terraform
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl
*.tfvars
!*.tfvars.example

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/

# Secrets
*.json
!package.json
*.pem
*.key

# Logs
*.log
```

2. **Create a `LICENSE` file** — MIT is standard for portfolio projects
3. **Verify no secrets** are in any committed files:
   - No service account keys
   - No `.tfvars` with real values (only `.tfvars.example`)
   - No hardcoded passwords or API keys

### Exercise 2 — Push with Clean History (20 min)

For each project, create the GitHub repository and push:

```bash
# Initialise (if not already a git repo)
cd /path/to/project
git init
git add .
git commit -m "feat: initial release — [project description]"

# Create GitHub repo (via github.com or gh CLI)
# Then link and push:
git remote add origin https://github.com/yourusername/project-name.git
git branch -M main
git push -u origin main
```

**If your existing commit history is messy**, consider a clean start:
```bash
# Option: Interactive rebase to clean up commits
git rebase -i --root
# Squash/reword commits as needed
```

**Add topics** via GitHub web UI: Repository → About (gear icon) → Topics

### Exercise 3 — Create Releases (10 min)

For each project, create a v1.0.0 release:

1. Go to repository on GitHub
2. Click "Releases" → "Create a new release"
3. Tag: `v1.0.0`
4. Title: `v1.0.0 — Initial Release`
5. Description: Use the release notes template from Part 1
6. Check "Set as latest release"
7. Publish

### Exercise 4 — Create Profile README (15 min)

1. Create a new repository named **exactly** your GitHub username
2. Initialise with a README.md
3. Use the profile README template from Part 1
4. Customise with your actual projects, certifications, and links
5. Pin your top 3 project repositories to your profile

**Verification checklist:**
- [ ] Profile README visible on your GitHub profile page
- [ ] Top 3 projects pinned
- [ ] Each repo has: description, topics, README, licence
- [ ] Each repo has a v1.0.0 release
- [ ] No secrets or sensitive data in any repository
- [ ] `.gitignore` prevents accidental secret commits

---

## Part 3 — Revision: Key Takeaways (15 min)

- **GitHub profile = technical CV** — recruiters check profile README, pinned repos, commit history
- **Pin your top 3 projects** — they appear front and centre on your profile
- **Use conventional commit messages:** `feat:`, `fix:`, `docs:`, `refactor:`
- **Create tagged releases** with changelogs — shows project maturity and versioning discipline
- **Profile README formula:** who you are + what you work with + featured projects + certifications + contact
- **Add topics/tags** to every repo: `gcp`, `terraform`, `infrastructure-as-code`, `cloud-engineer`
- **Always use `.gitignore`** — prevent `.tfstate`, `.tfvars`, keys, and IDE files from being committed
- **Never commit secrets** — use `.tfvars.example` pattern, check with `git log --all --full-history -S "password"`
- **Clean commit history matters** — rebase/squash messy commits before publishing
- **MIT licence** is standard for portfolio projects — include a `LICENSE` file

---

## Part 4 — Quiz (15 min)

**Q1.** Why should you create tagged releases (e.g., v1.0.0) for portfolio projects instead of just having a main branch?

<details><summary>Answer</summary>

Tagged releases demonstrate **professional software practices**: (1) **Versioning discipline** — you treat your project like production software, not a one-off script, (2) **Release documentation** — changelogs show what's included and what changed, (3) **Maturity signal** — it tells reviewers the project reached a stable, complete state, (4) **Reproducibility** — someone can checkout a specific version if needed. It also shows you understand **release management**, which is a key part of infrastructure engineering (Terraform module versioning, provider pinning, etc.).
</details>

**Q2.** Your commit history for a project looks like: "initial commit", "update", "fix", "more updates", "final", "actually final", "done". What should you do before publishing to GitHub?

<details><summary>Answer</summary>

Use **interactive rebase** (`git rebase -i --root`) to clean up the history. Options:
1. **Squash** all commits into one clean commit: `feat: initial release — production-grade VPC with Terraform`
2. Or **reword + squash** into 3-5 logical commits that tell a story: initial structure, core implementation, documentation, final polish

The goal is a commit history that a reviewer can read like a **story of how the project was built**, not a log of your messy development process. For portfolio projects, a single well-worded commit is perfectly acceptable.
</details>

**Q3.** What should a GitHub profile README include, and why is it different from a regular project README?

<details><summary>Answer</summary>

A **profile README** is about **you as an engineer**, not a specific project. It should include:
1. **Name + title** — "Cloud Infrastructure Engineer"
2. **Key skills/technologies** — positioned for the roles you're targeting
3. **Featured projects table** — links to your best work with one-line descriptions
4. **Certifications** — ACE, any others
5. **Contact information** — LinkedIn, email

It's different from a project README because it's **a personal landing page**, not technical documentation. Think of it as the "above the fold" section of your technical CV. Keep it scannable — a recruiter should understand who you are and what you do in 10 seconds.
</details>

**Q4.** You accidentally committed a `terraform.tfvars` file with your real GCP project ID and a service account key path. What should you do?

<details><summary>Answer</summary>

1. **Immediately** add `*.tfvars` and `!*.tfvars.example` to `.gitignore`
2. Remove the file from tracking: `git rm --cached terraform.tfvars`
3. Commit the removal: `git commit -m "fix: remove tfvars with real values, add to gitignore"`
4. **Critical:** If a service account key was committed, **revoke the key immediately** in GCP Console → IAM → Service Accounts → Keys, even if you remove it from Git — the key is in Git history forever unless you rewrite history
5. For history cleanup: `git filter-branch` or `BFG Repo Cleaner` to remove from all commits
6. Force push if already pushed: `git push --force` (destructive — be certain)
7. Add `.tfvars.example` with placeholder values as the safe alternative

Prevention: Always set up `.gitignore` **before** your first commit.
</details>
