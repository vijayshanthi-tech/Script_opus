# Day 143 — Mock Round 2: Advanced Scenarios

> **Week 24 · Job Application** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Tackle advanced interview scenarios — system design, behavioural deep-dives, and salary negotiation — to prepare for second-round and final-round interviews.

---

## Part 1 — Concept: What to Expect in Round 2+ (30 min)

### Interview Progression

| Round | Format | Focus | Duration |
|---|---|---|---|
| **Phone screen** | Recruiter call | Culture fit, salary expectations, experience overview | 20-30 min |
| **Technical screen** | Video call, sometimes live coding | Core technical skills, problem-solving | 45-60 min |
| **System design** | Whiteboard / diagram exercise | Architecture thinking, trade-offs, communication | 45-60 min |
| **Behavioural deep-dive** | Panel or 1:1 with manager | Leadership, conflict, growth mindset, team fit | 30-45 min |
| **Final / bar raiser** | Senior engineer or director | Overall calibre, cultural alignment, long-term fit | 30-60 min |

### System Design Lite (for Infrastructure Roles)

You won't be asked to design Google Search, but you may be asked to design infrastructure systems:

**Common system design questions for Cloud/Infra Engineers:**

| Question | What They're Testing |
|---|---|
| "Design a monitoring system for our production environment" | Observability knowledge, tooling choices, alert strategy |
| "Design a secure VPC for a 3-tier web application" | Networking, security, defence in depth |
| "How would you set up a CI/CD pipeline for Terraform?" | IaC practices, automation, state management |
| "Design a disaster recovery strategy for a europe-west2 deployment" | DR concepts, RPO/RTO, multi-region design |
| "How would you migrate 50 VMs from on-premise to GCP?" | Migration strategy, phased approach, risk management |

### The System Design Framework

Use this 4-step framework for any design question:

**Step 1 — Clarify Requirements (2-3 min)**
- Ask questions before designing. This is expected and valued.
- "What's the scale? How many services, how much traffic?"
- "What's the availability requirement? 99.9%? 99.99%?"
- "What's the budget constraint?"
- "What's already in place that I need to integrate with?"

**Step 2 — High-Level Design (5-10 min)**
- Draw/describe the main components
- Show the data flow between components
- Name specific GCP services you'd use

**Step 3 — Deep Dive (10-15 min)**
- Pick 1-2 areas to go deeper
- Discuss trade-offs: "I chose X over Y because..."
- Address security, monitoring, and failure modes

**Step 4 — Discuss Trade-Offs (5 min)**
- "If budget were tighter, I'd simplify by..."
- "If we needed higher availability, I'd add..."
- "The main risk with this approach is..."

### Behavioural Deep-Dives

Round 2+ behavioural questions go deeper than Round 1:

| Round 1 Question | Round 2+ Deep Dive |
|---|---|
| "Tell me about a challenge" | "What would you do differently if you faced that again?" |
| "Describe a project" | "What was the hardest trade-off you made?" |
| "How do you handle conflict?" | "Give me a specific example where you and a colleague disagreed on a technical approach. Walk me through exactly how you resolved it." |
| "What's your weakness?" | "How has that weakness impacted a project, and what concrete steps have you taken to improve?" |

### Salary Negotiation Basics

| Principle | Why |
|---|---|
| **Never give a number first** | Let them anchor. "I'd prefer to understand the full compensation package before discussing numbers." |
| **Research the market** | Glassdoor, levels.fyi, LinkedIn salary insights for UK Cloud Engineer roles |
| **Consider total compensation** | Base salary + bonus + pension + stock + benefits + remote flexibility |
| **Have a range ready** | Know your floor (won't accept below this) and target (what you want) |
| **Negotiate after the offer** | Never negotiate during the interview process; wait for a written offer |
| **Be professional, not adversarial** | "Based on my research and experience, I was hoping for £X. Is there flexibility?" |

**UK Cloud Infrastructure Engineer salary ranges (2024-2025, approximate):**

| Level | London (£) | Outside London (£) |
|---|---|---|
| Junior / Entry Cloud Engineer | 35k - 50k | 30k - 42k |
| Mid-Level Cloud / Infra Engineer | 50k - 70k | 42k - 60k |
| Senior Cloud / Infra Engineer | 70k - 95k | 58k - 80k |
| Lead / Principal | 90k - 130k+ | 75k - 110k+ |

---

## Part 2 — Hands-On Activity: Practice Advanced Scenarios (60 min)

### Exercise 1 — System Design: Monitoring System (20 min)

**Scenario:** "Your team manages 50 Compute Engine VMs, 10 Cloud SQL instances, and 5 GKE clusters in europe-west2. Design a monitoring and alerting system."

**Step 1 — Clarify (write your clarification questions):**

| # | Question | Assumed Answer |
|---|---|---|
| 1 | What's the current monitoring? Starting from scratch? | Some basic Cloud Monitoring, nothing custom |
| 2 | What's the on-call structure? | 1 engineer on call, weekly rotation |
| 3 | SLA requirement? | 99.9% uptime |
| 4 | Budget constraint? | Moderate — prefer GCP-native where possible |

**Step 2 — High-Level Design:**

Write/sketch your design. Key components to cover:

| Component | GCP Service / Tool | Purpose |
|---|---|---|
| **Metrics collection** | Cloud Monitoring (built-in) | CPU, memory, disk, network for all resources |
| **Custom metrics** | Cloud Monitoring custom metrics + ops agent | Application-level metrics (queue depth, latency) |
| **Log aggregation** | Cloud Logging | Centralised logs from all VMs and services |
| **Log-based metrics** | Cloud Logging → metric | Turn error patterns into alertable metrics |
| **Dashboards** | Cloud Monitoring dashboards | Per-service overview, SLI/SLO tracking |
| **Alerting** | Cloud Monitoring alerting policies | Threshold and absence-based alerts |
| **Notification** | PagerDuty / Slack via notification channels | On-call paging, team-wide awareness |
| **Uptime checks** | Cloud Monitoring uptime checks | External blackbox monitoring |

**Step 3 — Deep Dive (pick one area):**

Choose alerting strategy OR logging architecture and write 5-6 sentences going deeper:

> _Your deep dive here_

**Step 4 — Trade-Offs:**

| Decision | Trade-Off |
|---|---|
| GCP-native vs third-party (Datadog) | GCP-native: lower cost, simpler. Third-party: better dashboards, multi-cloud |
| Alert threshold tuning | Too sensitive: alert fatigue. Too lenient: miss real issues |
| Log retention | Longer: more cost. Shorter: lose investigation ability |

---

### Exercise 2 — System Design: Secure VPC (20 min)

**Scenario:** "Design a VPC architecture for a 3-tier web application (web frontend, API backend, database) in GCP. Security is the top priority."

**Step 1 — Clarify:**

| # | Question | Assumed Answer |
|---|---|---|
| 1 | Is this internet-facing? | Yes, web tier is public |
| 2 | What database? | Cloud SQL (PostgreSQL) |
| 3 | Compliance requirements? | Standard security best practices |
| 4 | Region? | europe-west2 |

**Step 2 — High-Level Design:**

| Tier | Subnet | CIDR (example) | Access |
|---|---|---|---|
| **Web tier** | `web-subnet` | 10.0.1.0/24 | Internet → Load Balancer → web VMs |
| **API tier** | `api-subnet` | 10.0.2.0/24 | Only from web tier (internal) |
| **Database tier** | `db-subnet` | 10.0.3.0/24 | Only from API tier, private IP only |

**Firewall rules:**

| Rule | Source | Target | Ports | Action |
|---|---|---|---|---|
| Allow HTTPS to LB | 0.0.0.0/0 | Web instances (via LB) | 443 | Allow |
| Allow web→api | web-subnet tag | api-subnet tag | 8080 | Allow |
| Allow api→db | api-subnet tag | db-subnet tag | 5432 | Allow |
| Deny all other | any | any | any | Deny (implicit) |

**Security layers:**

| Layer | Implementation |
|---|---|
| Cloud Armor | DDoS protection, WAF rules on the load balancer |
| Private Google Access | DB subnet accesses Google APIs without public IP |
| Cloud NAT | API and DB tiers reach internet (for updates) without public IPs |
| VPC Flow Logs | Enabled on all subnets for audit |
| Private Service Connect | Cloud SQL uses private IP, no public endpoint |
| IAM | Service accounts per tier with minimum necessary roles |

**Step 3 — Deep Dive:** Pick network security or database security and elaborate.

> _Your deep dive here_

---

### Exercise 3 — Behavioural Deep-Dive Practice (10 min)

Answer these advanced behavioural questions. Write 3-4 sentences for each (STAR format):

**Q: "What would you do differently if you could redo your most challenging project?"**

> _Your answer here — show self-awareness and growth mindset_

**Q: "Tell me about a time you received critical feedback. How did you respond?"**

> _Your answer here — show you can receive feedback constructively_

**Q: "If you joined and disagreed with the team's current infrastructure approach, how would you handle it?"**

> _Your answer here — show diplomacy, data-driven thinking, and respect for context_

---

### Exercise 4 — Salary Negotiation Role-Play (10 min)

**Scenario:** You receive a verbal offer of £52,000 base salary for a Cloud Infrastructure Engineer role in the UK (outside London). The role listing suggested £50k-65k.

**Draft your response for each scenario:**

**If the offer is at the low end but you want the role:**
> _"Thank you for the offer — I'm excited about the role and the team. Based on my research and my experience bringing [specific value: 6 years infrastructure + ACE cert + LDAP/IAM background], I was hoping for something closer to £58,000. Is there flexibility in the base salary?"_

**If they say the base is fixed:**
> _"I understand. Could we discuss [signing bonus / review timeline / additional training budget / remote flexibility] as part of the overall package?"_

**If the offer is strong and you want to accept:**
> _"Thank you — I'm happy with this offer and excited to join. Could I have the written offer to review by [date]? I'd like to confirm by [date + 2-3 days]."_

---

## Part 3 — Revision: Key Takeaways (15 min)

- **System design uses a 4-step framework:** Clarify → High-Level Design → Deep Dive → Trade-Offs
- **Always ask clarifying questions first** — jumping straight to design is a red flag
- **Name specific GCP services** — "I'd use Cloud Monitoring" not "I'd set up monitoring"
- **Discuss trade-offs explicitly** — this is what separates senior from junior thinking
- **Round 2+ behavioural questions go deeper** — prepare for "what would you do differently?" follow-ups
- **Salary: never give a number first** — let them make the offer
- **Research market rates** — know your floor, target, and stretch numbers
- **Negotiate after the written offer** — not during interviews
- **Total compensation matters** — base + bonus + pension + benefits + flexibility
- **Be professional in negotiation** — collaborative, not adversarial; data-driven, not emotional

---

## Part 4 — Quiz (15 min)

**Q1.** An interviewer asks "Design a disaster recovery strategy for our europe-west2 deployment." Walk through your framework.

<details><summary>Answer</summary>

**Step 1 — Clarify:**
- "What's the RPO (Recovery Point Objective)? How much data loss is acceptable?"
- "What's the RTO (Recovery Time Objective)? How quickly must we recover?"
- "What services are most critical?"
- "What's the budget for DR?"
- "Is multi-region or multi-zone sufficient?"

**Step 2 — High-Level Design (assuming RPO: 1 hour, RTO: 4 hours):**

| Component | Primary (europe-west2) | DR (europe-west1) |
|---|---|---|
| Compute | Active VMs / GKE cluster | Standby VMs or auto-scale from 0 |
| Database | Cloud SQL primary | Cloud SQL read replica with promotion capability |
| Storage | GCS bucket | Cross-region replication (dual-region or multi-region) |
| Load balancing | Global HTTPS LB with health checks | Automatic failover to healthy backend |
| DNS | Cloud DNS with health-checked routing | Failover to DR region if primary unhealthy |

**Step 3 — Deep Dive (database DR):**
Cloud SQL cross-region replication provides asynchronous replication to europe-west1. Typical replication lag is seconds to minutes. For failover, we'd promote the replica to primary — this takes 5-10 minutes. Application config via Secret Manager can point to the new primary. We'd practice this failover quarterly with a game day exercise.

**Step 4 — Trade-Offs:**
- Active-active (both regions serving traffic): faster failover but higher cost and complexity
- Active-passive (DR on standby): lower cost but longer RTO
- Multi-zone within region: lowest cost, protects against zone failure but not region failure
- RPO vs cost: tighter RPO = more frequent backups/replication = higher cost
</details>

**Q2.** How should you handle the question "What's your expected salary?" in a first-round phone screen?

<details><summary>Answer</summary>

**Best approach — defer gracefully:**

"I'd prefer to learn more about the role, the team, and the full compensation package before discussing specific numbers. Could you share the budgeted range for this position?"

**If they insist:**

"Based on my research for Cloud Infrastructure Engineer roles in the UK with my level of experience, I'm looking at the range of £X-£Y. But I'm flexible depending on the overall package and growth opportunities."

**Key principles:**
1. Always try to let them share the range first
2. If you must give a number, give a range (not a single figure)
3. Base your range on research, not your current salary
4. Say "I'm flexible depending on the total package" — this gives room to negotiate
5. Never lie about your current salary (some companies verify, and it damages trust)
6. In the UK, employers cannot legally require your current salary in many contexts

**If they ask your current salary:**

"I'd prefer to focus on the value I'd bring to this role rather than my current compensation. The roles are quite different, and I'd like to understand your range for this position."
</details>

**Q3.** During a system design exercise, the interviewer says "Your design is too complex for our needs." How do you respond?

<details><summary>Answer</summary>

**This is a test of how you handle feedback, not a criticism of your skills.**

**Good response:**

"That's a fair point. Let me simplify." Then remove the unnecessary components. Ask: "If we strip this down to the essentials, what's the minimum that meets our requirements?"

**Show your thinking:**
1. "I started with a more complete design to show the full picture, but you're right — for the stated requirements, we could simplify."
2. Remove the most complex component and explain why it's OK to defer: "We could start without multi-region DR and add it later when scale requires it."
3. "The advantage of simplifying is lower cost and faster implementation. The risk is [specific thing we lose]. That feels like an acceptable trade-off for the current scale."

**What they're really testing:**
- Can you take feedback without getting defensive?
- Can you simplify when needed? (Over-engineering is a common mistake)
- Do you understand that good design is the simplest design that meets requirements?
- Can you articulate what you're trading off when simplifying?

**What NOT to do:**
- Defend your design stubbornly: "No, this complexity is necessary"
- Completely throw away your work: "Sure, I'll redo it" (shows no conviction)
- Get flustered: this is a normal part of design discussions
</details>

**Q4.** An interviewer asks: "Where do you see yourself in 3 years?" How do you answer authentically for a career transitioner?

<details><summary>Answer</summary>

**Strong answer for a Linux-to-Cloud transitioner:**

"In 3 years, I want to be a confident Senior Cloud Infrastructure Engineer — someone the team trusts to design and implement production GCP infrastructure end-to-end. Specifically:

**Year 1:** Become productive quickly by applying my Linux infrastructure background while deepening my GCP expertise. Take on infrastructure projects with increasing complexity. Earn the Professional Cloud Architect certification.

**Year 2:** Take ownership of significant infrastructure workstreams. Start contributing to architecture decisions and mentoring newer team members. Develop expertise in an area like networking, security, or reliability engineering.

**Year 3:** Be the go-to person for infrastructure design and troubleshooting. Help shape the team's practices and standards. Potentially move into a senior or lead engineer track."

**Why this works:**
1. Shows ambition without overreaching ("I want to be CTO" sounds unrealistic)
2. Demonstrates you've thought about the journey, not just the destination
3. Includes specific, achievable milestones
4. Shows you want to grow *at this company*, not just use them as a stepping stone
5. Connects current skills (Linux) to future growth (cloud architecture)
6. Include giving back (mentoring) — shows team orientation

**Avoid:**
- "I don't know" — shows no direction
- "In your job" — sounds like you're after their position
- "Running my own company" — signals you'll leave
- Anything that suggests this role is just a temporary stop
</details>
