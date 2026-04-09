# Day 134 — Networking Scenario Interview Questions

> **Week 23 · Interview Prep** | Prep 30 min | Activity 60 min | Revision 15 min | Quiz 15 min
>
> **Objective:** Master the debugging methodology for common GCP networking scenarios asked in interviews — "VM can't reach internet", "Two VMs can't communicate", "Firewall rule not working" — with systematic, step-by-step answers.

---

## Part 1 — Concept: Networking Debugging Methodology (30 min)

### The Networking Interview Pattern

Networking questions in cloud interviews are almost always **scenario-based**: "Something isn't working — walk me through how you'd fix it." Interviewers assess:

1. **Structured thinking** — do you have a systematic approach or do you guess randomly?
2. **Layer awareness** — do you check from physical/network up to application?
3. **GCP-specific knowledge** — do you know the GCP networking model?
4. **Practical experience** — have you actually debugged these issues?

### The Debugging Framework: Inside-Out

```
Application Layer    → Is the service running? Is it listening on the right port?
OS/Firewall Layer    → Is the OS firewall blocking? (iptables/nftables)
GCP Firewall Layer   → Does a GCP firewall rule allow this traffic?
Routing Layer        → Does a route exist? Is Cloud NAT configured?
Network Layer        → Are the VMs in the same VPC/subnet? Is VPC peering set up?
External Layer       → DNS resolution? Internet gateway? ISP issue?
```

**Always start from the VM (inside) and work outward.** This prevents wasting time on external issues when the problem is a stopped service.

### Top Networking Scenarios

| # | Scenario | Key Areas to Check |
|---|---|---|
| 1 | VM can't reach the internet | External IP / Cloud NAT, routes, firewall egress |
| 2 | Two VMs in same VPC can't ping each other | Firewall rules (ICMP), subnet, network tags |
| 3 | VM can't reach a specific service (e.g., Cloud SQL) | Private service access, firewall, IAM |
| 4 | Firewall rule exists but traffic is still blocked | Priority, direction, tags, source ranges |
| 5 | High latency between two VMs | Same zone? Same region? Network tier |
| 6 | Load balancer health check failing | Firewall for health check ranges, backend config |
| 7 | DNS not resolving | Cloud DNS config, VPC DNS settings, /etc/resolv.conf |
| 8 | VPC peering not working | Peering state, overlapping CIDRs, transitive routing |

### Scenario 1: "A VM Can't Reach the Internet"

**Model Answer:**

> "I'd work through this systematically from the VM outward:
>
> **Step 1 — Check the VM has an internet path:**
> Does it have an external IP? If not, is Cloud NAT configured for its subnet? For a private VM in europe-west2, Cloud NAT on the router is required for outbound internet access.
>
> **Step 2 — Check routing:**
> `gcloud compute routes list --filter="network=my-vpc"` — is there a default route (0.0.0.0/0) pointing to the default internet gateway?
>
> **Step 3 — Check GCP firewall rules:**
> Are there any egress deny rules? GCP has an implied allow-all-egress rule, but explicit deny rules with higher priority could override it.
>
> **Step 4 — Check from inside the VM:**
> ```bash
> # Can we resolve DNS?
> nslookup google.com
> # Can we reach the gateway?
> ping -c 3 $(ip route | grep default | awk '{print $3}')
> # Can we reach external IPs?
> curl -I https://www.google.com
> ```
>
> **Step 5 — Check OS firewall:**
> `sudo iptables -L -n` — is iptables blocking outbound traffic?
>
> **Most common cause:** VM has no external IP and Cloud NAT isn't configured, or there's a missing default route."

### Scenario 2: "Two VMs in the Same VPC Can't Ping Each Other"

**Model Answer:**

> "Ping uses ICMP, which GCP blocks by default. Here's my checklist:
>
> **Step 1 — Verify both VMs are in the same VPC.**
> Different VPCs can't communicate without peering or Shared VPC.
>
> **Step 2 — Check firewall rules for ICMP:**
> GCP doesn't allow ICMP by default. You need:
> ```
> gcloud compute firewall-rules create allow-internal-icmp \
>   --network=my-vpc \
>   --allow=icmp \
>   --source-ranges=10.0.0.0/8
> ```
>
> **Step 3 — Check network tags:**
> If the firewall rule uses target tags, both VMs must have the matching tag.
>
> **Step 4 — Check firewall rule priority:**
> A higher-priority deny rule could block ICMP even if an allow rule exists.
>
> **Step 5 — Test from VM:**
> ```bash
> ping -c 3 <other-vm-internal-ip>
> # If ping fails, try:
> curl <other-vm-internal-ip>:<port>  # Test TCP instead of ICMP
> ```
>
> **Most common cause:** Missing ICMP allow rule — GCP's default rules don't include ping."

### Scenario 4: "A Firewall Rule Exists But Traffic Is Still Blocked"

**Model Answer:**

> "When a firewall rule doesn't seem to work, I check five things:
>
> 1. **Direction** — Is it INGRESS or EGRESS? Most people create ingress when they need egress, or vice versa.
> 2. **Priority** — Lower number = higher priority. A deny rule at priority 100 beats an allow at 1000.
> 3. **Target tags** — Does the VM have the tag the rule targets? `gcloud compute instances describe vm-name` to check.
> 4. **Source ranges** — Is the source IP range correct? Common mistake: using 0.0.0.0/0 when it should be 35.235.240.0/20 (for IAP) or the internal subnet range.
> 5. **Protocol and port** — Is it `tcp:22` or `tcp:80`? Wrong protocol or port means no match.
>
> **Debug tool:** GCP Firewall Rules Logging. Enable logging on the rule and check Cloud Logging for `ALLOWED` or `DENIED` entries for the specific source/destination pair.
>
> **Most common cause:** Network tags not applied to the VM, or a higher-priority deny rule overriding the allow."

---

## Part 2 — Hands-On Activity: Practice Scenario Answers (60 min)

### Exercise 1 — Write Scenario Walkthrough Answers (30 min)

Write model answers for these scenarios using the inside-out debugging framework:

**Scenario A:** "A web application VM is showing as healthy in Compute Engine but the website is returning 502 errors through the load balancer."

**Scenario B:** "Two VMs in different subnets but the same VPC can communicate, but adding a third VM in a new subnet can't reach either of the others."

**Scenario C:** "A VM can reach the internet but can't connect to a Cloud SQL instance configured with Private IP."

For each scenario, write:
1. Your systematic debugging steps (numbered)
2. Specific commands or checks at each step
3. The most likely root cause
4. The fix

### Exercise 2 — Timed Practice (20 min)

Practice answering 4 scenarios aloud, 5 minutes each:

1. Start a timer
2. Read the scenario
3. Answer as if in an interview — structured, calm, specific
4. Self-assess: Did you follow a framework? Were you specific enough?

**Scenarios to practice:**

1. "VM can't SSH — connection times out"
2. "Application works locally but fails from another VM in the same VPC"
3. "VPC peering is configured but VMs can't communicate across VPCs"
4. "Cloud NAT is configured but VMs still can't reach external APIs"

### Exercise 3 — Gap Analysis (10 min)

Rate your confidence for each networking area:

| Topic | Confidence (1-5) | Need to Review? |
|---|---|---|
| Firewall rules (ingress/egress, tags, priority) | | |
| Cloud NAT and internet access | | |
| VPC peering | | |
| Private Google Access | | |
| Load balancer health checks | | |
| IAP tunnelling | | |
| DNS resolution | | |
| Route management | | |

Focus your remaining study time on anything rated 3 or below.

---

## Part 3 — Revision: Key Takeaways (15 min)

- **Use the inside-out debugging framework:** Application → OS → GCP Firewall → Routing → Network → External
- **GCP blocks ICMP by default** — this is the #1 "gotcha" for "VMs can't ping" scenarios
- **Firewall rule troubleshooting checklist:** direction, priority, target tags, source ranges, protocol:port
- **No external IP?** VM needs Cloud NAT for internet access — most common cause of "can't reach internet"
- **Network tags must match** between firewall rule targets and VM tags
- **Priority matters** — lower number wins. A deny at 100 beats allow at 1000
- **Firewall Rules Logging** is the debugging tool — shows ALLOWED/DENIED with specific source/dest
- **Load balancer health checks** need firewall rules from `130.211.0.0/22` and `35.191.0.0/16`
- **Always state your methodology** in interviews — "I'd check in this order..." scores better than jumping to the answer
- **Reference your on-prem experience** — iptables, network troubleshooting, tcpdump all transfer

---

## Part 4 — Quiz (15 min)

**Q1.** An interviewer asks: "A developer says their VM can't reach the internet. It's in a private subnet with no external IP. Cloud NAT is configured. Walk me through your debugging."

<details><summary>Answer</summary>

"Starting from the VM and working outward:

1. **Verify Cloud NAT is on the right router and subnet:** `gcloud compute routers nats list --router=my-router --region=europe-west2` — confirm the NAT covers this VM's subnet
2. **Check the VM is in the correct subnet:** `gcloud compute instances describe vm-name --zone=europe-west2-a` — verify the subnet matches the NAT configuration
3. **Check routing:** `gcloud compute routes list` — confirm a default route (0.0.0.0/0) exists pointing to the default internet gateway
4. **Check egress firewall:** Are there any explicit egress deny rules? `gcloud compute firewall-rules list --filter="direction=EGRESS AND network=my-vpc"`
5. **Test from the VM:**
   - `nslookup google.com` — DNS working?
   - `curl -I https://httpbin.org/ip` — can reach internet?
   - `ip route show` — is the default route present at the OS level?
6. **Check Cloud NAT logs:** If NAT is configured but not working, check for NAT IP exhaustion or port allocation issues

**Most likely causes:** (a) NAT is configured on a different router than the VM's subnet uses, (b) NAT IP allocation is exhausted, (c) Explicit egress deny firewall rule with higher priority."
</details>

**Q2.** "We have a load balancer configured but health checks are failing for all backends. The application is running fine when accessed directly via internal IP. What's wrong?"

<details><summary>Answer</summary>

"This is almost certainly a **firewall rule issue for health check probes**. GCP load balancer health checks originate from specific IP ranges:
- `130.211.0.0/22`
- `35.191.0.0/16`

If there's no firewall rule allowing traffic from these ranges to the backend VMs on the health check port, the firewall silently drops the probes, and the load balancer marks all backends as unhealthy.

**Fix:**
```
gcloud compute firewall-rules create allow-health-checks \
  --network=my-vpc \
  --allow=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=web-backend
```

**Other things to check:**
1. Health check port matches the port the application actually listens on
2. Health check path returns HTTP 200 (not a redirect to HTTPS)
3. Backend VMs have the correct network tags matching the firewall rule
4. Application is bound to `0.0.0.0`, not just `127.0.0.1`"
</details>

**Q3.** "You have VPC peering between VPC-A and VPC-B, but VMs in VPC-A can't reach VMs in VPC-B. Both peering connections show 'Active'. What do you check?"

<details><summary>Answer</summary>

"Peering is active but traffic isn't flowing — I'd check:

1. **Overlapping CIDR ranges:** If both VPCs use the same subnet ranges (e.g., 10.0.1.0/24), routing conflicts prevent communication. Verify with `gcloud compute networks subnets list`.

2. **Firewall rules on BOTH sides:** Peering doesn't bypass firewalls. VPC-B needs an ingress allow rule for traffic from VPC-A's CIDR range, and vice versa. Most people only configure one side.

3. **Export custom routes:** If using custom routes, check that 'Export custom routes' and 'Import custom routes' are enabled on both peering connections.

4. **Transitive routing:** VPC peering is NOT transitive. If VPC-A peers with VPC-B and VPC-B peers with VPC-C, VPC-A cannot reach VPC-C through VPC-B. You need direct peering.

5. **Internal DNS:** Peered VPCs don't automatically resolve each other's internal DNS names. Use internal IP addresses or configure Cloud DNS peering zones.

**Most common cause:** Missing firewall rules on the receiving VPC — peering creates the route but doesn't auto-allow traffic."
</details>

**Q4.** Explain the difference between ingress and egress firewall rules in GCP, and what the default behaviour is.

<details><summary>Answer</summary>

"**Ingress rules** control inbound traffic TO VMs. **Egress rules** control outbound traffic FROM VMs.

**Default behaviour:**
- **Implied deny-all ingress** (priority 65535) — all inbound traffic is blocked unless explicitly allowed
- **Implied allow-all egress** (priority 65535) — all outbound traffic is allowed unless explicitly denied

This means: a new VM can reach the internet and other VMs (egress) but nothing can reach it (ingress) until you create firewall rules.

**Key implications:**
1. You MUST create ingress rules for SSH (tcp:22), HTTP (tcp:80), etc.
2. You generally don't need egress rules unless you want to RESTRICT outbound traffic (e.g., prevent VMs from reaching the internet)
3. When restricting egress, remember to still allow traffic to Google API ranges and metadata server (169.254.169.254)

**Interview tip:** Many candidates confuse the defaults — they think ingress is allowed by default (it's not) because they've only used VPCs with auto-created firewall rules like `default-allow-ssh` and `default-allow-internal`."
</details>
