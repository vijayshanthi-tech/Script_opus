# Day 137 — IAM Troubleshooting Scenarios

> **Week 23 · Interview Prep** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Prepare for IAM-focused interview scenarios — "user can't access a resource", "service account permission denied", "least privilege audit" — with systematic debugging methodology.

---

## Part 1 — Concept: IAM Interview Strategy (30 min)

### Why IAM Questions Are Common

IAM is the **#1 security control** in cloud environments. Misconfigurations cause breaches. Every Cloud/Infra Engineer interview includes IAM questions because:
- It's the first thing you configure in any GCP project
- It's the most common source of access issues
- Understanding it deeply shows security maturity
- Your RHDS/LDAP background gives you unique insight

### IAM Debugging Framework

```
1. WHO    → Which identity? (user, SA, group)
2. WHAT   → Which resource? (project, VM, bucket)
3. ROLE   → Which permission? (what are they trying to do?)
4. WHERE  → At which level? (org, folder, project, resource)
5. HOW    → Direct binding? Group membership? Policy inheritance?
```

### Top IAM Interview Scenarios

| # | Scenario | Complexity |
|---|---|---|
| 1 | "User can't access a Compute Engine VM" | Medium |
| 2 | "Service account gets 403 Permission Denied" | Medium |
| 3 | "How would you audit for least privilege?" | Hard |
| 4 | "A user has more permissions than expected — how?" | Hard |
| 5 | "How do you handle service account key management?" | Medium |
| 6 | "Design an IAM structure for a multi-team project" | Hard |
| 7 | "What's the difference between basic, predefined, and custom roles?" | Easy |
| 8 | "Explain Workload Identity Federation" | Medium |

### Scenario 1: "User Can't Access a Compute Engine VM"

**Model Answer:**

> "I'd troubleshoot systematically using the IAM debugging framework:
>
> **Step 1 — Identify the exact error:**
> What's the error message? `Permission denied` or `404 Not Found`? The error tells me if it's an IAM issue or a resource existence issue.
>
> **Step 2 — Check the user's effective permissions:**
> Use the IAM Policy Troubleshooter in GCP Console, or:
> ```
> gcloud asset analyze-iam-policy \
>   --organization=ORG_ID \
>   --identity=user:email@example.com \
>   --full-resource-name=//compute.googleapis.com/projects/PROJECT/zones/ZONE/instances/VM_NAME
> ```
>
> **Step 3 — Check where permissions are granted:**
> IAM policies can be set at org, folder, project, or resource level. Check:
> - Project-level: `gcloud projects get-iam-policy PROJECT_ID`
> - Is the user a direct member or in a group?
>
> **Step 4 — Check what role they need:**
> For SSH access: `roles/compute.osLogin` or `roles/compute.osAdminLogin`
> For instance management: `roles/compute.instanceAdmin`
> For viewing: `roles/compute.viewer`
>
> **Step 5 — Check for deny policies:**
> GCP now has IAM deny policies that override allow policies.
>
> **Common causes:** Wrong role (viewer instead of admin), role granted at wrong level, user not in the expected group, or OS Login not enabled on the VM."

### Scenario 2: "Service Account Gets 403 Permission Denied"

**Model Answer:**

> "Service account permission issues are the most common IAM problem I encounter. My debugging steps:
>
> **Step 1 — Verify which service account is being used:**
> The VM might be using the default compute service account instead of the custom one you assigned.
> `gcloud compute instances describe VM_NAME --zone=europe-west2-a --format='get(serviceAccounts.email)'`
>
> **Step 2 — Check the SA's IAM roles:**
> `gcloud projects get-iam-policy PROJECT_ID --flatten='bindings[].members' --filter='bindings.members:serviceAccount:SA_EMAIL'`
>
> **Step 3 — Verify the specific permission needed:**
> A 403 on `storage.objects.get` means the SA needs `roles/storage.objectViewer` or higher on the bucket.
>
> **Step 4 — Check scope vs IAM:**
> Compute Engine VMs have OAuth scopes that can further restrict permissions. Even with the right IAM role, if the scope doesn't include the API, it's denied. Check:
> `gcloud compute instances describe VM_NAME --format='get(serviceAccounts.scopes)'`
> Best practice: use `cloud-platform` scope and control everything through IAM.
>
> **Step 5 — Check resource-level permissions:**
> Some resources (like GCS buckets) can have their own IAM policies separate from project-level.
>
> **Most common cause:** Using the default compute service account (which has Editor role but wrong scopes) or forgetting to grant the role on the specific resource."

### Scenario 3: "How Would You Audit for Least Privilege?"

**Model Answer:**

> "Least privilege audit is about ensuring identities have only the permissions they actually need. My approach:
>
> **1. Inventory all IAM bindings:**
> ```
> gcloud asset search-all-iam-policies --scope=projects/PROJECT_ID
> ```
>
> **2. Identify overprivileged accounts:**
> - Any identity with `roles/owner` or `roles/editor` — these are almost never appropriate for production
> - Service accounts with `roles/editor` (the default) — replace with specific predefined roles
> - Users with roles they don't actively use
>
> **3. Use IAM Recommender:**
> GCP's IAM Recommender analyses actual permission usage and suggests right-sized roles:
> ```
> gcloud recommender recommendations list \
>   --project=PROJECT_ID \
>   --recommender=google.iam.policy.Recommender \
>   --location=global
> ```
>
> **4. Review service account keys:**
> - Are there keys older than 90 days? Rotate or delete
> - Are there unused service accounts? Disable them
>
> **5. Implement ongoing governance:**
> - Quarterly access reviews
> - Alerts on role grants (Cloud Audit Logs → Log-based alerts)
> - Policy constraints to prevent `roles/owner` assignment
>
> Drawing from my LDAP experience: this is the IAM equivalent of the quarterly access reviews we did for directory services — removing old accounts, auditing group memberships, and ensuring people only had the access they needed."

### Bridging LDAP to GCP IAM

| LDAP Concept | GCP IAM Equivalent |
|---|---|
| LDAP user account | Google identity (user or SA) |
| LDAP groups | Google Groups for IAM binding |
| OUs (Organisational Units) | GCP folders in the resource hierarchy |
| Access Control Lists (ACIs) | IAM policies (allow + deny bindings) |
| LDAP replication | IAM policy propagation (global, near-instant) |
| Directory admin | Organization Admin / Security Admin |
| Bind DN permissions | Service account roles |
| LDAP audit log | Cloud Audit Logs |

---

## Part 2 — Hands-On Activity: Practice IAM Scenarios (60 min)

### Exercise 1 — Write Model Answers (30 min)

Write answers for these 4 additional scenarios:

**Scenario 4:** "A user seems to have more permissions than you explicitly granted. How do you investigate?"
- Hint: group membership inheritance, resource hierarchy, conditional bindings

**Scenario 5:** "How do you handle service account key management?"
- Hint: avoid keys when possible (Workload Identity), rotation, expiry, alternative authentication

**Scenario 6:** "Design an IAM structure for a project where 3 teams need different access levels"
- Hint: Google Groups, predefined roles, resource hierarchy, separation of duties

**Scenario 8:** "Explain Workload Identity Federation and when you'd use it"
- Hint: keyless authentication, external IdP, GKE Workload Identity, CI/CD pipelines

### Exercise 2 — Rapid-Fire Practice (20 min)

Answer these quick questions aloud (2 minutes each):

1. What's the difference between `roles/viewer`, `roles/editor`, and `roles/owner`?
2. When would you create a custom role vs use a predefined role?
3. What is a service account, and how is it different from a user account?
4. What are IAM conditions, and give an example of when you'd use one?
5. How does IAM inheritance work in the GCP resource hierarchy?
6. What's the most dangerous IAM misconfiguration you've seen (or can imagine)?
7. How do you grant temporary access to a resource?
8. Explain the principle of least privilege in your own words
9. What's a deny policy and when would you use one?
10. How does your LDAP experience relate to cloud IAM?

### Exercise 3 — Confidence Assessment (10 min)

| Topic | Confidence (1-5) | Notes |
|---|---|---|
| IAM policy troubleshooting | | |
| Service account management | | |
| Resource hierarchy / inheritance | | |
| Least privilege implementation | | |
| Custom roles | | |
| Workload Identity | | |
| LDAP-to-IAM bridging | | |
| IAM Recommender | | |

---

## Part 3 — Revision: Key Takeaways (15 min)

- **IAM debugging framework:** WHO → WHAT → ROLE → WHERE → HOW
- **Most common SA issue:** using default compute SA with wrong scopes instead of custom SA with right IAM roles
- **Policy Troubleshooter** is your best friend for "user can't access X" scenarios
- **Least privilege audit:** inventory bindings, remove Editor/Owner, use IAM Recommender, review SA keys
- **OAuth scopes ≠ IAM roles** — scopes restrict further; best practice is `cloud-platform` scope + IAM-only control
- **IAM inheritance flows down:** org → folder → project → resource. Can't revoke inherited roles at a lower level (use deny policies)
- **Bridge your LDAP experience:** LDAP groups = Google Groups, OUs = folders, ACIs = IAM policies
- **Service account key management:** avoid keys → use Workload Identity, rotate if keys required, alert on key creation
- **Deny policies override allow** — new GCP feature for hard security boundaries
- **Your 3 years of LDAP experience is IAM experience** — make this connection explicit in interviews

---

## Part 4 — Quiz (15 min)

**Q1.** An interviewer asks: "A developer says they can't access a Cloud Storage bucket from their VM. Walk me through your debugging."

<details><summary>Answer</summary>

"I'd debug in this order:

1. **Get the exact error:** Is it 403 Forbidden or 404 Not Found? 403 = permission denied. 404 = wrong bucket name or doesn't exist.

2. **Check which service account the VM uses:**
   `gcloud compute instances describe vm-name --zone=europe-west2-a --format='get(serviceAccounts[0].email)'`
   Common issue: VM is using the default compute SA, not a custom one.

3. **Check the SA's IAM roles on the bucket:**
   `gsutil iam get gs://bucket-name` — is the SA listed with an appropriate role (objectViewer, objectCreator, etc.)?

4. **Check OAuth scopes on the VM:**
   `gcloud compute instances describe vm-name --format='get(serviceAccounts[0].scopes)'`
   If the VM has `devstorage.read_only` scope but the app needs to write, it'll fail. Best practice: use `cloud-platform` scope.

5. **Check bucket-level vs project-level IAM:**
   The role might be granted at project level but the bucket has uniform IAM that overrides it, or vice versa.

6. **Check for org-level deny policies:**
   A deny policy at the org or folder level could block access regardless of allow policies.

**Most likely causes:** (a) Wrong service account, (b) Missing role on the specific bucket, (c) OAuth scope too restrictive."
</details>

**Q2.** "How does your LDAP experience relate to cloud IAM management?" How do you answer this?

<details><summary>Answer</summary>

"The core principles are identical — I managed identity and access at scale using LDAP, and those concepts map directly to cloud IAM:

- **LDAP users/groups** → **GCP identities and Google Groups.** I provisioned 5,000+ user accounts and managed group-based access — the same pattern used for IAM bindings through Google Groups.
- **LDAP ACIs (Access Control Instructions)** → **IAM policies.** Both define who can do what to which resources.
- **Organisational Units** → **GCP resource hierarchy (org/folder/project).** Both use hierarchical structures for policy inheritance.
- **Audit and compliance** → **Cloud Audit Logs + IAM Recommender.** I ran quarterly access reviews in LDAP; the same discipline applies to IAM.
- **Principle of least privilege** → **Same concept, different tools.** In LDAP, I restricted access to specific directory subtrees. In GCP, I use predefined roles at the most specific resource level.

The main difference is scale and automation. In LDAP, policy changes propagated via replication. In GCP, IAM changes are global and near-instant, but the governance challenges — stale accounts, over-provisioned access, audit requirements — are exactly the same."
</details>

**Q3.** "You're asked to ensure all service accounts in a project follow least privilege. What's your plan?"

<details><summary>Answer</summary>

"A structured approach in 4 phases:

**Phase 1 — Inventory (Week 1):**
- List all service accounts: `gcloud iam service-accounts list`
- For each SA, identify: what roles it has, where, and whether it has keys
- Flag any SA with `roles/editor` or `roles/owner` as high-priority

**Phase 2 — Analyse Usage (Week 2-3):**
- Use **IAM Recommender** to see which permissions each SA actually uses vs what it has
- Check **Cloud Audit Logs** for SA activity — SAs with no activity in 90 days should be investigated
- Identify SAs with user-managed keys — plan to migrate to Workload Identity where possible

**Phase 3 — Right-Size (Week 3-4):**
- Replace Editor/Owner with specific predefined roles based on Recommender suggestions
- Create custom roles if needed for SAs that need a specific subset of permissions
- Implement gradually: dev first, then staging, then prod — monitoring for breakage

**Phase 4 — Governance (Ongoing):**
- Alert on new role grants: Cloud Audit Logs → alert on `SetIamPolicy` events
- Quarterly review of SA permissions using IAM Recommender
- Policy constraint: deny `roles/editor` and `roles/owner` at the org level for SAs
- Document each SA's purpose and required permissions"
</details>

**Q4.** When would you create a custom IAM role versus using a predefined role?

<details><summary>Answer</summary>

"**Use predefined roles** in most cases — they're maintained by Google, tested, and cover common access patterns. Examples: `roles/compute.instanceAdmin`, `roles/storage.objectViewer`.

**Create a custom role** when:
1. **Predefined role is too broad** — you need a subset of permissions. Example: a CI/CD SA needs `compute.instances.start` and `compute.instances.stop` but NOT `compute.instances.delete`. No predefined role offers exactly this.
2. **Compliance requirement** — audit requires you to grant exactly the permissions needed, no more
3. **Cross-service combination** — you need 2-3 permissions from different services that no single predefined role covers

**When NOT to create custom roles:**
- Don't create one per team — use Google Groups with predefined roles instead
- Don't create one that mirrors an existing predefined role
- Consider maintenance: custom roles need updating when APIs change; predefined roles update automatically

**Best practice:** Start with predefined roles. Use IAM Recommender to identify if a role is too broad. Only create a custom role when the data shows the predefined role grants significantly more permissions than needed AND the resource is security-sensitive."
</details>
