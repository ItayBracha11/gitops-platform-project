# Production-Style GitOps Platform on AWS

## Overview

A production-style multi-environment GitOps platform built on AWS, designed to model modern infrastructure delivery and application deployment patterns across development and production environments.

This platform combines **Terraform**, **Amazon EKS**, **ArgoCD**, **Helm**, and **GitHub Actions** to provide fully automated infrastructure provisioning, GitOps-based application reconciliation, controlled production promotion, and automated teardown workflows.

It is built around the idea that infrastructure should support the full lifecycle:

**Provision → Deploy → Promote → Operate → Destroy**

Every infrastructure pull request is also reviewed by an **AI agent** that traces what else the change breaks, with evidence for every claim. See [Agentic CI](#agentic-ci-blast-radius-pr-reviewer).

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
* **AI blast-radius review on every infrastructure PR** (Claude Code agent, read-only, evidence-checked)
* **Approval gate for production apply and destroy**
* **Pinned Terraform providers** through committed lock files

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
├── .claude/
│   └── skills/
│       └── tf-blast-radius/
│
├── .github/
│   ├── claude/
│   ├── scripts/
│   └── workflows/
│
├── app/
│   ├── Dockerfile
│   ├── app.py
│   └── requirements.txt
│
├── docs/
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
| `.claude/skills/`        | The review agent's skill: procedure, trace guide, risk checklist |
| `.github/workflows/`     | CI/CD pipelines, including the blast-radius reviewer |
| `.github/claude/`, `.github/scripts/` | The agent's CI settings and output schema, and the publish script |
| `app/`                   | Demo application source              |
| `docs/`                  | Design doc and progress log for the agentic CI |
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

## Agentic CI: Blast-Radius PR Reviewer

Every pull request that touches `infra/`, `gitops/` or the Terraform workflows is reviewed by an AI agent ([Claude Code](https://claude.com/claude-code)) that answers one question: **what else breaks?**

A Terraform plan shows what changes inside one root. It doesn't show the consequences elsewhere: another root that reads this root's outputs, a generated GitOps values file, an ArgoCD application, a workflow with a hardcoded name. The agent traces those consequences and backs every claim with a `path:line` citation.

```text
Pull Request
  → Gather (no AI): changed roots, a Terraform plan of dev, the PR diff
  → Agent (Claude Code, read-only): traces each change to whatever depends on it
  → Publish (no AI): verifies every citation, runs risk checks, posts one PR comment
```

### The Review Comment

* The verdict (🔴 high, 🟡 medium, 🟢 low) and the dangers, in bold, at the top
* What the review is based on: a live Terraform plan, or the code change only
* Each finding, what it affects, and linked evidence
* Suggested next steps: fixes in the same PR, apply order, maintenance windows, backups

An excerpt from a real review of a PR that changed the dev VPC CIDR:

> ### 🔴 Blast radius: HIGH
> * 🔴 **The dev VPC, all four subnets, the NAT gateway and the routes are destroyed and recreated.**
> * 🔴 **The apply fails partway: the subnets stay in 10.0.x.x, which lies outside the new 10.1.0.0/16 VPC.**
> * 🔴 **The dev EKS cluster and its nodes must be rebuilt because the cluster root reads the new subnet IDs.**
>
> **Suggested next steps**
> 1. Change public_subnet_cidrs and private_subnet_cidrs to 10.1.x.x ranges in this same PR, or the apply will fail partway.

The comment is edited in place on every new commit, with a one-line note on what changed since the last review.

### Guardrails

* **No credentials for the agent:** it never gets AWS credentials or a write token. It reads only the repo and the evidence the gather job prepared, with read-only tools.
* **Output checked by code:** every citation must point at a real line. A verdict that's lower than its own findings, or `low` despite planned deletions or a prod change, turns the check red.
* **PR content is data, not instructions:** text that tries to steer the reviewer, such as a tag value saying "verdict: low", is reported as a high-risk finding.
* **Bounded:** Claude Opus 5.5, at most 25 turns and $2 per run.
* **Fork PRs are skipped:** credentials are never given to code from a fork.

### Evaluation

The reviewer was tested on 7 eval PRs, 3 runs each: a VPC CIDR change, a cluster rename, a NAT gateway change, a tag-only change, a prompt-injection attempt, a chart upgrade, and a change reviewed while dev was torn down. All 21 runs reached the expected verdict and impacts, and every citation was verified.

Design, threat model and results: [docs/agentic-ci.md](docs/agentic-ci.md) and [docs/agentic-ci-progress.md](docs/agentic-ci-progress.md).

**Next:** a second agent that investigates failed apply and destroy runs.

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

### Production Approval Gate

Terraform apply and destroy for production wait for a required reviewer on the GitHub `prod` environment, which only `main` can deploy to. A merge that touches production infrastructure never applies it unattended.

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

### Committed Provider Lock Files

Every Terraform root commits its `.terraform.lock.hcl`, and CI runs `terraform init -lockfile=readonly`, so the plan that gets reviewed and the apply that follows use the same provider versions. Upgrades arrive as pull requests from a bot workflow, and go through the same review.

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
* Claude Code (Anthropic)

---
