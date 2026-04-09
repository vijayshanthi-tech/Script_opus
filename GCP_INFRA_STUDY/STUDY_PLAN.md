# GCP Infrastructure Engineer — 24-Week Study Plan

## Your Profile Summary

| Attribute | Detail |
|---|---|
| Background | 6 years Linux infra, 3 years RHDS LDAP |
| Certification | Google Cloud Associate Cloud Engineer |
| Target Role | GCP Infrastructure / Cloud Engineer |
| Daily Time | 2 hours |
| Learning Mode | 100% self-learning |

---

## How Each Day Is Structured (2 Hours)

| Block | Duration | Activity |
|---|---|---|
| Concept | 30 min | Read docs / watch focused video |
| Hands-On | 60 min | Lab / code / GCP console practice |
| Revision | 15 min | Review revision sheet, key commands |
| Quiz | 15 min | Self-test with interview questions |

---

## WEEK 1 — Compute Engine Basics

**Goal:** Understand VM components, SSH, disks, snapshots, and Linux hardening on GCP.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 1 | Mon | Server basics, SSH keys, OS Login overview | Docs: OS Login / SSH | Create SSH key pair, restrict SSH | SSH safe + OS login notes |
| 2 | Tue | Disks & snapshots | Docs: Persistent Disk, Snapshots | Snapshot disk, restore new disk | Snapshot proof + steps |
| 3 | Wed | Compute Engine VM components | Skills Boost: Create a VM / Docs: Compute Engine | Create Linux VM + SSH via Cloud Shell | SSH proof + VM config notes |
| 4 | Thu | (Review + consolidate) | Previous docs | Review all concepts, fill gaps | Consolidated notes |
| 5 | Fri | Linux baseline hardening | CIS basics + your runbook | Patch VM, create non-root admin, disable services | Commands + before/after |
| 6 | Sat | **PROJECT: Secure VM Baseline** | Your build + Docs reference | End-to-end build + short README | README + screenshots/diagram |

---

## WEEK 2 — Networking: VPC Fundamentals

**Goal:** Master VPC, subnets, CIDR, firewall rules, routes, and Cloud NAT.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 7 | Mon | VPC, subnets, CIDR, routes | Docs: VPC overview | Create custom VPC + subnet | Diagram + rationale |
| 8 | Tue | Firewall rules (ingress/egress) + tags | Docs: Firewall rules | Allow SSH only from your IP / controlled source | Rule config + rationale |
| 9 | Wed | Private vs public IP, internal connectivity | Docs: IP addresses | Create 2 VMs; test internal ping/SSH | Connectivity proof |
| 10 | Thu | Routes deep dive | Docs: Routes | Inspect routes; explain routing | 5-bullet route summary |
| 11 | Fri | NAT concept (high-level) | Docs: Cloud NAT (read) | Write how-to enable internet without public IP | 1-page summary |
| 12 | Sat | **PROJECT: Secure VPC + 2-Tier VM Setup** | Your build | VPC+firewall+2 VMs + internal comms | README + architecture sketch |

---

## WEEK 3 — Monitoring & Logging

**Goal:** Build observability skills with Cloud Logging, Monitoring, Alerting, and Ops Agent.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 13 | Mon | Cloud Logging basics; queries | Docs: Cloud Logging | Generate syslog entry, find in Logs Explorer | README + screenshot |
| 14 | Tue | Cloud Monitoring metrics + dashboards | Docs: Cloud Monitoring | Create dashboard for CPU+disk | Dashboard + screenshot |
| 15 | Wed | Alerting policies | Docs: Alerting | Create CPU alert | Alert config + notes |
| 16 | Thu | Ops Agent / VM insights | Docs: Ops Agent | Install agent; verify metrics/logs | Before/after note |
| 17 | Fri | Health check scripting | Your scripts | Create health-check script + sample run | Script + output |
| 18 | Sat | **PROJECT: Monitoring Pack** | Your build | Dashboard+alerting+logs query pack | README + scripts |

---

## WEEK 4 — Terraform Basics

**Goal:** Learn Terraform fundamentals — lifecycle, variables, state, modules, and VPC provisioning.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 19 | Mon | Terraform lifecycle | HashiCorp: Terraform basics | Provision 1 VM via Terraform | Proof + tf apply proof |
| 20 | Tue | Variables + outputs | Terraform docs | Parameterize VM; add outputs | variables.tf + outputs.tf |
| 21 | Wed | Terraform VPC + Firewall | Terraform provider docs (GCP) | VPC+subnet+firewall via TF | TF repo structure |
| 22 | Thu | State + drift | Terraform docs: state | Introduce drift; observe plan | Drift note + fix |
| 23 | Fri | Modules (basic) | Terraform docs: modules | Create VM module and call it | module/vm created |
| 24 | Sat | **PROJECT: Terraform Landing Zone Lite** | Your build | VPC+subnet+firewall+VM module | GitHub ready README |

---

## WEEK 5 — Terraform Networking Module

**Goal:** Build a reusable Terraform module for VPC, subnets, firewall rules, and routes.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 25 | Mon | VPC module (inputs/outputs) | HashiCorp + Terraform Docs (Google) | Hands-on: VPC module (inputs/outputs) | Proof + notes |
| 26 | Tue | Subnets patterns (multi-subnet) | HashiCorp + Terraform Docs | Hands-on: Subnets patterns (multi-subnet) | Proof + notes |
| 27 | Wed | Firewall rule patterns (least privilege) | HashiCorp + Terraform Docs (Google) | Hands-on: Firewall rule patterns (least privilege) | Proof + notes |
| 28 | Thu | Routes via Terraform | HashiCorp + Terraform Docs (Google) | Hands-on: Routes via Terraform | Proof + notes |
| 29 | Fri | Naming/labels/tags standards | HashiCorp + Terraform Docs (Google) | Hands-on: Naming/labels/tags standards | Proof + notes |
| 30 | Sat | **PROJECT: Reusable Network Module** | HashiCorp + Terraform Docs | Build end-to-end: Reusable Network Module | README + screenshots/diagram |

---

## WEEK 6 — Storage & Backup

**Goal:** Master Cloud Storage security, VM backup strategies, image creation, and restore procedures.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 31 | Mon | Cloud Storage basics + security | Skills Boost + Cloud Docs | Hands-on: Cloud Storage basics + security | Proof + notes |
| 32 | Tue | Lifecycle + versioning | Skills Boost + Cloud Docs | Hands-on: Lifecycle + versioning | Proof + notes |
| 33 | Wed | VM backup strategy (snapshots scheduling) | Skills Boost + Cloud Docs | Hands-on: VM backup strategy (snapshots) | Proof + notes |
| 34 | Thu | Image creation + cloning | Skills Boost + Cloud Docs | Hands-on: Image creation + cloning | Proof + notes |
| 35 | Fri | Backup/restore runbook | Skills Boost + Cloud Docs | Hands-on: Backup/restore runbook | Proof + notes |
| 36 | Sat | **PROJECT: Backup & Restore Lab** | Your build + Cloud Docs | Build end-to-end: Backup & Restore Lab | README + screenshots/diagram |

---

## WEEK 7 — Automation & Ops

**Goal:** Automate VM setup with startup scripts, package management, monitoring, and log rotation.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 37 | Mon | Startup scripts / cloud-init | Skills Boost + Cloud Docs | Hands-on: Startup scripts / cloud-init | Proof + notes |
| 38 | Tue | Automated package install + hardening | Skills Boost + Cloud Docs | Hands-on: Automated package install + hardening | Proof + notes |
| 39 | Wed | Monitoring script + cron | Skills Boost + Cloud Docs | Hands-on: Monitoring script + cron | Proof + notes |
| 40 | Thu | Log rotation/housekeeping automation | Skills Boost + Cloud Docs | Hands-on: Log rotation/housekeeping | Proof + notes |
| 41 | Fri | Ops runbook: VM baseline | Skills Boost + Cloud Docs | Hands-on: Ops runbook: VM baseline | Proof + notes |
| 42 | Sat | **PROJECT: Golden VM Baseline Automation** | Skills Boost + Cloud Docs | Build end-to-end: Golden VM baseline | README + screenshots/diagram |

---

## WEEK 8 — Portfolio & Review (Checkpoint 1)

**Goal:** Clean up all work, improve documentation, rebuild from scratch, and prepare for mock interview.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 43 | Mon | Clean Terraform repo structure | HashiCorp + Terraform Docs | Hands-on: Clean Terraform repo structure | Proof + notes |
| 44 | Tue | Improve READMEs + diagrams | Cloud Docs + your scripts | Hands-on: Improve READMEs + diagrams | Proof + notes |
| 45 | Wed | Add troubleshooting notes | Skills Boost + Cloud Docs | Hands-on: Add troubleshooting notes | Proof + notes |
| 46 | Thu | Rebuild from scratch (timebox) | Skills Boost + Cloud Docs | Hands-on: Rebuild from scratch (timebox) | Proof + notes |
| 47 | Fri | Mock interview: explain projects | Skills Boost + Cloud Docs | Hands-on: Mock interview: explain projects | Proof + notes |
| 48 | Sat | **PROJECT: Publish Portfolio v1** | Skills Boost + Cloud Docs | Build end-to-end: Publish Portfolio v1 | README + screenshots/diagram |

---

## WEEK 9 — Managed Instance Groups & Autoscaling

**Goal:** Learn MIG concepts, autoscaling, Terraform MIG, health checks, and rolling updates.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 49 | Mon | MIG concepts | Cloud Docs + your scripts | Hands-on: MIG concepts | Proof + notes |
| 50 | Tue | Create MIG + autoscaling (console) | Cloud Docs + your Linux scripts | Hands-on: Create MIG + autoscaling (console) | Proof + notes |
| 51 | Wed | Terraform MIG (basic) | HashiCorp + Terraform Docs (Google) | Hands-on: Terraform MIG (basic) | Proof + notes |
| 52 | Thu | Health checks + rolling updates | Cloud Docs + your Linux scripts | Hands-on: Health checks + rolling updates | Proof + notes |
| 53 | Fri | Scaling strategy notes | Cloud Docs + your Linux scripts | Hands-on: Scaling strategy notes | Proof + notes |
| 54 | Sat | **PROJECT: Scalable VM Group** | Cloud Docs + your Linux scripts | Build end-to-end: Scalable VM group | README + screenshots/diagram |

---

## WEEK 10 — Load Balancing

**Goal:** Understand LB types, create HTTP LB, add logging/monitoring, and troubleshoot common issues.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 55 | Mon | LB types interview | Cloud Docs + your Linux scripts | Hands-on: LB types overview | Proof + notes |
| 56 | Tue | Create simple HTTP LB | HashiCorp + Cloud Docs + your scripts | Hands-on: Create simple HTTP LB | Proof + notes |
| 57 | Wed | Logging + monitoring for LB | HashiCorp + Cloud Docs | Hands-on: Logging + monitoring for LB | Proof + notes |
| 58 | Thu | Terraform LB basics | HashiCorp + Terraform Docs (Google) | Hands-on: Terraform LB basics | Proof + notes |
| 59 | Fri | Troubleshoot common LB issues | Cloud Docs + your scripts | Hands-on: Troubleshoot common LB issues | Proof + notes |
| 60 | Sat | **PROJECT: App Behind LB** | Skills Boost + Cloud Docs | Build end-to-end: App behind LB | README + screenshots/diagram |

---

## WEEK 11 — Security Posture

**Goal:** Understand shared responsibility, IAM basics, least privilege, no-public-IP design, and VM security.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 61 | Mon | Shared responsibility + posture | Skills Boost + Cloud Docs | Hands-on: Shared responsibility + posture | Proof + notes |
| 62 | Tue | IAM intro (roles, bindings, service accounts) | Cloud IAM Docs + audit logs docs | Hands-on: IAM intro (roles, bindings, service) | Proof + notes |
| 63 | Wed | Least privilege exercise (custom role concept) | Skills Boost + Cloud Docs | Hands-on: Least privilege exercise (custom role) | Proof + notes |
| 64 | Thu | No public IP approach (concept + implement) | Skills Boost + Cloud Docs | Hands-on: No public IP approach | Proof + notes |
| 65 | Fri | Security checklist for VMs | Skills Boost + Cloud Docs | Hands-on: Security checklist for VMs | Proof + notes |
| 66 | Sat | **PROJECT: Hardened Private VM Blueprint** | Skills Boost + Cloud Docs | Build end-to-end: Hardened private VM | README + screenshots/diagram |

---

## WEEK 12 — Incident Response & Ops

**Goal:** Build logging strategy, tune alerts, simulate failures, write RCA templates, and create Ops Playbook.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 67 | Mon | Logging strategy (what to log) | Cloud Docs + your Linux scripts | Hands-on: Logging strategy (what to log) | Proof + notes |
| 68 | Tue | Alert tuning (reduce noise) | Cloud Docs + your Linux scripts | Hands-on: Alert tuning (reduce noise) | Proof + notes |
| 69 | Wed | Simulate failure, detect via alert | Cloud Docs + your Linux scripts | Hands-on: Simulate failure, detect via alert | Proof + notes |
| 70 | Thu | RCA write-up template | Cloud Docs + your Linux scripts | Hands-on: RCA write-up template | Proof + notes |
| 71 | Fri | Ops Playbook v1 | Cloud Docs + your Linux scripts | Hands-on: Ops Playbook v1 | Proof + notes |
| 72 | Sat | **PROJECT: Incident Simulation + RCA Report** | Cloud Docs + your Linux scripts | Build end-to-end: Incident simulation + RCA | README + screenshots/diagram |

---

## WEEK 13 — IAM Deep Dive

**Goal:** Master IAM model, service accounts, troubleshooting, and least privilege in practice.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 73 | Mon | IAM model: members/roles/policies | Cloud IAM Docs + audit logs | Hands-on: IAM model: members/roles/policies | Proof + notes |
| 74 | Tue | Service accounts: create + attach to VM | Cloud IAM Docs + audit logs | Hands-on: Service accounts: create + attach | Proof + notes |
| 75 | Wed | IAM troubleshooting: permission denied | Cloud IAM Docs + audit logs | Hands-on: IAM troubleshooting: permission denied | Proof + notes |
| 76 | Thu | Least privilege: narrow role + test | Cloud IAM Docs + audit logs | Hands-on: Least privilege: narrow role + test | Proof + notes |
| 77 | Fri | IAM troubleshooting steps document | Cloud IAM Docs + audit logs | Hands-on: IAM troubleshooting steps | Proof + notes |
| 78 | Sat | **PROJECT: IAM Lab Pack (grant/test/revoke)** | Cloud IAM Docs + audit logs | Build end-to-end: IAM lab pack | README + screenshots/diagram |

---

## WEEK 14 — Secure Access Patterns

**Goal:** Implement OS Login, eliminate long-lived keys, per-workload service accounts, and IAM via Terraform.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 79 | Mon | OS Login / secure SSH pattern | Skills Boost + Cloud Docs | Hands-on: OS Login / secure SSH pattern | Proof + notes |
| 80 | Tue | No long-lived keys (concept) | Skills Boost + Cloud Docs | Hands-on: No long-lived keys (concept) | Proof + notes |
| 81 | Wed | Service account per workload | Skills Boost + Cloud Docs | Hands-on: Service account per workload | Proof + notes |
| 82 | Thu | IAM bindings with Terraform | HashiCorp + Terraform Docs (Google) | Hands-on: IAM bindings with Terraform | Proof + notes |
| 83 | Fri | Audit notes: who changed what | Skills Boost + HashiCorp + Terraform Docs | Hands-on: Audit notes: who changed what | Proof + notes |
| 84 | Sat | **PROJECT: Secure Access Blueprint + Terraform** | HashiCorp + Terraform Docs | Build end-to-end: Secure access blueprint | README + screenshots/diagram |

---

## WEEK 15 — Audit & Compliance

**Goal:** Master audit logs, query for IAM changes, alert on suspicious actions, and build compliance documentation.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 85 | Mon | Audit log basics | Cloud IAM Docs + audit logs | Hands-on: Audit log basics | Proof + notes |
| 86 | Tue | Query audit logs for IAM changes | Cloud IAM Docs + audit logs | Hands-on: Query audit logs for IAM changes | Proof + notes |
| 87 | Wed | Alert on suspicious actions (concept/lab) | Cloud IAM Docs + audit logs | Hands-on: Alert on suspicious actions | Proof + notes |
| 88 | Thu | Access review checklist | Cloud IAM Docs + audit logs | Hands-on: Access review checklist | Proof + notes |
| 89 | Fri | Compliance-friendly notes | Cloud IAM Docs + audit logs | Hands-on: Compliance-friendly notes | Proof + notes |
| 90 | Sat | **PROJECT: Audit Dashboard + Queries Pack** | Cloud IAM Docs + audit logs | Build end-to-end: Audit dashboard + queries | README + screenshots/diagram |

---

## WEEK 16 — Identity Architecture

**Goal:** Map LDAP to IAM, understand identity lifecycle (JML), directory sync, and hybrid identity.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 91 | Mon | Map LDAP concepts to IAM | Cloud IAM Docs + audit logs | Hands-on: Map LDAP concepts to IAM | Proof + notes |
| 92 | Tue | Identity lifecycle: JML | Cloud IAM Docs + audit logs | Hands-on: Identity lifecycle: JML | Proof + notes |
| 93 | Wed | Directory sync concepts (read) | Skills Boost + Cloud Docs | Hands-on: Directory sync concepts (read) | Proof + notes |
| 94 | Thu | Hybrid identity overview doc | Cloud IAM Docs + audit logs | Hands-on: Hybrid identity overview doc | Proof + notes |
| 95 | Fri | Interview story: RHDS upgrade + security | Skills Boost + Cloud Docs | Hands-on: Interview story: RHDS upgrade + security | Proof + notes |
| 96 | Sat | **PROJECT: Identity Architecture Notes + Diagrams** | Cloud IAM Docs + audit logs | Build end-to-end: Identity architecture notes | README + screenshots/diagram |

---

## WEEK 17 — Terraform Best Practices

**Goal:** Production-grade repo structure, remote state, linting, secrets handling, and reusable templates.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 97 | Mon | Repo structure: envs/modules | HashiCorp + Terraform Docs (Google) | Hands-on: Repo structure: envs/modules | Proof + notes |
| 98 | Tue | Remote state (concept) | HashiCorp + Terraform Docs (Google) | Hands-on: Remote state (concept) | Proof + notes |
| 99 | Wed | Lint/format + standards | HashiCorp + Terraform Docs (Google) | Hands-on: Lint/format + standards | Proof + notes |
| 100 | Thu | Variables hygiene + secrets handling | HashiCorp + Terraform Docs (Google) | Hands-on: Variables hygiene + secrets handling | Proof + notes |
| 101 | Fri | Reusable templates | HashiCorp + Terraform Docs (Google) | Hands-on: Reusable templates | Proof + notes |
| 102 | Sat | **PROJECT: Production-Grade Terraform Repo** | HashiCorp + Terraform Docs | Build end-to-end: Production-grade Terraform repo | README + screenshots/diagram |

---

## WEEK 18 — SRE Monitoring (Advanced)

**Goal:** Define SLOs/SLAs/SLIs, build golden signal dashboards, tune alerts, and create monitoring strategy.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 103 | Mon | SLO/SLA/SLI (light) | Cloud Docs + your Linux scripts | Hands-on: SLO/SLA/SLI (light) | Proof + notes |
| 104 | Tue | Dashboards: golden signals | Cloud Docs + your Linux scripts | Hands-on: Dashboards: golden signals | Proof + notes |
| 105 | Wed | Alert tuning: reduce false positives | Cloud Docs + your Linux scripts | Hands-on: Alert tuning: reduce false positives | Proof + notes |
| 106 | Thu | Log-based metrics (if available) | Cloud Docs + your Linux scripts | Hands-on: Log-based metrics | Proof + notes |
| 107 | Fri | Monitoring strategy document | Cloud Docs + your Linux scripts | Hands-on: Monitoring strategy document | Proof + notes |
| 108 | Sat | **PROJECT: SRE Monitoring Pack v2** | Cloud Docs + your Linux scripts | Build end-to-end: SRE Monitoring Pack v2 | README + screenshots/diagram |

---

## WEEK 19 — IAM Troubleshooting (Advanced)

**Goal:** Diagnose IAM failures, understand service account impersonation, and build IAM runbook.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 109 | Mon | Common IAM failures & diagnosis | Cloud IAM Docs + audit logs | Hands-on: Common IAM failures & diagnosis | Proof + notes |
| 110 | Tue | Service account impersonation (read) | Cloud IAM Docs + audit logs | Hands-on: Service account impersonation | Proof + notes |
| 111 | Wed | Audit: who accessed what | Cloud IAM Docs + audit logs | Hands-on: Audit: who accessed what | Proof + notes |
| 112 | Thu | Least privilege policies in Terraform | Cloud IAM Docs + audit logs | Hands-on: Least privilege policies in Terraform | Proof + notes |
| 113 | Fri | IAM runbook | Cloud IAM Docs + audit logs | Hands-on: IAM runbook | Proof + notes |
| 114 | Sat | **PROJECT: IAM Troubleshooting Cases (5)** | Cloud IAM Docs + audit logs | Build end-to-end: IAM troubleshooting cases | README + screenshots/diagram |

---

## WEEK 20 — GenAI for Ops

**Goal:** Use GenAI safely to summarize logs, draft runbooks, generate Terraform, and build prompt library.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 115 | Mon | Summarize logs safely with GenAI | Skills Boost + Cloud Docs | Hands-on: Summarize logs safely with GenAI | Proof + notes |
| 116 | Tue | Draft runbooks from notes using GenAI | Skills Boost + Cloud Docs | Hands-on: Draft runbooks from notes using GenAI | Proof + notes |
| 117 | Wed | Generate Terraform boilerplate with GenAI (validated) | HashiCorp + Terraform Docs (Google) | Hands-on: Generate Terraform boilerplate | Proof + notes |
| 118 | Thu | RCA summarizer prompt template | Skills Boost + Cloud Docs | Hands-on: RCA summarizer prompt template | Proof + notes |
| 119 | Fri | Prompt library documentation | Skills Boost + Cloud Docs | Hands-on: Prompt library documentation | Proof + notes |
| 120 | Sat | **PROJECT: Ops Automation Assistant Notes** | Skills Boost + Cloud Docs | Build end-to-end: Ops automation assistant | README + screenshots/diagram |

---

## WEEK 21 — Portfolio v2

**Goal:** Polish your top 3 projects, add screenshots, troubleshooting, and push to GitHub.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 121 | Mon | Select top 3 projects | Skills Boost + Cloud Docs | Hands-on: Select top 3 projects | Proof + notes |
| 122 | Tue | Improve READMEs + diagrams | Skills Boost + Cloud Docs | Hands-on: Improve READMEs + diagrams | Proof + notes |
| 123 | Wed | Add screenshots + how-to-run | Skills Boost + Cloud Docs | Hands-on: Add screenshots + how-to-run | Proof + notes |
| 124 | Thu | Add troubleshooting section | Skills Boost + Cloud Docs | Hands-on: Add troubleshooting section | Proof + notes |
| 125 | Fri | Push to GitHub + tag releases | Skills Boost + Cloud Docs | Hands-on: Push to GitHub + tag releases | Proof + notes |
| 126 | Sat | **PROJECT: Portfolio v2 Published** | Skills Boost + Cloud Docs | Build end-to-end: Portfolio v2 published | README + screenshots/diagram |

---

## WEEK 22 — Resume & CV

**Goal:** Rewrite your resume with cloud infra focus, add impact metrics and project links.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 127 | Mon | Rewrite summary (Cloud Infra + IAM) | Cloud IAM Docs + audit logs | Hands-on: Rewrite summary (Cloud Infra + IAM) | Proof + notes |
| 128 | Tue | Add impact bullets (metrics) | Skills Boost + Cloud Docs | Hands-on: Add impact bullets (metrics) | Proof + notes |
| 129 | Wed | Add projects section with links | Skills Boost + Cloud Docs | Hands-on: Add projects section with links | Proof + notes |
| 130 | Thu | Tailor to 2 job descriptions | Skills Boost + Cloud Docs | Hands-on: Tailor to 2 job descriptions | Proof + notes |
| 131 | Fri | Update LinkedIn headline + About | Skills Boost + Cloud Docs | Hands-on: Update LinkedIn headline + About | Proof + notes |
| 132 | Sat | **PROJECT: Job Application Kit Folder** | Skills Boost + Cloud Docs | Build end-to-end: Job application kit folder | README + screenshots/diagram |

---

## WEEK 23 — Interview Preparation

**Goal:** Practice technical questions, scenario-based answers, and mock interviews.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 133 | Mon | Compute + Linux deep questions | Skills Boost + Cloud Docs | Hands-on: Compute + Linux deep questions | Proof + notes |
| 134 | Tue | Networking scenario questions | HashiCorp + Terraform Docs | Hands-on: Networking scenario questions | Proof + notes |
| 135 | Wed | Terraform Qs: state/drift/modules | HashiCorp + Terraform Docs | Hands-on: Terraform Qs: state/drift/modules | Proof + notes |
| 136 | Thu | Monitoring + incident response stories | Skills Boost + Cloud Docs | Hands-on: Monitoring + incident response stories | Proof + notes |
| 137 | Fri | IAM troubleshooting scenarios | Cloud IAM Docs + audit logs | Hands-on: IAM troubleshooting scenarios | Proof + notes |
| 138 | Sat | **PROJECT: Mock Interview (Record Yourself)** | Skills Boost + Cloud Docs | Build end-to-end: Mock interview (record) | README + screenshots/diagram |

---

## WEEK 24 — Job Application & Final Review

**Goal:** Apply to roles, refine STAR stories, deep dive companies, and plan next 3 months.

| Day | Weekday | Topic (Learn) | Where to Learn | Hands-on / Apply | Deliverable |
|---|---|---|---|---|---|
| 139 | Mon | Apply to 5 roles (qualify) | Skills Boost + Cloud Docs | Hands-on: Apply to 5 roles (qualify) | Proof + notes |
| 140 | Tue | Adjust resume to feedback | Skills Boost + Cloud Docs | Hands-on: Adjust resume to feedback | Proof + notes |
| 141 | Wed | Prepare STAR stories (5) | Skills Boost + Cloud Docs | Hands-on: Prepare STAR stories (5) | Proof + notes |
| 142 | Thu | Deep dive 2 companies | Skills Boost + Cloud Docs | Hands-on: Deep dive 2 companies | Proof + notes |
| 143 | Fri | Mock round 2 | Skills Boost + Cloud Docs | Hands-on: Mock round 2 | Proof + notes |
| 144 | Sat | **PROJECT: Final Review + Next 3-Month Plan** | Skills Boost + Cloud Docs | Build end-to-end: Final review + plan | README + screenshots/diagram |

---

## Progress Tracker

| Week | Theme | Project | Status |
|---|---|---|---|
| 1 | Compute Basics | Secure VM Baseline | Not Started |
| 2 | Networking VPC | Secure VPC + 2-Tier VM | Not Started |
| 3 | Monitoring & Logging | Monitoring Pack | Not Started |
| 4 | Terraform Basics | Terraform Landing Zone Lite | Not Started |
| 5 | Terraform Networking | Reusable Network Module | Not Started |
| 6 | Storage & Backup | Backup & Restore Lab | Not Started |
| 7 | Automation & Ops | Golden VM Baseline Automation | Not Started |
| 8 | Portfolio Review | Publish Portfolio v1 | Not Started |
| 9 | MIG & Autoscaling | Scalable VM Group | Not Started |
| 10 | Load Balancing | App Behind LB | Not Started |
| 11 | Security Posture | Hardened Private VM Blueprint | Not Started |
| 12 | Incident Response | Incident Simulation + RCA | Not Started |
| 13 | IAM Deep Dive | IAM Lab Pack | Not Started |
| 14 | Secure Access | Secure Access Blueprint | Not Started |
| 15 | Audit & Compliance | Audit Dashboard + Queries | Not Started |
| 16 | Identity Architecture | Identity Architecture Notes | Not Started |
| 17 | Terraform Best Practices | Production-Grade Terraform Repo | Not Started |
| 18 | SRE Monitoring | SRE Monitoring Pack v2 | Not Started |
| 19 | IAM Troubleshooting | IAM Troubleshooting Cases | Not Started |
| 20 | GenAI for Ops | Ops Automation Assistant | Not Started |
| 21 | Portfolio v2 | Portfolio v2 Published | Not Started |
| 22 | Resume & CV | Job Application Kit | Not Started |
| 23 | Interview Prep | Mock Interview | Not Started |
| 24 | Job Application | Final Review + Next Plan | Not Started |
