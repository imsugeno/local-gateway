#!/bin/sh
set -eu

ENDPOINT="http://localstack:4566"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
FUNCTION_NAME="authz-go"
ROLE_NAME="lambda-authorizer-role"
POLICY_NAME="lambda-authorizer-policy"
TABLE_NAME="${ALLOWED_TOKENS_TABLE:-AllowedTokens}"

echo "[lambda] waiting for LocalStack to be ready..."
sleep 2

# IAM Roleの作成
echo "[lambda] creating IAM role: $ROLE_NAME"
ROLE_ARN=$(aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' \
  --endpoint-url="$ENDPOINT" \
  --query 'Role.Arn' \
  --output text 2>/dev/null || \
  aws iam get-role \
    --role-name "$ROLE_NAME" \
    --endpoint-url="$ENDPOINT" \
    --query 'Role.Arn' \
    --output text)

echo "[lambda] role ARN: $ROLE_ARN"

# IAM Policyの作成
echo "[lambda] creating IAM policy: $POLICY_NAME"
POLICY_ARN=$(aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [
        \"dynamodb:GetItem\",
        \"dynamodb:Query\"
      ],
      \"Resource\": \"arn:aws:dynamodb:${REGION}:000000000000:table/${TABLE_NAME}\"
    }]
  }" \
  --endpoint-url="$ENDPOINT" \
  --query 'Policy.Arn' \
  --output text 2>/dev/null || \
  aws iam list-policies \
    --endpoint-url="$ENDPOINT" \
    --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" \
    --output text | head -n1)

echo "[lambda] policy ARN: $POLICY_ARN"

# PolicyをRoleにアタッチ
echo "[lambda] attaching policy to role"
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN" \
  --endpoint-url="$ENDPOINT" 2>/dev/null || echo "[lambda] policy already attached"

# Lambda関数のデプロイ
echo "[lambda] checking if function.zip exists"
ZIP_PATH="/init/../lambda/${FUNCTION_NAME}/function.zip"
if [ ! -f "$ZIP_PATH" ]; then
  echo "[lambda] ERROR: function.zip not found at $ZIP_PATH. Please run 'make build' first."
  exit 1
fi

echo "[lambda] deploying Lambda function: $FUNCTION_NAME"
FUNCTION_EXISTS=$(aws lambda get-function \
  --function-name "$FUNCTION_NAME" \
  --endpoint-url="$ENDPOINT" \
  --query 'Configuration.FunctionName' \
  --output text 2>/dev/null || echo "")

if [ -n "$FUNCTION_EXISTS" ]; then
  echo "[lambda] updating existing function"
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://${ZIP_PATH}" \
    --endpoint-url="$ENDPOINT" >/dev/null

  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --environment "Variables={
      ALLOWED_TOKENS_TABLE=${TABLE_NAME},
      AWS_REGION=${REGION},
      LOCALSTACK_HOSTNAME=localstack
    }" \
    --endpoint-url="$ENDPOINT" >/dev/null
else
  echo "[lambda] creating new function"
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime provided.al2 \
    --role "$ROLE_ARN" \
    --handler bootstrap \
    --zip-file "fileb://${ZIP_PATH}" \
    --timeout 30 \
    --environment "Variables={
      ALLOWED_TOKENS_TABLE=${TABLE_NAME},
      AWS_REGION=${REGION},
      LOCALSTACK_HOSTNAME=localstack
    }" \
    --endpoint-url="$ENDPOINT" >/dev/null
fi

echo "[lambda] waiting for function to be ready..."
sleep 2

echo "[lambda] verifying function"
aws lambda get-function \
  --function-name "$FUNCTION_NAME" \
  --endpoint-url="$ENDPOINT" \
  --query 'Configuration.[FunctionName,Runtime,Role]' \
  --output table

echo "[lambda] done"

