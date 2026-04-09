# Day 135 — Terraform Interview Questions

> **Week 23 · Interview Prep** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Prepare for Terraform-specific interview questions covering state management, modules, drift detection, secrets handling, and CI/CD pipeline integration.

---

## Part 1 — Concept: Terraform Interview Landscape (30 min)

### What Interviewers Test

| Area | What They Want to Know | Difficulty |
|---|---|---|
| **State Management** | Do you understand remote state, locking, corruption recovery? | High |
| **Modules** | Can you write reusable code? Versioning? Source management? | Medium |
| **Workflow** | Do you know plan/apply, workspaces, environments? | Medium |
| **Drift** | Can you detect and handle configuration drift? | High |
| **Secrets** | How do you manage sensitive values safely? | High |
| **CI/CD** | Can you automate Terraform in a pipeline? | High |
| **Troubleshooting** | "Terraform plan shows unexpected changes" — can you debug? | High |
| **Best Practices** | Naming, structure, DRY principles, provider pinning? | Medium |

### Top Terraform Interview Questions

| # | Question | Category |
|---|---|---|
| 1 | What is Terraform state and why is it needed? | State |
| 2 | How do you handle state in a team environment? | State |
| 3 | The state file is corrupted. What do you do? | State |
| 4 | What's the difference between modules and workspaces? | Structure |
| 5 | How do you manage secrets in Terraform? | Security |
| 6 | `terraform plan` shows changes you didn't make. What's happening? | Troubleshooting |
| 7 | How do you handle drift between state and real infrastructure? | Drift |
| 8 | Describe your Terraform CI/CD pipeline | CI/CD |
| 9 | How do you structure a Terraform project for multiple environments? | Structure |
| 10 | What's the difference between `terraform import` and data sources? | Usage |
| 11 | How do you handle provider version updates safely? | Operations |
| 12 | When would you use `terraform taint` vs `terraform apply -replace`? | Usage |
| 13 | How do you test Terraform code? | Testing |
| 14 | What are Terraform provisioners and when should you use them? | Best Practices |
| 15 | Explain the Terraform dependency graph | Internals |

### Model Answers — Key Questions

**Q1: What is Terraform state and why is it needed?**

> "Terraform state is a JSON file (`terraform.tfstate`) that maps your Terraform configuration to real-world resources. It's needed because:
>
> 1. **Resource tracking** — Terraform needs to know which real resources correspond to which config blocks to update or destroy correctly
> 2. **Performance** — state caches resource attributes so Terraform doesn't need to query every resource via API on every plan
> 3. **Dependency resolution** — state records the dependency graph for correct ordering
>
> Without state, Terraform would create duplicate resources on every apply. It's the single source of truth for what Terraform manages."

**Q2: How do you handle state in a team environment?**

> "In a team, local state files are dangerous — multiple people could overwrite each other's changes. I'd use:
>
> **Remote backend (GCS):**
> ```hcl
> terraform {
>   backend "gcs" {
>     bucket = "my-project-tf-state"
>     prefix = "terraform/state"
>   }
> }
> ```
>
> **Key features:**
> - **Remote storage** — state in GCS, not on anyone's laptop
> - **State locking** — GCS backend supports locking to prevent concurrent modifications
> - **Versioning** — enable GCS bucket versioning to recover from state corruption
> - **Encryption** — GCS encrypts at rest by default; add CMEK for extra control
>
> From my Linux admin background, this is similar to using a central config management server rather than local config files on each admin's workstation."

**Q5: How do you manage secrets in Terraform?**

> "This is a critical security question. My approach:
>
> 1. **Never store secrets in `.tf` files or state in plain text** — state includes secret values
> 2. **Use `sensitive = true`** on variables and outputs to prevent display in plan/apply output
> 3. **Environment variables** for sensitive inputs: `TF_VAR_db_password`
> 4. **Secret Manager integration** — reference secrets from GCP Secret Manager using data sources
> 5. **Encrypted state backend** — GCS with bucket-level encryption
> 6. **`.gitignore`** — `*.tfvars` (use `*.tfvars.example` with placeholders)
>
> The reality is that Terraform state WILL contain secrets in plain text — this is a known limitation. That's why remote state with encryption and strict IAM on the state bucket is essential."

**Q6: `terraform plan` shows changes you didn't make. What's happening?**

> "This is drift detection in action. Common causes:
>
> 1. **Manual changes** — someone modified the resource via Console or gcloud (most common)
> 2. **Provider update** — new provider version reads or computes attributes differently
> 3. **API changes** — GCP API returns different defaults or normalises values
> 4. **Non-deterministic values** — timestamps, random IDs, or computed values
> 5. **Different user/credentials** — different permissions may result in different visible attributes
>
> **My debugging approach:**
> - `terraform plan` with `-detailed-exitcode` to see exactly what changed
> - `terraform state show <resource>` to compare state with plan output
> - Check GCP Console for the resource — was it modified manually?
> - Check `terraform version` and provider version — did either update?
>
> **Resolution:** If the manual change is correct, use `terraform apply` to align state with reality. If the config is correct, apply to revert the manual change. If it's a provider issue, pin the provider version."

**Q8: Describe your Terraform CI/CD pipeline.**

> "A typical Terraform CI/CD pipeline I'd set up:
>
> ```
> PR Created → terraform fmt → terraform validate → terraform plan → Manual approval → terraform apply
> ```
>
> **Stages:**
> 1. **Format check** (`terraform fmt -check`) — fails if code isn't formatted
> 2. **Validate** (`terraform validate`) — syntax and reference checks
> 3. **Plan** — generates plan, posts as PR comment for review
> 4. **Manual approval** — a human reviews the plan before apply
> 5. **Apply** — runs only on merge to main, after approval
>
> **Key principles:**
> - Never auto-apply without review — infrastructure changes need human eyes
> - Plan output in the PR so reviewers see exactly what will change
> - Use a service account with minimum required permissions
> - State locking prevents concurrent applies
> - Separate pipeline per environment (dev → staging → prod)"

---

## Part 2 — Hands-On Activity: Practice Terraform Answers (60 min)

### Exercise 1 — Write Model Answers (30 min)

Write answers for these 6 additional questions:

**Q3:** The state file is corrupted. What do you do?
- Hint: backup recovery, `terraform state pull/push`, GCS versioning

**Q4:** What's the difference between modules and workspaces?
- Hint: modules = reusable components, workspaces = separate state per environment

**Q7:** How do you handle drift between state and real infrastructure?
- Hint: `terraform refresh`, `terraform plan`, `terraform import`

**Q9:** How do you structure a Terraform project for multiple environments?
- Hint: directory per environment vs workspaces vs Terragrunt

**Q11:** How do you handle provider version updates safely?
- Hint: version constraints, lock files, test in dev first

**Q14:** What are Terraform provisioners and when should you use them?
- Hint: `local-exec`, `remote-exec`, why they're a last resort, prefer startup scripts

### Exercise 2 — Scenario Practice (20 min)

Practice these scenario questions aloud (5 min each):

1. "You run `terraform apply` and it fails halfway through — some resources were created, others weren't. What do you do?"
2. "A team member accidentally ran `terraform destroy` on the production state. How do you recover?"
3. "You need to rename a resource in Terraform without destroying and recreating it. How?"
4. "Your Terraform plan takes 10 minutes to run because of too many resources. How do you improve this?"

### Exercise 3 — Confidence Assessment (10 min)

| Topic | Confidence (1-5) | Notes |
|---|---|---|
| State management (remote, locking) | | |
| Module creation and versioning | | |
| Secrets handling | | |
| Drift detection and resolution | | |
| CI/CD pipeline design | | |
| Troubleshooting unexpected changes | | |
| `terraform import` usage | | |
| Provider version management | | |

---

## Part 3 — Revision: Key Takeaways (15 min)

- **State is Terraform's source of truth** — maps config to real resources, enables updates/destroys
- **Team state = remote backend (GCS)** with locking, versioning, and encryption
- **Secrets in Terraform are a known problem** — state stores them in plain text; mitigate with encrypted backends, environment variables, and Secret Manager
- **Unexpected plan changes = drift** — check for manual changes, provider updates, API normalisations
- **CI/CD pipeline:** fmt → validate → plan → manual approval → apply
- **Never auto-apply infrastructure** — always require human review of plan output
- **Modules vs workspaces:** modules = reusable components; workspaces = separate state
- **State corruption recovery:** GCS versioning, `terraform state pull/push`, partial disaster recovery
- **Provisioners are a last resort** — prefer startup scripts, custom images, or configuration management
- **Pin provider versions** — use `~>` constraints and test updates in dev first

---

## Part 4 — Quiz (15 min)

**Q1.** An interviewer asks: "Your team uses Terraform and someone made a change via the GCP Console. `terraform plan` now shows it wants to revert that change. What do you do?"

<details><summary>Answer</summary>

"This is a **configuration drift** scenario. I'd handle it based on which change is correct:

**If the console change is correct** (it was an intentional fix):
1. Update the Terraform config to match the console change
2. Run `terraform plan` — should now show no changes
3. Commit the config update with a meaningful message explaining the change

**If the Terraform config is correct** (console change was accidental):
1. Run `terraform apply` to revert the manual change
2. Communicate to the team that manual changes cause drift

**If you're unsure:**
1. Run `terraform plan` to see exactly what will change
2. Investigate with the person who made the console change
3. Decide which state is desired, then align config and state

**Prevention:** Establish a policy that all changes go through Terraform (no manual console changes). Implement drift detection as a scheduled job that runs `terraform plan` and alerts on any differences. This is an operational discipline issue as much as a technical one."
</details>

**Q2.** "How would you recover if the Terraform state file was accidentally deleted?"

<details><summary>Answer</summary>

"Recovery options, in order of preference:

1. **GCS bucket versioning** (best case) — if the state backend bucket has versioning enabled, restore the previous version from GCS. This is why I always enable versioning on state buckets.

2. **Remote state backup** — if you have state backups (e.g., `.terraform.tfstate.backup` locally or CI/CD artifacts), use `terraform state push` to restore.

3. **`terraform import`** (worst case) — if no backup exists, you need to re-import every resource:
   - List actual resources in GCP: `gcloud compute instances list`, etc.
   - Import each one: `terraform import google_compute_instance.vm projects/my-project/zones/europe-west2-a/instances/my-vm`
   - This is tedious for large projects (could be hundreds of imports)

4. **Recreate** — if the environment is dev/test, it may be faster to `terraform destroy` (if anything remains) and `terraform apply` from scratch.

**Prevention:** (1) Always enable GCS bucket versioning, (2) Restrict IAM on the state bucket — only the CI/CD service account should write, (3) Regular state backups, (4) Use object lifecycle rules to retain versions for 30+ days."
</details>

**Q3.** "What's your approach to structuring Terraform for dev, staging, and production environments?"

<details><summary>Answer</summary>

"I prefer the **directory-per-environment** approach over workspaces for production use:

```
terraform/
├── modules/           # Shared, reusable modules
│   ├── vpc/
│   ├── compute/
│   └── monitoring/
├── environments/
│   ├── dev/
│   │   ├── main.tf        # References shared modules
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── prod/
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars
```

**Why directories over workspaces:**
1. **Separate state files** per environment — no risk of accidentally applying prod changes to dev
2. **Different configurations** — prod might have more replicas, stricter firewall rules
3. **Independent apply cycles** — can update dev without touching prod
4. **Clearer in CI/CD** — each environment has its own pipeline stage

**Modules provide the DRY principle** — the VPC module is written once and parameterised per environment. This means the same architecture in dev, staging, and prod, just with different sizes and configurations."
</details>

**Q4.** "In a Terraform CI/CD pipeline, why should `terraform apply` never run automatically without human approval?"

<details><summary>Answer</summary>

"Infrastructure changes are **high-impact and hard to reverse**. Automatic apply risks:

1. **Accidental destruction** — a misconfigured resource change could destroy a production database. `terraform plan` showing 'destroy' is a critical signal that needs human review.
2. **Unexpected scope** — a change that looks small in code might affect dozens of resources due to dependency chains. Only a human reviewing the plan output can assess if this is expected.
3. **Blast radius** — unlike application deployments that can be rolled back, infrastructure changes (especially deletions) may lose data permanently.
4. **Security review** — firewall rule changes, IAM modifications, and network changes need security review before application.
5. **Compliance** — many organisations require approval workflows for infrastructure changes as part of change management.

**My pipeline design:** Auto-run `fmt`, `validate`, and `plan`. Post the plan output as a PR comment. Require manual approval (code review + explicit approval step) before `apply` runs. For production, require two approvers.

The only exception might be dev environments where rapid iteration matters more, but even there, having plan output visible helps catch mistakes early."
</details>
