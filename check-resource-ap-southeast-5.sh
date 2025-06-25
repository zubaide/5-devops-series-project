#!/bin/bash
# Check existing AWS resources for CI/CD Pipeline

# Configuration variables (must match aws_setup.sh)
CLUSTER_NAME="webapp-cicd-cluster"
SERVICE_NAME="webapp-cicd-service"
TASK_FAMILY="webapp-cicd-task"
ECR_REPOSITORY="my-webapp"
AWS_REGION="ap-southeast-5"
GITHUB_USER_NAME="github-actions-user"
EXECUTION_ROLE_NAME="ecsTaskExecutionRole-$CLUSTER_NAME"
SECURITY_GROUP_NAME="webapp-cicd-sg"
LOG_GROUP_NAME="/ecs/$TASK_FAMILY"

echo "=========================================="
echo "🔍 CHECKING AWS RESOURCES STATUS"
echo "=========================================="
echo "Region: $AWS_REGION"
echo ""

# Check AWS CLI
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "❌ AWS CLI not configured. Please run 'aws configure' first."
    exit 1
fi

RESOURCES_FOUND=0

# Check ECS Cluster
echo "🏗️ ECS Cluster ($CLUSTER_NAME):"
if aws ecs describe-clusters --clusters $CLUSTER_NAME --region $AWS_REGION --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
    echo "   ✅ EXISTS"
    RESOURCES_FOUND=$((RESOURCES_FOUND + 1))
else
    echo "   ❌ NOT FOUND"
fi

# Check ECS Service
echo "🚀 ECS Service ($SERVICE_NAME):"
if aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION --query 'services[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
    echo "   ✅ EXISTS"
    RESOURCES_FOUND=$((RESOURCES_FOUND + 1))
else
    echo "   ❌ NOT FOUND"
fi

# Check Task Definitions
echo "📋 Task Definitions ($TASK_FAMILY):"
TASK_COUNT=$(aws ecs list-task-definitions --family-prefix $TASK_FAMILY --region $AWS_REGION --query 'length(taskDefinitionArns)' --output text 2>/dev/null || echo "0")
if [ "$TASK_COUNT" -gt 0 ]; then
    echo "   ✅ EXISTS ($TASK_COUNT definitions)"
    RESOURCES_FOUND=$((RESOURCES_FOUND + 1))
else
    echo "   ❌ NOT FOUND"
fi

# Check ECR Repository
echo "📦 ECR Repository ($ECR_REPOSITORY):"
if aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION >/dev/null 2>&1; then
    IMAGE_COUNT=$(aws ecr list-images --repository-name $ECR_REPOSITORY --region $AWS_REGION --query 'length(imageIds)' --output text 2>/dev/null || echo "0")
    echo "   ✅ EXISTS ($IMAGE_COUNT images)"
    RESOURCES_FOUND=$((RESOURCES_FOUND + 1))
else
    echo "   ❌ NOT FOUND"
fi

# Check Security Group
echo "🛡️ Security Group ($SECURITY_GROUP_NAME):"
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
if [ "$SECURITY_GROUP_ID" != "None" ]; then
    echo "   ✅ EXISTS ($SECURITY_GROUP_ID)"
    RESOURCES_FOUND=$((RESOURCES_FOUND + 1))
else
    echo "   ❌ NOT FOUND"
fi

# Check CloudWatch Log Group
echo "📊 CloudWatch Log Group ($LOG_GROUP_NAME):"
if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --region $AWS_REGION --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
    echo "   ✅ EXISTS"
    RESOURCES_FOUND=$((RESOURCES_FOUND + 1))
else
    echo "   ❌ NOT FOUND"
fi

# Check IAM User
echo "👤 IAM User ($GITHUB_USER_NAME):"
if aws iam get-user --user-name $GITHUB_USER_NAME >/dev/null 2>&1; then
    ACCESS_KEY_COUNT=$(aws iam list-access-keys --user-name $GITHUB_USER_NAME --query 'length(AccessKeyMetadata)' --output text 2>/dev/null || echo "0")
    echo "   ✅ EXISTS ($ACCESS_KEY_COUNT access keys)"
    RESOURCES_FOUND=$((RESOURCES_FOUND + 1))
else
    echo "   ❌ NOT FOUND"
fi

# Check IAM Role
echo "🔐 IAM Role ($EXECUTION_ROLE_NAME):"
if aws iam get-role --role-name $EXECUTION_ROLE_NAME >/dev/null 2>&1; then
    echo "   ✅ EXISTS"
    RESOURCES_FOUND=$((RESOURCES_FOUND + 1))
else
    echo "   ❌ NOT FOUND"
fi

echo ""
echo "=========================================="
echo "📊 SUMMARY"
echo "=========================================="
echo "Total resources found: $RESOURCES_FOUND"
echo ""

if [ "$RESOURCES_FOUND" -eq 0 ]; then
    echo "🎉 All resources have been cleaned up!"
    echo "No further action needed."
else
    echo "⚠️ $RESOURCES_FOUND resources still exist."
    echo "Run './cleanup-aws.sh' to delete remaining resources."
fi

echo "=========================================="
