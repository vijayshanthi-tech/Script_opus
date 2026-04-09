# Day 1 — 5-Minute Revision Sheet: GCP Data Services Overview

## Bullet Point Summary

- GCP data services fall into 5 categories: **Ingest → Store → Process → Analyze → Orchestrate**
- **Cloud Storage (GCS):** Object storage for files (like S3). 4 storage classes: Standard, Nearline, Coldline, Archive
- **BigQuery:** Serverless data warehouse. SQL-based. Stores & analyzes petabytes. Pay per query or flat-rate
- **Pub/Sub:** Serverless messaging. Decouples producers and consumers. At-least-once delivery
- **Dataflow:** Serverless stream/batch processing. Based on Apache Beam. Auto-scales
- **Dataproc:** Managed Spark/Hadoop clusters. Use for migrating existing Spark jobs
- **Cloud SQL:** Managed relational DB (MySQL, PostgreSQL, SQL Server). Single region
- **Cloud Spanner:** Globally distributed relational DB. For massive scale + strong consistency
- **Cloud Composer:** Managed Apache Airflow. Orchestrates multi-step pipelines (DAGs)
- **Data Fusion:** Visual/drag-drop ETL tool. Built on CDAP. For non-coding ETL
- **Cloud DLP:** Detects and redacts PII/sensitive data

---

## Key Concepts

| Concept | One-Liner |
|---|---|
| Serverless | No servers to manage. You pay for usage, not uptime |
| ETL | Extract → Transform → Load (move data from source to warehouse) |
| ELT | Extract → Load → Transform (load raw, transform in warehouse — BQ pattern) |
| Streaming | Process data in real-time as it arrives |
| Batch | Process data in chunks on a schedule |
| Data Lake | Raw storage of all data formats (GCS) |
| Data Warehouse | Structured, optimized storage for analytics (BigQuery) |

---

## Architecture Diagram

```
               ┌──────────┐     ┌──────────┐
               │  Files /  │     │  Events / │
               │   Batch   │     │ Streaming │
               └─────┬─────┘     └─────┬─────┘
                     │                  │
                     ▼                  ▼
              ┌──────────┐       ┌──────────┐
              │   GCS    │       │  Pub/Sub  │
              │(Data Lake)│       │(Messaging)│
              └─────┬─────┘       └─────┬─────┘
                    │                   │
                    └────────┬──────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │   PROCESSING    │
                    │  Dataflow (new) │
                    │  Dataproc (Spark)│
                    │  Data Fusion(ETL)│
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │   BigQuery      │
                    │  (Data Warehouse)│
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    ▼                 ▼
             ┌──────────┐     ┌──────────┐
             │ Dashboards│     │ ML / AI  │
             │ (Looker)  │     │ (Vertex) │
             └──────────┘     └──────────┘

        Orchestrated by: Cloud Composer (Airflow)
```

---

## Real-World Examples

### Example 1: E-Commerce Daily Sales Report
```
Online store DB → Cloud SQL (source)
    → Extract daily sales via Dataflow
    → Load into BigQuery (partitioned by date)
    → Looker dashboard shows daily revenue
    → Cloud Composer runs this daily at 2 AM
```

### Example 2: IoT Sensor Monitoring
```
1000 sensors → Pub/Sub (real-time events)
    → Dataflow (streaming, 1-min windows)
    → BigQuery (real-time analytics)
    → Alert via Pub/Sub + Cloud Function if temp > threshold
    → Raw events archived in GCS (Coldline after 30 days)
```

---

## Common Interview Questions

**Q1: "What's the difference between a data lake and a data warehouse?"**
> **Data Lake** (GCS): Stores raw data in any format (CSV, JSON, Parquet, images). Schema-on-read. Cheap.
> **Data Warehouse** (BigQuery): Stores structured, cleaned data. Schema-on-write. Optimized for fast SQL queries.
> In practice, you use BOTH: land raw data in the lake, then process and load into the warehouse.

**Q2: "Your manager asks you to build a pipeline. How do you choose between Dataflow, Dataproc, and Data Fusion?"**
> - **Dataflow**: Default choice for new pipelines. Serverless, auto-scales, handles streaming + batch.
> - **Dataproc**: Only if migrating existing Spark/Hadoop code, or need specific Hadoop tools.
> - **Data Fusion**: If the team is non-technical and needs a visual drag-and-drop interface.

**Q3: "What is Pub/Sub and when would you use it?"**
> Pub/Sub is a serverless messaging service that decouples data producers from consumers. Use it when:
> - You need real-time event ingestion (IoT, clickstream, logs)
> - Multiple consumers need the same data independently
> - You need to buffer between a fast producer and slow consumer

**Q4: "Explain the GCP data services you'd use for a typical analytics pipeline."**
> Source → **GCS** (land raw files) → **Dataflow** (clean, transform) → **BigQuery** (analyze with SQL) → **Looker** (visualize). Orchestrate with **Cloud Composer**. Secure with **IAM** + **DLP**. Monitor with **Cloud Monitoring**.

---

## Quick Reference: Service Selection Cheat Sheet

```
Need to store files?           → GCS
Need SQL analytics?            → BigQuery
Need real-time messaging?      → Pub/Sub
Need serverless processing?    → Dataflow
Need Spark/Hadoop?             → Dataproc
Need visual ETL?               → Data Fusion
Need workflow orchestration?   → Cloud Composer
Need relational DB (single)?   → Cloud SQL
Need relational DB (global)?   → Cloud Spanner
Need to detect PII?            → Cloud DLP
Need NoSQL wide-column?        → Bigtable
Need NoSQL document?           → Firestore
```

---

*Next: Day 2 — Cloud Storage deep dive (storage classes, `gsutil`, lifecycle policies)*
