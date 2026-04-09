# Day 138 — PROJECT: Mock Interview Session

> **Week 23 · Interview Prep** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Run a complete mock interview session with 30 questions across all domains, self-assess with a rubric, and identify areas for final preparation.

---

## Part 1 — Concept: Mock Interview Structure (30 min)

### Real Interview Format

A typical Cloud Infrastructure Engineer interview has 2-4 rounds:

| Round | Duration | Content | What They Assess |
|---|---|---|---|
| **Phone Screen** | 30 min | High-level skills, motivation, salary | Culture fit, basic qualifications |
| **Technical Interview 1** | 45-60 min | Hands-on technical questions | Core cloud + Linux skills |
| **Technical Interview 2** | 45-60 min | Scenario-based + system design | Problem-solving, architecture |
| **Behavioural** | 30-45 min | STAR stories, team dynamics | Soft skills, culture fit |

### Your Mock Interview: 30 Questions

This mock covers all domains in a single session. In reality, these would be spread across rounds.

### Self-Assessment Rubric

After each answer, rate yourself:

| Score | Meaning | Criteria |
|---|---|---|
| **5** | Excellent | Direct answer, specific details, experience referenced, GCP-aware, under 2 min |
| **4** | Good | Mostly complete, minor gaps, reasonable timing |
| **3** | Acceptable | Answered the question but vague or missing key details |
| **2** | Weak | Partial answer, significant gaps, rambling |
| **1** | Poor | Couldn't answer or completely wrong |

### Common Interview Mistakes

| Mistake | Why It Hurts | Fix |
|---|---|---|
| Starting with "Um, that's a good question..." | Wastes time, sounds unprepared | Start with the direct answer |
| Giving a 5-minute answer | Interviewer lost interest at minute 2 | Aim for 60-90 seconds |
| Only theoretical knowledge | "I read that..." vs "In my experience..." | Reference real experience |
| Not asking for clarification | Answering the wrong question | "Just to clarify, are you asking about X or Y?" |
| Saying "I don't know" and stopping | Missed chance to show thinking | "I haven't done that specifically, but my approach would be..." |
| Not mentioning your experience | You have 6 years — USE it | Bridge every answer back to experience |

### Confidence-Building Tips

1. **You have 6 years of production experience** — most cloud candidates don't have this
2. **ACE certification validates your knowledge** — you passed a Google exam
3. **Your portfolio is real** — you built actual infrastructure on GCP
4. **It's OK not to know everything** — showing your thinking process matters more
5. **The interviewer wants you to succeed** — they need to fill a role
6. **Preparation is the antidote to anxiety** — the more you practice, the calmer you'll be

---

## Part 2 — Hands-On Activity: Full Mock Interview (60 min)

### Instructions

1. Set a timer for the full 60 minutes
2. Read each question, answer aloud (or write key points if practising solo)
3. Allocate ~2 minutes per question
4. Score yourself using the rubric after each answer
5. Don't look at cheat sheets — this simulates the real thing

### Section A — Introduction & Motivation (5 min)

**Q1.** "Tell me about yourself." (Your elevator pitch — 60 seconds)

**Q2.** "Why are you transitioning from Linux admin to cloud engineering?"

**Q3.** "What interests you about this particular role/company?"

### Section B — Compute & Linux (10 min)

**Q4.** "How do you choose the right machine type for a workload in GCP?"

**Q5.** "A VM is running but has very high CPU usage. Walk me through your debugging."

**Q6.** "How would you harden a Linux VM for production in GCP?"

**Q7.** "Explain the difference between preemptible/spot VMs and on-demand VMs."

**Q8.** "What's your approach to patching 200+ Linux servers?"

### Section C — Networking (10 min)

**Q9.** "A VM in a private subnet can't reach the internet. Walk me through your debugging."

**Q10.** "Two VMs in the same VPC can't ping each other. What do you check?"

**Q11.** "Explain the difference between ingress and egress firewall rules. What are the defaults?"

**Q12.** "How would you design a VPC for a production application with web, app, and database tiers?"

**Q13.** "A firewall rule exists but traffic is still blocked. What's your checklist?"

### Section D — Terraform (10 min)

**Q14.** "What is Terraform state and how do you manage it in a team?"

**Q15.** "Someone made a change via the Console. Terraform plan wants to revert it. What do you do?"

**Q16.** "How do you manage secrets in Terraform?"

**Q17.** "Describe your ideal Terraform CI/CD pipeline."

**Q18.** "How do you structure Terraform for dev, staging, and production environments?"

### Section E — IAM & Security (10 min)

**Q19.** "A developer can't access a Cloud Storage bucket from their VM. Debug this."

**Q20.** "How would you audit IAM for least privilege in a project?"

**Q21.** "What's the difference between basic, predefined, and custom IAM roles? When do you use each?"

**Q22.** "How does your LDAP experience relate to cloud IAM?"

### Section F — Monitoring & SRE (10 min)

**Q23.** "How would you set up monitoring for a new production service on GCP?"

**Q24.** "What are SLOs and SLIs? Give an example for a web application."

**Q25.** "Tell me about a time you resolved a critical production outage." (STAR format)

**Q26.** "How do you handle alert fatigue?"

### Section G — Behavioural (5 min)

**Q27.** "Tell me about a time you disagreed with a team member on a technical approach."

**Q28.** "Describe a situation where you had to learn a new technology quickly."

**Q29.** "How do you prioritise when you have multiple urgent tasks?"

**Q30.** "Where do you see yourself in 2-3 years?"

---

### Self-Assessment Scorecard

Fill this in after completing all 30 questions:

| Section | Questions | Total Possible | Your Score | Score % |
|---|---|---|---|---|
| A — Intro & Motivation | Q1-Q3 | 15 | /15 | % |
| B — Compute & Linux | Q4-Q8 | 25 | /25 | % |
| C — Networking | Q9-Q13 | 25 | /25 | % |
| D — Terraform | Q14-Q18 | 25 | /25 | % |
| E — IAM & Security | Q19-Q22 | 20 | /20 | % |
| F — Monitoring & SRE | Q23-Q26 | 20 | /20 | % |
| G — Behavioural | Q27-Q30 | 20 | /20 | % |
| **Total** | **30** | **150** | **/150** | **%** |

**Score interpretation:**

| Score Range | Assessment | Action |
|---|---|---|
| 120-150 (80-100%) | Interview ready | Light review, focus on polish |
| 90-119 (60-79%) | Strong with gaps | Focus on weak sections |
| 60-89 (40-59%) | Needs more preparation | Re-study weak areas, practice daily |
| <60 (<40%) | Not ready | Go back to study materials, practice fundamentals |

### Recording Checklist

For maximum benefit, record yourself answering:

- [ ] Record audio or video of yourself answering all 30 questions
- [ ] Watch/listen back and note:
  - [ ] Filler words ("um", "basically", "so yeah")
  - [ ] Rambling answers (>2 minutes)
  - [ ] Missed experience references
  - [ ] Answers that were too vague
  - [ ] Body language (if video) — eye contact, confidence

---

## Part 3 — Revision: Key Takeaways (15 min)

- **Mock interviews are the highest-ROI preparation activity** — practice beats theory
- **Start every answer with the direct answer** — then add detail and experience
- **60-90 seconds per answer** — if you're over 2 minutes, you're rambling
- **Reference your experience in every answer** — it's your differentiator
- **"I don't know, but here's how I'd approach it"** is better than silence
- **Ask for clarification** if a question is ambiguous — shows communication skills
- **Score yourself honestly** — identify weak areas and focus your remaining study time there
- **Record yourself** — you'll catch habits you don't notice while speaking
- **7 sections, 30 questions** — covers the full scope of a Cloud Infra Engineer interview
- **You're more prepared than you think** — 6 years experience + ACE + portfolio + this prep

---

## Part 4 — Quiz (15 min)

**Q1.** An interviewer asks: "Why are you transitioning from Linux administration to cloud engineering?" What's a strong answer?

<details><summary>Answer</summary>

"It's a natural evolution, not a departure. In 6 years of managing production Linux infrastructure — 200+ RHEL servers, LDAP directory services, monitoring, automation — I realised that the skills I use daily are exactly what cloud infrastructure requires, just with different tools.

I earned my ACE certification to formalise my GCP knowledge and built a portfolio of infrastructure projects using Terraform, Cloud Monitoring, and VPC architecture. What excites me about cloud engineering is the ability to apply infrastructure discipline at greater scale with more automation. I'm not leaving Linux behind — I'm building on it.

Specifically, my LDAP experience translates directly to cloud IAM, my monitoring experience maps to Cloud Monitoring and SRE practices, and my server administration skills are the foundation for managing compute infrastructure in GCP."

**Why this works:** (1) Frames transition as evolution not escape, (2) References specific experience backed by numbers, (3) Mentions certification and portfolio, (4) Bridges on-prem to cloud concretely, (5) Shows enthusiasm without being generic.
</details>

**Q2.** You're asked a question you genuinely don't know the answer to. What do you do?

<details><summary>Answer</summary>

**Never say "I don't know" and go silent.** Instead:

1. **Acknowledge honestly:** "I haven't worked with that specific technology/scenario directly..."
2. **Show your thinking process:** "...but based on my understanding of [related concept], my approach would be..."
3. **Bridge to what you know:** "...in my Linux experience, the equivalent would be [X], and I'd apply similar principles here."
4. **Express willingness to learn:** "...and this is something I'd research and test before implementing."

**Example:** "How would you set up Anthos for hybrid cloud?"

"I haven't worked with Anthos hands-on, but I understand it provides a consistent Kubernetes-based platform across on-prem and cloud. Based on my experience managing hybrid Linux environments, the key challenges would be networking between environments, consistent IAM, and monitoring across both. I'd approach it by first understanding the current on-prem infrastructure, then designing the GKE clusters on GCP, and establishing secure connectivity. This is definitely an area I'm interested in exploring further."

Interviewers value **thought process over memorisation**. Showing how you'd approach an unknown problem is often more impressive than reciting a memorised answer.
</details>

**Q3.** How should you answer "Where do you see yourself in 2-3 years?"

<details><summary>Answer</summary>

**Good answer:** Specific, realistic, shows growth within their organisation.

"In 2-3 years, I'd like to be a senior cloud infrastructure engineer, potentially leading infrastructure projects or mentoring team members. Specifically, I plan to earn the Professional Cloud Architect certification, deepen my expertise in Kubernetes and GKE, and take on more architectural responsibilities — designing infrastructure for reliability and scale, not just implementing it.

I see this role as the foundation for that path. The combination of [company's] infrastructure challenges and my Linux/GCP background would give me the real-world experience to grow into that senior role."

**Why this works:** (1) Shows ambition without threatening the interviewer, (2) Mentions specific technical growth (PCA cert, Kubernetes), (3) Ties growth to the company, not just personal goals, (4) References the role as a stepping stone, showing you'll stay and grow.

**Avoid:** "I see myself in management" (they're hiring an engineer), "I want to start my own company" (they want retention), "I don't know" (lacks direction).
</details>

**Q4.** What's the most important thing to remember throughout an entire interview day?

<details><summary>Answer</summary>

**Be authentic and reference real experience.** Everything else — technical accuracy, timing, structure — supports this.

Key principles for the full interview day:

1. **Consistency across rounds** — your story should be the same whether you're talking to a recruiter, engineer, or manager. Inconsistencies are red flags.

2. **Every answer is an opportunity to show experience** — even a simple technical question like "what is Terraform state?" becomes stronger with "In my experience managing state for my infrastructure projects..."

3. **Energy management** — interview days are exhausting. Stay hydrated, take bathroom breaks, take a breath before each answer. A calm, measured response beats a rapid, panicked one.

4. **Ask good questions** — "What does the team's current infrastructure look like?", "What's the biggest challenge your team faces right now?", "How does the team handle on-call?". These show genuine interest and help you assess the role.

5. **You're interviewing them too** — evaluate whether you'd enjoy working there. This confidence shift is subtle but interviewers can feel it.

Your 6 years of real experience is your biggest asset. No bootcamp graduate or cert-collector can match genuine production operations stories. Own that advantage.
</details>
