---
name: odi-demo-builder
description: |
  Guides Andy and Niraj through building a production-ready Fivetran ODI demo from scratch in a 3-hour hands-on session. Covers GATHER (vertical/persona setup, SQL Server connectivity via 1Password), PROVISION (Terraform S3+Glue+IAM, Fivetran MDLS destination via REST API, SQL Server connector via REST API), BUILD (dbt bronze/silver/gold scaffold, Niraj content rules applied inline, React frontend shell), and RUN (first sync trigger, Iceberg verification, demo tour). Surfaces Hybrid deployment as the answer to data-residency objections. Makes AI reasoning visible at each decision point.
  Use when Andy or Niraj says "build a new ODI demo", "start a demo from scratch", "odi-demo-builder", "run the build session", or "walk me through provisioning the demo".
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent, WebFetch
version: 1.0.0
license: MIT
---

# ODI Demo Builder — 3-hour hands-on build session

This skill is a facilitated step-by-step build guide for two specific people: Andy (HVR veteran, SQL Server / CDC expert, presales for banks and healthcare orgs) and Niraj (sets demo content standards for the entire portfolio). It produces a working, Niraj-compliant Fivetran ODI demo with a real SQL Server connector, a provisioned MDLS destination, a dbt bronze/silver/gold pipeline, and a React frontend shell — all from zero.

Claude Code narrates its reasoning at every decision point so Andy and Niraj can see why each choice is being made, not just what is being done.

**Do not explain CDC to Andy.** He knows log-based replication better than almost anyone. Instead, defer to him on update-method decisions and frame those as expert-input checkpoints.

---

## When to run

Trigger phrases:
- "build a new ODI demo"
- "start a demo from scratch"
- "odi-demo-builder"
- "run the build session"
- "walk me through provisioning the demo"
- "let's build [vertical] demo today"

---

## Inputs

Before Phase 1 begins, collect:

1. **Vertical and fictional company name** — Ask: "What industry is this demo for, and what fictional company name do you want? It must not collide with a real entity. If unsure, I'll suggest one." Validate by searching the name; if it's a real company, propose an alternative.
2. **Buyer persona** — CDO, CIO, or Head of Data Engineering? This shapes the frontend narrative and the talking points for Hybrid deployment.
3. **1Password item name** — Ask: "What is the 1Password item name for the SQL Server credentials? I'll pull host, port, user, and password from it using the `op` CLI."
4. **Target database and tables** — After connectivity is confirmed, list available databases and tables. User picks which tables to replicate.
5. **AWS region and S3 bucket prefix** — Ask for region (default `us-east-1`) and a bucket name prefix (e.g., `acme-odi`). A random suffix is appended by Terraform to ensure global uniqueness.

If any of the above is missing at session start, ask for it before proceeding. Do not start Phase 2 without all five.

---

## Phase 1 — GATHER (target: 15 minutes)

**Goal:** Confirm the demo context, pull SQL Server credentials from 1Password, verify database connectivity, list tables, and lock the replication scope. Surface the CDC decision as an expert checkpoint for Andy.

### Step 1.1: Confirm vertical and fictional org name

Ask the user for the vertical and proposed company name. Reasoning to narrate aloud: "I'm checking the name against real entities before committing it — Niraj's content standard requires fictional names that cannot be confused with real customers or competitors."

Validate:
```bash
# Quick sanity check — does this name return real corporate results?
# If WebFetch is available, fetch a search URL. Otherwise, prompt user to confirm.
echo "Proposed name: [NAME]. Please confirm this is not a real company before proceeding."
```

If the name looks safe, record it as `DEMO_ORG_NAME` for use in all generated copy.

### Step 1.2: Pull SQL Server credentials from 1Password

Ask the user for the exact 1Password item name (e.g., `SQL Server Demo`). Then fetch each field using the `op` CLI. Narrate: "I'm using `op read` to pull credentials from 1Password rather than asking you to paste them in plaintext. The values will be held in shell variables for this session only."

```bash
# Replace ITEM_NAME with the user-provided item name
export SQLSRV_HOST=$(op read "op://Private/ITEM_NAME/host")
export SQLSRV_PORT=$(op read "op://Private/ITEM_NAME/port" 2>/dev/null || echo "1433")
export SQLSRV_USER=$(op read "op://Private/ITEM_NAME/username")
export SQLSRV_PASS=$(op read "op://Private/ITEM_NAME/password")
echo "Credentials loaded. Host: $SQLSRV_HOST Port: $SQLSRV_PORT User: $SQLSRV_USER"
```

If `op` is not signed in, surface: "Run `op signin` in your terminal first, then re-run this step."

### Step 1.3: Test SQL Server connectivity

Narrate: "Confirming I can reach the SQL Server before provisioning anything — this saves us from debugging a failed connector an hour from now."

```bash
# Use sqlcmd if available, otherwise nc for a port check
if command -v sqlcmd &>/dev/null; then
  sqlcmd -S "$SQLSRV_HOST,$SQLSRV_PORT" -U "$SQLSRV_USER" -P "$SQLSRV_PASS" -Q "SELECT @@VERSION" -l 10
else
  nc -zv "$SQLSRV_HOST" "$SQLSRV_PORT" && echo "Port reachable" || echo "Port not reachable — check VPN or security group"
fi
```

**Expected Behavior:** SQL Server version string returned, or "Port reachable" confirmation.

**If connectivity fails:** Check VPN. If the server is in a private subnet, surface the Hybrid deployment option now (see the Hybrid aside in Phase 2). Do not proceed until connectivity is confirmed.

### Step 1.4: List databases and tables

```bash
sqlcmd -S "$SQLSRV_HOST,$SQLSRV_PORT" -U "$SQLSRV_USER" -P "$SQLSRV_PASS" \
  -Q "SELECT name FROM sys.databases WHERE name NOT IN ('master','tempdb','model','msdb') ORDER BY name" \
  -l 10
```

After user selects a database:

```bash
export SQLSRV_DATABASE="[USER_CHOSEN_DB]"
sqlcmd -S "$SQLSRV_HOST,$SQLSRV_PORT" -U "$SQLSRV_USER" -P "$SQLSRV_PASS" \
  -d "$SQLSRV_DATABASE" \
  -Q "SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_SCHEMA, TABLE_NAME" \
  -l 10
```

Present the table list. Ask the user to name the tables to replicate.

### Step 1.5: CDC vs XACT decision checkpoint (expert input for Andy)

Narrate: "Andy, this is the update-method decision. I'll surface the tradeoffs and let you call it — you've run this pattern for large banks and healthcare orgs and know what the customer's SQL Server can support."

Present as a question:

```
Update method options for this SQL Server connector:

  TELEPORT         — Full table reload each sync. No SQL Server agent or
                     special permissions required. Simple, but no sub-hour
                     deltas. Best for smaller tables or batch-tolerant pipelines.

  BINARY_LOG_READER (CDC) — Log-based change capture. Requires SQL Server
                     Agent enabled and VIEW SERVER STATE permission. Delivers
                     row-level deltas without full reloads. This is the HVR
                     replacement story for Andy's banking and healthcare customers.

Andy, which do you want for this demo? I'll wire the connector config accordingly.
```

Record the choice as `UPDATE_METHOD` (value: `TELEPORT` or `BINARY_LOG_READER`).

---

## Phase 2 — PROVISION (target: 45 minutes)

**Goal:** Apply Terraform to create S3 bucket, Glue catalog databases, and IAM role. Create the Fivetran MDLS destination via REST API. Create the SQL Server connector via REST API. Test the connector.

### Step 2.1: Scaffold Terraform

Create the project directory and Terraform files. Narrate: "I'm generating Terraform that matches the pattern used in FinancialServices-MDLS-DuckDB and Healthcare-Epic-MDLS-DuckDB — S3 bucket with versioning and encryption, three Glue databases (bronze, silver, gold), IAM role scoped to the bronze prefix, and an Athena workgroup."

Create the directory:

```bash
DEMO_SLUG=$(echo "$DEMO_ORG_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
DEMO_DIR="/Users/jason.chletsos/Documents/GitHub/${DEMO_SLUG}-odi-demo"
mkdir -p "$DEMO_DIR/infra"
cd "$DEMO_DIR"
git init
```

Write `infra/main.tf`:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region"           { default = "us-east-1" }
variable "bucket_prefix"        {}
variable "fivetran_aws_account_id" {}
variable "fivetran_external_id" {}
variable "demo_slug"            {}

data "aws_caller_identity" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

# --- S3 ---

resource "aws_s3_bucket" "lake" {
  bucket = "${var.bucket_prefix}-${random_id.suffix.hex}"
  force_destroy = true
  tags = { demo = var.demo_slug }
}

resource "aws_s3_bucket_versioning" "lake" {
  bucket = aws_s3_bucket.lake.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id
  rule {
    id     = "transition-to-ia"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# --- Glue Data Catalog ---

resource "aws_glue_catalog_database" "bronze" {
  name = "${var.demo_slug}_bronze"
}

resource "aws_glue_catalog_database" "silver" {
  name = "${var.demo_slug}_silver"
}

resource "aws_glue_catalog_database" "gold" {
  name = "${var.demo_slug}_gold"
}

# --- IAM role for Fivetran MDLS ---

data "aws_iam_policy_document" "fivetran_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.fivetran_aws_account_id}:root"]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.fivetran_external_id]
    }
  }
}

resource "aws_iam_role" "fivetran_mdls" {
  name               = "${var.demo_slug}-fivetran-mdls"
  assume_role_policy = data.aws_iam_policy_document.fivetran_trust.json
}

data "aws_iam_policy_document" "fivetran_mdls" {
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning"
    ]
    resources = [aws_s3_bucket.lake.arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = ["${aws_s3_bucket.lake.arn}/bronze/*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "glue:CreateTable", "glue:UpdateTable", "glue:DeleteTable",
      "glue:GetTable", "glue:GetTables", "glue:GetDatabase",
      "glue:GetPartitions", "glue:BatchCreatePartition",
      "glue:BatchUpdatePartition", "glue:BatchDeletePartition"
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
      aws_glue_catalog_database.bronze.arn,
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.bronze.name}/*"
    ]
  }
}

resource "aws_iam_role_policy" "fivetran_mdls" {
  name   = "fivetran-mdls-policy"
  role   = aws_iam_role.fivetran_mdls.id
  policy = data.aws_iam_policy_document.fivetran_mdls.json
}

# --- Athena ---

resource "aws_athena_workgroup" "demo" {
  name = var.demo_slug
  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.lake.bucket}/athena-results/"
      encryption_configuration { encryption_option = "SSE_S3" }
    }
  }
}

# --- Outputs ---

output "bucket_name"      { value = aws_s3_bucket.lake.bucket }
output "fivetran_role_arn" { value = aws_iam_role.fivetran_mdls.arn }
output "bronze_db"        { value = aws_glue_catalog_database.bronze.name }
output "silver_db"        { value = aws_glue_catalog_database.silver.name }
output "gold_db"          { value = aws_glue_catalog_database.gold.name }
output "athena_workgroup" { value = aws_athena_workgroup.demo.name }
```

Write `infra/terraform.tfvars` (user fills in fivetran_aws_account_id and fivetran_external_id from the Fivetran UI):

```
aws_region              = "us-east-1"
bucket_prefix           = "[BUCKET_PREFIX]"
demo_slug               = "[DEMO_SLUG]"
fivetran_aws_account_id = "[FROM_FIVETRAN_MDLS_SETUP_UI]"
fivetran_external_id    = "[FROM_FIVETRAN_MDLS_SETUP_UI]"
```

Narrate: "The `fivetran_aws_account_id` and `fivetran_external_id` come from the Fivetran dashboard when you start MDLS destination setup. Pause here, go to fivetran.com/dashboard, start a new MDLS destination, and copy those two values into tfvars before running apply."

### Step 2.2: Apply Terraform

```bash
cd "$DEMO_DIR/infra"
terraform init
terraform plan -out=tfplan
# Surface the plan to user for review before apply
terraform apply tfplan
```

Capture outputs:

```bash
export LAKE_BUCKET=$(terraform output -raw bucket_name)
export FIVETRAN_ROLE_ARN=$(terraform output -raw fivetran_role_arn)
export BRONZE_DB=$(terraform output -raw bronze_db)
echo "S3 bucket: $LAKE_BUCKET"
echo "Fivetran IAM role: $FIVETRAN_ROLE_ARN"
```

**Expected Behavior:** All resources created. S3 bucket name and IAM role ARN captured for use in the API calls that follow.

### Step 2.3: Create Fivetran MDLS destination via REST API

Narrate: "I'm calling the Fivetran REST API to create the MDLS destination. The Terraform provider does not yet support fivetran_destination for MDLS, so the API is the right path here. I'm reading the API key from the FIVETRAN_API_KEY environment variable — never hardcoded."

```bash
# FIVETRAN_API_KEY must be set in the environment (export FIVETRAN_API_KEY=key:secret)
# Split into key and secret
FIVETRAN_KEY=$(echo "$FIVETRAN_API_KEY" | cut -d: -f1)
FIVETRAN_SECRET=$(echo "$FIVETRAN_API_KEY" | cut -d: -f2)

curl -s -u "$FIVETRAN_KEY:$FIVETRAN_SECRET" \
  -X POST https://api.fivetran.com/v1/groups \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$DEMO_SLUG\"}" | jq .
```

Capture the group_id from the response, then create the destination:

```bash
export FIVETRAN_GROUP_ID="[CAPTURED_FROM_ABOVE]"

curl -s -u "$FIVETRAN_KEY:$FIVETRAN_SECRET" \
  -X POST "https://api.fivetran.com/v1/destinations" \
  -H "Content-Type: application/json" \
  -d "{
    \"group_id\": \"$FIVETRAN_GROUP_ID\",
    \"service\": \"managed_data_lake\",
    \"region\": \"AWS_US_EAST_1\",
    \"config\": {
      \"bucket\": \"$LAKE_BUCKET\",
      \"region\": \"us-east-1\",
      \"role_arn\": \"$FIVETRAN_ROLE_ARN\",
      \"catalog\": \"aws_glue\",
      \"glue_database_name\": \"$BRONZE_DB\"
    }
  }" | jq .
```

**Expected Behavior:** Response contains `"code": "Created"` and a destination id. If this fails with a permissions error, check that the Fivetran external_id in tfvars matches the one from the destination setup UI.

### Step 2.4: Create Fivetran SQL Server connector via REST API

Narrate: "Now I'm creating the SQL Server connector, wiring it to the group we just provisioned. The update method is set to whatever Andy chose in Step 1.5. Note the `schema_prefix` — this becomes the bronze schema prefix in Glue and must follow Niraj's naming convention (no org name that collides with real entities, no raw table names exposed)."

```bash
SCHEMA_PREFIX="${DEMO_SLUG}_bronze"

curl -s -u "$FIVETRAN_KEY:$FIVETRAN_SECRET" \
  -X POST https://api.fivetran.com/v1/connectors \
  -H "Content-Type: application/json" \
  -d "{
    \"service\": \"sql_server\",
    \"group_id\": \"$FIVETRAN_GROUP_ID\",
    \"trust_certificates\": true,
    \"trust_fingerprint\": true,
    \"config\": {
      \"schema_prefix\": \"$SCHEMA_PREFIX\",
      \"host\": \"$SQLSRV_HOST\",
      \"port\": $SQLSRV_PORT,
      \"database\": \"$SQLSRV_DATABASE\",
      \"user\": \"$SQLSRV_USER\",
      \"password\": \"$SQLSRV_PASS\",
      \"update_method\": \"$UPDATE_METHOD\",
      \"connection_type\": \"Directly\"
    }
  }" | jq .
```

Capture the connector id:

```bash
export CONNECTOR_ID="[CAPTURED_FROM_ABOVE]"
export CONNECTOR_DEEP_LINK="https://fivetran.com/dashboard/connectors/$CONNECTOR_ID"
echo "Connector deep link: $CONNECTOR_DEEP_LINK"
```

**[critical]** Store `CONNECTOR_DEEP_LINK` — it must appear in the pipeline.json and the React frontend connector list per Niraj's standard. Every connector entry gets a fivetran_id deep link. No exceptions.

### Step 2.5: Test connector and verify connection

```bash
curl -s -u "$FIVETRAN_KEY:$FIVETRAN_SECRET" \
  -X POST "https://api.fivetran.com/v1/connectors/$CONNECTOR_ID/test" \
  -H "Content-Type: application/json" | jq '.data.setup_tests'
```

**Expected Behavior:** `setup_state: "CONNECTED"`. If `INCOMPLETE`, surface the failure message and stop.

### Hybrid deployment aside (surface at this point in every session)

Narrate to Andy: "For your banking and healthcare customers who raise data-residency objections — 'we can't send data to Fivetran's cloud infrastructure' — here is how you swap this exact demo to Hybrid deployment without changing the connector configuration or the dbt pipeline at all."

Surface the following talking points as a sidebar (not a detour — this takes 3 minutes):

```
Fivetran Hybrid Deployment:

  What changes:    The Hybrid Agent runs inside the customer's network (VPC, on-prem,
                   or air-gapped environment). It handles all data movement.
                   Fivetran's cloud plane only receives metadata and orchestration
                   signals — no customer data leaves the customer's perimeter.

  What stays the same: This connector config. The MDLS destination. The dbt
                   bronze/silver/gold pipeline. The React frontend. Everything
                   built today works identically with a Hybrid Agent in front.

  How to demo it:  In the connector setup, check "Use Hybrid Deployment". Point
                   the agent at the customer's SQL Server. The rest of the Fivetran
                   workflow is identical.

  Andy's pitch:    "This is the HVR story, but with a managed control plane. You
                   get log-based CDC without standing up and operating HVR yourself.
                   Data never leaves your network. Fivetran handles scheduling,
                   monitoring, schema drift, and delivery to your Iceberg lake."
```

---

## Phase 3 — BUILD (target: 60 minutes)

**Goal:** Scaffold the dbt project (bronze/silver/gold), apply Niraj content rules inline, generate the React frontend shell, and run `dbt build`.

### Step 3.1: Scaffold dbt project structure

Narrate: "I'm generating the dbt project structure that matches the portfolio standard — bronze as a sources-only layer, silver for staging and intermediate views, gold for Iceberg-materialized fact and dimension tables. The profile targets Athena with the Glue catalog."

```bash
mkdir -p "$DEMO_DIR/dbt/models/bronze"
mkdir -p "$DEMO_DIR/dbt/models/silver"
mkdir -p "$DEMO_DIR/dbt/models/gold"
mkdir -p "$DEMO_DIR/dbt/seeds"
mkdir -p "$DEMO_DIR/dbt/macros"
mkdir -p "$DEMO_DIR/dbt/tests"
```

Generate `dbt/dbt_project.yml` with the project name derived from the demo slug (e.g., `acme_odi`):

```yaml
name: "[DEMO_SLUG_UNDERSCORED]_odi"
version: "1.0.0"
config-version: 2

profile: "[DEMO_SLUG_UNDERSCORED]_odi"

model-paths: ["models"]
seed-paths: ["seeds"]
test-paths: ["tests"]
macro-paths: ["macros"]
analysis-paths: ["analyses"]
snapshot-paths: ["snapshots"]

target-path: "target"
clean-targets: ["target", "dbt_packages"]

models:
  [DEMO_SLUG_UNDERSCORED]_odi:
    silver:
      +materialized: view
      +schema: silver
    gold:
      +materialized: table
      +table_type: iceberg
      +format: parquet
      +schema: gold

seeds:
  [DEMO_SLUG_UNDERSCORED]_odi:
    +schema: seeds

tests:
  +store_failures: true
  +schema: test_results
```

Generate `dbt/packages.yml`:

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: 1.3.3
  - package: metaplane/dbt_expectations
    version: 0.10.4
```

Generate `dbt/profiles.yml` (env-var driven, nothing hardcoded):

```yaml
[DEMO_SLUG_UNDERSCORED]_odi:
  target: dev
  outputs:
    dev:
      type: athena
      region_name: "{{ env_var('AWS_REGION', 'us-east-1') }}"
      schema: silver
      database: awsdatacatalog
      s3_staging_dir: "s3://{{ env_var('LAKE_BUCKET') }}/athena-results/"
      s3_data_dir: "s3://{{ env_var('LAKE_BUCKET') }}/dbt/"
      work_group: "{{ env_var('ATHENA_WORKGROUP', '[DEMO_SLUG]') }}"
      threads: 4
      num_retries: 2
    prod:
      type: athena
      region_name: "{{ env_var('AWS_REGION', 'us-east-1') }}"
      schema: silver
      database: awsdatacatalog
      s3_staging_dir: "s3://{{ env_var('LAKE_BUCKET') }}/athena-results/"
      s3_data_dir: "s3://{{ env_var('LAKE_BUCKET') }}/dbt/"
      work_group: "{{ env_var('ATHENA_WORKGROUP', '[DEMO_SLUG]') }}"
      threads: 8
      num_retries: 2
```

### Step 3.2: Generate bronze sources.yml

Narrate: "The bronze layer is sources-only — no SQL models here, just the YAML that declares what Fivetran landed. One source per replicated table. I'm using the schema prefix we set on the connector."

For each table the user selected in Step 1.4, generate an entry in `dbt/models/bronze/sources.yml`:

```yaml
version: 2

sources:
  - name: bronze_[source_system]
    description: |
      Raw data landed by the Fivetran SQL Server connector from the
      [DEMO_ORG_NAME] source system. Loaded via log-based CDC or full
      reload depending on update method selected at connector setup.
    database: awsdatacatalog
    schema: "[SCHEMA_PREFIX]"
    loader: fivetran_sql_server
    tables:
      - name: [table_name]
        description: "[User-provided description of this table's business meaning]"
        columns:
          - name: _fivetran_synced
            description: Timestamp the row was last synced by Fivetran.
            data_tests:
              - not_null
          - name: _fivetran_deleted
            description: True if Fivetran has soft-deleted this row.
```

### Step 3.3: Generate silver staging models

For each source table, generate a `stg_[source]__[table].sql` in `dbt/models/silver/` using the standard CTE pattern:

```sql
{{ config(materialized='view') }}

with source as (
    select *
    from {{ source('bronze_[source_system]', '[table_name]') }}
    where coalesce(_fivetran_deleted, false) = false
),

renamed as (
    select
        -- Primary keys
        cast([pk_column] as varchar)     as [pk_column],

        -- Dimensions
        trim([name_column])              as [name_column],
        upper(trim([code_column]))       as [code_column],

        -- Dates
        cast([date_column] as date)      as [date_column],

        -- Metrics
        cast([amount_column] as double)  as [amount_column],

        -- Fivetran metadata
        _fivetran_synced                 as loaded_at
    from source
)

select * from renamed
```

Ask the user to identify the primary key column, date columns, and any amounts for each table. Generate the renamed CTE accordingly.

### Step 3.4: Generate gold fact and dimension models

For each logical entity (ask the user to identify the main dimension entity and the main fact/event entity), generate:

**`dbt/models/gold/dim_[entity].sql`:**

```sql
{{ config(
    materialized='table',
    table_type='iceberg',
    format='parquet',
    partitioned_by=['bucket(8, [pk_column])']
) }}

with [entity] as (
    select * from {{ ref('stg_[source]__[entity_table]') }}
),

final as (
    select
        [pk_column],
        [dimension_columns],
        loaded_at
    from [entity]
)

select * from final
```

**`dbt/models/gold/fct_[event].sql`:**

```sql
{{ config(
    materialized='table',
    table_type='iceberg',
    format='parquet',
    partitioned_by=['year([date_column])']
) }}

with events as (
    select * from {{ ref('stg_[source]__[event_table]') }}
),

dims as (
    select * from {{ ref('dim_[entity]') }}
),

joined as (
    select
        e.[pk_column],
        e.[date_column],
        d.[dimension_attribute],
        e.[metric_column],
        e.loaded_at
    from events e
    left join dims d on e.[fk_column] = d.[pk_column]
)

select * from joined
```

### Step 3.5: Apply Niraj content rules inline

Narrate: "Before generating any frontend copy, I'm applying Niraj's content rules to everything we've built. These are non-negotiable for any demo that goes in front of a customer."

**Rule 1 — No exposed table names in body copy.**
Grep every generated file for raw table names (e.g., `sales_orders`, `customer_master`). If any appear in strings that will render in the UI, replace with generic business-domain prose: "the unified transaction record", "the customer-profile mart". Keep schema-qualified names in SQL models — they're load-bearing there.

**Rule 2 — Fictional org name must not collide with real entities.**
Confirm `DEMO_ORG_NAME` was validated in Step 1.1. Every `<title>`, H1, and navbar reference must use this name.

**Rule 3 — Every connector entry gets a Fivetran deep link.**
The `pipeline.json` (or equivalent config file) must include:

```json
{
  "connectors": [
    {
      "name": "SQL Server",
      "service": "sql_server",
      "fivetran_id": "[CONNECTOR_ID]",
      "deep_link": "[CONNECTOR_DEEP_LINK]",
      "schema_prefix": "[SCHEMA_PREFIX]"
    }
  ]
}
```

The Pipeline page must render each connector name as a link to `https://fivetran.com/dashboard/connectors/{fivetran_id}` and include an "Open in Fivetran" CTA.

### Step 3.6: Generate React frontend shell

Narrate: "I'm generating a minimal but Niraj-compliant React frontend shell. It follows the frontend-design skill's aesthetic principles — no generic AI look, distinctive typography, a clean pipeline view, and analytical charts instead of dense tables. No emojis. No pipe separators in copy."

Create `frontend/` directory with:

- `src/App.tsx` — top-level router with routes: Landing, Pipeline, Analysis
- `src/pages/Landing.tsx` — hero section with `DEMO_ORG_NAME`, buyer-persona-appropriate tagline, pipeline diagram (Fivetran → S3/Iceberg → dbt → Athena)
- `src/pages/Pipeline.tsx` — connector list rendered from `pipeline.json`, each connector name links to its Fivetran deep link
- `src/pages/Analysis.tsx` — placeholder for analytical charts (Recharts bar/line combo) once dbt gold models have data
- `src/components/ConnectorCard.tsx` — renders connector name, schema, status badge, and "Open in Fivetran" link

**ConnectorCard "Open in Fivetran" link pattern:**
```tsx
<a
  href={connector.deep_link}
  target="_blank"
  rel="noopener noreferrer"
  className="connector-cta"
>
  Open in Fivetran
</a>
```

Invoke the `frontend-design` skill for the full aesthetic pass after the shell is generated:

```
/frontend-design — apply to $DEMO_DIR/frontend — vertical is [INDUSTRY], buyer is [PERSONA], org name is [DEMO_ORG_NAME]
```

### Step 3.7: Run dbt build

```bash
cd "$DEMO_DIR/dbt"
export LAKE_BUCKET="[VALUE_FROM_TERRAFORM_OUTPUT]"
export AWS_REGION="us-east-1"
export ATHENA_WORKGROUP="[DEMO_SLUG]"

dbt deps
dbt seed
dbt build --select bronze silver gold
```

**Expected Behavior:** All models compile and pass. Gold Iceberg tables created in the Glue catalog.

**If dbt build fails:** Surface the error. Common causes: wrong `awsdatacatalog` database reference in profiles.yml, missing Athena workgroup, IAM permissions gap. Diagnose from the error message before suggesting a fix.

---

## Phase 4 — RUN (target: 30 minutes)

**Goal:** Trigger the first Fivetran sync, monitor status, verify data landed in Iceberg, and tour the demo end-to-end.

### Step 4.1: Trigger first Fivetran sync

Narrate: "Triggering the first sync. This is a historical sync — Fivetran will pull all selected tables. For large tables, this can take a while. I'll poll status every 30 seconds and surface updates."

```bash
# Trigger sync
curl -s -u "$FIVETRAN_KEY:$FIVETRAN_SECRET" \
  -X POST "https://api.fivetran.com/v1/connectors/$CONNECTOR_ID/sync" \
  -H "Content-Type: application/json" | jq .

# Poll status
while true; do
  STATUS=$(curl -s -u "$FIVETRAN_KEY:$FIVETRAN_SECRET" \
    "https://api.fivetran.com/v1/connectors/$CONNECTOR_ID" | \
    jq -r '.data.status.sync_state')
  echo "$(date '+%H:%M:%S') sync_state: $STATUS"
  if [ "$STATUS" = "SYNCED" ] || [ "$STATUS" = "ERROR" ]; then
    break
  fi
  sleep 30
done
```

**Expected Behavior:** `sync_state` transitions from `SYNCING` to `SYNCED`. If `ERROR`, surface the Fivetran error message.

### Step 4.2: Verify Iceberg data

```bash
# List S3 objects in bronze prefix
aws s3 ls "s3://$LAKE_BUCKET/" --recursive | grep "metadata.json" | head -20
```

Then verify via Athena:

```bash
aws athena start-query-execution \
  --query-string "SELECT COUNT(*) FROM \"$BRONZE_DB\".\"[TABLE_NAME]\"" \
  --work-group "$DEMO_SLUG" \
  --result-configuration "OutputLocation=s3://$LAKE_BUCKET/athena-results/" \
  --region us-east-1
```

**Expected Behavior:** Row count returned. Iceberg metadata files visible in S3.

### Step 4.3: Run dbt build against synced data

```bash
cd "$DEMO_DIR/dbt"
dbt build --select silver gold
```

**Expected Behavior:** All staging views and gold Iceberg tables populated. `dbt test` passes.

### Step 4.4: Demo tour checklist

Walk through the demo in order:

1. Landing page — `DEMO_ORG_NAME` branding visible, no raw table names, buyer-appropriate tagline
2. Pipeline page — SQL Server connector card visible, "Open in Fivetran" link active and correct
3. Fivetran dashboard — connector shows `SYNCED`, schema prefix visible
4. Athena — query gold dim and fact tables, confirm row counts match source
5. Analysis page — charts rendering (if data volume is sufficient)

Narrate each step aloud so Andy and Niraj can see the full narrative arc a buyer would experience.

---

## Hybrid deployment talking points (full version for Andy's bank/healthcare customers)

This section is a reference card for Andy's post-session use. Surface it at Step 2.5 as a 3-minute aside, and include it in the demo's README.

**The objection:** "We can't send patient data / transaction records / PII to a third-party cloud."

**The answer:**

Fivetran Hybrid Deployment runs the data-movement agent inside the customer's own network. Fivetran's cloud plane receives only orchestration signals and metadata — row counts, schema, sync timestamps. No customer data transits Fivetran's cloud infrastructure.

From the customer's perspective:
- The agent deploys as a container in their VPC, on-prem datacenter, or air-gapped environment
- They control the agent's network egress rules
- The connector configuration (SQL Server host, credentials, update method) is identical to a standard deployment
- The MDLS destination writes directly to the customer's S3 bucket inside their account

From Andy's HVR replacement pitch perspective:
- HVR required customers to operate their own change-data infrastructure — patching, scaling, failover
- Fivetran Hybrid gives them the same log-based CDC with a managed control plane
- Schema drift detection, backfill management, and delivery orchestration are handled by Fivetran
- Customers keep data sovereignty; they stop operating infrastructure

**How to swap this demo to Hybrid:** In the connector setup, select "Use Hybrid Deployment" and point the agent to the customer's SQL Server. The dbt pipeline, the MDLS destination, and the React frontend are unchanged.

---

## Output

At the end of all four phases, surface a summary block:

```
ODI Demo Build Summary
----------------------
Demo:              [DEMO_ORG_NAME] ([VERTICAL])
Repo:              [DEMO_DIR]
Fivetran group:    [FIVETRAN_GROUP_ID]
Connector:         [CONNECTOR_ID]
Connector URL:     [CONNECTOR_DEEP_LINK]
S3 bucket:         [LAKE_BUCKET]
Glue bronze DB:    [BRONZE_DB]
dbt project:       [DEMO_SLUG_UNDERSCORED]_odi
Update method:     [UPDATE_METHOD]
Sync status:       [LAST_SYNC_STATE]
Gold tables built: [COUNT] models passed

Next steps:
- Push repo to fivetran-jasonchletsos GitHub org
- Add to landing-catalog hub-app/src/lib/demos.ts
- Run /demo-blitz for full Niraj content audit + frontend-design pass
- Add analytical charts to Analysis page once data volume warrants
```

If any phase failed, list the phase name and error. Do not suppress partial failures.

---

## Troubleshooting

**`op read` returns empty:** Run `op signin` and try again. Confirm the item name matches exactly (case-sensitive).

**SQL Server port not reachable:** Check VPN. Check EC2 security group inbound rule for port 1433 from the build machine's IP. If the server is in a private subnet, raise the Hybrid deployment option — this is a real-world data-residency scenario.

**Terraform apply fails on IAM role:** The `fivetran_aws_account_id` in tfvars must match the Fivetran AWS account ID shown in the MDLS destination setup UI. Fetch it from the UI and update tfvars.

**Fivetran API returns 401:** The `FIVETRAN_API_KEY` env var must be in `key:secret` format (colon-separated). Confirm with `echo $FIVETRAN_API_KEY | cut -d: -f1` — if it returns nothing, the format is wrong.

**dbt build fails with "database not found":** Confirm `database: awsdatacatalog` in profiles.yml (not the Glue database name). The Glue database name goes in the `schema` field of the source definition.

**Sync state stuck in SYNCING:** For large tables, this is expected. Poll for up to 30 minutes before escalating. For BINARY_LOG_READER (CDC), confirm SQL Server Agent is running on the source server and the user has VIEW SERVER STATE permission.

**Gold Iceberg tables empty after dbt build:** If the sync completed but source tables have no data, confirm the selected tables have rows in the source database. Run `dbt run --select silver --full-refresh` to reprocess.

---

## Linked memories

- [[dbt-labs-merger-branding]] — architecture diagrams must show "dbt labs" on bronze-to-silver and silver-to-gold edges
- [[feedback-fivetran-ui-demos]] — for CDO/CIO buyers, lead with destination/lake/ODI story; the Fivetran sync UI is not the demo surface
- [[marsh-account-intel]] — Databricks-first pitch pattern; pitch ODI as feeding Databricks, not replacing it (relevant if the buyer session is for a similar account type)
