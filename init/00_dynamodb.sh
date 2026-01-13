#!/bin/sh
set -eu

ENDPOINT="http://localstack:4566"
TABLE="AllowedTokens"

echo "[init] waiting a bit..."
sleep 1

echo "[init] create dynamodb table (if not exists): $TABLE"

# 既にあれば何もしない
if aws dynamodb describe-table --table-name "$TABLE" --endpoint-url="$ENDPOINT" >/dev/null 2>&1; then
  echo "[init] table already exists: $TABLE"
else
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=token,AttributeType=S \
    --key-schema AttributeName=token,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --endpoint-url="$ENDPOINT"

  echo "[init] waiting for table active..."
  aws dynamodb wait table-exists --table-name "$TABLE" --endpoint-url="$ENDPOINT"
fi

echo "[init] seed allow token"
aws dynamodb put-item \
  --table-name "$TABLE" \
  --item '{"token":{"S":"allow"}}' \
  --endpoint-url="$ENDPOINT" >/dev/null

echo "[init] list tables"
aws dynamodb list-tables --endpoint-url="$ENDPOINT"

echo "[init] done"
