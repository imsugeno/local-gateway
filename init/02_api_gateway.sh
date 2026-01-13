#!/bin/sh
set -eu

ENDPOINT="http://localstack:4566"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
FUNCTION_NAME="authz-go"
API_NAME="local-gateway-api"
STAGE_NAME="test"
RESOURCE_PATH="/test"
HTTP_METHOD="GET"

echo "[apigateway] waiting for Lambda function to be ready..."
sleep 2

# Lambda関数のARNを取得
FUNCTION_ARN=$(aws lambda get-function \
  --function-name "$FUNCTION_NAME" \
  --endpoint-url="$ENDPOINT" \
  --query 'Configuration.FunctionArn' \
  --output text 2>/dev/null)

if [ -z "$FUNCTION_ARN" ]; then
  echo "[apigateway] ERROR: Lambda function '$FUNCTION_NAME' not found"
  exit 1
fi

echo "[apigateway] Lambda function ARN: $FUNCTION_ARN"

# REST APIの作成または取得
echo "[apigateway] creating/getting REST API: $API_NAME"
API_ID=$(aws apigateway create-rest-api \
  --name "$API_NAME" \
  --endpoint-url="$ENDPOINT" \
  --query 'id' \
  --output text 2>/dev/null || \
  aws apigateway get-rest-apis \
    --endpoint-url="$ENDPOINT" \
    --query "items[?name=='${API_NAME}'].id" \
    --output text | head -n1)

if [ -z "$API_ID" ]; then
  echo "[apigateway] ERROR: Failed to create or get REST API"
  exit 1
fi

echo "[apigateway] API ID: $API_ID"

# ルートリソースIDを取得
ROOT_RESOURCE_ID=$(aws apigateway get-resources \
  --rest-api-id "$API_ID" \
  --endpoint-url="$ENDPOINT" \
  --query "items[?path=='/'].id" \
  --output text)

echo "[apigateway] root resource ID: $ROOT_RESOURCE_ID"

# リソースの作成または取得
echo "[apigateway] creating/getting resource: $RESOURCE_PATH"
RESOURCE_ID=$(aws apigateway create-resource \
  --rest-api-id "$API_ID" \
  --parent-id "$ROOT_RESOURCE_ID" \
  --path-part "$(echo $RESOURCE_PATH | sed 's|^/||')" \
  --endpoint-url="$ENDPOINT" \
  --query 'id' \
  --output text 2>/dev/null || \
  aws apigateway get-resources \
    --rest-api-id "$API_ID" \
    --endpoint-url="$ENDPOINT" \
    --query "items[?path=='${RESOURCE_PATH}'].id" \
    --output text | head -n1)

if [ -z "$RESOURCE_ID" ]; then
  echo "[apigateway] ERROR: Failed to create or get resource"
  exit 1
fi

echo "[apigateway] resource ID: $RESOURCE_ID"

# Authorizerの作成または取得
echo "[apigateway] creating/getting authorizer"
# LocalStack用のauthorizer URI形式
AUTHORIZER_URI="arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${FUNCTION_ARN}/invocations"
AUTHORIZER_ID=$(aws apigateway create-authorizer \
  --rest-api-id "$API_ID" \
  --name "token-authorizer" \
  --type TOKEN \
  --authorizer-uri "$AUTHORIZER_URI" \
  --identity-source "method.request.header.Authorization" \
  --authorizer-result-ttl-in-seconds 300 \
  --endpoint-url="$ENDPOINT" \
  --query 'id' \
  --output text 2>/dev/null || \
  aws apigateway get-authorizers \
    --rest-api-id "$API_ID" \
    --endpoint-url="$ENDPOINT" \
    --query "items[?name=='token-authorizer'].id" \
    --output text | head -n1)

if [ -z "$AUTHORIZER_ID" ]; then
  echo "[apigateway] ERROR: Failed to create or get authorizer"
  exit 1
fi

echo "[apigateway] authorizer ID: $AUTHORIZER_ID"

# Lambda関数にAPI Gatewayからの呼び出し権限を付与
echo "[apigateway] granting invoke permission to Lambda"
aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id "apigateway-invoke-$(date +%s)" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:000000000000:${API_ID}/*/*" \
  --endpoint-url="$ENDPOINT" 2>/dev/null || echo "[apigateway] permission may already exist"

# メソッドの作成または更新
echo "[apigateway] creating/updating method: $HTTP_METHOD"
aws apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method "$HTTP_METHOD" \
  --authorization-type CUSTOM \
  --authorizer-id "$AUTHORIZER_ID" \
  --endpoint-url="$ENDPOINT" >/dev/null 2>/dev/null || \
aws apigateway update-method \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method "$HTTP_METHOD" \
  --patch-ops "op=replace,path=/authorizationType,value=CUSTOM" "op=replace,path=/authorizerId,value=${AUTHORIZER_ID}" \
  --endpoint-url="$ENDPOINT" >/dev/null

# MOCK統合の設定
echo "[apigateway] setting up MOCK integration"
aws apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method "$HTTP_METHOD" \
  --type MOCK \
  --request-templates '{"application/json":"{\"statusCode\": 200}"}' \
  --endpoint-url="$ENDPOINT" >/dev/null

# 統合レスポンスの設定
echo "[apigateway] setting up integration response"
aws apigateway put-integration-response \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method "$HTTP_METHOD" \
  --status-code 200 \
  --response-templates '{"application/json":"{\"message\": \"Authorized successfully\", \"statusCode\": 200}"}' \
  --endpoint-url="$ENDPOINT" >/dev/null

# メソッドレスポンスの設定
echo "[apigateway] setting up method response"
aws apigateway put-method-response \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method "$HTTP_METHOD" \
  --status-code 200 \
  --response-models '{"application/json":"Empty"}' \
  --endpoint-url="$ENDPOINT" >/dev/null 2>/dev/null || echo "[apigateway] method response may already exist"

# APIのデプロイ
echo "[apigateway] deploying API to stage: $STAGE_NAME"
aws apigateway create-deployment \
  --rest-api-id "$API_ID" \
  --stage-name "$STAGE_NAME" \
  --endpoint-url="$ENDPOINT" >/dev/null

# API GatewayのURLを表示
# LocalStackのAPI Gatewayエンドポイント形式
# 形式1: http://localhost:4566/restapis/{api-id}/{stage}/{resource-path}
# 形式2: http://{api-id}.execute-api.localhost.localstack.cloud:4566/{stage}/{resource-path}
API_URL="http://localhost:4566/restapis/${API_ID}/${STAGE_NAME}${RESOURCE_PATH}"
echo "[apigateway] API URL: $API_URL"
echo "[apigateway] Alternative URL: http://${API_ID}.execute-api.localhost.localstack.cloud:4566/${STAGE_NAME}${RESOURCE_PATH}"
echo "[apigateway] Test with: curl -H 'Authorization: Bearer allow' $API_URL"

echo "[apigateway] done"

