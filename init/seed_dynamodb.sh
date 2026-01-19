#!/bin/sh
# DynamoDB シードデータ投入スクリプト
#
# このスクリプトは DynamoDB テーブルに初期データを投入します。
# Terraform でテーブル作成後に実行してください。
#
# 投入データ:
#   - token: "allow" (Lambda Authorizer で使用される許可トークン)
#
# 注意: 既存のデータがある場合は上書きされます。
set -eu

ENDPOINT="$AWS_ENDPOINT_URL"
TABLE="AllowedTokens"
MAX_RETRIES=30
RETRY_INTERVAL=2

# テーブルが利用可能になるまで待機
echo "[seed] waiting for $TABLE table to be available..."
retry_count=0
while [ $retry_count -lt $MAX_RETRIES ]; do
  if aws dynamodb describe-table \
    --table-name "$TABLE" \
    --endpoint-url="$ENDPOINT" > /dev/null 2>&1; then
    echo "[seed] table $TABLE is available"
    break
  fi
  retry_count=$((retry_count + 1))
  echo "[seed] waiting for table... (attempt $retry_count/$MAX_RETRIES)"
  sleep $RETRY_INTERVAL
done

if [ $retry_count -eq $MAX_RETRIES ]; then
  echo "[seed] ERROR: table $TABLE not available after $MAX_RETRIES attempts"
  exit 1
fi

echo "[seed] inserting allow token into $TABLE"
aws dynamodb put-item \
  --table-name "$TABLE" \
  --item '{"token":{"S":"allow"}}' \
  --endpoint-url="$ENDPOINT"

echo "[seed] verifying data"
aws dynamodb scan \
  --table-name "$TABLE" \
  --endpoint-url="$ENDPOINT"

echo "[seed] done"
