# Secure Terraform + EKS

An AWS stack built with **Terraform** as a deep, hands-on Infrastructure as Code
learning project: a VPC with networking best practices, an **EKS** cluster with
least-privilege IAM, and **security baked into the CI/CD pipeline** (IaC scanning
with tfsec/checkov).

> Portfolio project. The goal is to understand and justify every decision, not to move
> fast. Architecture decisions are documented as ADRs (see `docs/adr/`).

## Status / Roadmap

Each milestone is integrated via **Pull Request** (branch → PR → review → merge to `main`).

- [x] **M-S** — Personal AWS account (MFA, non-root admin, CLI profile, budget alert)
- [x] **M0** — Remote state: S3 backend with native S3 locking (`use_lockfile`)
- [ ] **M1** — Network: VPC with public/private subnets across 2+ AZs, NAT gateway
- [ ] **M2** — Least-privilege baseline IAM
- [ ] **M3** — EKS cluster + IRSA
- [ ] **M4** — Modularization (`network/`, `eks/`, `iam/`)
- [ ] **M5** — Infra testing (`validate`, `tflint`, Terratest)
- [ ] **M6** — Security: tfsec/checkov in the pipeline
- [ ] **M7** — Delivery pipeline (plan on PR, apply on merge with manual approval)
- [ ] **M8** — Secrets management (Secrets Manager / SSM)
- [ ] **M9** — Documentation (architecture diagram + ADRs)
- [ ] **M10** — (optional) sample workload + observability

## Stack

Terraform · AWS (S3, VPC, EKS, IAM) · GitHub Actions · tfsec/checkov · tflint

## Architecture

Network diagram (M1 — VPC, public/private subnets, IGW, NAT): [`docs/diagrams/m1-network-architecture.drawio`](docs/diagrams/m1-network-architecture.drawio).
Open it at [diagrams.net](https://app.diagrams.net) or with the [Draw.io Integration VS Code extension](https://marketplace.visualstudio.com/items?itemName=hediet.vscode-drawio).

> 🚧 Full architecture diagram (EKS, IAM) pending as later milestones land (M9).

Terraform state is stored remotely and durably in **S3**, with **native S3 locking**
(`use_lockfile`) to prevent concurrent applies. DynamoDB is not used: since S3 supports
conditional writes, locking is handled by a `.tflock` object in the bucket itself (see the
corresponding ADR once documented in M9).

## Repository layout

```
.
├── bootstrap/            # Backend stack (remote state). Has its own lifecycle.
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.hcl.example
│   └── terraform.tfvars.example
├── infra/                # Network + (later) EKS/IAM stack. Own state, own lifecycle.
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.hcl.example
│   └── terraform.tfvars.example
├── docs/
│   └── diagrams/
│       └── m1-network-architecture.drawio
└── README.md
```

## Setup

Requires [Terraform](https://developer.hashicorp.com/terraform) ≥ 1.5 and the
[AWS CLI](https://aws.amazon.com/cli/) configured with a profile that has sufficient
permissions.

Account-specific configuration is **not versioned**. Copy the templates and fill in your
own values:

```bash
cd bootstrap
cp backend.hcl.example backend.hcl           # bucket, region, profile for your account
cp terraform.tfvars.example terraform.tfvars # bucket name, profile

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

> The backend uses *partial configuration*: the code (`.tf`) is generic and public, while
> account-specific data lives in `backend.hcl` / `terraform.tfvars`, which are gitignored.

## Why Terraform and this approach

A practical application of Kief Morris's *Infrastructure as Code*: small, composable
stacks, infrastructure testing, delivery pipelines (no manual applies), secrets
management, and drift handling. The reasoning behind each decision is captured in the ADRs.
