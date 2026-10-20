# EducateED Current Infrastructure Terraform

This stack is for codifying the infrastructure that already exists today.

It is intentionally conservative:

- It does not move runtime workloads to AWS yet.
- It does not store Vercel/Supabase/Stripe/Telnyx/Resend secrets in Terraform state.
- It starts by importing and managing project-level settings that are safe to codify.

## Current Inventory

- App host: Vercel project `educateed`
- Vercel project ID: set locally in `terraform.tfvars`
- Vercel team ID: set locally in `terraform.tfvars`
- Supabase project: `EducateEd`
- Supabase project ref: set locally in `terraform.tfvars`
- Supabase organization: set locally in `terraform.tfvars`
- Supabase region: `us-east-2`
- Supabase storage bucket: `documents`
- Cron: Vercel cron runs `/api/cron/reapplication-check` hourly from `vercel.json`

## Prerequisites

Install Terraform locally:

```bash
brew install terraform
```

Set provider credentials outside the repo:

```bash
export VERCEL_API_TOKEN="..."
export SUPABASE_ACCESS_TOKEN="..."
```

Create a local variable file from the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` must stay uncommitted because `supabase_database_password` is sensitive.

## First Import

Initialize providers:

```bash
terraform init
```

Import existing resources:

```bash
terraform import 'vercel_project.educateed' '<vercel_team_id>/<vercel_project_id>'
terraform import 'supabase_project.educateed' '<supabase_project_ref>'
terraform import 'supabase_settings.educateed' '<supabase_project_ref>'
```

Then inspect drift without applying:

```bash
terraform plan
```

## Secrets Policy

Vercel environment variables are currently managed in Vercel, not Terraform.

Reason: most values are secrets, and Terraform state would persist them unless we first set up a secure remote backend and a secret injection workflow. For now, Terraform records the project shape and Supabase project settings; Vercel env vars remain operational state.

Current required secret/environment keys are listed in `locals.tf` as inventory only.

## AWS Migration Direction

Future AWS migration should be a separate stack, likely under `infra/terraform/aws`.

Target mapping:

- Vercel Next.js runtime -> OpenNext/SST, ECS/Fargate, or App Runner
- Supabase Postgres -> RDS Postgres
- Supabase Storage -> S3
- Vercel Cron -> EventBridge Scheduler
- Vercel env vars -> AWS Secrets Manager/SSM Parameter Store
- Supabase Auth -> keep temporarily, then migrate deliberately to Cognito or custom auth
