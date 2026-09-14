# Portfolio CRM — Bank Debt Collections Workflow (AWS)

A cloud-native collections and legal-escalation system modeled on how a Singapore bank manages delinquent loan portfolios end-to-end — from first payment reminder through to legal referral. Built as a hands-on project to apply cloud security architecture and MAS-regulated compliance thinking to a real, working system rather than isolated labs.

> **Status:** Infrastructure is currently torn down to avoid ongoing AWS cost. All code, Terraform configuration, and architecture below reflect a fully deployed and tested build. See [Running it yourself](#running-it-yourself) to redeploy.

## Why this project

Coming from six years in MAS-regulated credit risk and collections roles (Anext Bank, Maybank, ETHOZ Capital), I wanted to prove out cloud security and architecture concepts against a domain I actually understand — rather than a generic tutorial app. The delinquency workflow, legal escalation ladder, and compliance record-keeping in this project are modeled on real collections practice.

## Architecture

```
                              ┌─────────────────┐
                              │   React Frontend │
                              │   (Vite + S3)    │
                              └────────┬─────────┘
                                       │ HTTPS
                              ┌────────▼─────────┐
                              │   API Gateway     │
                              │  (Cognito authZ)  │
                              └────────┬─────────┘
                                       │
                       ┌───────────────┴───────────────┐
                       │                                │
                ┌──────▼──────┐                 ┌───────▼──────┐
                │   Lambda     │                 │   Lambda      │
                │  (10 funcs,  │                 │  functions    │
                │  least-priv  │                 │  in VPC,      │
                │  IAM roles)  │                 │  private      │
                └──────┬──────┘                 └───────┬──────┘
                       │                                │
            ┌──────────▼──────┐              ┌──────────▼───────┐
            │   RDS PostgreSQL │              │  S3 (legal        │
            │  (private subnet,│              │  docs, via VPC    │
            │   encrypted,     │              │  endpoint —       │
            │   not public)    │              │  no public        │
            └──────────────────┘              │  internet hop)    │
                                               └────────────────────┘
```

*(SES email identities are provisioned in Terraform but not yet wired into any Lambda's send path — see [What I'd build next](#what-id-build-next).)*

**VPC:** Public/private subnet split across two AZs (`ap-southeast-1`). Lambda functions and RDS sit entirely in private subnets; a bastion host provides on-demand SSH access for debugging only, with ingress rules removed when not actively in use.

**Security groups:** Least-privilege by design — RDS only accepts inbound PostgreSQL (5432) from the Lambda security group specifically, not from the VPC broadly. Lambda's only egress paths are to RDS (5432) and to S3 via VPC endpoint (443, scoped to the endpoint's prefix list) — no open internet egress.

**IAM:** All 10 Lambda functions run under individually scoped least-privilege roles rather than a shared broad role.

**Data protection:** RDS storage is encrypted at rest; the database is not publicly accessible; legal documents in S3 are served via presigned URLs rather than public bucket access; a cross-tenant data isolation issue in the original presigned-URL flow was identified and fixed during development.

**Authentication:** Cognito handles user auth; API Gateway routes are protected by Cognito authorizers (with a documented risk noted for new routes: authorizers must be explicitly attached, or a route is left open).

## Modeling the actual collections/legal workflow

The schema and application logic follow a real bank delinquency lifecycle, not a generic CRUD app:

- **Delinquency staging:** accounts move through `current → special_mention → substandard → doubtful → loss → legal_escalation → resolved`, with a full audit trail of stage transitions (`delinquency_events`).
- **Communications with dedup protection:** a unique constraint prevents the same reminder template from being sent to the same account twice in one day — a real operational safeguard, not just a nice-to-have.
- **Legal escalation ladder:** models Singapore's legal referral process (letter of demand → law firm referral → status tracking through drafted/sent/acknowledged/closed), including generated legal documents (via a `reportlab` Lambda layer) and S3-backed document storage.
- **Unified event timeline:** a SQL view (`collection_events`) merges reminders, calls, and legal letters into one chronological account history — mirroring how a real collections officer would need to see a case.

## Tech stack

| Layer | Technology |
|---|---|
| Infrastructure as Code | Terraform |
| Compute | AWS Lambda (Python) |
| Database | RDS PostgreSQL (Multi-AZ capable) |
| Auth | AWS Cognito |
| API | API Gateway (Cognito-authorized) |
| Storage | S3 (via VPC endpoint), presigned URLs |
| Frontend | React + Vite |
| Networking | Custom VPC, public/private subnets, security groups, bastion host |

## Running it yourself

Infrastructure is torn down between demos to avoid ongoing cost (RDS + NAT/bastion are not free-tier indefinitely). To redeploy:

```bash
terraform init
terraform apply
```

Requires an AWS account and configured credentials. See `start-project.ps1` / `stop-project.ps1` for the automated bring-up/tear-down scripts used during development.

## What I'd build next

- Wire up SES send logic (identities are provisioned; actual reminder/notification emails from Lambda are not yet implemented)
- Automated `find customer` search (by name, phone, email, or NRIC)
- RDS Proxy in front of Lambda to manage connection concurrency at scale
- Toggle Multi-AZ on for production-realistic failover testing

## Note on data

This is a portfolio project. Seed data is synthetic — no real customer, account, or NRIC data is used or stored anywhere in this repository.

---

Built by [Chai Yao Yang](https://www.linkedin.com/in/chai-yao-yang-3922b0258/) as part of a transition from MAS-regulated credit risk into cloud security and GRC.
