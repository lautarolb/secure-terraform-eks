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
- [x] **M1** — Network: VPC with public/private subnets across 2+ AZs, NAT gateway
- [x] **M2** — Least-privilege baseline IAM
- [x] **M3** — EKS cluster + IRSA
- [x] **M4** — Modularization (`network/`, `eks/`, `iam/`)
- [x] **M5** — Infra testing (`validate`, `tflint`, Terratest)
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

**EKS API endpoint (M3):** the cluster's Kubernetes API endpoint is **private-only**
(`endpoint_public_access = false`, `endpoint_private_access = true`). By default EKS
exposes the API endpoint to the public internet (network-reachable by anyone, though
still gated by IAM + RBAC auth) — closing it entirely means the API surface can't be
touched from outside the VPC at all, not even to attempt authentication. The trade-off:
the cluster can only be administered from inside the VPC, so a **bastion host** is
required to run `kubectl`/`aws` from a laptop. Considered and rejected: leaving the
public endpoint open and restricting it to a single IP via `public_access_cidrs` —
simpler (no bastion needed), but still network-reachable from the internet in
principle, just IP-filtered at the AWS API layer.

**Bastion host (M3):** lives in a **private** subnet with no public IP and a security
group with zero inbound rules — access is exclusively via **SSM Session Manager**
(IAM-authenticated, no SSH keys, sessions audited in CloudTrail), not traditional
SSH. Neither the bastion nor the administrator dials in directly to each other;
both independently connect outbound to the AWS Systems Manager service, which brokers
the interactive session — that's why no inbound port or public IP is needed at all.

**Modularization (M4):** the code is split into reusable modules
(`modules/network`, `modules/iam`, `modules/eks`) with clean variables/outputs, but
**deliberately kept on a single Terraform state** — module boundaries here are about
code organization and reuse, not blast-radius isolation. A `module` block sharing the
root's state is a different mechanism from separate state files per stack; this
project accepts the shared-state trade-off
(an `apply` touching `eks` can, in principle, still affect `network`/`iam` in the same
operation) in exchange for less operational overhead — one `init`/`plan`/`apply`
instead of three separate stacks wired together via `terraform_remote_state`. Revisit
if this ever needs independent CI pipelines per stack.

## Repository layout

```
.
├── bootstrap/            # Backend stack (remote state). Has its own lifecycle.
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.hcl.example
│   └── terraform.tfvars.example
├── infra/                # Network + EKS/IAM stack. Own state, own lifecycle.
│   ├── main.tf           # terraform{}/provider{} only
│   ├── modules.tf        # wires network/iam/eks modules together
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.hcl.example
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── network/  # VPC, subnets, IGW, NAT, route tables
│       ├── iam/      # EKS cluster role + node role
│       └── eks/      # cluster, node group, IRSA, bastion
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

**Linting (M5):** [`tflint`](https://github.com/terraform-linters/tflint) runs against every
stack from the repo root with `tflint --recursive` (config in `.tflint.hcl`). Wiring it into
CI is part of M7 (delivery pipeline).

**Pre-commit hook (M5):** `hooks/pre-commit` runs `terraform fmt -check` and `tflint
--recursive` before every commit — a plain git hook (no extra dependency, no `pre-commit`
framework needed for two checks). Git doesn't version `.git/hooks/`, so install it once per
clone:

```bash
ln -sf ../../hooks/pre-commit .git/hooks/pre-commit
```

**Terratest (M5):** `test/network_test.go` is a **plan-only** sanity test for the `network`
module — it runs `terraform init`/`plan` (via Terratest) and asserts on the planned VPC/subnet
CIDRs and the NAT gateway, but never applies, so it costs nothing and is safe to run any time:

```bash
cd test
go test -v ./...
```

A full Terratest suite would normally `apply` real infrastructure and assert against it (then
`destroy`) — deliberately not done here for `eks`/`iam`, since an EKS apply/destroy cycle
costs money and takes 15–20 minutes; this repo prefers to keep real applies manual and
explicit rather than have `go test` spend money silently.

> The backend uses *partial configuration*: the code (`.tf`) is generic and public, while
> account-specific data lives in `backend.hcl` / `terraform.tfvars`, which are gitignored.

## Why Terraform and this approach

Small, composable stacks, infrastructure testing, delivery pipelines (no manual
applies), secrets management, and drift handling. The reasoning behind each decision
is captured in the ADRs.
