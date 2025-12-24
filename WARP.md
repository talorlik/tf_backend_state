# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This repository provisions AWS infrastructure for Terraform remote state management using S3. It creates:
- **S3 bucket**: Stores Terraform state files with versioning, encryption, and file-based locking enabled
- **Security features**: Public access blocked, private ACL, IAM-based access control
- **Dynamic configuration**: Bucket name includes AWS account ID for global uniqueness; principal ARN automatically detected
- **GitHub Pages Documentation**: Comprehensive documentation site with theme toggle (light/dark), responsive design, and organized content sections

**Critical**: This infrastructure is a prerequisite for other Terraform projects that use remote state. Changes here can affect multiple downstream projects.

## Prerequisites

**For GitHub Actions:**
- GitHub repository with Actions enabled
- AWS OIDC Identity Provider configured
- GitHub secrets and variables configured (see Configuration Files section)

**For Local Execution:**
- AWS CLI V2
- Terraform >= 1.14.0
- GitHub CLI (`gh`) installed and authenticated
- `jq` for JSON parsing
- AWS Secrets Manager secret 'github-role' with key 'AWS_STATE_ACCOUNT_ROLE_ARN'
- IAM permissions: `secretsmanager:GetSecretValue` for 'github-role' secret
- IAM permissions: Assume role specified in `AWS_STATE_ACCOUNT_ROLE_ARN`

## Common Commands

### Automated State Management (Recommended)

Provision infrastructure and upload state file:
```bash
./set-state.sh
```
This script automatically:
- Assumes the IAM role from GitHub secrets
- Runs terraform init, validate, plan, and apply
- Saves bucket name to GitHub repository variable
- Uploads state file to S3

Download existing state file from S3:
```bash
./get-state.sh
```
This script automatically:
- Assumes the IAM role from GitHub secrets
- Downloads terraform.tfstate from S3

### Manual Terraform Operations

Initialize Terraform (required after clone or provider changes):
```bash
terraform init -backend=false
```

Validate configuration syntax:
```bash
terraform validate
```

Format Terraform files:
```bash
terraform fmt
```

Plan changes:
```bash
terraform plan -var-file="variables.tfvars"
```

Apply changes:
```bash
terraform apply -var-file="variables.tfvars"
```

Destroy infrastructure (use with extreme caution):
```bash
terraform plan -var-file="variables.tfvars" -destroy -out terraform.tfplan
terraform apply -auto-approve terraform.tfplan
```

### Working with State

View current state:
```bash
terraform show
```

List resources in state:
```bash
terraform state list
```

Get bucket name output:
```bash
terraform output -raw bucket_name
```

## Architecture

### Dynamic Configuration

The infrastructure uses dynamic configuration to avoid hardcoded values:

- **Account ID**: Retrieved via `data.aws_caller_identity.current` and included in bucket name for global uniqueness
- **Principal ARN**: Defaults to current caller's ARN via `locals.principal_arn`, allowing automatic detection of the IAM role assumed by GitHub Actions or local execution
- **Bucket Naming**: Pattern is `{prefix}-{account-id}-s3-tfstate`

### Resource Dependencies

The infrastructure has careful dependency ordering to handle AWS S3 restrictions:

1. **Data Source** (`data.aws_caller_identity.current`) - Retrieved first to get account ID and caller ARN
2. **S3 Bucket** (`aws_s3_bucket.terraform_state`) - Created with account ID in name
3. **Ownership Controls** (`aws_s3_bucket_ownership_controls.terraform_state_acl_ownership`) - Must exist before ACL
4. **Bucket ACL** (`aws_s3_bucket_acl.terraform_state_acl`) - Depends on ownership controls
5. **Public Access Block** (`aws_s3_bucket_public_access_block.terraform_state_public_block`) - Prevents public access
6. **Bucket Policy** (`aws_s3_bucket_policy.terraform_state_policy`) - Depends on public access block; grants access to principal ARN
7. **Versioning** (`aws_s3_bucket_versioning.terraform_state_versioning`) - Enables state history
8. **Encryption** (`aws_s3_bucket_server_side_encryption_configuration.terraform_state_encryption`) - AES256 encryption at rest

### Configuration Files

**variables.tfvars**: Single configuration file that defines:
- `env`: Environment name (e.g., "prod")
- `region`: AWS region (e.g., "us-east-1")
- `prefix`: Resource name prefix (e.g., "talo-tf")
- `principal_arn`: (Optional) IAM principal ARN - defaults to current caller if not set

### State Locking

This infrastructure uses **file-based locking** instead of DynamoDB:
- Lock file stored in S3 alongside the state file
- Configured via `use_lockfile = true` in backend configuration
- Simpler setup, lower cost, no additional resources needed

### Security Considerations

- **Dynamic Principal**: The bucket policy automatically uses the current caller's ARN via `locals.principal_arn`. No hardcoded ARNs!
- **Bucket Policy**: Grants ListBucket, GetObject, PutObject, and DeleteObject permissions to the detected principal ARN
- **Public Access**: Explicitly blocked via `aws_s3_bucket_public_access_block`
- **Encryption**: AES256 encryption at rest for all state files
- **State Files**: The `.gitignore` excludes `terraform.tfstate*` files - never commit state files as they contain sensitive data
- **AWS Secrets Manager**: Local scripts retrieve role ARN from AWS Secrets Manager with proper validation and error handling

### AWS Secrets Manager Setup (for Local Scripts)

Local bash scripts require an AWS Secrets Manager secret to store the role ARN:

**Secret Configuration:**
- **Secret name**: `github-role`
- **Secret type**: Key-value pairs (or JSON string)
- **Required key**: `AWS_STATE_ACCOUNT_ROLE_ARN`
- **Value format**: IAM role ARN (e.g., `arn:aws:iam::123456789012:role/github-actions-state-role`)

**Example JSON structure:**
```json
{
  "AWS_STATE_ACCOUNT_ROLE_ARN": "arn:aws:iam::<account-id>:role/<role-name>"
}
```

**Creating the secret via AWS CLI:**
```bash
aws secretsmanager create-secret \
  --name github-role \
  --description "IAM role ARNs for GitHub Actions" \
  --secret-string '{"AWS_STATE_ACCOUNT_ROLE_ARN":"arn:aws:iam::<account-id>:role/<role-name>"}'
```

**Required IAM permissions for your user:**
Your AWS user/role must have permission to retrieve the secret:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:<region>:<account-id>:secret:github-role-*"
    }
  ]
}
```

**Testing secret retrieval:**
```bash
aws secretsmanager get-secret-value --secret-id github-role --query SecretString --output text | jq .
```

## CI/CD Workflows

### GitHub Actions

Two workflows are configured, both using **OIDC authentication** (no access keys):

**Provisioning** (`.github/workflows/tfstate_infra_provisioning.yaml`):
- Triggered manually via `workflow_dispatch`
- Uses Terraform 1.14.0
- Authenticates via AWS OIDC (assumes role from `AWS_STATE_ACCOUNT_ROLE_ARN`)
- Automatically detects and uses assumed role's ARN for bucket policy
- Checks for existing state file in S3 and downloads if available
- Saves bucket name to `BACKEND_BUCKET_NAME` repository variable
- Uploads state file to S3 at path specified by `BACKEND_PREFIX`

**Destroying** (`.github/workflows/tfstate_infra_destroying.yaml`):
- Triggered manually via `workflow_dispatch`
- Downloads state file from S3 before destroying
- Destroys all infrastructure
- **Warning**: This will delete the S3 bucket, breaking any dependent Terraform projects

**Note**: Both workflows use OIDC authentication and retrieve the role ARN from GitHub repository secrets (`AWS_STATE_ACCOUNT_ROLE_ARN`), not from AWS Secrets Manager.

### Required GitHub Configuration

**Secrets:**
- `AWS_STATE_ACCOUNT_ROLE_ARN`: ARN of IAM role that trusts GitHub OIDC provider
  - **Used by**: GitHub Actions workflows (retrieved directly from GitHub repository secrets)
  - **For local scripts**: The same role ARN must be stored in AWS Secrets Manager (secret 'github-role', key 'AWS_STATE_ACCOUNT_ROLE_ARN')
- `GH_TOKEN`: GitHub Personal Access Token with `repo` scope (for writing repository variables)

**Variables:**
- `AWS_REGION`: AWS region (e.g., "us-east-1")
- `BACKEND_PREFIX`: S3 path for state file (e.g., "backend_state/terraform.tfstate")
- `BACKEND_BUCKET_NAME`: (Auto-generated) S3 bucket name after provisioning

## Automation Scripts

Two bash scripts automate state file management:

### set-state.sh
- Retrieves role ARN from **AWS Secrets Manager** (secret 'github-role', key 'AWS_STATE_ACCOUNT_ROLE_ARN')
- Retrieves repository variables via `gh` CLI
- Assumes IAM role with temporary credentials
- Runs terraform init, validate, plan, apply (if infrastructure doesn't exist)
- Saves bucket name to GitHub repository variable
- Uploads state file to S3
- **Prerequisites**: AWS CLI, Terraform, GitHub CLI (`gh`), `jq`
- **AWS Secrets Manager Requirements**:
  - Secret named `github-role` must exist
  - Secret must contain JSON with key `AWS_STATE_ACCOUNT_ROLE_ARN`
  - User must have `secretsmanager:GetSecretValue` permission

### get-state.sh
- Retrieves role ARN from **AWS Secrets Manager** (secret 'github-role', key 'AWS_STATE_ACCOUNT_ROLE_ARN')
- Retrieves repository variables via `gh` CLI
- Assumes IAM role with temporary credentials
- Downloads state file from S3 if it exists
- **Prerequisites**: AWS CLI, GitHub CLI (`gh`), `jq`
- **AWS Secrets Manager Requirements**:
  - Secret named `github-role` must exist
  - Secret must contain JSON with key `AWS_STATE_ACCOUNT_ROLE_ARN`
  - User must have `secretsmanager:GetSecretValue` permission

Both scripts:
- Handle role assumption automatically
- Provide colored output for success/error/info messages
- Include comprehensive error handling for secret retrieval and validation
- Validate JSON structure and key existence in AWS Secrets Manager secrets

## Documentation

### GitHub Pages Site

This repository includes a comprehensive documentation website hosted via GitHub Pages:

**Location**: `docs/` directory

**Files**:
- `index.html`: Full-featured documentation page with sticky navigation, theme toggle, and responsive design
- `light-theme.css`: Professional light theme with GitHub-inspired color scheme
- `dark-theme.css`: Professional dark theme for better readability in low-light environments
- `favicon.ico`: Site icon for browser tabs
- `header_banner.png`: Visual branding banner for the documentation header

**Features**:
- **Sticky navigation**: Easy access to all sections while scrolling
- **Theme toggle**: Switch between light and dark themes with persistent preference (saved to localStorage)
- **Responsive design**: Mobile-friendly layout that adapts to different screen sizes
- **Active section highlighting**: Visual indication of current section in navigation
- **Smooth scrolling**: Enhanced user experience with animated transitions
- **Organized sections**: Overview, Prerequisites, Configuration, Getting Started, Architecture, Security, Troubleshooting, Support

**Accessing the Documentation**:
- If GitHub Pages is enabled for this repository, access it at: `https://<username>.github.io/<repository-name>/`
- Or open `docs/index.html` locally in a web browser

**Updating the Documentation**:
- Edit `docs/index.html` to update content
- Modify `docs/light-theme.css` or `docs/dark-theme.css` to adjust styling
- Replace `docs/header_banner.png` or `docs/favicon.ico` to update branding
- Changes will be reflected immediately when viewing locally or after pushing to GitHub (if GitHub Pages is enabled)

## Terraform Provider Constraints

- **AWS Provider**: Version 6.21.0 (pinned)
- **Terraform Version**: 1.14.0 (pinned)
- Both CI workflows and local environment should use Terraform 1.14.0

## Important Notes

- **No DynamoDB**: This setup uses file-based locking in S3 instead of DynamoDB for simplicity and lower cost
- **Dynamic Principal**: The `principal_arn` variable is optional and defaults to the current caller's ARN - no hardcoded values!
- **OIDC Authentication**: GitHub Actions uses OIDC to assume an IAM role instead of using access keys
- **AWS Secrets Manager**:
  - Local scripts retrieve role ARN from AWS Secrets Manager (secret 'github-role', key 'AWS_STATE_ACCOUNT_ROLE_ARN')
  - GitHub Actions retrieve role ARN directly from GitHub repository secrets
  - User must have `secretsmanager:GetSecretValue` permission for the 'github-role' secret
  - Secret must contain valid JSON with the required key
- **Force Destroy**: The S3 bucket has `force_destroy = true`, allowing deletion even if it contains files - use with caution
- **Provider Versions**: The `.terraform.lock.hcl` file tracks provider versions - commit changes when upgrading providers
- **State Files**: Never commit `terraform.tfstate*` files to version control - they contain sensitive data and are in `.gitignore`
- **Bucket Naming**: Bucket names include AWS account ID to ensure global uniqueness across all AWS accounts

## Key Differences from Traditional Setup

This infrastructure differs from typical Terraform backend setups:

1. **No hardcoded ARNs**: Uses `data.aws_caller_identity` and `locals` to automatically detect the principal ARN
2. **No DynamoDB**: Uses file-based locking instead of DynamoDB table for state locking
3. **OIDC-based CI/CD**: GitHub Actions uses OIDC provider instead of access keys
4. **Automated scripts**: Bash scripts handle role assumption and state file management
5. **AWS Secrets Manager integration**: Local scripts retrieve secrets from AWS Secrets Manager instead of environment variables
6. **Account ID in bucket name**: Ensures global uniqueness without manual naming conflicts
