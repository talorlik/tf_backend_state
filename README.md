# Terraform Backend State Infrastructure

This directory contains Terraform configuration to provision the AWS
infrastructure needed to store Terraform state files remotely. This includes an
S3 bucket for state storage with file-based locking.

## Overview

This infrastructure creates:

- **S3 Bucket**: Stores Terraform state files with versioning enabled and
file-based locking
- **Security**: Encrypted storage, private access, and IAM-based access control

The bucket name is dynamically generated based on your prefix and AWS account ID
to ensure global uniqueness.

## Prerequisites

- **AWS Account A (State Account)** with appropriate permissions for S3 bucket
creation
- GitHub repository with Actions enabled
- AWS SSO/OIDC configured (see AWS IAM Setup section)
- Terraform >= 1.2.0 (for local execution)
- AWS Cli V2

## GitHub Repository Configuration

Before running the workflows, you need to configure the following in your GitHub
repository:

### Required Secrets

Secrets are sensitive values that are encrypted and only accessible to
workflows. Configure them at:
**Repository → Settings → Secrets and variables → Actions → Secrets**

1. `AWS_STATE_ACCOUNT_ROLE_ARN`

    - **Type**: Secret
    - **Description**: ARN of the IAM role in Account A (State Account) that
    trusts GitHub OIDC provider
    - **Format**: `arn:aws:iam::ACCOUNT_A_ID:role/github-actions-state-role`
    - **How to set it up**:
      1. Create an OIDC Identity Provider in AWS IAM:
         - Provider URL: `https://token.actions.githubusercontent.com`
         - Audience: `sts.amazonaws.com`
      2. Create an IAM Role that trusts the GitHub OIDC provider (see AWS IAM
      Setup below)
      3. Attach permissions policy with S3 access to state bucket
      4. Copy the role ARN and set it as this secret
    - **Used for**: Authenticating AWS API calls in GitHub Actions via OIDC (no
    access keys needed)
    - **Permissions needed**: S3 access to create/manage state bucket

2. `GH_TOKEN`

    - **Type**: Secret
    - **Description**: GitHub Personal Access Token (PAT) with `repo` scope
    - **How to create it**:
      1. Go to GitHub → Settings → Developer settings → Personal access tokens →
      Tokens (classic)
      2. Click "Generate new token (classic)"
      3. Give it a descriptive name (e.g., "Terraform Backend State")
      4. Select scope: **`repo`** (Full control of private repositories)
      5. Click "Generate token" and copy it immediately
      6. Store it as a repository secret named `GH_TOKEN`
    - **Used for**: Creating/updating the `BACKEND_BUCKET_NAME` repository
    variable after provisioning
    - **Why needed**: The default `GITHUB_TOKEN` may not have permissions to
    write repository variables

### Required Variables

Variables are non-sensitive values that can be accessed by workflows. Configure
them at:
**Repository → Settings → Secrets and variables → Actions → Variables**

1. `AWS_REGION`

    - **Type**: Variable
    - **Description**: AWS region where resources will be created
    - **Example values**: `us-east-1`, `us-west-2`, `eu-west-1`
    - **Used for**: Setting the AWS region for all operations
    - **⚠️ Important**: This should match the region in your `variables.tfvars`
    file

2. `BACKEND_PREFIX`

    - **Type**: Variable
    - **Description**: The prefix that will be created once the state file is
    saved in the bucket
    - **Example values**: `backend_state/terraform.tfstate`
    - **Used for**: Setting the bucket prefix for all operations

3. `BACKEND_BUCKET_NAME` (Auto-generated)

    - **Type**: Variable
    - **Description**: The dynamically generated S3 bucket name
    - **How it's created**: Automatically set by the provisioning workflow after
    the bucket is created
    - **Used for**: Other workflows that need to know the bucket name (e.g.,
    destroying workflow)
    - **⚠️ Note**: You don't need to create this manually - it's created
    automatically

## Terraform Variables

Configure these **required** variables in `variables.tfvars` before running:

1. `env`

    - **Type**: `string`
    - **Description**: Deployment environment identifier
    - **Example**: `"prod"`, `"dev"`, `"staging"`
    - **Used for**: Tagging resources and organizing by environment

2. `region`

    - **Type**: `string`
    - **Description**: AWS region for resource deployment
    - **Example**: `"us-east-1"`, `"us-west-2"`
    - **Used for**: Specifying where AWS resources are created
    - **⚠️ Important**: Should match `AWS_REGION` GitHub variable

3. `prefix`

    - **Type**: `string`
    - **Description**: Prefix added to all resource names for identification
    - **Example**: `"mycompany-tf"`, `"project-name"`
    - **Used for**: Creating unique names for all resources
    - **⚠️ Important**: Choose a unique prefix to avoid naming conflicts

### Optional Variables

1. `principal_arn` (Optional - Not Required)

    - **Type**: `string` (optional, defaults to current caller's ARN)
    - **Description**: AWS IAM principal (user or role) ARN that will have
    access to the S3 bucket. If not provided, Terraform automatically
    detects and uses the current caller's ARN (the identity running
    Terraform).
    - **Default**: Automatically uses `data.aws_caller_identity.current.arn`
    - **Example**: `"arn:aws:iam::123456789012:user/myuser"` or
    `"arn:aws:iam::123456789012:role/myrole"`
    - **Used for**: Granting access to AWS to execute all needed operations.
    - **Security Note**: ⚠️ **No need to hard-code ARNs!** The default behavior
    automatically uses the current caller's ARN, whether it's:
      - Your local IAM user
      - An assumed IAM role (automatically handled by the scripts - see [Local
      Execution](#option-2-local-execution))
      - A GitHub Actions OIDC role
    - **Local Deployment**: For local deployment, the scripts automatically
    assume the IAM role configured in `AWS_STATE_ACCOUNT_ROLE_ARN` GitHub
    secret. Terraform will automatically detect and use the assumed role's
    ARN.
    - **When to override**: Only set this if you need to grant access to a
    different principal than the one running Terraform.
    - **How to find it** (if needed):
      - For IAM User: AWS Console → IAM → Users → Your User → Summary → ARN
      - For IAM Role: AWS Console → IAM → Roles → Your Role → Summary → ARN

## How to Run

### Option 1: GitHub Actions (Recommended)

This is the recommended approach as it handles state file upload automatically.

#### Provisioning 1 (Create Infrastructure)

1. **Configure your variables**:
   - Edit `variables.tfvars` with your values
   - Commit and push the changes

2. **Run the workflow**:
   - Go to GitHub → Actions tab
   - Select "TF Backend State Provisioning" workflow
   - Click "Run workflow" → "Run workflow"
   - The workflow will:
     - Validate Terraform configuration
     - Create the S3 bucket
     - Save the bucket name as a repository variable
     - Upload the state file to S3

#### Destroying (Remove Infrastructure)

1. **Run the destroying workflow**:
   - Go to GitHub → Actions tab
   - Select "TF Backend State Destroying" workflow
   - Click "Run workflow" → "Run workflow"
   - The workflow will:
     - Download the state file from S3
     - Destroy all resources
     - ⚠️ **Warning**: This permanently deletes the S3 bucket

### Option 2: Local Execution

For local development or testing, use the provided automation scripts. These
scripts handle role assumption, Terraform operations, state file management, and
repository variable updates automatically.

> **⚠️ IMPORTANT**: The scripts automatically assume the IAM role configured in
`AWS_STATE_ACCOUNT_ROLE_ARN` GitHub secret. The S3 bucket policy grants access
to the role ARN (used by GitHub Actions), not your local user ARN. Terraform
will automatically detect and use the assumed role's ARN.

#### Prerequisites for Local Execution

Before running the scripts, ensure you have:

1. **GitHub CLI installed and authenticated**:

   ```bash
   # Install GitHub CLI (if not already installed)
   # macOS: brew install gh
   # Linux: See https://cli.github.com/manual/installation

   # Authenticate with GitHub
   gh auth login
   ```

2. **Required tools installed**:
   - AWS CLI V2
   - Terraform >= 1.2.0
   - GitHub CLI (`gh`)
   - `jq` (for JSON parsing)

3. **GitHub repository configured**:
   - `AWS_STATE_ACCOUNT_ROLE_ARN` secret set
   - `AWS_REGION` variable set (defaults to `us-east-1` if not set)
   - `BACKEND_PREFIX` variable set
   - `variables.tfvars` file configured with required variables

#### Provisioning 2 (Create Infrastructure)

Use the `set-state.sh` script to provision infrastructure and upload the state
file:

```bash
cd tf_backend_state
./set-state.sh
```

**What the script does automatically**:

1. Retrieves `AWS_STATE_ACCOUNT_ROLE_ARN` from GitHub repository secrets
2. Retrieves `AWS_REGION` from GitHub repository variables (defaults to
`us-east-1`)
3. Retrieves `BACKEND_PREFIX` from GitHub repository variables
4. Assumes the IAM role with temporary credentials
5. Checks if infrastructure already exists:
   - **If not exists**: Runs `terraform init`, `validate`, `plan`, and `apply`
   - **If exists**: Downloads existing state file from S3 (if available)
6. Saves bucket name to GitHub repository variable `BACKEND_BUCKET_NAME`
7. Uploads `terraform.tfstate` to S3 (only if infrastructure was just
provisioned)

#### Downloading Existing State File

If you need to download the state file from S3 (e.g., after running via GitHub
Actions), use the `get-state.sh` script:

```bash
cd tf_backend_state
./get-state.sh
```

**What the script does automatically**:

1. Retrieves `AWS_STATE_ACCOUNT_ROLE_ARN` from GitHub repository secrets
2. Retrieves `AWS_REGION` from GitHub repository variables (defaults to
`us-east-1`)
3. Assumes the IAM role with temporary credentials
4. Retrieves `BACKEND_BUCKET_NAME` and `BACKEND_PREFIX` from GitHub repository
variables
5. Downloads `terraform.tfstate` from S3 if it exists

#### Destroying Infrastructure

To destroy the infrastructure, use Terraform directly (after downloading the
state file if needed):

```bash
cd tf_backend_state

# Download state file if needed
./get-state.sh

# Destroy infrastructure
terraform plan -var-file="variables.tfvars" -destroy -out terraform.tfplan
terraform apply -auto-approve terraform.tfplan
```

> **⚠️ Warning**: This permanently deletes the S3 bucket and all resources.

## What Gets Created

### S3 Bucket

- **Name**: `{prefix}-{account-id}-s3-tfstate`
- **Features**:
  - Versioning enabled (allows recovery of previous state versions)
  - Encryption at rest (AES256)
  - Private access (no public access)
  - IAM-based access control
  - Force destroy enabled (allows bucket deletion even if not empty)

### State Locking

- **Method**: File-based locking using `use_lockfile = true` in the backend
configuration
- **Location**: Lock file is stored in the same S3 bucket as the state file
- **Benefits**: Simpler setup, lower cost, lock file stored alongside state in
S3

### Security Features

- **S3 Bucket Policy**: Grants access only to the specified IAM principal
- **Public Access Block**: Prevents any public access to the S3 bucket
- **Encryption**: All data encrypted at rest

## State File Management

### After Provisioning

- The state file is automatically uploaded to: `s3://{bucket-name}/{prefix}`
- The bucket name is saved as `BACKEND_BUCKET_NAME` repository variable
- The variable is accessible to all workflows via `${{ vars.BACKEND_BUCKET_NAME
}}`

### State File Location

- **Path in S3**: `{prefix}`
- **Versioning**: Enabled, so you can recover previous versions if needed

## Troubleshooting

### "Resource not accessible by integration" error

- **Cause**: `GH_TOKEN` doesn't have proper permissions or doesn't exist
- **Solution**: Create a PAT with `repo` scope and store it as `GH_TOKEN` secret

### "Access Denied" when accessing S3

- **Cause**: The IAM principal doesn't have S3 permissions, or there's a
mismatch between the caller and the bucket policy
- **Solution**:
  - By default, `principal_arn` automatically uses the current caller's ARN.
  Verify this matches your expectations:
    - Run `aws sts get-caller-identity` to see your current ARN
    - Ensure the caller has S3 permissions for the state bucket
  - If you've overridden `principal_arn`, verify it matches the IAM role ARN
  used in `AWS_STATE_ACCOUNT_ROLE_ARN` secret (for GitHub Actions)
  - Check that the OIDC trust relationship is correctly configured (for GitHub
  Actions)

### OIDC Authentication Issues

- **Cause**: GitHub OIDC provider not configured correctly or role trust policy
incorrect
- **Solution**:
  - Verify OIDC Identity Provider exists in Account A
  - Check role trust policy includes correct repository name
  - Ensure `AWS_STATE_ACCOUNT_ROLE_ARN` secret contains the correct role ARN

### Bucket name conflicts

- **Cause**: Another account is using the same prefix
- **Solution**: Use a more unique prefix in `variables.tfvars`

### State file not found during destroy

- **Cause**: The state file wasn't uploaded or the bucket name variable is
incorrect
- **Solution**: Verify `BACKEND_BUCKET_NAME` variable exists and contains the
correct bucket name

## Important Notes

1. **State File**: The state file contains sensitive information. Never commit
it to version control (it's in `.gitignore`).

2. **Bucket Deletion**: The bucket has `force_destroy = true`, meaning it can be
deleted even if it contains files. Use with caution.

3. **Costs**:
   - S3: Minimal cost for storage (typically < $1/month for small projects)
   - No additional costs for state locking (uses file-based locking in S3)

4. **Backup**: State file versioning is enabled, so you can recover previous
versions from the S3 console if needed.

5. **Multiple Environments**: If you need multiple environments (dev, staging,
prod), you can:
   - Use different prefixes in `variables.tfvars`
   - Or create separate Terraform workspaces
   - Or use separate repositories/variables for each environment

## AWS IAM Setup

### Account A (State Account) - OIDC Configuration

This infrastructure uses **AWS SSO via GitHub OIDC** for authentication instead
of access keys.

#### Step 1: Create OIDC Identity Provider

The OIDC Identity Provider establishes trust between GitHub Actions and AWS,
allowing GitHub to authenticate without access keys.

1. **Navigate to IAM Console**:
   - Go to AWS IAM Console → **Identity providers** (left sidebar)
   - Click **Add provider**

2. **Configure Provider**:
   - Select **OpenID Connect**
   - **Provider URL**: `https://token.actions.githubusercontent.com`
   - Click **Get thumbprint** (AWS will automatically fetch GitHub's certificate
   thumbprint for security)
   - **Audience**: `sts.amazonaws.com`
   - Click **Add provider**

3. **Verify Creation**:
   - You should see the provider listed with ARN format:
   `arn:aws:iam::ACCOUNT_A_ID:oidc-provider/token.actions.githubusercontent.com`
   - Note this ARN - it will be used in the role trust policy

**What this does:**

- Establishes GitHub as a trusted identity provider for AWS
- Allows GitHub Actions to request temporary AWS credentials via OIDC tokens
- No access keys needed - authentication happens through OIDC tokens

#### Step 2: Create IAM Role and Assign to Identity Provider

Now create an IAM Role that uses this Identity Provider for authentication. The
role will be "assigned" to the Identity Provider through its trust policy.

1. **Navigate to IAM Roles**:
   - Go to AWS IAM Console → **Roles** (left sidebar)
   - Click **Create role**

2. **Select Trusted Entity Type**:
   - Under **Trusted entity type**, select **Web identity**
   - Under **Web identity**, select the Identity Provider you just created:
   `token.actions.githubusercontent.com`
   - **Audience**: Select `sts.amazonaws.com` from the dropdown
   - Click **Next**

3. **Configure Trust Policy Conditions** (Recommended for Security):
   - Click **Add condition** to restrict which repositories can assume this role
   - **Condition key**: `token.actions.githubusercontent.com:sub`
   - **Operator**: `StringLike`
   - **Value**: `repo:YOUR_ORG/YOUR_REPO:*` (replace `YOUR_ORG/YOUR_REPO` with
   your GitHub organization and repository name)
     - Example: `repo:talorlik/ldap-2fa-on-k8s:*`
   - This ensures only workflows from your specific repository can assume the
   role
   - Click **Next**

4. **Add Permissions**:
   - Create or attach a policy with S3 permissions for the state bucket
   - **Minimum required permissions**:

     ```json
     {
       "Version": "2012-10-17",
       "Statement": [
         {
           "Effect": "Allow",
           "Action": [
             "s3:GetObject",
             "s3:PutObject",
             "s3:DeleteObject",
             "s3:ListBucket"
           ],
           "Resource": [
             "arn:aws:s3:::your-state-bucket-name",
             "arn:aws:s3:::your-state-bucket-name/*"
           ]
         }
       ]
     }
     ```

   - **Note**: For initial setup, you may want to use a broader policy (e.g.,
   `s3:*` on all buckets) and restrict it later once you know the exact
   bucket name
   - Click **Next**

5. **Name and Create Role**:
   - **Role name**: `github-actions-state-role` (or your preferred name)
   - **Description**: "Role for GitHub Actions to access Terraform state bucket
   via OIDC"
   - Click **Create role**

6. **Verify Role Configuration**:
   - After creation, click on the role name to view details
   - Under **Trust relationships**, you should see:
     - **Type**: Web identity
     - **Identity provider**: `token.actions.githubusercontent.com`
     - **Audience**: `sts.amazonaws.com`
     - **Condition**: `token.actions.githubusercontent.com:sub` equals
     `repo:YOUR_ORG/YOUR_REPO:*`
   - This confirms the role is properly assigned to the Identity Provider

7. **Copy Role ARN**:
   - The **Role ARN** is displayed at the top of the role details page
   - Format: `arn:aws:iam::ACCOUNT_A_ID:role/github-actions-state-role`
   - Copy this ARN → Set as `AWS_STATE_ACCOUNT_ROLE_ARN` GitHub secret

**Understanding the Relationship:**

- **Identity Provider**: Establishes trust with GitHub (created first)
- **IAM Role**: Uses the Identity Provider for authentication (created second)
- **Assignment**: The role is "assigned" to the Identity Provider through its
trust policy, which references the Identity Provider's ARN
- When GitHub Actions runs, it presents an OIDC token, which AWS validates
against the Identity Provider, then allows assuming the role

**Important Notes:**

- The Identity Provider must be created **before** the IAM Role
- The IAM Role's trust policy automatically references the Identity Provider you
selected during role creation
- The condition on `token.actions.githubusercontent.com:sub` restricts access to
your specific repository for security
- You can update the trust policy later to add more repositories or adjust
conditions
- The role ARN is what you'll use in GitHub Secrets, not the Identity Provider
ARN

#### Step 3: S3 Bucket Policy (Automatic)

The bucket policy in `main.tf` automatically uses the current caller's ARN by
default. **No configuration needed!**

- When running via GitHub Actions: The workflow automatically detects the
assumed role's ARN and uses it
- When running locally: The scripts automatically assume the IAM role and
Terraform detects the assumed role's ARN
- The `principal_arn` variable is optional - only set it if you need to grant
access to a different principal

> [!NOTE]
>
> For multi-account setups, Account A stores state, and Account B
> deploys resources. The workflows and scripts handle this automatically via role
> assumption, and the principal ARN is automatically detected.

## Related Documentation

- [Main README](../README.md) - Project overview and quick start
- [Backend Infrastructure](../backend_infra/README.md) - VPC, EKS, IRSA, and VPC
endpoints
- [Application Infrastructure](../application/README.md) - OpenLDAP, 2FA app,
and supporting services
