#!/bin/bash

# Terraform backend creation script (repo root layout)
# This script creates S3 bucket and DynamoDB table for Terraform state
# with best practices and security hardening built-in

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <environment> [region]"
    echo ""
    echo "Arguments:"
    echo "  environment    Environment name (qa, dev, prod)"
    echo "  region         AWS region (default: us-east-1)"
    echo ""
    echo "Examples:"
    echo "  $0 dev                    # Create backend for dev in us-east-1 (matches live/dev/us-east-1/root.hcl)"
    echo "  $0 dev us-east-1          # Same as above"
    echo "  $0 qa us-east-1            # Create backend for QA in us-east-1"
    echo ""
    echo "This script will create the following resources:"
    echo "  - S3 bucket: tazakerv3-<env>-terraform-state-<region_short>"
    echo "  - DynamoDB table: tazakerv3-<env>-terraform-<region_short>-locks"
    echo ""
    echo "With built-in security features:"
    echo "  - S3 versioning enabled"
    echo "  - Public access blocked"
    echo "  - Lifecycle rules for cost optimization"
    echo "  - DynamoDB point-in-time recovery"
    echo "  - Protection tags for identification"
}

# Check if environment is provided
if [ $# -lt 1 ]; then
    print_error "Environment argument is required"
    show_usage
    exit 1
fi

ENVIRONMENT=$1
REGION=${2:-us-east-1}

# Convert region to short format
case $REGION in
    us-east-1)
        REGION_SHORT="use1"
        ;;
    us-west-2)
        REGION_SHORT="usw2"
        ;;
    us-west-1)
        REGION_SHORT="usw1"
        ;;
    eu-west-1)
        REGION_SHORT="euw1"
        ;;
    eu-central-1)
        REGION_SHORT="euc1"
        ;;
    ap-southeast-1)
        REGION_SHORT="apse1"
        ;;
    ap-northeast-1)
        REGION_SHORT="apne1"
        ;;
    *)
        print_warning "Unknown region: $REGION, using as-is for region_short"
        REGION_SHORT=$(echo $REGION | sed 's/-//g')
        ;;
esac

# Set resource names (match live/dev/us-east-1/root.hcl defaults for dev + us-east-1)
BUCKET_NAME="tazakerv3-${ENVIRONMENT}-terraform-state-${REGION_SHORT}"
TABLE_NAME="tazakerv3-${ENVIRONMENT}-terraform-${REGION_SHORT}-locks"

print_status "Creating Terraform backend for environment: $ENVIRONMENT"
print_status "Region: $REGION ($REGION_SHORT)"
print_status "S3 Bucket: $BUCKET_NAME"
print_status "DynamoDB Table: $TABLE_NAME"
echo ""

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed or not in PATH"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured or invalid"
    exit 1
fi

print_success "AWS CLI is configured and working"
echo ""

# Function to check if S3 bucket exists
check_s3_bucket() {
    if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$REGION" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to check if DynamoDB table exists
check_dynamodb_table() {
    if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Create S3 Bucket with best practices
create_s3_bucket() {
    print_status "Creating S3 bucket: $BUCKET_NAME"
    
    if check_s3_bucket; then
        print_warning "S3 bucket $BUCKET_NAME already exists, skipping creation"
        return 0
    fi
    
    # Create bucket (retry on OperationAborted - conflicting create in progress)
    create_bucket_ok=false
    max_attempts=5
    retry_seconds=15
    for attempt in $(seq 1 $max_attempts); do
        if [ "$REGION" = "us-east-1" ]; then
            if aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"; then
                create_bucket_ok=true
                break
            fi
        else
            if aws s3api create-bucket \
                --bucket "$BUCKET_NAME" \
                --region "$REGION" \
                --create-bucket-configuration LocationConstraint="$REGION"; then
                create_bucket_ok=true
                break
            fi
        fi
        if check_s3_bucket; then
            create_bucket_ok=true
            break
        fi
        if [ "$attempt" -lt "$max_attempts" ]; then
            print_warning "CreateBucket failed or conflict in progress, retrying in ${retry_seconds}s... (attempt $attempt/$max_attempts)"
            sleep $retry_seconds
        fi
    done
    if ! $create_bucket_ok && ! check_s3_bucket; then
        print_error "Failed to create S3 bucket $BUCKET_NAME. Try again in a minute."
        return 1
    fi
    print_success "S3 bucket created"
    
    # Enable versioning
    print_status "Enabling versioning..."
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --versioning-configuration Status=Enabled
    print_success "Versioning enabled"
    
    # Block public access
    print_status "Blocking public access..."
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    print_success "Public access blocked"
    
    # Add lifecycle rule for non-current versions
    print_status "Adding lifecycle rule for cost optimization..."
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --lifecycle-configuration '{
            "Rules": [
                {
                    "ID": "terraform-state-lifecycle",
                    "Status": "Enabled",
                    "Filter": {
                        "Prefix": ""
                    },
                    "NoncurrentVersionExpiration": {
                        "NoncurrentDays": 30
                    },
                    "AbortIncompleteMultipartUpload": {
                        "DaysAfterInitiation": 7
                    }
                }
            ]
        }'
    print_success "Lifecycle rule added"
    
    # Add tags
    print_status "Adding protection tags..."
    aws s3api put-bucket-tagging \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --tagging '{
            "TagSet": [
                {"Key": "Terraform", "Value": "true"},
                {"Key": "Environment", "Value": "'$ENVIRONMENT'"},
                {"Key": "Project", "Value": "tazaker"},
                {"Key": "DeletionProtection", "Value": "enabled"},
                {"Key": "BackupRequired", "Value": "true"},
                {"Key": "Critical", "Value": "true"},
                {"Key": "CreatedBy", "Value": "terraform"},
                {"Key": "CreatedDate", "Value": "'$(date -u +%Y-%m-%d)'"}
            ]
        }'
    print_success "Protection tags added"
    
    print_success "S3 bucket creation completed"
}

# Create DynamoDB Table with best practices
create_dynamodb_table() {
    print_status "Creating DynamoDB table: $TABLE_NAME"
    
    if check_dynamodb_table; then
        print_warning "DynamoDB table $TABLE_NAME already exists, skipping creation"
        return 0
    fi
    
    # Create table
    aws dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$REGION" \
        --tags \
        Key=Terraform,Value=true \
        Key=Environment,Value="$ENVIRONMENT" \
        Key=Project,Value=tazaker \
        Key=DeletionProtection,Value=enabled \
        Key=BackupRequired,Value=true \
        Key=Critical,Value=true \
        Key=CreatedBy,Value=terraform \
        Key=CreatedDate,Value="$(date -u +%Y-%m-%d)"
    
    print_success "DynamoDB table created"
    
    # Wait for table to be active
    print_status "Waiting for table to become active..."
    aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$REGION"
    print_success "Table is now active"
    
    # Enable point-in-time recovery
    print_status "Enabling point-in-time recovery..."
    aws dynamodb update-continuous-backups \
        --table-name "$TABLE_NAME" \
        --region "$REGION" \
        --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true
    print_success "Point-in-time recovery enabled"
    
    # Enable deletion protection
    print_status "Enabling deletion protection..."
    aws dynamodb update-table \
        --table-name "$TABLE_NAME" \
        --region "$REGION" \
        --deletion-protection-enabled
    print_success "Deletion protection enabled"
    
    print_success "DynamoDB table creation completed"
}

# Main execution
main() {
    print_status "Starting Terraform backend creation process..."
    echo ""
    
    # Create S3 bucket
    if create_s3_bucket; then
        echo ""
    else
        print_error "Failed to create S3 bucket"
        exit 1
    fi
    
    # Create DynamoDB table
    if create_dynamodb_table; then
        echo ""
    else
        print_error "Failed to create DynamoDB table"
        exit 1
    fi
    
    print_success "Terraform backend creation completed successfully!"
    echo ""
    print_status "Summary of created resources:"
    echo "  ✅ S3 bucket: $BUCKET_NAME"
    echo "  ✅ DynamoDB table: $TABLE_NAME"
    echo ""
    print_status "Security features applied:"
    echo "  ✅ S3 versioning enabled"
    echo "  ✅ Public access blocked"
    echo "  ✅ Lifecycle rule for cost optimization (30 days)"
    echo "  ✅ DynamoDB point-in-time recovery enabled"
    echo "  ✅ DynamoDB deletion protection enabled"
    echo "  ✅ Protection tags added to both resources"
    echo ""
    print_status "Next steps:"
    echo "  1. cd live/dev/us-east-1 && terragrunt run init --all --reconfigure"
    echo "  2. terragrunt run apply --all --non-interactive -- -auto-approve -input=false"
    echo ""
    print_warning "Note: These are identification tags, not true deletion protection."
    print_warning "For true deletion protection, consider using AWS Organizations SCPs."
    print_warning "To delete the backend later: disable DynamoDB deletion protection, then empty S3 and delete both resources (e.g. via AWS Console or CLI)."
}

# Run main function
main
