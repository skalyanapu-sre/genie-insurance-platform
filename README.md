# Genie Insurance Platform

<div align="center">

# Enterprise Data, AI & Platform Engineering

<p>
  <img src="https://api.visitorbadge.io/api/VisitorHit?user=skalyanapu-sre&repo=genie-insurance-platform&label=REPOSITORY%20VISITS&labelColor=%232F363D&countColor=%232EA44F" alt="Repository Visits" />
  <img src="https://img.shields.io/github/stars/skalyanapu-sre/genie-insurance-platform?style=flat&label=Stars&labelColor=2F363D&color=0969DA" alt="GitHub Stars" />
  <img src="https://img.shields.io/github/forks/skalyanapu-sre/genie-insurance-platform?style=flat&label=Forks&labelColor=2F363D&color=8250DF" alt="GitHub Forks" />
  <img src="https://img.shields.io/github/last-commit/skalyanapu-sre/genie-insurance-platform?style=flat&label=Last%20Commit&labelColor=2F363D&color=FB8C00" alt="Last Commit" />
</p>

**Azure · Databricks · Terraform · ADLS Gen2 · Delta Lake · Unity Catalog · PySpark · Kafka · AKS · Airflow · GitHub Actions · MLflow · MLOps · SRE**

</div>

---

## Repository Traffic

> **Important:** The green `REPOSITORY VISITS` badge above is a public README visit counter.  
> It is **not the same metric as GitHub's official Unique Visitors**.
>
> GitHub's official repository traffic data is available to authorized repository users under:
>
> **Insights → Traffic**
>
> GitHub exposes official page-view and unique-visitor breakdowns only for the previous **14 days**.  
> To maintain real monthly, quarterly, yearly, and all-time unique-visitor graphs, historical traffic must be collected and stored outside the README.

### Traffic Views

[![Daily](https://img.shields.io/badge/Traffic-Daily-0969DA?style=for-the-badge)](#daily-traffic)
[![Weekly](https://img.shields.io/badge/Traffic-Weekly-8250DF?style=for-the-badge)](#weekly-traffic)
[![Monthly](https://img.shields.io/badge/Traffic-Monthly-1A7F37?style=for-the-badge)](#monthly-traffic)
[![Quarterly](https://img.shields.io/badge/Traffic-Quarterly-BF8700?style=for-the-badge)](#quarterly-traffic)
[![Yearly](https://img.shields.io/badge/Traffic-Yearly-BC4C00?style=for-the-badge)](#yearly-traffic)
[![All Time](https://img.shields.io/badge/Traffic-All%20Time-CF222E?style=for-the-badge)](#all-time-traffic)

---

### Daily Traffic

<!--
ACTIVATE THIS AFTER A TRAFFIC-COLLECTOR ENDPOINT IS CONFIGURED.

Replace:
https://YOUR-TRAFFIC-ENDPOINT.example.com

with your traffic service URL.

Example endpoint contract:
GET /graph.svg?repo=skalyanapu-sre/genie-insurance-platform&period=daily

Then uncomment:

<p align="center">
  <img
    src="https://YOUR-TRAFFIC-ENDPOINT.example.com/graph.svg?repo=skalyanapu-sre/genie-insurance-platform&period=daily"
    alt="Daily Unique Visitor Traffic"
    width="900"
  />
</p>
-->

**Metric:** Official GitHub unique visitors, aggregated by day.

---

### Weekly Traffic

<!--
<p align="center">
  <img
    src="https://YOUR-TRAFFIC-ENDPOINT.example.com/graph.svg?repo=skalyanapu-sre/genie-insurance-platform&period=weekly"
    alt="Weekly Unique Visitor Traffic"
    width="900"
  />
</p>
-->

**Metric:** Official GitHub unique visitors, aggregated by week.

---

### Monthly Traffic

<!--
<p align="center">
  <img
    src="https://YOUR-TRAFFIC-ENDPOINT.example.com/graph.svg?repo=skalyanapu-sre/genie-insurance-platform&period=monthly"
    alt="Monthly Unique Visitor Traffic"
    width="900"
  />
</p>
-->

**Metric:** Historical unique-visitor data aggregated by month.

---

### Quarterly Traffic

<!--
<p align="center">
  <img
    src="https://YOUR-TRAFFIC-ENDPOINT.example.com/graph.svg?repo=skalyanapu-sre/genie-insurance-platform&period=quarterly"
    alt="Quarterly Unique Visitor Traffic"
    width="900"
  />
</p>
-->

**Metric:** Historical unique-visitor data aggregated by calendar quarter.

---

### Yearly Traffic

<!--
<p align="center">
  <img
    src="https://YOUR-TRAFFIC-ENDPOINT.example.com/graph.svg?repo=skalyanapu-sre/genie-insurance-platform&period=yearly"
    alt="Yearly Unique Visitor Traffic"
    width="900"
  />
</p>
-->

**Metric:** Historical unique-visitor data aggregated by year.

---

### All-Time Traffic

<!--
<p align="center">
  <img
    src="https://YOUR-TRAFFIC-ENDPOINT.example.com/graph.svg?repo=skalyanapu-sre/genie-insurance-platform&period=all"
    alt="All-Time Unique Visitor Traffic"
    width="900"
  />
</p>
-->

**Metric:** Complete historical traffic retained by the external traffic collector.

---

## Overview

The **Genie Insurance Platform** demonstrates a production-oriented enterprise Data and AI platform implemented with secure infrastructure automation, governed data engineering, machine learning, AI-assisted analytics, Kubernetes integration, observability, and SRE practices.

The platform is designed to ingest data from enterprise sources, process it through governed **Bronze, Silver, and Gold** layers, and expose trusted data products for analytics, Databricks AI/BI Genie, machine learning, APIs, and downstream enterprise applications.

---

## Core Technologies

| Domain | Technologies |
|---|---|
| Cloud | Microsoft Azure |
| Data Platform | Azure Databricks |
| Storage | ADLS Gen2 |
| Data Format | Delta Lake |
| Processing | Apache Spark, PySpark, SQL |
| Streaming | Apache Kafka |
| Orchestration | Apache Airflow |
| Infrastructure as Code | Terraform |
| CI/CD | GitHub Actions |
| Containers | AKS / Kubernetes |
| Governance | Unity Catalog |
| AI / Analytics | Databricks AI/BI Genie |
| ML / MLOps | MLflow |
| Operations | Observability, DevOps, SRE |

---

## Platform Capabilities

- Infrastructure as Code using Terraform
- Secure GitHub-to-Azure authentication using OIDC
- Automated CI/CD with GitHub Actions
- Enterprise batch and streaming ingestion
- Bronze, Silver, and Gold Medallion Architecture
- Delta Lake data management
- Unity Catalog governance and lineage
- Role-based access control
- Row-level and column-level security
- Data quality validation
- Databricks Genie natural-language analytics
- MLflow experiment tracking and model lifecycle management
- AKS-based containerized workloads
- Monitoring, alerting, and production observability
- SLI, SLO, error-budget, and SRE operating practices
- Production deployment and recovery runbooks

---

## Architecture

```text
Enterprise Data Sources
        |
        v
+-----------------------------+
| Ingestion Layer             |
| Kafka / Airflow / APIs      |
+--------------+--------------+
               |
               v
+-----------------------------+
| ADLS Gen2                   |
| Landing / Raw Data          |
+--------------+--------------+
               |
               v
+-----------------------------+
| Azure Databricks            |
| Spark / PySpark / Delta     |
+--------------+--------------+
               |
          +----+----+
          |         |
          v         v
       Bronze    Streaming
          |
          v
        Silver
          |
          v
         Gold
          |
     +----+--------------------+
     |                         |
     v                         v
Analytics / BI           AI / ML / Genie
                               |
                               v
                         MLflow / MLOps
```

---

## Infrastructure Automation

Terraform and GitHub Actions are used to provision and validate infrastructure through controlled deployment workflows.

Key components include:

- Azure Resource Groups
- Terraform remote state
- Azure Storage
- Microsoft Entra ID
- Federated identity credentials
- GitHub OIDC authentication
- Azure Databricks
- ADLS Gen2
- AKS
- Enterprise networking
- RBAC
- Environment-specific configuration

---

## CI/CD

```text
Developer
   |
   v
Feature Branch
   |
   v
Pull Request
   |
   +--> terraform fmt
   +--> terraform validate
   +--> security checks
   +--> terraform plan
   |
   v
Peer Review
   |
   v
Merge to Main
   |
   v
Controlled Terraform Apply
   |
   v
Post-Deployment Validation
```

---

## Security and Governance

- Least-privilege Azure RBAC
- GitHub OIDC authentication
- Secretless CI/CD authentication where supported
- Unity Catalog access controls
- Managed identities
- Service principals
- Data lineage
- Audit logging
- Row-level security
- Column-level security
- Environment isolation

---

## Data Engineering

### Bronze

Raw source data is ingested with minimal transformation while preserving source fidelity.

### Silver

Data is:

- cleaned
- standardized
- validated
- deduplicated
- enriched
- conformed across domains

### Gold

Business-ready data products support:

- claims analytics
- policy analytics
- customer analytics
- advisor analytics
- product analytics
- financial reporting
- machine learning
- AI/BI Genie
- governed downstream consumption

---

## AI and Machine Learning

The platform supports:

- Databricks AI/BI Genie
- Natural-language-to-SQL analytics
- Governed semantic datasets
- MLflow experiment tracking
- Model registration
- Model deployment
- Feature engineering
- GPU-enabled machine-learning workloads
- MLOps pipelines
- AI-agent integration

---

## Kubernetes / AKS

AKS is used where container orchestration provides a better workload boundary than Databricks.

Typical workloads include:

- APIs
- microservices
- AI services
- inference services
- integration services
- platform utilities
- independently scalable container workloads

Databricks remains the primary compute plane for distributed data engineering, Spark processing, governed analytics, and data-centric ML workloads.

---

## Reliability and SRE

Production reliability practices include:

- platform monitoring
- centralized logging
- alerting
- health checks
- deployment validation
- rollback procedures
- SLI and SLO monitoring
- error-budget management
- incident response
- operational runbooks
- disaster-recovery planning

---

## Repository Structure

```text
genie-insurance-platform/
|
├── docs/
|   └── Architecture and implementation documentation
|
├── infra/
|   └── bootstrap/
|       └── Terraform bootstrap infrastructure
|
├── .gitignore
├── About-Me.md
├── Project-Architecture.md
└── README.md
```

---

## Implementation Methodology

```text
Design
  |
Implement
  |
Validate
  |
Test
  |
Document
  |
Integrate
  |
Regression Test
  |
Promote
```

Each capability is implemented and validated independently before integration with the broader platform.

---

## Project Objective

Demonstrate a complete enterprise implementation spanning:

**Architecture → Infrastructure → Data Engineering → Governance → DevOps → MLOps → AI → Kubernetes → Observability → SRE**

with emphasis on secure, repeatable, testable, governed, and production-oriented engineering practices.
