# RDS Custom AMI Builder — License‑Included (WS2019 + SQL Server 2022)

This repo builds a **Custom Engine Version (CEV)** for **RDS Custom for SQL Server** using an **AWS License‑Included (LI)** base image on **Windows Server 2019**. You launch a short‑lived builder from an LI AMI (Web/Standard/Enterprise), apply any OS tweaks, **Sysprep** via **SSM**, create an **AMI**, create a **CEV** from that AMI, then create the **RDS Custom** instance from the CEV.

> Notes that matter:
> - **Windows Server 2019** is required for RDS Custom CEVs.
> - A **CEV stays `pending-validation` until you successfully create a DB** from it; that DB create run performs validation.
> - The builder’s public/private status does **not** affect the AMI/CEV. You can build public for convenience and deploy a **private** DB.

---

## TL;DR
1. **Pick LI AMI** for the edition you want (Web/Standard/Enterprise) on **WS2019** using SSM Parameter Store.
2. `terraform apply -var-file=terraform/ami-builder.tfvars` to launch the **builder**.
3. Run `bash scripts/sysprep_and_ami.sh` → preflights SSM → Sysprep → AMI → prints **AMI ID**.
4. Run `bash scripts/create-cev.sh` to create the **CEV** from that AMI (engine must match edition; e.g. `custom-sqlserver-dev` | `custom-sqlserver-se` | `custom-sqlserver-ee`).
5. Point Terraform for your DB to that **CEV** and apply.
6. Destroy the builder when done.

---

## Prereqs

- **AWS CLI** configured; permissions for EC2, RDS, IAM, and VPCEs if you’re private.
- **Network** from the builder (and later the DB) to:
  - Interface VPC Endpoints or NAT for: `ssm`, `ssmmessages`, `ec2messages`.
  - For the DB creation/validation also ensure: `logs`, `monitoring`, `events`, `secretsmanager`, and **S3 Gateway** on the route tables.
- **IAM**: the builder instance profile needs `AmazonSSMManagedInstanceCore`.

### S3 access (required for BYOM ISO and DB validation)

You have two supported paths:

**A) Public/NAT path**
- Give the builder a public IP or NAT egress. No S3 Gateway VPCE required.

**B) Private VPC path**
- Create an **S3 Gateway VPC Endpoint** and attach it to the **route tables** used by your builder/DB subnets.
- Ensure your **bucket policy** allows reads from your account (or specific roles). Example (entire account allowed):
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AccountList",
        "Effect": "Allow",
        "Principal": { "AWS": "arn:aws:iam::050752651470:root" },
        "Action": ["s3:ListBucket"],
        "Resource": "arn:aws:s3:::dev-sqlserver-supportfiles-backups-and-iso-files"
      },
      {
        "Sid": "AccountRead",
        "Effect": "Allow",
        "Principal": { "AWS": "arn:aws:iam::050752651470:root" },
        "Action": ["s3:GetObject"],
        "Resource": "arn:aws:s3:::dev-sqlserver-supportfiles-backups-and-iso-files/*"
      }
    ]
  }
  ```
- Attach minimal **IAM** to the builder instance profile (if using `aws s3 cp` inside SSM):
  ```json
  {
    "Version":"2012-10-17",
    "Statement":[
      {"Effect":"Allow","Action":["s3:ListBucket"],"Resource":"arn:aws:s3:::dev-sqlserver-supportfiles-backups-and-iso-files"},
      {"Effect":"Allow","Action":["s3:GetObject"],"Resource":"arn:aws:s3:::dev-sqlserver-supportfiles-backups-and-iso-files/*"}
    ]
  }
  ```
- Verify your route table has the S3 prefix list route via the VPCE (shows `DestinationPrefixListId`):
  ```bash
  aws ec2 describe-route-tables \
    --route-table-ids rtb-XXXXXXXX \
    --query 'RouteTables[0].Routes[?DestinationPrefixListId!=null]'
  ```

---

## Quick Start

### 0) Choose your LI AMI (examples for us‑east‑2)
Resolve the latest WS2019 + SQL 2022 AMIs via SSM parameters:

```
# Web edition
aws ssm get-parameters --region us-east-2 \
  --names "/aws/service/ami-windows-latest/Windows_Server-2019-English-Full-SQL_2022_Web" \
  --query 'Parameters[0].Value' --output text

# Standard edition
aws ssm get-parameters --region us-east-2 \
  --names "/aws/service/ami-windows-latest/Windows_Server-2019-English-Full-SQL_2022_Standard" \
  --query 'Parameters[0].Value' --output text

# Enterprise edition
aws ssm get-parameters --region us-east-2 \
  --names "/aws/service/ami-windows-latest/Windows_Server-2019-English-Full-SQL_2022_Enterprise" \
  --query 'Parameters[0].Value' --output text
```

### 1) Configure variables
Edit `terraform/ami-builder.tfvars`:

```
project_name         = "legacy-webapp"
env                  = "dev"
region               = "us-east-2"

# Easy/repeatable: give the builder a public IP and skip VPCEs
builder_public       = true
create_ssm_endpoints = false
```

> If you want a fully private builder (no NAT), set `builder_public = false` and `create_ssm_endpoints = true` to have Terraform create Interface VPCEs for SSM.

### 2) Deploy the builder
```
cd terraform
terraform init
terraform apply -var-file=ami-builder.tfvars
```
Copy the `builder_instance_id` from outputs.

### 3) Sysprep and create AMI (SSM‑driven)
```
cd ../scripts
bash sysprep_and_ami.sh
```
The script will:
1) Preflight SSM (auto‑create/attach the SSM role/profile if missing; wire VPCEs/SGs if needed)
2) Run Sysprep via SSM (Runbook if present; else Run Command)
3) Wait for the instance to stop
4) Create the AMI and wait until it becomes **available**

It prints the **AMI ID** when done.

### 4) Create the CEV from the AMI
```
cd ./
bash create-cev.sh
```
- Use a supported SQL 2022 build; we default to **CU19** in examples: `16.00.4195.2.dev-cev-YYYYMMDD`.
- **Engine must match edition** of the AMI:
  - Web → `custom-sqlserver-dev`
  - Standard → `custom-sqlserver-se`
  - Enterprise → `custom-sqlserver-ee`

**Edition → engine quick map**

| Edition    | Engine                 |
|------------|------------------------|
| Web        | custom-sqlserver-dev   |
| Standard   | custom-sqlserver-se    |
| Enterprise | custom-sqlserver-ee    |

> The CEV will show **`pending-validation`** until you successfully create an RDS Custom DB instance from it.

### 5) Deploy RDS Custom from the CEV
In your RDS module variables (or resource):
```
engine         = "custom-sqlserver-dev"   # or custom-sqlserver-se / custom-sqlserver-ee
engine_version = "16.00.4195.2.dev-cev-YYYYMMDD"
```
Then apply your infra as usual.

### 6) Clean up the builder
```
cd ../terraform
terraform destroy -var-file=ami-builder.tfvars
```
Keep the AMI and CEV.

---

## Optional: BYOM Developer ISO mode

If you prefer to start from a plain WS2019 AMI and install **SQL Server 2022 Developer** yourself (e.g., from an S3-hosted ISO), the `scripts/sysprep_and_ami.sh` supports that path. Provide the S3 URI when prompted.

The script:
- Ensures SSM is ready, then downloads the ISO (`aws s3 cp` under IAM; falls back to presigned URL if needed).
- Installs prerequisites **.NET Framework 4.8** and **VC++ 2015–2022 (x64)** silently if missing.
- Mounts ISO and runs silent setup for `SQLENGINE`.
- Syspreps and creates the AMI.

**Requirements**
- WS2019 base AMI.
- S3 access (see the *S3 access* section).
- Instance profile with `AmazonSSMManagedInstanceCore` plus S3 read if using IAM auth for `aws s3 cp`.

---

## Troubleshooting

- **403 / AccessDenied downloading ISO from S3**
  - If the script prints `[BYOM] Falling back to presigned URL + BITS` and still fails: fix the bucket policy and/or attach S3 read to the instance profile (see *S3 access*). For private subnets, ensure an S3 Gateway VPCE is attached to the route table.

- **SQL setup exit code -2068709375 (0x84B40000)**
  - Missing prerequisites. The script now installs **.NET 4.8** and **VC++ 2015–2022 x64** automatically. If you customized it, ensure those packages install successfully before running `setup.exe`.

- **SSM not registering / send-command fails**
  - Ensure the builder has an instance profile with `AmazonSSMManagedInstanceCore`.
  - Provide egress: NAT route or Interface VPCEs for `ssm`, `ssmmessages`, `ec2messages` with Private DNS enabled and SG 443 from the builder SG.
  - NACLs must allow 443 and ephemeral return traffic.

- **CEV stuck `pending-validation`**
  - You must **successfully create a DB** from the CEV; that run performs validation.
  - Ensure DB subnets can reach: `logs`, `monitoring`, `events`, `secretsmanager` and S3 (Gateway) in addition to the three SSM services.

- **Invalid DB engine**
  - Engine must match the AMI’s SQL edition: Web → `custom-sqlserver-dev`, Standard → `custom-sqlserver-se`, Enterprise → `custom-sqlserver-ee`.

- **`incompatible-network` during DB create**
  - Missing VPCEs/NAT, SG/NACL blocks, or no free IPs in DB subnets. Fix endpoints and 443 egress.

---

## Verification snippets

```
# Confirm AMI is available
aws ec2 describe-images --owners self \
  --filters Name=name,Values=ws2019-sql2022-* \
  --query "Images[?State=='available'].[ImageId,Name,CreationDate]" --output table

# Check a specific CEV
aws rds describe-db-engine-versions \
  --engine custom-sqlserver-dev \
  --engine-version "16.00.4195.2.dev-cev-YYYYMMDD" \
  --region us-east-2
```

# Verify required Interface VPCEs exist and have Private DNS enabled (example us-east-2)
for svc in ssm ssmmessages ec2messages logs monitoring events secretsmanager; do
  aws ec2 describe-vpc-endpoints \
    --filters Name=vpc-id,Values=vpc-XXXXXXXX Name=service-name,Values=com.amazonaws.us-east-2.$svc \
    --query 'VpcEndpoints[].{Id:VpcEndpointId,PrivateDNS:PrivateDnsEnabled}'
done

# Verify S3 Gateway VPCE is associated to your route table
aws ec2 describe-vpc-endpoints \
  --filters Name=vpc-id,Values=vpc-XXXXXXXX Name=vpc-endpoint-type,Values=Gateway Name=service-name,Values=com.amazonaws.us-east-2.s3 \
  --query 'VpcEndpoints[0].RouteTableIds'
```

---

## Cost notes
- Builder instance while it runs, AMI storage, and the RDS Custom instance. Destroy the builder ASAP after AMI creation.
