#!/bin/bash
# AWS Infrastructure Cleanup for CI/CD Pipeline
# Combined: Check resources first, then delete what exists

set -e  # Exit on any error

# Configuration variables (must match aws_setup.sh)
CLUSTER_NAME="webapp-cicd-cluster"
SERVICE_NAME="webapp-cicd-service"
TASK_FAMILY="webapp-cicd-task"
ECR_REPOSITORY="my-webapp"
AWS_REGION="us-east-1"
GITHUB_USER_NAME="github-actions-user"
EXECUTION_ROLE_NAME="ecsTaskExecutionRole-$CLUSTER_NAME"
SECURITY_GROUP_NAME="webapp-cicd-sg"
LOG_GROUP_NAME="/ecs/$TASK_FAMILY"

echo "=========================================="
echo "🔍 CHECKING & CLEANING AWS INFRASTRUCTURE"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "ECR Repository: $ECR_REPOSITORY"
echo "Region: $AWS_REGION"
echo ""

# Check if AWS CLI is configured
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "❌ AWS CLI not configured. Please run 'aws configure' first."
    exit 1
fi

echo "✅ AWS CLI configured"
echo ""

# Arrays to track what exists
declare -a RESOURCES_TO_DELETE=()
declare -a DELETION_SUMMARY=()

echo "=========================================="
echo "📋 PHASE 1: RESOURCE DISCOVERY"
echo "=========================================="

# Check ECS Service
echo "🚀 Checking ECS Service ($SERVICE_NAME):"
if aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION --query 'services[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
    echo "   ✅ EXISTS - Will be deleted"
    RESOURCES_TO_DELETE+=("ECS_SERVICE")
else
    echo "   ❌ NOT FOUND"
fi

# Check ECS Cluster
echo "🏗️ Checking ECS Cluster ($CLUSTER_NAME):"
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters $CLUSTER_NAME --region $AWS_REGION --query 'clusters[0].status' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
    echo "   ✅ EXISTS - Will be deleted"
    RESOURCES_TO_DELETE+=("ECS_CLUSTER")
else
    echo "   ❌ NOT FOUND"
fi

# Check Task Definitions
echo "📋 Checking Task Definitions ($TASK_FAMILY):"
TASK_ARNS=$(aws ecs list-task-definitions --family-prefix $TASK_FAMILY --region $AWS_REGION --query 'taskDefinitionArns' --output text 2>/dev/null || echo "")
if [ -n "$TASK_ARNS" ]; then
    TASK_COUNT=$(echo $TASK_ARNS | wc -w)
    echo "   ✅ EXISTS ($TASK_COUNT definitions) - Will be deregistered"
    RESOURCES_TO_DELETE+=("TASK_DEFINITIONS")
else
    echo "   ❌ NOT FOUND"
fi

# Check ECR Repository
echo "📦 Checking ECR Repository ($ECR_REPOSITORY):"
if aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION >/dev/null 2>&1; then
    IMAGE_COUNT=$(aws ecr list-images --repository-name $ECR_REPOSITORY --region $AWS_REGION --query 'length(imageIds)' --output text 2>/dev/null || echo "0")
    echo "   ✅ EXISTS ($IMAGE_COUNT images) - Will be deleted"
    RESOURCES_TO_DELETE+=("ECR_REPOSITORY")
else
    echo "   ❌ NOT FOUND"
fi

# Check Security Group
echo "🛡️ Checking Security Group ($SECURITY_GROUP_NAME):"
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
if [ "$SECURITY_GROUP_ID" != "None" ]; then
    echo "   ✅ EXISTS ($SECURITY_GROUP_ID) - Will be deleted"
    RESOURCES_TO_DELETE+=("SECURITY_GROUP")
else
    echo "   ❌ NOT FOUND"
fi

# Check CloudWatch Log Group
echo "📊 Checking CloudWatch Log Group ($LOG_GROUP_NAME):"
if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --region $AWS_REGION --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
    echo "   ✅ EXISTS - Will be deleted"
    RESOURCES_TO_DELETE+=("LOG_GROUP")
else
    echo "   ❌ NOT FOUND"
fi

# Check IAM User
echo "👤 Checking IAM User ($GITHUB_USER_NAME):"
if aws iam get-user --user-name $GITHUB_USER_NAME >/dev/null 2>&1; then
    ACCESS_KEY_COUNT=$(aws iam list-access-keys --user-name $GITHUB_USER_NAME --query 'length(AccessKeyMetadata)' --output text 2>/dev/null || echo "0")
    echo "   ✅ EXISTS ($ACCESS_KEY_COUNT access keys) - Will be deleted"
    RESOURCES_TO_DELETE+=("IAM_USER")
else
    echo "   ❌ NOT FOUND"
fi

# Check IAM Role
echo "🔐 Checking IAM Role ($EXECUTION_ROLE_NAME):"
if aws iam get-role --role-name $EXECUTION_ROLE_NAME >/dev/null 2>&1; then
    echo "   ✅ EXISTS - Will be deleted"
    RESOURCES_TO_DELETE+=("IAM_ROLE")
else
    echo "   ❌ NOT FOUND"
fi

echo ""
echo "=========================================="
echo "📊 DISCOVERY SUMMARY"
echo "=========================================="
echo "Resources found for deletion: ${#RESOURCES_TO_DELETE[@]}"

if [ ${#RESOURCES_TO_DELETE[@]} -eq 0 ]; then
    echo ""
    echo "🎉 No resources found to delete!"
    echo "All resources have already been cleaned up."
    echo "=========================================="
    exit 0
fi

echo "Resources to be deleted:"
for resource in "${RESOURCES_TO_DELETE[@]}"; do
    echo "   • $resource"
done

echo ""
read -p "Do you want to proceed with deletion? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deletion cancelled by user."
    exit 0
fi

echo ""
echo "=========================================="
echo "🗑️ PHASE 2: RESOURCE DELETION"
echo "=========================================="

# Delete ECS Service
if [[ " ${RESOURCES_TO_DELETE[@]} " =~ " ECS_SERVICE " ]]; then
    echo "🛑 Deleting ECS Service..."
    echo "   📉 Scaling service to 0 tasks..."
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --desired-count 0 \
        --region $AWS_REGION >/dev/null
    
    echo "   ⏳ Waiting for service to scale down..."
    aws ecs wait services-stable \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $AWS_REGION
    
    echo "   🗑️ Deleting service..."
    aws ecs delete-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --region $AWS_REGION >/dev/null
    
    echo "   ⏳ Waiting for service deletion..."
    aws ecs wait services-inactive \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $AWS_REGION
    
    echo "   ✅ ECS Service deleted"
    DELETION_SUMMARY+=("✅ ECS Service: $SERVICE_NAME")
fi

# Deregister Task Definitions
if [[ " ${RESOURCES_TO_DELETE[@]} " =~ " TASK_DEFINITIONS " ]]; then
    echo "📋 Deregistering Task Definitions..."
    for TASK_ARN in $TASK_ARNS; do
        echo "   🗑️ Deregistering: $(basename $TASK_ARN)"
        aws ecs deregister-task-definition \
            --task-definition $TASK_ARN \
            --region $AWS_REGION >/dev/null
    done
    echo "   ✅ All task definitions deregistered"
    DELETION_SUMMARY+=("✅ Task Definitions: $TASK_FAMILY ($(echo $TASK_ARNS | wc -w) definitions)")
fi

# Delete ECS Cluster
if [[ " ${RESOURCES_TO_DELETE[@]} " =~ " ECS_CLUSTER " ]]; then
    echo "🏗️ Deleting ECS Cluster..."
    aws ecs delete-cluster --cluster $CLUSTER_NAME --region $AWS_REGION >/dev/null
    echo "   ✅ ECS Cluster deleted"
    DELETION_SUMMARY+=("✅ ECS Cluster: $CLUSTER_NAME")
fi

# Delete ECR Repository
if [[ " ${RESOURCES_TO_DELETE[@]} " =~ " ECR_REPOSITORY " ]]; then
    echo "📦 Deleting ECR Repository..."
    echo "   🗑️ Deleting all images..."
    
    # Get all image digests and delete them
    IMAGE_DIGESTS=$(aws ecr list-images \
        --repository-name $ECR_REPOSITORY \
        --region $AWS_REGION \
        --query 'imageIds[*].imageDigest' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$IMAGE_DIGESTS" ]; then
        aws ecr batch-delete-image \
            --repository-name $ECR_REPOSITORY \
            --image-ids imageDigest=$IMAGE_DIGESTS \
            --region $AWS_REGION >/dev/null 2>/dev/null || true
    fi
    
    echo "   🗑️ Deleting repository..."
    aws ecr delete-repository \
        --repository-name $ECR_REPOSITORY \
        --region $AWS_REGION \
        --force >/dev/null
    echo "   ✅ ECR Repository deleted"
    DELETION_SUMMARY+=("✅ ECR Repository: $ECR_REPOSITORY")
fi

# Delete Security Group
if [[ " ${RESOURCES_TO_DELETE[@]} " =~ " SECURITY_GROUP " ]]; then
    echo "🛡️ Deleting Security Group..."
    aws ec2 delete-security-group --group-id $SECURITY_GROUP_ID >/dev/null
    echo "   ✅ Security Group deleted"
    DELETION_SUMMARY+=("✅ Security Group: $SECURITY_GROUP_NAME ($SECURITY_GROUP_ID)")
fi

# Delete CloudWatch Log Group
if [[ " ${RESOURCES_TO_DELETE[@]} " =~ " LOG_GROUP " ]]; then
    echo "📊 Deleting CloudWatch Log Group..."
    aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME" --region $AWS_REGION >/dev/null
    echo "   ✅ CloudWatch Log Group deleted"
    DELETION_SUMMARY+=("✅ CloudWatch Log Group: $LOG_GROUP_NAME")
fi

# Delete IAM User
if [[ " ${RESOURCES_TO_DELETE[@]} " =~ " IAM_USER " ]]; then
    echo "👤 Deleting IAM User..."
    
    # Delete access keys
    echo "   🔑 Deleting access keys..."
    ACCESS_KEYS=$(aws iam list-access-keys \
        --user-name $GITHUB_USER_NAME \
        --query 'AccessKeyMetadata[*].AccessKeyId' \
        --output text 2>/dev/null || echo "")
    
    for ACCESS_KEY in $ACCESS_KEYS; do
        if [ -n "$ACCESS_KEY" ]; then
            aws iam delete-access-key \
                --user-name $GITHUB_USER_NAME \
                --access-key-id $ACCESS_KEY >/dev/null
        fi
    done
    
    # Detach policies
    echo "   🔓 Detaching policies..."
    aws iam detach-user-policy \
        --user-name $GITHUB_USER_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess >/dev/null 2>/dev/null || true
    
    aws iam detach-user-policy \
        --user-name $GITHUB_USER_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess >/dev/null 2>/dev/null || true
    
    # Delete user
    echo "   🗑️ Deleting user..."
    aws iam delete-user --user-name $GITHUB_USER_NAME >/dev/null
    echo "   ✅ IAM User deleted"
    DELETION_SUMMARY+=("✅ IAM User: $GITHUB_USER_NAME")
fi

# Delete IAM Role
if [[ " ${RESOURCES_TO_DELETE[@]} " =~ " IAM_ROLE " ]]; then
    echo "🔐 Deleting IAM Role..."
    
    # Detach policy
    echo "   🔓 Detaching policies..."
    aws iam detach-role-policy \
        --role-name $EXECUTION_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy >/dev/null 2>/dev/null || true
    
    # Delete role
    echo "   🗑️ Deleting role..."
    aws iam delete-role --role-name $EXECUTION_ROLE_NAME >/dev/null
    echo "   ✅ IAM Role deleted"
    DELETION_SUMMARY+=("✅ IAM Role: $EXECUTION_ROLE_NAME")
fi

echo ""
echo "=========================================="
echo "🎉 CLEANUP COMPLETE!"
echo "=========================================="
echo ""
echo "📋 Successfully deleted resources:"
for summary in "${DELETION_SUMMARY[@]}"; do
    echo "   $summary"
done

echo ""
echo "💡 Don't forget to:"
echo "   • Remove GitHub repository secrets"
echo "   • Clean up any local Docker images"
echo "   • Review AWS billing for any remaining charges"
echo ""
echo "=========================================="
