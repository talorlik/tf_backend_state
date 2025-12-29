# Changelog

All notable changes to the Terraform Backend State infrastructure module
will be documented in this file.

The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Enhanced `set-state.sh` script with comprehensive automation:
  - Automatic role assumption from AWS Secrets Manager
  - Intelligent infrastructure provisioning detection
  - Automatic state file download from S3 when bucket exists
  - Terraform validation, plan, and apply workflow integration
  - Bucket name verification and GitHub repository variable management
  - Comprehensive error handling with colored output
  - Always updates bucket name and state file to ensure synchronization
- **GitHub Actions Workflows**:
  - Created `.github/workflows/tfstate_infra_provisioning.yaml` - Automated provisioning
  workflow with OIDC authentication
  - Created `.github/workflows/tfstate_infra_destroying.yaml` - Automated destroying
  workflow with OIDC authentication
  - Both workflows support state file management, bucket name variable updates,
  and OIDC-based AWS authentication

### Changed

- Simplified Terraform configuration:
  - Removed `principal_arn` variable - bucket policy now always uses current
    caller's ARN automatically via `data.aws_caller_identity.current.arn`
  - Eliminates need to pass principal ARN as a variable, simplifying
    configuration
- Updated `set-state.sh` script:
  - Removed principal ARN retrieval and passing to Terraform plan command
  - Script now relies on automatic principal detection via `data.aws_caller_identity.current.arn`
  - Removed conditional check for `PROVISIONED_INFRA` - script now always
    updates bucket name and state file
  - Ensures bucket name repository variable and state file are always
    synchronized with latest values
  - Checks for existing `BACKEND_BUCKET_NAME` repository variable to determine
    if infrastructure needs provisioning
  - Automatically downloads existing state file from S3 when bucket is found
  - Validates bucket name consistency between repository variable and Terraform
    output
  - Enhanced credential extraction with jq fallback to sed for broader
    compatibility
  - Improved user feedback with colored status messages (INFO, SUCCESS, ERROR)

### Removed

- Removed `principal_arn` variable from `variables.tf` - no longer needed as
  bucket policy automatically uses current caller's ARN
- Removed `locals` block from `main.tf` that handled `principal_arn` fallback logic
- Removed all references to `principal_arn` from documentation:
  - Removed from README.md (Optional Variables section and troubleshooting)
  - Removed from `docs/index.html` (Terraform Variables table and troubleshooting
  section)

### Security

- Enhanced credential handling in `set-state.sh`:
  - Secure role assumption with timestamped session names
  - Credential verification before proceeding with operations
  - Proper error handling for failed role assumptions
- Simplified security model:
  - Bucket policy now always uses current caller's ARN automatically
  - Eliminates potential misconfiguration from manual ARN specification
  - Ensures bucket access is always aligned with the executing identity

### Documentation

- Updated README.md:
  - Removed reference to non-existent `SECRETS_REQUIREMENTS.md` file
  - Added inline information about AWS Secrets Manager secret structure
  - Removed "Optional Variables" section about `principal_arn`
  - Updated troubleshooting section to reflect automatic principal detection
- Updated `docs/index.html`:
  - Removed `principal_arn` from Terraform Variables table
  - Updated Step 3 section to clarify bucket policy uses `data.aws_caller_identity.current.arn`
  directly
  - Updated troubleshooting section to remove `principal_arn` references

## [1.0.0] - 2025

### Added

- Initial Terraform configuration for S3 backend state bucket
- S3 bucket with versioning enabled for state file storage
- Server-side encryption (AES256) for state files at rest
- S3 bucket policy with IAM-based access control
- Public access block configuration to prevent unauthorized access
- Bucket ownership controls to support ACL configuration
- Dynamic bucket naming using prefix and AWS account ID for global
  uniqueness
- Support for optional `principal_arn` variable with automatic detection
  of current caller's ARN (removed in [Unreleased])
- Terraform output for bucket name
- Comprehensive README documentation with setup instructions
- Local automation scripts (`get-state.sh` and `set-state.sh`) for
  state file management
- AWS Secrets Manager integration for role ARN retrieval in local
  scripts
- GitHub repository variable management for bucket name and
  configuration
- Support for GitHub OIDC authentication via IAM roles
- Automatic state file upload/download functionality
- Environment and prefix-based resource tagging
- **GitHub Pages Documentation Site**:
  - Created comprehensive documentation site in `docs/` directory
  - `index.html` - Full-featured documentation page with sticky navigation, theme
  toggle (light/dark), and responsive design
  - `light-theme.css` and `dark-theme.css` - Professional styling with GitHub-inspired
  color schemes
  - `favicon.ico` and `header_banner.png` - Visual branding elements
  - Organized content sections: Overview, Prerequisites, Configuration, Getting
  Started, Architecture, Security, Troubleshooting, Support
  - Mobile-responsive navigation with smooth scrolling and active section highlighting
  - Theme persistence using localStorage

### Changed

- Updated AWS provider to version 6.21.0
- Updated Terraform required version to 1.14.0
- Improved automation scripts to use AWS Secrets Manager for secret access
- **Secret Retrieval Implementation**:
  - Implemented `get_aws_secret(secret_name)` function - Retrieves secret JSON
  from AWS Secrets Manager
  - Implemented `get_secret_key_value(secret_json, key_name)` function - Extracts
  key value from secret JSON with validation
  - Enhanced validation: Added comprehensive error handling for secret existence,
  JSON parsing, and key validation
- Enhanced documentation with detailed troubleshooting sections
- Improved error handling and user feedback in automation scripts

### Fixed

- Fixed bucket prefix handling to prevent leading slash issues in
  backend configuration
- Corrected Markdown lint errors for row length across documentation
- Fixed state file management to prevent committing sensitive state to
  repository

### Removed

- (No removals in this version)

### Security

- Implemented private bucket ACL configuration
- Added comprehensive public access blocking
- Enabled encryption at rest for all state files
- Implemented IAM-based access control with principal ARN support
- Added support for OIDC-based authentication (no access keys
  required)

## [0.1.0] - Initial Development

### Added

- Basic S3 bucket configuration
- S3 file-based state locking
- Basic documentation

## Notes

- **State Locking**: Uses S3 file-based locking (`use_lockfile = true`)
- **Bucket Naming**: Format is `{prefix}-{account-id}-s3-tfstate` to
  ensure global uniqueness
- **Access Control**: Always uses the current caller's ARN automatically via
  `data.aws_caller_identity.current.arn` - no manual configuration needed
- **Automation**: Supports both GitHub Actions workflows and local
  script execution
- **Security**: All state files are encrypted, private, and
  access-controlled via IAM policies
