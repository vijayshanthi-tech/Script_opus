# Day 0 — GCP Fundamentals: Projects, Billing, Regions & Zones

## Today's Objective

Understand the foundational building blocks of Google Cloud Platform — how resources are organized, how billing works, and how the global infrastructure of regions and zones affects your design decisions. Then create your first GCP project and enable the Compute Engine API.

**Source:** [Google Cloud Docs — GCP Basics](https://cloud.google.com/docs/overview)

---

## Part 1: Concept (30 minutes)

### 1.1 GCP Resource Hierarchy

Everything in GCP lives inside a **resource hierarchy**. Think of it as a tree:

```
┌──────────────────────────────────────────────────────┐
│                   Organization                        │
│            (your-company.com domain)                  │
│                                                       │
│   ┌──────────────────┐   ┌──────────────────┐        │
│   │   Folder: Prod   │   │   Folder: Dev    │        │
│   │                  │   │                  │        │
│   │  ┌────────────┐  │   │  ┌────────────┐  │        │
│   │  │ Project A  │  │   │  │ Project C  │  │        │
│   │  │ (prod-app) │  │   │  │ (dev-app)  │  │        │
│   │  └────────────┘  │   │  └────────────┘  │        │
│   │  ┌────────────┐  │   │  ┌────────────┐  │        │
│   │  │ Project B  │  │   │  │ Project D  │  │        │
│   │  │ (prod-data)│  │   │  │ (sandbox)  │  │        │
│   │  └────────────┘  │   │  └────────────┘  │        │
│   └──────────────────┘   └──────────────────┘        │
└──────────────────────────────────────────────────────┘
```

| Level | What It Is | Key Fact |
|---|---|---|
| **Organization** | Top-level node tied to a Google Workspace or Cloud Identity domain | Policies set here cascade down to all folders and projects |
| **Folder** | Grouping mechanism (e.g., by team, environment, department) | Optional but useful for applying policies to a group of projects |
| **Project** | The fundamental unit of organization. All resources (VMs, buckets, datasets) live inside a project | Has a unique **Project ID** (immutable), **Project Name** (editable), and **Project Number** (auto-assigned) |
| **Resource** | Individual services — a VM, a GCS bucket, a BigQuery dataset | Each resource belongs to exactly one project |

#### Key Identifiers

| Identifier | Example | Editable? | Unique? |
|---|---|---|---|
| Project Name | `My Data Lab` | Yes | No (can duplicate) |
| Project ID | `my-data-lab-385217` | No (set at creation) | Yes (globally unique) |
| Project Number | `482947103856` | No (auto-assigned) | Yes |

> **Linux analogy:** A project is like a separate Linux server — it has its own resources, its own IAM (users/permissions), and its own billing. Folders are like organizing servers into racks.

---

### 1.2 Billing in GCP

Billing controls **who pays** for what. Understanding it prevents surprise charges.

```
┌───────────────────────────────────┐
│       Billing Account             │
│  (linked to payment method)       │
│                                   │
│  ┌───────────┐  ┌───────────┐    │
│  │ Project A │  │ Project B │    │
│  │  $12/mo   │  │   $5/mo   │    │
│  └───────────┘  └───────────┘    │
└───────────────────────────────────┘
```

#### Billing Concepts

| Concept | Description |
|---|---|
| **Billing Account** | Holds a payment method (credit card, invoice). One billing account can pay for multiple projects |
| **Budget** | A threshold you set (e.g., $10/month). Does NOT stop spending — only sends alerts |
| **Budget Alerts** | Email notifications at thresholds (e.g., 50%, 80%, 100% of budget) |
| **Billing Export** | Sends detailed billing data to BigQuery for analysis |
| **Free Tier** | Many services have an always-free tier (e.g., 5 GB in GCS, 1 TB BQ queries/month) |
| **Quotas** | Hard limits on resource usage (e.g., max 24 CPUs per region). Protects against runaway spend |
| **Labels** | Key-value tags (e.g., `env:dev`, `team:data`) you attach to resources for cost tracking |

#### Billing Hierarchy

```
Organization
  └── Billing Account (payment method)
        ├── Project A → resources → costs
        ├── Project B → resources → costs
        └── Project C → resources → costs
```

#### Cost Control Best Practices

1. **Always set a budget alert** — even if you're on free tier
2. **Use labels** — tag resources by environment, team, or purpose
3. **Export billing to BigQuery** — analyze costs with SQL
4. **Disable unused APIs** — some APIs have minimum charges
5. **Delete resources after labs** — VMs and clusters cost money when idle

> **Important:** Budgets are alerts only. To actually cap spending, you need to set up programmatic budget actions (Cloud Functions that shut down resources when thresholds are hit).

---

### 1.3 Regions and Zones

GCP's infrastructure spans the globe. Understanding regions and zones is critical for latency, availability, and compliance.

```
┌──────────────────────────────────────────────────────────────────┐
│                     GCP Global Infrastructure                     │
│                                                                   │
│  ┌─────────────────────┐   ┌─────────────────────┐              │
│  │  Region: europe-west2│   │  Region: us-central1│              │
│  │  (London)            │   │  (Iowa)              │              │
│  │                     │   │                     │              │
│  │  ┌───────────────┐  │   │  ┌───────────────┐  │              │
│  │  │ Zone: ew2-a   │  │   │  │ Zone: uc1-a   │  │              │
│  │  │ (Data Center 1)│  │   │  │ (Data Center 1)│  │              │
│  │  └───────────────┘  │   │  └───────────────┘  │              │
│  │  ┌───────────────┐  │   │  ┌───────────────┐  │              │
│  │  │ Zone: ew2-b   │  │   │  │ Zone: uc1-b   │  │              │
│  │  │ (Data Center 2)│  │   │  │ (Data Center 2)│  │              │
│  │  └───────────────┘  │   │  └───────────────┘  │              │
│  │  ┌───────────────┐  │   │  ┌───────────────┐  │              │
│  │  │ Zone: ew2-c   │  │   │  │ Zone: uc1-c   │  │              │
│  │  │ (Data Center 3)│  │   │  │ Zone: uc1-f   │  │              │
│  │  └───────────────┘  │   │  └───────────────┘  │              │
│  └─────────────────────┘   └─────────────────────┘              │
│                                                                   │
│  ┌─────────────────────┐   ┌─────────────────────┐              │
│  │  Region: asia-south1│   │  Region: us-east1   │              │
│  │  (Mumbai)           │   │  (S. Carolina)       │              │
│  │  ...                │   │  ...                 │              │
│  └─────────────────────┘   └─────────────────────┘              │
└──────────────────────────────────────────────────────────────────┘
```

#### Key Definitions

| Term | Definition | Example |
|---|---|---|
| **Region** | A specific geographic location containing multiple zones | `europe-west2` (London), `us-central1` (Iowa) |
| **Zone** | An isolated deployment area within a region (think: independent data center) | `europe-west2-a`, `europe-west2-b` |
| **Multi-region** | A large geographic area containing two or more regions | `EU`, `US` (used for GCS, BigQuery) |

#### How Resources Map to Regions/Zones

| Resource Type | Scope | Example |
|---|---|---|
| **Zonal** | Lives in a single zone. If the zone goes down, resource is unavailable | Compute Engine VMs, Persistent Disks |
| **Regional** | Replicated across zones within a region. Survives single zone failure | Cloud SQL (HA), Regional GCS buckets |
| **Multi-regional** | Replicated across regions. Highest availability | Multi-region GCS buckets, BigQuery datasets |
| **Global** | Not tied to any region | IAM policies, VPC networks, Cloud DNS |

#### Choosing a Region — Decision Factors

| Factor | Guidance |
|---|---|
| **Latency** | Choose a region close to your users (e.g., `europe-west2` for UK users) |
| **Cost** | Pricing varies by region. `us-central1` is often cheapest |
| **Compliance** | Data residency laws may require data to stay in a specific country/region |
| **Service availability** | Not all services are available in every region. Check [cloud.google.com/about/locations](https://cloud.google.com/about/locations) |
| **Disaster recovery** | For DR, pick a secondary region far from the primary |

> **VMO2 context:** Since VMO2 operates in the UK, `europe-west2` (London) is your primary region for low latency and data residency compliance.

---

### 1.4 How Projects, Billing, and Regions Connect

```
┌─────────────────────────────────────────────────────┐
│                     PROJECT                          │
│                                                      │
│  Billing Account ──── pays for ────► Resources       │
│                                                      │
│  Resources are deployed in:                          │
│    • Specific zones   (VMs, disks)                   │
│    • Specific regions (Cloud SQL, regional buckets)  │
│    • Multi-regions    (BigQuery, multi-region GCS)   │
│    • Global scope     (IAM, VPC)                     │
│                                                      │
│  IAM policies control WHO can access WHAT            │
│  Labels track cost by team/env/purpose               │
└─────────────────────────────────────────────────────┘
```

---

## Part 2: Hands-On Lab (60 minutes)

### Lab: Create a GCP Project + Enable Compute Engine API

---

### Step 1: Create a New Project via Console (10 min)

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Click the **project selector** dropdown (top-left, next to "Google Cloud")
3. Click **NEW PROJECT**
4. Fill in:
   - **Project name:** `gcp-fundamentals-lab`
   - **Organization:** Select yours (or leave as "No organization" for personal accounts)
   - **Location:** Choose a folder or leave at root
5. Click **CREATE**

Record your identifiers:
```
Project Name:   gcp-fundamentals-lab
Project ID:     __________________________ (auto-generated, note it down)
Project Number: __________________________ (find in project dashboard)
```

**Via Cloud Shell (alternative):**
```bash
# Create the project
gcloud projects create gcp-fundamentals-lab --name="GCP Fundamentals Lab"

# Verify
gcloud projects describe gcp-fundamentals-lab

# Set as active project
gcloud config set project gcp-fundamentals-lab
```

**Expected output:**
```
Create in progress for [https://cloudresourcemanager.googleapis.com/v1/projects/gcp-fundamentals-lab].
Waiting for [operations/cp.xxxx] to finish...done.
```

---

### Step 2: Link a Billing Account (5 min)

1. Navigate to **Billing** in the left menu (or search for "Billing" in the top search bar)
2. If prompted, click **LINK A BILLING ACCOUNT**
3. Select your billing account from the dropdown
4. Click **SET ACCOUNT**

**Via gcloud:**
```bash
# List available billing accounts
gcloud billing accounts list

# Link billing to your project (replace BILLING_ACCOUNT_ID)
gcloud billing projects link gcp-fundamentals-lab \
  --billing-account=XXXXXX-XXXXXX-XXXXXX
```

---

### Step 3: Set a Budget Alert (5 min)

1. Go to **Billing → Budgets & Alerts**
2. Click **CREATE BUDGET**
3. Configure:
   - **Name:** `fundamentals-budget`
   - **Projects:** Select `gcp-fundamentals-lab`
   - **Amount:** `$5` (more than enough for learning)
   - **Alert thresholds:** `50%`, `80%`, `100%`
   - **Email alerts to:** billing admins and project owners
4. Click **FINISH**

> You'll get email alerts if your spending approaches $5. For this lab, you'll spend $0 (free tier).

---

### Step 4: Explore Regions and Zones (10 min)

```bash
# List all available regions
gcloud compute regions list

# Expected output (truncated):
# NAME             CPUS  DISKS_GB  ADDRESSES  RESERVED_ADDRESSES  STATUS
# asia-east1       0/24  0/4096    0/8        0/8                 UP
# europe-west2     0/24  0/4096    0/8        0/8                 UP
# us-central1      0/24  0/4096    0/8        0/8                 UP
# ...

# List all zones in europe-west2 (London)
gcloud compute zones list --filter="region:europe-west2"

# Expected output:
# NAME             REGION         STATUS
# europe-west2-a   europe-west2   UP
# europe-west2-b   europe-west2   UP
# europe-west2-c   europe-west2   UP

# Set a default region and zone
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-a

# Verify your configuration
gcloud config list
```

---

### Step 5: Enable the Compute Engine API (5 min)

```bash
# Enable Compute Engine API
gcloud services enable compute.googleapis.com

# Expected output:
# Operation "operations/acat.p2-XXXXXXX-XXXX" finished successfully.

# Verify it's enabled
gcloud services list --enabled --filter="name:compute"

# Expected output:
# NAME                       TITLE
# compute.googleapis.com     Compute Engine API
```

---

### Step 6: Verify Everything Works (10 min)

Run this verification script to confirm your setup:

```bash
echo "=== GCP Fundamentals Lab Verification ==="
echo ""

# 1. Project info
echo "1. PROJECT INFO"
gcloud config get-value project
echo ""

# 2. Billing status
echo "2. BILLING STATUS"
gcloud billing projects describe $(gcloud config get-value project) \
  --format="value(billingEnabled)"
echo ""

# 3. Default region and zone
echo "3. DEFAULT REGION & ZONE"
gcloud config get-value compute/region
gcloud config get-value compute/zone
echo ""

# 4. Compute API enabled
echo "4. COMPUTE API STATUS"
gcloud services list --enabled --filter="name:compute" --format="value(name)"
echo ""

echo "=== Verification Complete ==="
```

**Expected output:**
```
=== GCP Fundamentals Lab Verification ===

1. PROJECT INFO
gcp-fundamentals-lab

2. BILLING STATUS
True

3. DEFAULT REGION & ZONE
europe-west2
europe-west2-a

4. COMPUTE API STATUS
compute.googleapis.com

=== Verification Complete ===
```

---

### Step 7: Explore the Console (15 min)

Navigate through these pages and note what you see:

| Console Page | What to Look For |
|---|---|
| **Dashboard** (`console.cloud.google.com/home/dashboard`) | Project info card, resource summary, API activity |
| **IAM & Admin → IAM** | Your role (Owner), how permissions are structured |
| **APIs & Services → Dashboard** | Which APIs are enabled, traffic graphs |
| **APIs & Services → Library** | Browse all available APIs (2000+) |
| **Billing → Overview** | Billing account, linked projects, cost breakdown |
| **Billing → Reports** | Cost trends over time (nothing yet, but bookmark it) |
| **Compute Engine → VM Instances** | Empty for now — we'll use this in later labs |

---

## Part 3: Revision (15 minutes)

### 5-Minute Revision Sheet

#### Projects
- A **project** is the fundamental unit — all resources live inside one
- Three identifiers: **Name** (editable), **ID** (immutable, globally unique), **Number** (auto-assigned)
- Hierarchy: Organization → Folders → Projects → Resources
- IAM policies can be set at any level and **inherit downward**

#### Billing
- A **billing account** holds the payment method and can fund multiple projects
- **Budgets** are alerts only — they don't stop spending
- Always set budget alerts at 50%, 80%, 100%
- Use **labels** to track costs per team/environment
- Use **billing export to BigQuery** for detailed cost analysis
- **Free tier** covers most learning activities ($0 cost)

#### Regions & Zones
- **Region** = geographic location (e.g., `europe-west2` = London)
- **Zone** = isolated data center within a region (e.g., `europe-west2-a`)
- **Multi-region** = `EU`, `US` — used for high-availability storage (GCS, BigQuery)
- Resources have different scopes: **zonal** (VM), **regional** (Cloud SQL HA), **multi-regional** (GCS), **global** (IAM)
- Choose region based on: **latency**, **cost**, **compliance**, **service availability**
- For UK workloads: default to `europe-west2`

#### Key gcloud Commands
```bash
gcloud projects create PROJECT_ID          # Create a project
gcloud config set project PROJECT_ID       # Switch active project
gcloud billing accounts list               # List billing accounts
gcloud compute regions list                # List all regions
gcloud compute zones list                  # List all zones
gcloud services enable SERVICE.googleapis.com  # Enable an API
gcloud config set compute/region REGION    # Set default region
gcloud config set compute/zone ZONE        # Set default zone
```

---

## Part 4: Quiz (15 minutes)

### Self-Test Questions

**Q1:** What are the three identifiers for a GCP project? Which one is immutable?
<details>
<summary>Answer</summary>
Project Name (editable), Project ID (immutable, globally unique), Project Number (auto-assigned, immutable). The <b>Project ID</b> is set at creation and cannot be changed.
</details>

**Q2:** Does setting a budget in GCP automatically stop spending when the limit is reached?
<details>
<summary>Answer</summary>
No. Budgets in GCP are <b>alerts only</b>. They send email notifications at configured thresholds but do not stop resource usage. To cap spending, you need to set up programmatic budget actions (e.g., a Cloud Function that shuts down VMs).
</details>

**Q3:** A company in London wants low-latency access and must comply with UK data residency laws. Which region and why?
<details>
<summary>Answer</summary>
<b>europe-west2</b> (London). It provides the lowest latency for UK users and keeps data within the UK for compliance with data residency regulations.
</details>

**Q4:** What's the difference between a region and a zone? Give an example.
<details>
<summary>Answer</summary>
A <b>region</b> is a geographic location (e.g., <code>europe-west2</code> = London). A <b>zone</b> is an isolated deployment area (data center) within that region (e.g., <code>europe-west2-a</code>). Each region has 3+ zones. If one zone fails, resources in other zones within the same region continue to operate.
</details>

**Q5:** You have a VM in `us-central1-a` and the zone goes down. What happens to your VM?
<details>
<summary>Answer</summary>
The VM becomes <b>unavailable</b>. VMs are <b>zonal resources</b> — they exist in a single zone. To survive zone failures, you need to design for redundancy: use managed instance groups spread across multiple zones, or use regional services.
</details>

**Q6:** What is the GCP resource hierarchy from top to bottom?
<details>
<summary>Answer</summary>
<b>Organization → Folders → Projects → Resources</b>. IAM policies set at a higher level inherit downward. Folders are optional grouping mechanisms.
</details>

**Q7:** You've been asked to track cloud costs separately for the dev and prod teams. How would you do this?
<details>
<summary>Answer</summary>
Use <b>labels</b> on all resources (e.g., <code>team:dev</code>, <code>team:prod</code>). Separate projects per team is also an option for stronger isolation. Enable <b>billing export to BigQuery</b> and query costs grouped by label.
</details>

**Q8:** A teammate created a project with ID `my-project-123` but wants to change it to `data-project-456`. Is this possible?
<details>
<summary>Answer</summary>
No. The <b>Project ID is immutable</b> — it's set at creation and cannot be changed. The teammate can change the <b>Project Name</b>, or create a new project with the desired ID and migrate resources.
</details>

---

## Cleanup

For this lab, no cleanup is needed — the project itself costs nothing. The Compute Engine API is free to enable; charges only occur when you create resources (VMs, disks, etc.).

If you want to start fresh later:
```bash
# Delete the project (this deletes ALL resources inside it)
gcloud projects delete gcp-fundamentals-lab
```

---

## What's Next

Now that you understand GCP's foundational structure, you're ready for **Day 1 — GCP Data Services Overview + Project Setup**, where you'll explore the full data engineering toolkit and set up a project geared towards data services.
