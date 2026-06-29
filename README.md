# stagecraft-infra

Terraform infrastructure for Stagecraft on AWS EKS. Uses
[terraform-aws-modules](https://github.com/terraform-aws-modules) from the public registry for
VPC/EKS/ECR/ACM/IAM; custom modules (`modules/`) only for things specific to this project —
IRSA role wiring, Secrets Manager entries, SQS + its DLQ/alarm, and Bedrock Agents.

**Part of**: [Stagecraft-Ops](https://github.com/Stagecraft-Ops). For the full explanatory writeup (why
things are structured this way, what alternatives were considered, every incident found and
fixed) see the `guide/` folder at the root of the umbrella project, not in this repo.

## Directory layout

```
stagecraft-infra/
├── environments/
│   ├── dev/              # main AWS account, dev — base infra: VPC, EKS, RDS, SQS, ECR,
│   │   │                 # IAM/IRSA, Secrets Manager, CloudWatch, WAF, CloudFront, Karpenter IAM
│   │   └── *.tf          # one file per concern (network, compute, database, registry,
│   │                     # iam, messaging, secrets, security, monitoring, cdn, dns)
│   ├── dev-platform/      # SIBLING of dev (not nested) — separate Terraform root + state.
│   │   │                 # Installs ArgoCD, kGateway, External Secrets Operator, Karpenter's
│   │   │                 # Helm release + NodePool, and the monitoring stack. Reads dev's
│   │   │                 # outputs via a data source; never the other way around.
│   ├── prod/               # same shape as dev, not currently deployed
│   ├── prod-platform/      # sibling of prod, same relationship as dev-platform
│   └── bedrock/             # a DIFFERENT AWS account — only creates the 5 Bedrock Agents
└── modules/                 # reusable building blocks called BY the environments above —
    ├── iam/                 # no state of their own; same module, different inputs per call
    ├── secrets/
    ├── sqs/
    └── bedrock_agents/
```

**Why split `dev` and `dev-platform` into two Terraform roots instead of one?** Different
provider requirements — the platform layer needs the `kubernetes`/`helm` providers, which need
a *live* EKS cluster's endpoint to even initialize. That cluster doesn't exist until `dev`'s
own `terraform apply` has already run. One root module can't express "apply this part, wait,
then apply this other part" within a single `terraform apply` — hence two roots, with
`dev-platform` reading `dev`'s outputs via `data "terraform_remote_state"`.

**Why `modules/` separately from `environments/`?** `modules/` holds reusable code with no
state of its own — `modules/iam` gets called once by `dev`, once by `prod`, once by `bedrock`,
each time creating a *different* set of real IAM roles depending on the inputs it's given.
`environments/*` are the actual deployments — each is independently `terraform apply`-able,
each has its own state file in S3. Confusing the two ("why are there so many folders") usually
comes from `modules/` and `environments/` looking like the same kind of thing in a file
browser when they're not — one is a function, the other is 5 independent running instances of
infrastructure.

## What's actually provisioned

| Component | Source | Notes |
|-----------|--------|-------|
| VPC | `terraform-aws-modules/vpc/aws` | 3 AZs, public/private/database subnet tiers, 1 NAT Gateway |
| EKS | `terraform-aws-modules/eks/aws` | 2 managed node groups (`app`, `worker`), IRSA, core add-ons |
| Karpenter | `terraform-aws-modules/eks/aws//modules/karpenter` | IAM in `dev`, Helm release + NodePool in `dev-platform`. Dev only. |
| RDS | `aws_db_instance` (raw resource, no module) | Postgres 15, `db.t3.micro`, single-AZ |
| Redis | a plain `kubernetes_deployment` (platform layer) | **Not** ElastiCache — cost tradeoff for this environment |
| ECR | `terraform-aws-modules/ecr/aws` | 5 repos, immutable tags, 20-image lifecycle policy |
| SQS | `modules/sqs/` (custom) | DLQ + CloudWatch alarm, IAM queue policy |
| IAM / IRSA | `modules/iam/` (custom) + `iam-role-for-service-accounts-eks` | Per-service roles, scoped to exactly what each service needs |
| Secrets Manager | `modules/secrets/` (custom) | One secret per service per environment — see below |
| External Secrets Operator | `helm_release` (platform layer) | Syncs Secrets Manager → k8s Secrets |
| ArgoCD | `helm_release` + `kubernetes_manifest` (platform layer) | Watches `stagecraft-helm`, auto-deploys on every commit |
| WAF | `aws_wafv2_web_acl` (two: REGIONAL + CLOUDFRONT scope) | CLOUDFRONT one is attached and live; REGIONAL one isn't attached to anything yet |
| CloudFront + ACM + Route53 | `aws_cloudfront_distribution` + manual cert/zone | Dev only — the only way to attach WAF to an NLB |
| Bedrock Agents | `modules/bedrock_agents/` (custom), separate AWS account | 5 agents: classifier, root_cause, yaml_fixer, security_reviewer, pr_writer |
| Monitoring | `kube-prometheus-stack` via ArgoCD (platform layer) | Grafana ClusterIP-only, no public exposure |
| SNS | `aws_sns_topic` | Email alert on RDS CPU/storage thresholds and SQS DLQ depth |

## How secrets actually get to a running pod

```
terraform apply
  → module.secrets creates stagecraft/{env}/{service} in Secrets Manager
  → helm_release.external_secrets (platform layer) installs ESO with an IRSA role scoped to
    secretsmanager:GetSecretValue on arn:...:secret:stagecraft/*
  → kubernetes_manifest.cluster_secret_store registers that role with ESO
  → each Helm chart's templates/externalsecret.yaml (in stagecraft-helm) creates
    an ExternalSecret CR pointing at stagecraft/{env}/{service}
  → ESO syncs it into a native k8s Secret (polls every 5 minutes)
  → the Deployment's envFrom: secretRef reads it — but only at container START.
    Updating the Secret does NOT update an already-running pod's environment;
    a rollout restart is required after confirming the new value landed in the
    k8s Secret object (not just Secrets Manager).
```

GitHub OAuth credentials and Bedrock agent IDs are left as empty placeholders by Terraform —
filled in manually after the first apply (`ignore_changes` ensures a later `terraform apply`
never overwrites the manually-filled values).

**`SECRET_KEY` is shared between `api` and `worker`** (`random_password.secret_key`, generated
once) — it signs JWTs in `api` and derives the Fernet token-encryption key in both. Rotate both
secrets together or token decryption breaks.

## How a deploy actually happens (GitOps)

```
git push to a service repo (main branch)
  → ci.yml: build, scan (Trivy + SonarCloud), push to ECR,
    helm-update commits new image.repository + image.tag to stagecraft-helm
  → ArgoCD (installed by dev-platform, watching stagecraft-helm) detects the commit
  → ArgoCD syncs the chart to the stagecraft namespace automatically
```

ArgoCD needs read access to `stagecraft-helm` (private repo) — `argocd_repo_pat`, a GitHub PAT with
at least read access to that repo, passed as a Terraform variable (never committed).

**What this does NOT automate**: the base layer (`dev`) has a CI workflow that plans on every
push but only *applies* manually (`workflow_dispatch`). The platform layer (`dev-platform`) has
**no CI workflow at all** — it's applied via `stagecraft-workflows/scripts/bootstrap-new-account.sh`
(branch `test`), run locally. See the umbrella project's `guide/02-infrastructure-architecture.md`
("What's NOT automated") for why.

## Bootstrap (first time only, new AWS account)

```bash
# backend "s3" {} blocks cannot read variables — bucket/table names are literal
# strings in every backend.tf, edited by hand once per new account.
aws s3 mb s3://your-bucket-name --region us-east-1
aws dynamodb create-table \
  --table-name your-lock-table \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Then edit the `bucket`/`dynamodb_table` values in all 5 `backend.tf` files
(`dev`, `dev-platform`, `prod`, `prod-platform`, `bedrock`) to match.

See the umbrella project's `PROJECT_STATE.md` → "Full Recreation Checklist" for the complete,
ordered, copy-pasteable runbook (this repo's bootstrap is only one phase of several — GitHub
OAuth App, the Bedrock account, GitHub Actions secrets, and CloudFront/domain setup all happen
outside this repo).

## Usage (existing account)

```bash
cd environments/dev
terraform init

# alert_email has no default — supply it via -var or terraform.tfvars
terraform plan -var="alert_email=you@example.com"
terraform apply -var="alert_email=you@example.com"
```

## Known follow-ups (not yet done)

- `environments/prod/dns.tf` still has a Terraform-managed ACM cert (`module "acm"`) instead of
  the manual-cert-as-data-source pattern `dev` uses — never updated since prod isn't deployed.
- RDS is not encrypted at rest (`storage_encrypted = false`) — was blocked by an SCP on the
  account this was originally built in; the current main account has no such restriction.
- `dev` and `prod` duplicate most of their `.tf` files almost line-for-line (no shared module
  for the base layer) — a real module extraction would need `moved {}` blocks and a
  zero-destroy `terraform plan` verified before applying, since `dev` is live with real data.
