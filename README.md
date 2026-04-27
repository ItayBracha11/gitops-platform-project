# Production-Style GitOps Platform on AWS

## Overview

A production-style multi-environment GitOps platform built on AWS, designed to model modern infrastructure delivery and application deployment patterns across development and production environments.

This platform combines **Terraform**, **Amazon EKS**, **ArgoCD**, **Helm**, and **GitHub Actions** to provide fully automated infrastructure provisioning, GitOps-based application reconciliation, controlled production promotion, and automated teardown workflows.

It is built around the idea that infrastructure should support the full lifecycle:

**Provision → Deploy → Promote → Operate → Destroy**

---

## Key Capabilities

* **Multi-environment architecture** (`dev` / `prod`)
* **Multi-region deployment model** (`us-east-1` / `eu-west-1`)
* **Modular Terraform architecture**
* **GitOps delivery with ArgoCD App-of-Apps**
* **Automated CI/CD pipelines with GitHub Actions**
* **IRSA-based AWS integrations**
* **Controlled production image promotion**
* **Dynamic CI runner-based Kubernetes API access**
* **Fully automated environment teardown**
* **Reusable environment workflow orchestration**

---

## Architecture

```text
GitHub Repository
  → GitHub Actions
  → Terraform
  → AWS Infrastructure
  → Amazon EKS
  → ArgoCD
  → GitOps Applications
  → AWS Load Balancer Controller
  → Application Load Balancer
  → Demo Application
```

### Environment Layout

**Development**

* Region: `us-east-1`
* CIDR: `10.0.0.0/16`
* Node group: `2 x t3.small`

**Production**

* Region: `eu-west-1`
* CIDR: `10.1.0.0/16`
* Node group: `2 x t3.large`

---

## Repository Structure

```text
.
├── app/
│   ├── Dockerfile
│   ├── app.py
│   └── requirements.txt
│
├── gitops/
│   ├── applications/
│   │   ├── dev/
│   │   └── prod/
│   │
│   ├── apps/
│   │   └── demo-app/
│   │
│   └── infrastructure/
│       └── alb-controller/
│
├── infra/
│   ├── bootstrap/
│   ├── environments/
│   │   ├── dev/
│   │   └── prod/
│   │
│   └── modules/
│       ├── compute/
│       ├── network/
│       ├── platform/
│       └── security/
│
└── scripts/
```

### Directory Purpose

| Directory                | Purpose                              |
| ------------------------ | ------------------------------------ |
| `app/`                   | Demo application source              |
| `gitops/applications/`   | ArgoCD Application manifests         |
| `gitops/apps/`           | Helm applications                    |
| `gitops/infrastructure/` | Infrastructure Helm charts           |
| `infra/environments/`    | Environment-specific Terraform roots |
| `infra/modules/`         | Reusable Terraform modules           |
| `scripts/`               | Operational helper scripts           |

---

## Infrastructure Design

Infrastructure is intentionally split into separate Terraform roots:

```text
Network → Cluster → Platform → Bootstrap
```

This separation keeps lifecycle boundaries clean, reduces coupling, and makes both provisioning and teardown deterministic.

### Network

Responsible for:

* VPC
* Public / private subnets
* Internet Gateway
* NAT Gateway
* Route tables
* Kubernetes subnet tagging

### Cluster

Responsible for:

* Amazon EKS cluster
* Managed node groups
* OIDC provider
* IAM roles
* IRSA setup
* Generated environment-specific ALB controller values

### Platform

Responsible for:

* ArgoCD installation via Helm

### Bootstrap

Responsible for:

* Root ArgoCD Application
* GitOps App-of-Apps bootstrap

---

## GitOps Delivery Model

ArgoCD uses an **App-of-Apps** model.

Root application:

```text
root-app
```

Manages environment applications:

**Development**

* `aws-load-balancer-controller-dev`
* `aws-load-balancer-controller-sa-dev`
* `demo-app-dev`

**Production**

* `aws-load-balancer-controller-prod`
* `aws-load-balancer-controller-sa-prod`
* `demo-app-prod`

---

## Deployment Flow

```text
Code Change
  → Build Docker Image
  → Push to Amazon ECR
  → Deploy to Dev
  → Validate
  → Promote Image
  → Deploy to Prod
```

### Development

Application changes trigger:

* Docker build
* Push to Amazon ECR
* Dev environment deployment
* Validation in live environment

### Production

Production deployment is intentionally manual.

Promotion workflow:

1. Reads image tag from:

```text
gitops/apps/demo-app/values-dev.yaml
```

2. Updates:

```text
gitops/apps/demo-app/values-prod.yaml
```

3. Commits change to Git

4. ArgoCD reconciles production automatically

This creates a controlled:

**Validate in Dev → Promote → Deploy to Prod**

delivery model.

---

## Automated Destroy Workflow

Full environment teardown is supported:

```text
Bootstrap → Platform → Cluster → Network
```

Destroy orchestration includes:

* ArgoCD child application cleanup
* Graceful Kubernetes resource deletion
* ALB dependency waiting
* Leftover security group cleanup
* Retry logic for AWS eventual consistency

This allows complete lifecycle management without manual cloud cleanup.

---

## Security Considerations

### Dynamic Kubernetes API Access

EKS API access is restricted dynamically during CI runs.

GitHub Actions runner public IP is detected at runtime and allowed temporarily as:

```text
runner-ip/32
```

This avoids:

* static allowlists
* overly broad CIDRs
* permanently exposed cluster APIs

### IRSA-Based AWS Access

AWS integrations use **IAM Roles for Service Accounts (IRSA)** instead of static credentials.

This provides:

* least privilege access
* short-lived credentials
* workload identity separation

---

## Technical Decisions

### Modular Terraform

Reusable modules power all environments while keeping root configurations environment-specific.

### Generated Environment Values

Terraform generates environment-aware ALB controller values automatically (cluster name, VPC ID, region, IAM role ARN), reducing manual configuration drift.

### App-of-Apps Bootstrap

Separates platform provisioning from application reconciliation, making bootstrap deterministic and repeatable.

### Manual Production Promotion

Production deployment requires deliberate promotion while keeping actual deployment automated through GitOps reconciliation.

---

## Tech Stack

* Amazon Web Services
* Amazon Elastic Kubernetes Service
* Argo CD
* GitHub Actions
* Docker
* Kubernetes
* Helm
* HashiCorp
* Amazon Elastic Container Registry
* IAM / IRSA

---
