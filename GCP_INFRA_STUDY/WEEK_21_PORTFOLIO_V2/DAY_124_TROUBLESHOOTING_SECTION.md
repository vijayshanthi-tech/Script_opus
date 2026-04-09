# Day 124 — Add Troubleshooting Section

> **Week 21 · Portfolio v2** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Document common issues, error-to-fix mappings, and debugging thought processes for each project — demonstrating real-world experience that employers value highly.

---

## Part 1 — Concept: Troubleshooting as a Career Signal (30 min)

### Why Troubleshooting Documentation Matters

A troubleshooting section in your portfolio project tells an employer three things:
1. **You actually ran this project** — you hit real problems, not just copy-pasted configs
2. **You can debug systematically** — you know how to isolate and fix issues
3. **You think about other users** — you document for the next person (a team player signal)

Most portfolio projects on GitHub lack troubleshooting docs. Including one immediately sets you apart.

### The Error → Fix Mapping Format

| Error / Symptom | Cause | Fix | Prevention |
|---|---|---|---|
| `Error 403: Required permission 'compute.instances.create'` | Service account lacks Compute Admin role | Grant `roles/compute.admin` to the SA | Use `terraform plan` to catch permission issues before `apply` |
| `terraform init` fails with backend error | GCS bucket doesn't exist or wrong name | Create bucket first or check `backend.tf` bucket name | Add bucket creation to prerequisites |
| VM created but can't SSH | Firewall rule missing for port 22 | Add firewall rule allowing TCP:22 from IAP range `35.235.240.0/20` | Include IAP firewall rule in base Terraform |
| Monitoring agent not reporting | Ops Agent not installed or not running | SSH to VM, check `sudo systemctl status google-cloud-ops-agent` | Add startup script to install agent automatically |

### Troubleshooting Section Template

```markdown
## Troubleshooting

### Common Issues

#### 1. Permission Denied on Terraform Apply

**Symptom:** `Error 403: Required 'compute.instances.create' permission`

**Cause:** Your authenticated account or service account lacks the necessary IAM role.

**Fix:**
```bash
# Check current authenticated account
gcloud auth list

# Grant required role (run as project owner)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:your-email@example.com" \
  --role="roles/compute.admin"
```

**Prevention:** Always run `terraform plan` first to catch permission issues before `apply`.

---

#### 2. VM Created But Cannot SSH

**Symptom:** `ssh: connect to host <IP> port 22: Connection timed out`

**Cause:** Missing firewall rule for SSH, or trying to SSH to a VM with no external IP.

**Fix:**
- For IAP-based SSH (recommended): Ensure firewall rule allows TCP:22 from `35.235.240.0/20`
- For direct SSH: Ensure firewall rule allows TCP:22 from your IP

**Debugging steps:**
1. Check if VM is running: `gcloud compute instances describe <vm-name> --zone=europe-west2-a`
2. Check firewall rules: `gcloud compute firewall-rules list --filter="network:<vpc-name>"`
3. Try IAP tunnel: `gcloud compute ssh <vm-name> --zone=europe-west2-a --tunnel-through-iap`
```

### FAQ Format (Alternative)

```markdown
## FAQ

**Q: Terraform plan works but apply fails with quota error. What do I do?**

A: Check your quota in the GCP Console under IAM & Admin > Quotas. 
For `europe-west2`, common limits are 8 CPUs and 10 external IPs 
for free-tier accounts. Either request a quota increase or reduce 
the number/size of VMs in your configuration.

**Q: The monitoring dashboard shows "No data" for all charts.**

A: This usually means the Ops Agent isn't installed or running. 
SSH into your VM and run:
```bash
sudo systemctl status google-cloud-ops-agent
sudo journalctl -u google-cloud-ops-agent -f
```
If not installed, follow the agent installation in the Quick Start section.
```

### Documenting Your Debugging Thought Process

This is the most impressive part of a troubleshooting section — it shows **how you think**, not just what you did.

**Debugging Process Template:**

```markdown
### How I Debugged: Alert Not Firing

**Expected behaviour:** CPU alert should fire when load exceeds 80%.

**Actual behaviour:** Stress test running, CPU at 95%, no alert.

**Debugging steps:**
1. ✅ Verified alerting policy exists: `gcloud alpha monitoring policies list`
2. ✅ Verified notification channel is configured and verified
3. ✅ Checked metric in Metrics Explorer — CPU data IS being reported
4. ❌ Checked alignment period — was set to 10 minutes, test only ran for 3 minutes
5. 🔧 **Fix:** Reduced alignment period to 1 minute for testing
6. ✅ Re-ran stress test — alert fired after ~90 seconds

**Root cause:** The alignment period was too long relative to the test duration.

**Lesson:** Always consider the metric aggregation window when testing alerts.
```

### Categories of Issues to Document

| Category | Examples |
|---|---|
| **Authentication & IAM** | Wrong account, missing roles, SA key expired |
| **Networking** | Firewall blocking, no external IP, DNS not resolving |
| **Terraform** | State lock, provider version mismatch, dependency cycle |
| **Monitoring** | Agent not reporting, wrong metric name, alignment period |
| **Cost/Quota** | Quota exceeded, unexpected charges, resource limits |
| **Region-specific** | Service not available in europe-west2, capacity issues |

---

## Part 2 — Hands-On Activity: Build Troubleshooting Docs (60 min)

### Exercise 1 — Recall Issues You Encountered (15 min)

For each of your top 3 projects, list every issue you remember encountering. Check your terminal history, notes, and Git commits for clues.

**Template per project:**

```markdown
## Project: [Name]

### Issues I Encountered

1. **Issue:** [What went wrong]
   **When:** [During which step]
   **Fix:** [What I did]
   **Time to resolve:** [Estimate]

2. **Issue:** ...
```

Aim for at least 3-5 issues per project. Common areas to jog your memory:
- First `terraform init` / `terraform apply`
- First SSH attempt
- Setting up monitoring agent
- Firewall rules not working as expected
- IAM permissions
- API not enabled

### Exercise 2 — Write Error→Fix Mappings (20 min)

Convert your issue list into structured error→fix mappings. For each issue:

1. Write the exact error message or symptom (copy from terminal if possible)
2. Explain the cause in one sentence
3. Provide the fix with exact commands
4. Add a prevention tip

**Add to each project's README under a `## Troubleshooting` section.**

### Exercise 3 — Document One Debugging Story (15 min)

Pick the most interesting debugging experience across your projects and write it up as a full debugging narrative:

1. What you expected
2. What actually happened
3. Your step-by-step debugging process (what you checked, in order)
4. What the root cause turned out to be
5. What you learned

This is **interview gold** — you can reference this story when asked "tell me about a time you debugged a complex issue."

### Exercise 4 — Cross-Reference Verification (10 min)

Review your troubleshooting sections and verify:

- [ ] Every error message is accurate (not paraphrased)
- [ ] Every fix command actually works (test if possible)
- [ ] No sensitive data in error messages or fix commands
- [ ] Prevention tips are actionable, not generic
- [ ] At least one debugging narrative exists across your projects

---

## Part 3 — Revision: Key Takeaways (15 min)

- **Troubleshooting docs prove you ran the project for real** — not just wrote config files
- **Error → Fix mappings** should include: exact symptom, cause, fix command, and prevention
- **The debugging narrative is the most valuable part** — it shows how you think, not just what you know
- **Use the debugging template:** expected → actual → steps tried → root cause → lesson learned
- **Common GCP troubleshooting categories:** auth/IAM, networking, Terraform state, monitoring agents, quotas
- **FAQ format works well** for quick reference; narrative format works for complex issues
- **Include prevention tips** — this shows you think about how to avoid problems, not just fix them
- **Copy exact error messages** — don't paraphrase; exact messages are searchable and credible
- **Test your fix commands** — nothing undermines credibility like a documented fix that doesn't work
- **This content is interview preparation** — every issue you document is a story you can tell in interviews

---

## Part 4 — Quiz (15 min)

**Q1.** Why does a troubleshooting section in a portfolio project impress employers more than a perfect, error-free README?

<details><summary>Answer</summary>

A perfect README with no troubleshooting suggests the project was either **trivial, theoretical, or copied**. A troubleshooting section with real error messages and fixes proves you **actually built and ran the project**, encountered real challenges, and solved them. It demonstrates three skills employers value: (1) **debugging ability** — you can isolate and fix problems, (2) **documentation discipline** — you capture knowledge for the team, and (3) **honesty/transparency** — you acknowledge difficulties rather than hiding them. In real engineering roles, debugging is 40-60% of the job.
</details>

**Q2.** You encountered a "VM can't SSH" issue during your project. Write the troubleshooting entry in error→fix format.

<details><summary>Answer</summary>

**Symptom:** `ssh: connect to host 34.89.x.x port 22: Connection timed out` when running `gcloud compute ssh vm-1 --zone=europe-west2-a`

**Cause:** Missing firewall rule to allow SSH traffic. The VPC was created with no default rules, and no explicit rule was added for port 22.

**Fix:**
```bash
gcloud compute firewall-rules create allow-ssh-iap \
  --network=my-vpc \
  --allow=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --target-tags=allow-ssh \
  --description="Allow SSH via IAP"
```
Then add the `allow-ssh` network tag to your VM.

**Prevention:** Include IAP SSH firewall rule as a standard part of your VPC Terraform module so every VPC automatically allows IAP-based SSH.
</details>

**Q3.** What's the difference between an "error→fix mapping" and a "debugging narrative," and when should you use each?

<details><summary>Answer</summary>

An **error→fix mapping** is a quick-reference entry: symptom, cause, fix, prevention — designed for someone who hits the same error and needs a fast answer. Use it for **common, straightforward issues** like missing permissions, wrong config values, or missing firewall rules.

A **debugging narrative** is a detailed story: expected behaviour, actual behaviour, step-by-step investigation, root cause, and lesson learned. Use it for **complex, non-obvious issues** where the fix wasn't immediately clear and you had to investigate multiple possibilities. Debugging narratives are more valuable for interviews because they showcase your **problem-solving methodology**.

A good troubleshooting section has both: 4-6 error→fix mappings for common issues, plus 1-2 debugging narratives for interesting problems.
</details>

**Q4.** You're documenting a troubleshooting entry and the error message includes your GCP project ID, your email, and a service account key path. What should you redact and what can you keep?

<details><summary>Answer</summary>

- **Keep:** GCP project ID — it's not sensitive and adds authenticity (you can use a non-production project)
- **Redact:** Personal email address — replace with `your-email@example.com`
- **Redact:** Service account key file path — replace with `/path/to/your-sa-key.json`
- **Also redact if present:** Billing account IDs, OAuth tokens, API keys, IP addresses of production systems, internal hostnames

The general rule: keep information that proves the error is real but redact anything that could be used for identity theft, account access, or reconnaissance. When in doubt, redact and add a note like `(redacted)`.
</details>
