#!/bin/bash

# Script to assume AWS role and download Terraform state file from S3 if it exists
# ROLE_ARN is retrieved from GitHub repository secret 'AWS_STATE_ACCOUNT_ROLE_ARN'
# REGION is retrieved from GitHub repository variable 'AWS_REGION' (defaults to 'us-east-1' if not set)
# Bucket name and prefix are retrieved from GitHub repository variables

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}SUCCESS:${NC} $1"
}

print_info() {
    echo -e "${YELLOW}INFO:${NC} $1"
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed."
    echo "Please install it from: https://aws.amazon.com/cli/"
    exit 1
fi

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    print_error "GitHub CLI (gh) is not installed."
    echo "Please install it from: https://cli.github.com/"
    echo ""
    echo "Or use the alternative method with curl (requires GITHUB_TOKEN environment variable):"
    echo "  export GITHUB_TOKEN=your_token"
    exit 1
fi

# Check if user is authenticated with GitHub CLI
if ! gh auth status &> /dev/null; then
    print_error "Not authenticated with GitHub CLI."
    echo "Please run: gh auth login"
    exit 1
fi

# Check if jq is installed (required for gh --jq flag)
if ! command -v jq &> /dev/null; then
    print_error "jq is not installed."
    echo "Please install it:"
    echo "  macOS: brew install jq"
    echo "  Linux: sudo apt-get install jq (or use your package manager)"
    echo "  Or visit: https://stedolan.github.io/jq/download/"
    exit 1
fi

# Get repository owner and name
REPO_OWNER=$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || echo "")
REPO_NAME=$(gh repo view --json name --jq '.name' 2>/dev/null || echo "")

if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ]; then
    print_error "Could not determine repository information."
    echo "Please ensure you're in a git repository and have proper permissions."
    exit 1
fi

print_info "Repository: ${REPO_OWNER}/${REPO_NAME}"

# Function to get repository variable using GitHub CLI
get_repo_variable() {
    local var_name=$1
    local value

    value=$(gh variable list --repo "${REPO_OWNER}/${REPO_NAME}" --json name,value --jq ".[] | select(.name == \"${var_name}\") | .value" 2>/dev/null || echo "")

    if [ -z "$value" ]; then
        return 1
    fi

    echo "$value"
}

# Function to retrieve secret from AWS Secrets Manager
get_aws_secret() {
    local secret_name=$1
    local secret_json
    local exit_code

    # Retrieve secret from AWS Secrets Manager
    secret_json=$(aws secretsmanager get-secret-value \
        --secret-id "$secret_name" \
        --query SecretString \
        --output text 2>&1)

    # Capture exit code before checking
    exit_code=$?

    # Validate secret retrieval
    if [ $exit_code -ne 0 ]; then
        print_error "Failed to retrieve secret '${secret_name}' from AWS Secrets Manager"
        print_error "Error: $secret_json"
        return 1
    fi

    # Validate JSON can be parsed
    if ! echo "$secret_json" | jq empty 2>/dev/null; then
        print_error "Secret '${secret_name}' contains invalid JSON"
        return 1
    fi

    echo "$secret_json"
}

# Function to get key value from secret JSON
get_secret_key_value() {
    local secret_json=$1
    local key_name=$2
    local value

    # Validate JSON can be parsed
    if ! echo "$secret_json" | jq empty 2>/dev/null; then
        print_error "Invalid JSON provided to get_secret_key_value"
        return 1
    fi

    # Extract key value using jq
    value=$(echo "$secret_json" | jq -r ".[\"${key_name}\"]" 2>/dev/null)

    # Check if jq command succeeded
    if [ $? -ne 0 ]; then
        print_error "Failed to parse JSON or extract key '${key_name}'"
        return 1
    fi

    # Check if key exists (jq returns "null" for non-existent keys)
    if [ "$value" = "null" ] || [ -z "$value" ]; then
        print_error "Key '${key_name}' not found in secret JSON or value is empty"
        return 1
    fi

    echo "$value"
}

# Retrieve ROLE_ARN from AWS Secrets Manager
print_info "Retrieving AWS_STATE_ACCOUNT_ROLE_ARN from AWS Secrets Manager..."
SECRET_JSON=$(get_aws_secret "github-role" || echo "")
if [ -z "$SECRET_JSON" ]; then
    print_error "Failed to retrieve secret from AWS Secrets Manager"
    exit 1
fi

ROLE_ARN=$(get_secret_key_value "$SECRET_JSON" "AWS_STATE_ACCOUNT_ROLE_ARN" || echo "")
if [ -z "$ROLE_ARN" ]; then
    print_error "Failed to retrieve AWS_STATE_ACCOUNT_ROLE_ARN from secret"
    exit 1
fi
print_success "Retrieved AWS_STATE_ACCOUNT_ROLE_ARN"

# Retrieve REGION from repository variable
print_info "Retrieving AWS_REGION from repository variables..."
REGION=$(get_repo_variable "AWS_REGION" || echo "")
if [ -z "$REGION" ]; then
    print_info "AWS_REGION not found in repository variables, defaulting to 'us-east-1'"
    REGION="us-east-1"
else
    print_success "Retrieved AWS_REGION: $REGION"
fi

print_info "Assuming role: $ROLE_ARN"
print_info "Region: $REGION"

# Assume the role first
ROLE_SESSION_NAME="get-state-$(date +%s)"

# Assume role and capture output
ASSUME_ROLE_OUTPUT=$(aws sts assume-role \
    --role-arn "$ROLE_ARN" \
    --role-session-name "$ROLE_SESSION_NAME" \
    --region "$REGION" 2>&1)

if [ $? -ne 0 ]; then
    print_error "Failed to assume role: $ASSUME_ROLE_OUTPUT"
    exit 1
fi

# Extract credentials from JSON output
# Try using jq if available (more reliable), otherwise use sed/grep
if command -v jq &> /dev/null; then
    export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')
else
    # Fallback: use sed for JSON parsing (works on both macOS and Linux)
    export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | sed -n 's/.*"AccessKeyId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | sed -n 's/.*"SecretAccessKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | sed -n 's/.*"SessionToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_SESSION_TOKEN" ]; then
    print_error "Failed to extract credentials from assume-role output."
    print_error "Output was: $ASSUME_ROLE_OUTPUT"
    exit 1
fi

print_success "Successfully assumed role"

# Verify the credentials work
CALLER_ARN=$(aws sts get-caller-identity --region "$REGION" --query 'Arn' --output text 2>&1)
if [ $? -ne 0 ]; then
    print_error "Failed to verify assumed role credentials: $CALLER_ARN"
    exit 1
fi

print_info "Assumed role identity: $CALLER_ARN"

# Retrieve repository variables
print_info "Retrieving repository variables from GitHub..."

BUCKET_NAME=$(get_repo_variable "BACKEND_BUCKET_NAME" || echo "")
if [ -z "$BUCKET_NAME" ]; then
    print_info "BACKEND_BUCKET_NAME not found in repository variables."
    print_info "This means the infrastructure has not been provisioned yet."
    print_info "There is no existing state file to download."
    print_success "Script completed successfully (no state file exists)"
    exit 0
fi
print_success "Retrieved BACKEND_BUCKET_NAME: $BUCKET_NAME"

BACKEND_PREFIX=$(get_repo_variable "BACKEND_PREFIX" || echo "")
if [ -z "$BACKEND_PREFIX" ]; then
    print_error "BACKEND_PREFIX not found in repository variables."
    echo "Please ensure BACKEND_PREFIX is set in GitHub repository variables."
    exit 1
fi
print_success "Retrieved BACKEND_PREFIX: $BACKEND_PREFIX"

# Check if state file exists in S3
S3_PATH="s3://${BUCKET_NAME}/${BACKEND_PREFIX}"
print_info "Checking for state file at: $S3_PATH"

# Use aws s3 ls to check if the file exists
# This command will return 0 if the file exists, non-zero if it doesn't
if aws s3 ls "$S3_PATH" --region "$REGION" &>/dev/null; then
    print_success "State file exists, downloading..."

    # Download the state file
    if aws s3 cp "$S3_PATH" terraform.tfstate --region "$REGION"; then
        print_success "State file downloaded successfully to terraform.tfstate"
    else
        print_error "Failed to download state file"
        exit 1
    fi
else
    print_info "State file does not exist at $S3_PATH"
    print_info "This is expected if this is the first time provisioning the infrastructure."
    # Don't exit with error - just inform the user
fi

print_success "Script completed successfully"
