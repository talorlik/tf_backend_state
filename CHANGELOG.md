# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] - 2025-12-21

### Added
- **Comprehensive README.md** - Added 558-line detailed documentation covering:
  - Complete project overview and prerequisites
  - GitHub repository configuration guide (secrets and variables)
  - Terraform variable documentation
  - Step-by-step provisioning and destroying workflows
  - AWS IAM OIDC setup instructions
  - Troubleshooting guide
  - State file management procedures
- **Automation Scripts**:
  - `set-state.sh` - Automated script to provision infrastructure, assume IAM role, and upload state file to S3
  - `get-state.sh` - Automated script to download state file from S3 with role assumption
  - Both scripts include colored output, error handling, and integrate with GitHub CLI
- **outputs.tf** - Added output for bucket name to support automation
- **WARP.md** - Created comprehensive development guide for Warp AI agent:
  - Common commands and automated workflows
  - Architecture documentation with dynamic configuration details
  - Security considerations and best practices
  - CI/CD workflow documentation
  - Key differences from traditional Terraform backend setups
- **CHANGELOG.md** - This file, documenting all changes since inception

### Changed
- **Secret Retrieval Refactor**:
  - **Local Scripts**: Updated `get-state.sh` and `set-state.sh` to retrieve secrets from AWS Secrets Manager instead of environment variables
  - **Split Secret Functions**: Replaced `get_repo_secret_value()` with two separate functions:
    - `get_aws_secret(secret_name)` - Retrieves secret JSON from AWS Secrets Manager
    - `get_secret_key_value(secret_json, key_name)` - Extracts key value from secret JSON with validation
  - **AWS Secrets Manager Integration**: Scripts now retrieve role ARN from AWS Secrets Manager secret named 'github-role' with key 'AWS_STATE_ACCOUNT_ROLE_ARN'
  - **Enhanced Validation**: Added comprehensive error handling for secret existence, JSON parsing, and key validation
  - **GitHub Actions**: Workflows continue to use GitHub repository secrets directly (no change to workflow behavior)
- **Complete Infrastructure Refactor**:
  - **Removed DynamoDB state locking** - Replaced with file-based locking in S3 for simplicity and cost reduction
  - **Dynamic Principal ARN Detection** - Added `data.aws_caller_identity` to automatically detect and use current caller's ARN
  - **Dynamic Bucket Naming** - Bucket name now includes AWS account ID for global uniqueness: `{prefix}-{account-id}-s3-tfstate`
  - **Bucket Policy Modernization** - Switched from heredoc to `jsonencode()` for better syntax and validation
  - **Added Public Access Block** - Explicit S3 public access blocking for enhanced security
- **main.tf** - Complete rewrite:
  - Added `data.aws_caller_identity.current` data source
  - Added `locals` block for dynamic principal ARN with fallback to current caller
  - Updated S3 bucket resource to include account ID in name
  - Removed `lifecycle.prevent_destroy` block
  - Added `aws_s3_bucket_public_access_block` resource
  - Updated bucket policy to use `jsonencode()` instead of heredoc
  - Updated bucket policy to reference `local.principal_arn` instead of `var.principal_arn`
  - Added dependency on public access block in bucket policy
  - **Removed all DynamoDB resources**: `aws_dynamodb_table.terraform_lock` and `aws_dynamodb_resource_policy.terraform_lock_policy`
  - Removed 98 lines of commented-out legacy code
- **variables.tf** - Simplified configuration:
  - Removed `resource_alias` variable (no longer needed)
  - Made `principal_arn` optional with `default = null`
  - Updated `principal_arn` description to explain automatic detection behavior
- **Configuration Files**:
  - Removed `dev.tfvars` - Replaced with single unified config file
  - Removed `prod.tfvars` - Replaced with single unified config file
  - Added `variables.tfvars` - Single configuration file with optional `principal_arn`
- **providers.tf** - Updated provider versions:
  - AWS provider: `5.59.0` → `6.21.0` (pinned)
  - Terraform version constraint: `>= 1.2.0` → `= 1.14.0` (exact version pinned)
- **GitHub Actions Workflows** - Complete OIDC migration:
  - Renamed `infra_provisioning.yaml` → `tfstate_infra_provisioning.yaml`
  - Renamed `infra_destroying.yaml` → `tfstate_infra_destroying.yaml`
  - Migrated from AWS access keys to OIDC authentication (`aws-actions/configure-aws-credentials@v4`)
  - Updated Terraform version from 1.9.2 to 1.14.0
  - Updated checkout action from `v2` to `v4`
  - Added permissions block: `contents: write`, `actions: write`, `id-token: write`
  - Added dynamic principal ARN detection step
  - Added state file existence check before provisioning
  - Added state file download from S3 if it exists
  - Added state file upload to S3 after provisioning
  - Added GitHub repository variable management for `BACKEND_BUCKET_NAME`
  - Switched from hardcoded environment variables to GitHub secrets/variables
  - Added `github-script` actions for variable management with proper error handling

### Removed
- **DynamoDB Resources**:
  - `aws_dynamodb_table.terraform_lock` - No longer using DynamoDB for state locking
  - `aws_dynamodb_resource_policy.terraform_lock_policy` - Associated policy removed
- **Configuration Files**:
  - `dev.tfvars` - Consolidated into single `variables.tfvars`
  - `prod.tfvars` - Consolidated into single `variables.tfvars`
- **Variables**:
  - `resource_alias` variable - No longer needed
- **Old Workflows**:
  - `.github/workflows/infra_cleanup.yaml` - Removed in favor of destroying workflow
  - `.github/workflows/infra_deployment.yaml` - Removed in favor of provisioning workflow
- **Hardcoded Values**:
  - Removed hardcoded IAM user ARN from DynamoDB policy
  - Removed hardcoded principal ARN requirement via dynamic detection
- **Legacy Code**:
  - Removed 98 lines of commented-out alternative bucket policy implementation

### Security
- **OIDC Authentication** - GitHub Actions now use OIDC to assume IAM roles instead of storing AWS access keys
- **Public Access Block** - Added explicit S3 public access blocking (`aws_s3_bucket_public_access_block`)
- **Dynamic Principal Detection** - Principal ARN now automatically detected, eliminating hardcoded credentials
- **Role-Based Access** - Scripts use temporary credentials via role assumption
- **Improved Policy Dependencies** - Bucket policy now explicitly depends on public access block being in place

### Fixed
- **Bucket Naming Conflicts** - Account ID in bucket name prevents naming collisions across AWS accounts
- **ACL Compatibility** - Proper resource ordering ensures `aws_s3_bucket_ownership_controls` exists before ACL
- **State Locking Costs** - Eliminated DynamoDB costs by switching to file-based locking

## [1.2.0] - 2024-08-27

### Changed
- **providers.tf** - Updated AWS provider version from `5.59.0` to exact pinned version
- **Added Terraform lock file** - `.terraform.lock.hcl` added with provider version constraints

## [1.1.0] - 2024-08-15

### Changed
- **Workflow Restructuring**:
  - Renamed `.github/workflows/infra_cleanup.yaml` → `.github/workflows/infra_destroying.yaml`
  - Renamed `.github/workflows/infra_deployment.yaml` → `.github/workflows/infra_provisioning.yaml`
  - Updated workflow jobs and steps to match new naming convention
- **main.tf** - Enhanced resource configuration:
  - Added comprehensive S3 bucket configuration with ownership controls
  - Added bucket versioning for state file history
  - Added server-side encryption (AES256) for state files
  - Added DynamoDB table for state locking with PAY_PER_REQUEST billing
  - Added DynamoDB resource policy for access control
  - Implemented proper resource dependencies
- **providers.tf** - Updated AWS provider source and version configuration

### Removed
- **Workflow Files**:
  - Deleted `.github/workflows/infra_cleanup.yaml` (renamed to destroying)
  - Deleted `.github/workflows/infra_deployment.yaml` (renamed to provisioning)

## [1.0.0] - 2024-06-10

### Added
- **Initial Release** - First version of Terraform backend state infrastructure
- **Core Terraform Configuration**:
  - `main.tf` - S3 bucket and DynamoDB table for Terraform state management
  - `variables.tf` - Variable definitions for `env`, `region`, `prefix`, `resource_alias`, `principal_arn`
  - `providers.tf` - AWS provider configuration with version `~> 5.0`
- **Environment Configurations**:
  - `dev.tfvars` - Development environment configuration
  - `prod.tfvars` - Production environment configuration
- **GitHub Actions Workflows**:
  - `.github/workflows/infra_deployment.yaml` - Automated deployment workflow
  - `.github/workflows/infra_cleanup.yaml` - Automated cleanup workflow
  - Both workflows use AWS access keys (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
- **Git Configuration**:
  - `.gitignore` - Standard Terraform ignore patterns for state files, lock files, and credentials
- **LICENSE** - MIT License

### Infrastructure Features
- S3 bucket for Terraform state storage
- DynamoDB table for state locking
- Support for multiple environments (dev/prod)
- GitHub Actions CI/CD integration
- IAM-based access control via bucket and DynamoDB policies

---

## Migration Guide: v1.2.0 → Unreleased

If you're upgrading from version 1.2.0 to the unreleased version, follow these steps:

### Prerequisites
1. Install GitHub CLI (`gh`) and authenticate: `gh auth login`
2. Install `jq` for JSON parsing: `brew install jq` (macOS) or equivalent
3. Ensure you have Terraform 1.14.0 installed

### GitHub Configuration
1. **Set up AWS OIDC Identity Provider** in your AWS account (see README.md)
2. **Create IAM Role** that trusts GitHub OIDC provider
3. **Configure GitHub Secrets**:
   - Remove: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
   - Add: `AWS_STATE_ACCOUNT_ROLE_ARN` (IAM role ARN)
   - Add: `GH_TOKEN` (Personal Access Token with `repo` scope)
4. **Configure GitHub Variables**:
   - Add: `AWS_REGION` (e.g., "us-east-1")
   - Add: `BACKEND_PREFIX` (e.g., "backend_state/terraform.tfstate")

### Migration Steps
1. **Backup your current state**:
   ```bash
   cp terraform.tfstate terraform.tfstate.backup
   ```

2. **Export environment variable** (if using scripts locally):
   ```bash
   export AWS_STATE_ACCOUNT_ROLE_ARN="arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME"
   ```

3. **Update Terraform configuration**:
   - Run `terraform init -upgrade` to update provider versions
   - Review and update `variables.tfvars` (remove `resource_alias`, `principal_arn` is now optional)

4. **Note**: The DynamoDB table will be removed. Ensure no other projects depend on it.

5. **Apply changes**:
   - Use `./set-state.sh` for automated provisioning
   - Or manually run terraform with the new configuration

6. **Verify**:
   - Check that bucket name includes account ID
   - Verify OIDC authentication works in GitHub Actions
   - Confirm state file uploaded to S3

### Breaking Changes
- **DynamoDB table removed** - If other projects reference this table, update them first
- **Variable structure changed** - `dev.tfvars` and `prod.tfvars` replaced with `variables.tfvars`
- **Bucket naming changed** - Bucket name now includes account ID (will create new bucket)
- **Authentication changed** - Must migrate from access keys to OIDC

[Unreleased]: https://github.com/USERNAME/REPO/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/USERNAME/REPO/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/USERNAME/REPO/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/USERNAME/REPO/releases/tag/v1.0.0
