# Day 1 — GCP Data Services Overview + Project Setup

## Today's Objective

Understand the GCP data ecosystem at a high level — what services exist, when to use each one, and how they connect. Then set up your GCP project properly for all future labs.

---

## Part 1: Concept (30 minutes)

### The GCP Data Services Landscape

As a Linux infra engineer, you already understand compute, networking, and storage. Data engineering on GCP adds a **data processing layer** on top. Here's the map:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DATA SOURCES                                 │
│  Apps, IoT, Logs, Databases, Files, APIs, Streaming Events          │
└──────────────┬──────────────────────────────────┬───────────────────┘
               │                                  │
         [BATCH INGESTION]                 [STREAMING INGESTION]
               │                                  │
        ┌──────▼──────┐                   ┌───────▼───────┐
        │ Cloud Storage│                   │   Pub/Sub     │
        │   (GCS)      │                   │  (Messaging)  │
        └──────┬──────┘                   └───────┬───────┘
               │                                  │
               └──────────┬───────────────────────┘
                          │
                   [DATA PROCESSING]
                          │
          ┌───────────────┼───────────────────┐
          │               │                   │
   ┌──────▼──────┐ ┌─────▼──────┐  ┌─────────▼────────┐
   │  Dataflow   │ │  Dataproc  │  │  Data Fusion      │
   │ (Beam-based │ │ (Spark/    │  │  (Visual ETL,     │
   │  serverless)│ │  Hadoop)   │  │   CDAP-based)     │
   └──────┬──────┘ └─────┬──────┘  └─────────┬────────┘
          │               │                   │
          └───────────────┼───────────────────┘
                          │
                   [DATA STORAGE / WAREHOUSE]
                          │
          ┌───────────────┼───────────────────┐
          │               │                   │
   ┌──────▼──────┐ ┌─────▼──────┐  ┌─────────▼────────┐
   │  BigQuery   │ │ Cloud SQL  │  │  Cloud Spanner    │
   │ (Warehouse, │ │ (RDBMS,    │  │  (Global RDBMS,   │
   │  serverless)│ │  regional) │  │   horizontal)     │
   └──────┬──────┘ └────────────┘  └──────────────────┘
          │
   [ORCHESTRATION]          [GOVERNANCE]         [MONITORING]
   Cloud Composer           Data Catalog          Cloud Monitoring
   (Managed Airflow)        Dataplex              Cloud Logging
                            Cloud DLP
```

### When To Use What — The Decision Tree

**For Storage:**
| Question | Answer | Service |
|---|---|---|
| Need to store files/objects? | Yes | **Cloud Storage (GCS)** |
| Need a relational database? | Yes, single region | **Cloud SQL** |
| Need a relational database? | Yes, global scale | **Cloud Spanner** |
| Need a data warehouse for analytics? | Yes | **BigQuery** |
| Need a NoSQL key-value store? | Yes | **Bigtable** |
| Need a NoSQL document store? | Yes | **Firestore** |

**For Processing:**
| Question | Answer | Service |
|---|---|---|
| New pipeline, no existing Spark code? | Yes | **Dataflow** (serverless, auto-scales) |
| Existing Spark/Hadoop jobs to migrate? | Yes | **Dataproc** (managed clusters) |
| Non-technical team needs visual ETL? | Yes | **Data Fusion** (drag-and-drop) |
| Need to orchestrate multiple steps? | Yes | **Cloud Composer** (Airflow) |

**For Messaging:**
| Question | Answer | Service |
|---|---|---|
| Need real-time event streaming? | Yes | **Pub/Sub** |
| Need Kafka compatibility? | Yes | **Managed Kafka (or Pub/Sub Lite)** |

### Why This Matters For Your Background

As a Linux infra person, you've managed servers, file systems, cron jobs, and scripts. Here's how to map your knowledge:

| Linux Infra Concept | GCP Data Equivalent |
|---|---|
| NFS / file server | Cloud Storage (GCS) |
| PostgreSQL on a VM | Cloud SQL |
| Cron jobs | Cloud Composer (Airflow) |
| Shell scripts for ETL | Dataflow (Apache Beam) |
| Log files piped to a queue | Pub/Sub |
| Data sitting in files for reporting | BigQuery |

---

## Part 2: Hands-On Lab (60 minutes)

### Lab: Set Up Your GCP Data Engineering Project

#### Prerequisites
- Google account
- Web browser (Chrome recommended)
- Credit card for billing setup (you won't be charged if you stay within free tier)

---

### Step 1: Create a New GCP Project (10 min)

```bash
# Open Google Cloud Console
# URL: https://console.cloud.google.com

# Click on the project selector (top left, next to "Google Cloud")
# Click "NEW PROJECT"
# Project name: gcp-data-eng-learning
# Note your PROJECT_ID (auto-generated, like: gcp-data-eng-learning-12345)
```

If you prefer the command line (Cloud Shell):
```bash
# Open Cloud Shell (click the terminal icon in the top right of Console)

# Create the project
gcloud projects create gcp-data-eng-learning --name="GCP Data Eng Learning"

# Set it as your active project
gcloud config set project gcp-data-eng-learning
```

**Expected output:**
```
Create in progress for [https://cloudresourcemanager.googleapis.com/v1/projects/gcp-data-eng-learning].
Waiting for [operations/cp.xxxx] to finish...done.
Updated property [core/project].
```

---

### Step 2: Link Billing & Set Budget Alert (5 min)

```bash
# In Console: Go to Billing > Link a billing account to your project

# IMPORTANT: Set a budget alert
# Go to: Billing > Budgets & alerts > CREATE BUDGET
# Budget name: learning-budget
# Amount: $10/month (you'll likely use $0-5)
# Alert thresholds: 50%, 80%, 100%
```

**Why:** GCP free tier is generous but you want safety nets. Most labs we'll do cost $0-2/month total.

---

### Step 3: Enable Required APIs (10 min)

```bash
# In Cloud Shell, enable all the APIs we'll use over 8 weeks:

gcloud services enable \
  bigquery.googleapis.com \
  storage.googleapis.com \
  pubsub.googleapis.com \
  dataflow.googleapis.com \
  composer.googleapis.com \
  dataproc.googleapis.com \
  sqladmin.googleapis.com \
  dlp.googleapis.com \
  datacatalog.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com
```

**Expected output:**
```
Operation "operations/acat.p2-xxxx" finished successfully.
```

Verify:
```bash
gcloud services list --enabled --filter="name:bigquery OR name:storage OR name:pubsub"
```

**Expected output:**
```
NAME                              TITLE
bigquery.googleapis.com           BigQuery API
pubsub.googleapis.com             Cloud Pub/Sub API
storage.googleapis.com            Cloud Storage API
```

---

### Step 4: Create a Cloud Storage Bucket (10 min)

```bash
# Set a variable for your project ID
export PROJECT_ID=$(gcloud config get-value project)

# Create a regional bucket (us-central1 is cheapest for learning)
gsutil mb -l us-central1 gs://${PROJECT_ID}-data-lake

# Verify it was created
gsutil ls
```

**Expected output:**
```
gs://gcp-data-eng-learning-data-lake/
```

```bash
# Create folder structure for our future labs
gsutil cp /dev/null gs://${PROJECT_ID}-data-lake/raw/
gsutil cp /dev/null gs://${PROJECT_ID}-data-lake/processed/
gsutil cp /dev/null gs://${PROJECT_ID}-data-lake/archive/

# List the structure
gsutil ls gs://${PROJECT_ID}-data-lake/
```

**Expected output:**
```
gs://gcp-data-eng-learning-data-lake/archive/
gs://gcp-data-eng-learning-data-lake/processed/
gs://gcp-data-eng-learning-data-lake/raw/
```

---

### Step 5: Create a BigQuery Dataset (10 min)

```bash
# Create a dataset for our learning exercises
bq mk --dataset --location=us-central1 ${PROJECT_ID}:learning_dataset

# Verify
bq ls
```

**Expected output:**
```
     datasetId
 ----------------
  learning_dataset
```

```bash
# Run your first query on a public dataset
bq query --use_legacy_sql=false \
  'SELECT name, number 
   FROM `bigquery-public-data.usa_names.usa_1910_current` 
   WHERE year = 2020 
   ORDER BY number DESC 
   LIMIT 5'
```

**Expected output:**
```
+----------+--------+
|   name   | number |
+----------+--------+
| Liam     |  19659 |
| Noah     |  18252 |
| Olivia   |  17535 |
| Emma     |  15581 |
| Ava      |  13084 |
+----------+--------+
```

---

### Step 6: Test Pub/Sub (10 min)

```bash
# Create a test topic
gcloud pubsub topics create test-topic

# Create a subscription
gcloud pubsub subscriptions create test-sub --topic=test-topic

# Publish a message
gcloud pubsub topics publish test-topic --message="Hello from Day 1!"

# Pull the message
gcloud pubsub subscriptions pull test-sub --auto-ack
```

**Expected output:**
```
┌───────────────────┬──────────────────┬──────────────┬────────────┐
│       DATA        │    MESSAGE_ID    │ ORDERING_KEY │ ATTRIBUTES │
├───────────────────┼──────────────────┼──────────────┼────────────┤
│ Hello from Day 1! │ 12345678901234   │              │            │
└───────────────────┴──────────────────┴──────────────┴────────────┘
```

---

### Step 7: Verify Everything Works (5 min)

Run this verification script:
```bash
echo "=== Project ==="
gcloud config get-value project

echo "=== Cloud Storage ==="
gsutil ls

echo "=== BigQuery ==="
bq ls

echo "=== Pub/Sub Topics ==="
gcloud pubsub topics list

echo "=== Pub/Sub Subscriptions ==="
gcloud pubsub subscriptions list --format="table(name)"

echo "=== Day 1 Setup Complete! ==="
```

---

## Part 3: Revision (15 minutes)

Review the 5-minute revision sheet (separate file: `DAY_01_REVISION_SHEET.md`)

---

## Part 4: Self-Quiz (15 minutes)

Answer these questions OUT LOUD (as if in an interview):

### Question 1 — Scenario
> "Your company has 500GB of CSV log files generated daily. They need to be stored cheaply and queried for weekly reports. Which GCP services would you use?"

<details>
<summary>Answer</summary>

**Store** the raw CSV files in **Cloud Storage (GCS)** using the **Standard** storage class (since they're accessed within a week). Set up a **lifecycle policy** to transition files older than 30 days to **Nearline** or **Coldline**.

For querying, **load them into BigQuery** (batch load from GCS) into a **partitioned table** (partitioned by date). This makes weekly queries fast and cost-effective since BQ only scans the partitions you need.

Architecture: `Log files → GCS (raw) → BigQuery (partitioned table) → Weekly SQL queries`
</details>

### Question 2 — Comparison
> "When would you use Dataflow vs Dataproc?"

<details>
<summary>Answer</summary>

**Dataflow** — Use when:
- Building **new** pipelines from scratch
- You want **serverless** (no cluster management)
- You need **streaming** processing
- You want **autoscaling** without manual tuning

**Dataproc** — Use when:
- You have **existing Spark/Hadoop** code to migrate
- You need specific **Hadoop ecosystem tools** (Hive, Pig, Presto)
- You need **fine-grained cluster control**
- Your team already knows Spark well

**Rule of thumb:** New project → Dataflow. Migration → Dataproc.
</details>

### Question 3 — Architecture
> "Draw (describe) the architecture for a real-time fraud detection system on GCP."

<details>
<summary>Answer</summary>

```
Transaction App → Pub/Sub (ingest events)
                      │
                      ▼
               Dataflow (streaming)
               - Apply fraud rules
               - ML model scoring
               - Window: 5-min tumbling
                      │
              ┌───────┼────────┐
              ▼       ▼        ▼
          BigQuery  Pub/Sub   GCS
          (analytics) (alert  (archive
           & audit)   topic)  raw events)
                      │
                      ▼
               Cloud Function
               (send SMS/email alert)
```
</details>

---

## Day 1 Homework

Before Day 2:
1. Bookmark the [GCS documentation](https://cloud.google.com/storage/docs)
2. Read the [Cloud Storage overview page](https://cloud.google.com/storage/docs/introduction) (10 min)
3. Make sure your budget alert is active
4. **Write one sentence** about what each service does (from memory) — this solidifies learning

---

## Troubleshooting

| Issue | Solution |
|---|---|
| `ERROR: (gcloud.projects.create) PERMISSION_DENIED` | Ensure your Google account has the "Project Creator" role at the org level, or use a personal Gmail account |
| `gsutil mb` fails with 409 | Bucket name already taken globally — add random numbers to the name |
| BigQuery query shows 0 results | Check you're using `--use_legacy_sql=false` |
| Pub/Sub pull returns nothing | Messages expire; re-publish and pull immediately |
| Cloud Shell disconnects | It auto-disconnects after 20 min idle. Just reconnect — your project/config persists |
