# Week 1, Day 1 (Mon) — Server Basics, SSH Keys, OS Login Overview

## Today's Objective

Understand how SSH access works on GCP Compute Engine, the role of OS Login, and how to create and manage SSH key pairs securely.

**Source:** [Docs: OS Login](https://cloud.google.com/compute/docs/instances/managing-instance-access) | [Docs: SSH](https://cloud.google.com/compute/docs/instances/ssh)

**Deliverable:** SSH safety notes + OS Login configuration document

---

## Part 1: Concept (30 minutes)

### 1.1 How SSH Works on GCP

SSH on GCP works differently from traditional on-prem servers. There are **three methods** to SSH into a VM:

```
┌─────────────────────────────────────────────────────────┐
│               SSH ACCESS METHODS ON GCP                  │
│                                                          │
│  ┌───────────────┐  ┌───────────────┐  ┌─────────────┐  │
│  │  gcloud SSH   │  │  Console SSH  │  │  Manual SSH  │  │
│  │               │  │  (Browser)    │  │  (ssh cmd)   │  │
│  │  Auto-manages │  │  Opens SSH    │  │  You manage  │  │
│  │  keys via     │  │  in browser   │  │  keys in     │  │
│  │  metadata or  │  │  tab, injects │  │  metadata or │  │
│  │  OS Login     │  │  temp keys    │  │  OS Login    │  │
│  └───────────────┘  └───────────────┘  └─────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 1.2 Metadata-Based SSH vs OS Login

| Feature | Metadata SSH Keys | OS Login |
|---|---|---|
| **How keys are stored** | In project or instance metadata | In the user's Google identity (Cloud Identity / Workspace) |
| **Access control** | Anyone with metadata edit access can add keys | IAM roles control who can SSH |
| **Audit** | Hard to track who added which key | Full IAM audit trail |
| **POSIX accounts** | Generic username | Mapped to Google identity |
| **2FA support** | No | Yes (OS Login + 2FA) |
| **Best for** | Quick labs, personal projects | Production, teams, compliance |

### 1.3 OS Login — The Recommended Approach

```
┌──────────────────────────────────────────────────┐
│                   OS Login Flow                   │
│                                                   │
│  User ──► IAM Check ──► SSH Key from Identity     │
│              │                    │                │
│              ▼                    ▼                │
│    roles/compute.osLogin    POSIX account          │
│    or                       auto-created           │
│    roles/compute.osAdminLogin    on VM             │
│                                                   │
│  No keys in metadata!                             │
│  All controlled by IAM!                            │
└──────────────────────────────────────────────────┘
```

#### OS Login IAM Roles

| Role | Grants | Use Case |
|---|---|---|
| `roles/compute.osLogin` | Non-root SSH access | Regular users |
| `roles/compute.osAdminLogin` | Root (sudo) SSH access | Admins |
| `roles/iam.serviceAccountUser` | SSH to VMs with a service account | Service account VMs |

#### Enabling OS Login

```bash
# Enable at project level (all VMs)
gcloud compute project-info add-metadata \
  --metadata enable-oslogin=TRUE

# Enable for a specific VM only
gcloud compute instances add-metadata VM_NAME \
  --metadata enable-oslogin=TRUE
```

### 1.4 SSH Key Pairs — How They Work

```
┌──────────────────┐          ┌──────────────────┐
│  Your Machine     │          │    GCP VM         │
│                   │          │                   │
│  Private Key      │──SSH──►  │  Public Key       │
│  (~/.ssh/id_rsa)  │ Auth     │  (~/.ssh/         │
│  NEVER share!     │          │   authorized_keys)│
│                   │          │                   │
└──────────────────┘          └──────────────────┘
```

| Key | Location | Share? | Purpose |
|---|---|---|---|
| **Private key** | Your local machine (`~/.ssh/id_rsa`) | NEVER | Proves your identity |
| **Public key** | Remote server (`~/.ssh/authorized_keys`) | Yes | Verifies your identity |

### 1.5 Security Best Practices for SSH

| Practice | Why | How |
|---|---|---|
| **Use OS Login** | IAM-controlled, auditable | `enable-oslogin=TRUE` metadata |
| **Disable metadata SSH keys** | Prevent unauthorized key injection | `enable-oslogin=TRUE` blocks metadata keys |
| **Use IAP Tunnel** | No external IP needed, no port 22 exposed | `gcloud compute ssh --tunnel-through-iap` |
| **Restrict firewall** | Only allow SSH from known IPs | Firewall rule: allow tcp:22 from your IP only |
| **Use SSH config** | Simplify and secure connections | `~/.ssh/config` with specific key per host |
| **Rotate keys** | Reduce window if key is compromised | Regular key rotation policy |

> **Linux analogy:** OS Login is like centralized SSH key management via LDAP/FreeIPA instead of manually copying keys to `/root/.ssh/authorized_keys` on each server.

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create an SSH Key Pair (10 min)

```bash
# In Cloud Shell (or your local terminal)

# Generate an RSA key pair
ssh-keygen -t rsa -b 4096 -C "your-email@example.com" -f ~/.ssh/gcp_lab_key

# View the public key
cat ~/.ssh/gcp_lab_key.pub

# Expected output:
# ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ... your-email@example.com
```

### Step 2: Create a VM with OS Login Enabled (10 min)

```bash
# Create VM with OS Login
gcloud compute instances create ssh-lab-vm \
  --zone=europe-west2-a \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --metadata=enable-oslogin=TRUE

**Actual Output**

 vijibrabhaharan@cloudshell:~ (gcp-fundamentals-lab-492711)$ gcloud compute instances create ssh-lab-vm --zone=europe-west2-a --machine-type=e2-micro --image-family=debian-12 --image-project=debian-cloud --metadata=enable-oslogin=TRUE
Created [https://www.googleapis.com/compute/v1/projects/gcp-fundamentals-lab-492711/zones/europe-west2-a/instances/ssh-lab-vm].
NAME: ssh-lab-vm
ZONE: europe-west2-a
MACHINE_TYPE: e2-micro
PREEMPTIBLE: 
INTERNAL_IP: 10.154.0.4
EXTERNAL_IP: 34.89.8.44
STATUS: RUNNING
vijibrabhaharan@cloudshell:~ (gcp-fundamentals-lab-492711)$ 

# Verify OS Login is set
gcloud compute instances describe ssh-lab-vm \
  --zone=europe-west2-a \
  --format="value(metadata.items)"
```
**Actual output**
vijibrabhaharan@cloudshell:~ (gcp-fundamentals-lab-492711)$ gcloud compute instances describe ssh-lab-vm --zone=europe-west2-a --format="value(metadata.items)"
{'key': 'enable-oslogin', 'value': 'TRUE'}
vijibrabhaharan@cloudshell:~ (gcp-fundamentals-lab-492711)$ 


### Step 3: SSH Using gcloud (5 min)

```bash
# SSH via gcloud (auto-manages keys)
gcloud compute ssh ssh-lab-vm --zone=europe-west2-a

# Once inside, verify your username
whoami
# With OS Login: external_username (e.g., ext_v_brabhaharan_accenture_com)
# Without OS Login: your local username

# Check authorized keys
cat ~/.ssh/authorized_keys

exit
```

### Step 4: SSH via IAP Tunnel (No External IP) (15 min)

```bash
# Create a VM without external IP
gcloud compute instances create private-ssh-vm \
  --zone=europe-west2-a \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --no-address \
  --metadata=enable-oslogin=TRUE

# SSH via IAP Tunnel (works without external IP!)
gcloud compute ssh private-ssh-vm \
  --zone=europe-west2-a \
  --tunnel-through-iap

**Actual Output**

vijibrabhaharan@cloudshell:~ (gcp-fundamentals-lab-492711)$ gcloud services enable iap.googleapis.com
Operation "operations/acat.p2-100267315481-e3ca8d85-ab9e-441f-b63d-26e896a399ca" finished successfully.
vijibrabhaharan@cloudshell:~ (gcp-fundamentals-lab-492711)$ gcloud compute firewall-rules create allow-ssh-from-iap \
  --direction=INGRESS \
  --network=default \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=35.235.240.0/20
Creating firewall...working..Created [https://www.googleapis.com/compute/v1/projects/gcp-fundamentals-lab-492711/global/firewalls/allow-ssh-from-iap].      
Creating firewall...done.                                                                                                                                   
NAME: allow-ssh-from-iap
NETWORK: default
DIRECTION: INGRESS
PRIORITY: 1000
ALLOW: tcp:22
DENY: 
DISABLED: False
vijibrabhaharan@cloudshell:~ (gcp-fundamentals-lab-492711)$ gcloud compute instances describe private-ssh-vm \
  --zone=europe-west2-a \
  --format="value(status)"
RUNNING
vijibrabhaharan@cloudshell:~ (gcp-fundamentals-lab-492711)$ gcloud compute ssh private-ssh-vm \
  --zone=europe-west2-a \
  --tunnel-through-iap
WARNING: 

To increase the performance of the tunnel, consider installing NumPy. For instructions,
please see https://cloud.google.com/iap/docs/using-tcp-forwarding#increasing_the_tcp_upload_bandwidth

Warning: Permanently added 'compute.369144874436753747' (ED25519) to the list of known hosts.
Linux private-ssh-vm 6.1.0-43-cloud-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.1.162-1 (2026-02-08) x86_64

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.
Creating directory '/home/vijibrabhaharan_gmail_com'.
vijibrabhaharan_gmail_com@private-ssh-vm:~$ 

# Verify: no external IP
curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip
# Should return empty or error

exit
```

### Step 5: Restrict SSH via Firewall (10 min)

1, Exit the private VM first:
2, Run curl ifconfig.me from Cloud Shell (Step 5 is meant to be run from Cloud Shell, not from inside the VM):

That's expected — private-ssh-vm has no external IP and no internet access. It can't reach ifconfig.me (or any external site).

This confirms the whole point of Step 4: this VM is completely isolated from the internet, yet you were still able to SSH into it via IAP.

```bash
# Find your current public IP
curl ifconfig.me

vijibrabhaharan_gmail_com@private-ssh-vm:~$ curl ifconfig.me

curl: (28) Failed to connect to ifconfig.me port 80 after 130121 ms: Couldn't connect to server
vijibrabhaharan_gmail_com@private-ssh-vm:~$ 
vijibrabhaharan_gmail_com@private-ssh-vm:~$ exit
logout
Connection to compute.369144874436753747 closed.
vijibrabhaharan@cloudshell:~ (gcp-fundamentals-lab-492711)$ curl ifconfig.me
34.126.84.70
vijibrabhaharan@cloudshell:~ (gcp-fundamentals-lab-492711)$

**Key takeaway to note**
: A VM with --no-address has no outbound internet either — not just no inbound. It can only communicate within the VPC (and via IAP tunnel for management). In production, if a private VM needs to reach the internet (e.g., for apt update), you'd use a Cloud NAT.

# Create a firewall rule allowing SSH only from your IP
gcloud compute firewall-rules create allow-ssh-my-ip \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=YOUR_PUBLIC_IP/32 \
  --target-tags=restricted-ssh

# Apply tag to VM
gcloud compute instances add-tags ssh-lab-vm \
  --zone=europe-west2-a \
  --tags=restricted-ssh
```

### Step 6: Review SSH Configuration (5 min)

```bash
# View your SSH config
cat ~/.ssh/config

# View gcloud-managed SSH keys
ls -la ~/.ssh/google_compute_*

# View project-level SSH keys
gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items.filter(key:ssh-keys))"
```

### Step 7: Clean Up (5 min)

```bash
gcloud compute instances delete ssh-lab-vm private-ssh-vm \
  --zone=europe-west2-a --quiet

gcloud compute firewall-rules delete allow-ssh-my-ip --quiet
```

---

## Part 3: Revision (15 minutes)

### Quick Reference

- **3 SSH methods:** gcloud ssh (auto-keys), Console (browser), manual (your keys)
- **OS Login:** IAM-controlled SSH. Enable with `enable-oslogin=TRUE`. Best for teams/production
- **Metadata SSH:** Keys stored in project/instance metadata. Simpler but less secure
- **IAP Tunnel:** SSH without external IP. Uses `--tunnel-through-iap` flag. Most secure
- **Key pair:** Private key (yours, never share) + Public key (put on server)
- **OS Login roles:** `compute.osLogin` (normal), `compute.osAdminLogin` (sudo)

### Key Commands

```bash
gcloud compute ssh VM_NAME --zone=ZONE                    # SSH via gcloud
gcloud compute ssh VM_NAME --tunnel-through-iap            # SSH via IAP (no external IP)
gcloud compute project-info add-metadata --metadata enable-oslogin=TRUE  # Enable OS Login
ssh-keygen -t rsa -b 4096 -C "email" -f ~/.ssh/KEY_NAME   # Generate key pair
```

---

## Part 4: Quiz (15 minutes)

**Q1:** What are the two SSH key management approaches on GCP? Which is recommended for production?
<details><summary>Answer</summary>
<b>Metadata-based SSH keys</b> (stored in project/instance metadata) and <b>OS Login</b> (keys tied to Google identity, IAM-controlled). OS Login is recommended for production because it provides IAM-based access control, full audit trails, and optional 2FA.
</details>

**Q2:** How do you SSH into a VM that has no external IP address?
<details><summary>Answer</summary>
Use <b>IAP (Identity-Aware Proxy) Tunnel</b>: <code>gcloud compute ssh VM_NAME --tunnel-through-iap</code>. This creates a secure tunnel through Google's network without exposing port 22 to the internet.
</details>

**Q3:** What IAM role grants sudo access via OS Login?
<details><summary>Answer</summary>
<code>roles/compute.osAdminLogin</code> grants root/sudo SSH access. <code>roles/compute.osLogin</code> grants non-root access only.
</details>

**Q4:** Why should you restrict SSH firewall rules to specific source IPs?
<details><summary>Answer</summary>
To reduce the attack surface. The default <code>allow-ssh</code> rule allows port 22 from <code>0.0.0.0/0</code> (anywhere). Restricting to your IP/VPN range prevents brute-force attacks and unauthorized access attempts.
</details>
