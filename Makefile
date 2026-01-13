LAMBDA_DIR := lambda
GOOS := linux
GOARCH := amd64
CGO_ENABLED := 0

LAMBDAS := $(shell find $(LAMBDA_DIR) -maxdepth 1 -mindepth 1 -type d)

.PHONY: all build clean init-workspace add-lambda deploy test test-api-invoke test-api-from-container test-authorizer clean-all

all: build

# Workspaceの初期化（初回のみ実行）
init-workspace:
	@echo "==> initializing go workspace"
	@if [ ! -f go.work ]; then \
	  go work init; \
	fi
	@for dir in $(LAMBDAS); do \
	  echo "==> adding $$dir to workspace"; \
	  go work use $$dir 2>/dev/null || true; \
	  cd $$dir && \
	    [ -f go.mod ] || go mod init $$(basename $$dir); \
	  cd - >/dev/null ; \
	done
	@go work sync

build:
	@echo "==> syncing workspace"
	@go work sync
	@for dir in $(LAMBDAS); do \
	  echo "==> building $$dir"; \
	  cd $$dir && \
	    go mod tidy && \
	    GOOS=$(GOOS) GOARCH=$(GOARCH) CGO_ENABLED=$(CGO_ENABLED) \
	      go build -o bootstrap main.go && \
	    zip -j function.zip bootstrap && \
	  cd - >/dev/null ; \
	done

clean:
	@find $(LAMBDA_DIR) -name bootstrap -o -name function.zip | xargs rm -f
	@rm -f go.work go.work.sum

# 新しいLambda関数を追加する際のヘルパー
add-lambda:
	@if [ -z "$(LAMBDA_NAME)" ]; then \
	  echo "Usage: make add-lambda LAMBDA_NAME=<name>"; \
	  exit 1; \
	fi
	@mkdir -p $(LAMBDA_DIR)/$(LAMBDA_NAME)
	@go work use ./$(LAMBDA_DIR)/$(LAMBDA_NAME)
	@cd $(LAMBDA_DIR)/$(LAMBDA_NAME) && go mod init $(LAMBDA_NAME)
	@go work sync
	@echo "==> Lambda function $(LAMBDA_NAME) added to workspace"

# Lambda関数とAPI Gatewayのデプロイ（LocalStackが起動している必要がある）
deploy: build
	@echo "==> deploying Lambda function and API Gateway"
	@echo "Checking if containers are running..."
	@if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^gateway-awscli$$"; then \
	  echo "ERROR: awscli container (gateway-awscli) is not running. Run 'docker compose up -d' first."; \
	  exit 1; \
	fi
	@echo "Deploying Lambda function..."
	@docker exec gateway-awscli /bin/sh -c "/init/01_lambda.sh" || \
	 (echo "ERROR: Lambda deployment failed. Check logs with 'docker compose logs awscli'"; exit 1)
	@echo "Deploying API Gateway..."
	@docker exec gateway-awscli /bin/sh -c "/init/02_api_gateway.sh" || \
	 (echo "ERROR: API Gateway deployment failed. Check logs with 'docker compose logs awscli'"; exit 1)
	@echo "==> Deployment completed successfully"

# API Gatewayへのリクエストテスト
test:
	@echo "==> testing API Gateway"
	@echo "Checking if containers are running..."
	@if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^gateway-awscli$$"; then \
	  echo "ERROR: awscli container (gateway-awscli) is not running. Run 'docker compose up -d' first."; \
	  exit 1; \
	fi
	@echo "Getting API ID from LocalStack..."
	@API_ID=$$(docker exec gateway-awscli aws apigateway get-rest-apis \
	  --endpoint-url=http://localstack:4566 \
	  --query "items[?name=='local-gateway-api'].id" \
	  --output text 2>/dev/null | head -n1 || echo ""); \
	if [ -z "$$API_ID" ]; then \
	  echo "ERROR: API Gateway 'local-gateway-api' not found."; \
	  echo "Available APIs:"; \
	  docker exec gateway-awscli aws apigateway get-rest-apis \
	    --endpoint-url=http://localstack:4566 \
	    --query "items[*].[name,id]" \
	    --output table 2>/dev/null || echo "  (Could not list APIs)"; \
	  echo ""; \
	  echo "Try running: make deploy"; \
	  exit 1; \
	fi; \
	# LocalStack 4.xでは、エンドポイント形式が変更されている
	# 形式: http://{api-id}.execute-api.localhost.localstack.cloud:{PORT}/{stage}/{resource-path}
	# ポートは環境変数LOCALSTACK_PORTから取得（デフォルト: 4566）
	# 注意: /restapis/...形式はLocalStack 4.xでは使えません（NoSuchBucketエラー）
	LOCALSTACK_PORT=$${LOCALSTACK_PORT:-4566}; \
	API_URL="http://$$API_ID.execute-api.localhost.localstack.cloud:$$LOCALSTACK_PORT/test/test"; \
	echo "API ID: $$API_ID"; \
	echo "API URL (LocalStack 4.x format): $$API_URL"; \
	echo ""; \
	echo "Test 1: Request without token (should be Deny)"; \
	curl -s -w "\nHTTP Status: %{http_code}\n" -X GET $$API_URL || true; \
	echo ""; \
	echo "Test 2: Request with invalid token (should be Deny)"; \
	curl -s -w "\nHTTP Status: %{http_code}\n" -X GET $$API_URL \
	  -H "Authorization: Bearer invalid-token" || true; \
	echo ""; \
	echo "Test 3: Request with valid token 'allow' (should be Allow)"; \
	curl -s -w "\nHTTP Status: %{http_code}\n" -X GET $$API_URL \
	  -H "Authorization: Bearer allow" || true

# API Gateway経由でテスト（aws apigateway test-invoke-methodを使用、ホスト側から）
test-api-invoke:
	@echo "==> testing API Gateway using test-invoke-method (from host)"
	@echo "Checking if containers are running..."
	@if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^gateway-awscli$$"; then \
	  echo "ERROR: awscli container (gateway-awscli) is not running. Run 'docker compose up -d' first."; \
	  exit 1; \
	fi
	@echo "Getting API ID and Resource ID from LocalStack..."
	@API_ID=$$(docker exec gateway-awscli aws apigateway get-rest-apis \
	  --endpoint-url=http://localstack:4566 \
	  --query "items[?name=='local-gateway-api'].id" \
	  --output text 2>/dev/null | tr '\t' '\n' | head -n1 || echo ""); \
	if [ -z "$$API_ID" ]; then \
	  echo "ERROR: API Gateway 'local-gateway-api' not found. Run 'make deploy' first."; \
	  exit 1; \
	fi; \
	RESOURCE_ID=$$(docker exec gateway-awscli aws apigateway get-resources \
	  --rest-api-id $$API_ID \
	  --endpoint-url=http://localstack:4566 \
	  --query "items[?path=='/test'].id" \
	  --output text 2>/dev/null | tr '\t' '\n' | head -n1 || echo ""); \
	if [ -z "$$RESOURCE_ID" ]; then \
	  echo "ERROR: Resource '/test' not found."; \
	  exit 1; \
	fi; \
	echo "API ID: $$API_ID"; \
	echo "Resource ID: $$RESOURCE_ID"; \
	echo ""; \
	echo "Test 1: Request without token (should be Deny)"; \
	docker exec gateway-awscli aws apigateway test-invoke-method \
	  --rest-api-id $$API_ID \
	  --resource-id $$RESOURCE_ID \
	  --http-method GET \
	  --endpoint-url=http://localstack:4566 \
	  --output json 2>/dev/null | python3 -m json.tool 2>/dev/null || \
	  docker exec gateway-awscli aws apigateway test-invoke-method \
	    --rest-api-id $$API_ID \
	    --resource-id $$RESOURCE_ID \
	    --http-method GET \
	    --endpoint-url=http://localstack:4566 \
	    --output json 2>/dev/null || echo "Test failed"; \
	echo ""; \
	echo "Test 2: Request with invalid token (should be Deny)"; \
	docker exec gateway-awscli aws apigateway test-invoke-method \
	  --rest-api-id $$API_ID \
	  --resource-id $$RESOURCE_ID \
	  --http-method GET \
	  --headers 'Authorization=Bearer invalid-token' \
	  --endpoint-url=http://localstack:4566 \
	  --output json 2>/dev/null | python3 -m json.tool 2>/dev/null || \
	  docker exec gateway-awscli aws apigateway test-invoke-method \
	    --rest-api-id $$API_ID \
	    --resource-id $$RESOURCE_ID \
	    --http-method GET \
	    --headers 'Authorization=Bearer invalid-token' \
	    --endpoint-url=http://localstack:4566 \
	    --output json 2>/dev/null || echo "Test failed"; \
	echo ""; \
	echo "Test 3: Request with valid token 'allow' (should be Allow)"; \
	docker exec gateway-awscli aws apigateway test-invoke-method \
	  --rest-api-id $$API_ID \
	  --resource-id $$RESOURCE_ID \
	  --http-method GET \
	  --headers 'Authorization=Bearer allow' \
	  --endpoint-url=http://localstack:4566 \
	  --output json 2>/dev/null | python3 -m json.tool 2>/dev/null || \
	  docker exec gateway-awscli aws apigateway test-invoke-method \
	    --rest-api-id $$API_ID \
	    --resource-id $$RESOURCE_ID \
	    --http-method GET \
	    --headers 'Authorization=Bearer allow' \
	    --endpoint-url=http://localstack:4566 \
	    --output json 2>/dev/null || echo "Test failed"; \
	echo ""; \
	echo "Checking LocalStack logs for lambda.Invoke entries..."; \
	echo "Recent lambda.Invoke logs:"; \
	docker compose logs localstack 2>/dev/null | grep -i "lambda.Invoke" | tail -5 || echo "  (No lambda.Invoke entries found)"; \
	echo ""; \
	echo "Note: If lambda.Invoke entries are not found, LocalStack may not be calling the Authorizer."; \
	echo "This is a known limitation of LocalStack. The Lambda function itself works correctly (see: make test-authorizer)"

# API Gateway経由でテスト（aws apigateway test-invoke-methodを使用）
test-api-from-container:
	@echo "==> testing API Gateway using test-invoke-method"
	@echo "Checking if containers are running..."
	@if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^gateway-awscli$$"; then \
	  echo "ERROR: awscli container (gateway-awscli) is not running. Run 'docker compose up -d' first."; \
	  exit 1; \
	fi
	@echo "Getting API ID and Resource ID from LocalStack..."
	@API_ID=$$(docker exec gateway-awscli aws apigateway get-rest-apis \
	  --endpoint-url=http://localstack:4566 \
	  --query "items[?name=='local-gateway-api'].id" \
	  --output text 2>/dev/null | tr '\t' '\n' | head -n1 || echo ""); \
	if [ -z "$$API_ID" ]; then \
	  echo "ERROR: API Gateway 'local-gateway-api' not found. Run 'make deploy' first."; \
	  exit 1; \
	fi; \
	RESOURCE_ID=$$(docker exec gateway-awscli aws apigateway get-resources \
	  --rest-api-id $$API_ID \
	  --endpoint-url=http://localstack:4566 \
	  --query "items[?path=='/test'].id" \
	  --output text 2>/dev/null | tr '\t' '\n' | head -n1 || echo ""); \
	if [ -z "$$RESOURCE_ID" ]; then \
	  echo "ERROR: Resource '/test' not found."; \
	  exit 1; \
	fi; \
	echo "API ID: $$API_ID"; \
	echo "Resource ID: $$RESOURCE_ID"; \
	echo ""; \
	echo "Test 1: Request without token (should be Deny)"; \
	docker exec gateway-awscli aws apigateway test-invoke-method \
	  --rest-api-id $$API_ID \
	  --resource-id $$RESOURCE_ID \
	  --http-method GET \
	  --endpoint-url=http://localstack:4566 \
	  --output json 2>/dev/null | python3 -m json.tool 2>/dev/null || \
	  docker exec gateway-awscli aws apigateway test-invoke-method \
	    --rest-api-id $$API_ID \
	    --resource-id $$RESOURCE_ID \
	    --http-method GET \
	    --endpoint-url=http://localstack:4566 \
	    --output json 2>/dev/null || echo "Test failed"; \
	echo ""; \
	echo "Test 2: Request with invalid token (should be Deny)"; \
	docker exec gateway-awscli aws apigateway test-invoke-method \
	  --rest-api-id $$API_ID \
	  --resource-id $$RESOURCE_ID \
	  --http-method GET \
	  --headers 'Authorization=Bearer invalid-token' \
	  --endpoint-url=http://localstack:4566 \
	  --output json 2>/dev/null | python3 -m json.tool 2>/dev/null || \
	  docker exec gateway-awscli aws apigateway test-invoke-method \
	    --rest-api-id $$API_ID \
	    --resource-id $$RESOURCE_ID \
	    --http-method GET \
	    --headers 'Authorization=Bearer invalid-token' \
	    --endpoint-url=http://localstack:4566 \
	    --output json 2>/dev/null || echo "Test failed"; \
	echo ""; \
	echo "Test 3: Request with valid token 'allow' (should be Allow)"; \
	docker exec gateway-awscli aws apigateway test-invoke-method \
	  --rest-api-id $$API_ID \
	  --resource-id $$RESOURCE_ID \
	  --http-method GET \
	  --headers 'Authorization=Bearer allow' \
	  --endpoint-url=http://localstack:4566 \
	  --output json 2>/dev/null | python3 -m json.tool 2>/dev/null || \
	  docker exec gateway-awscli aws apigateway test-invoke-method \
	    --rest-api-id $$API_ID \
	    --resource-id $$RESOURCE_ID \
	    --http-method GET \
	    --headers 'Authorization=Bearer allow' \
	    --endpoint-url=http://localstack:4566 \
	    --output json 2>/dev/null || echo "Test failed"; \
	echo ""; \
	echo "Checking LocalStack logs for lambda.Invoke entries..."; \
	echo "Recent lambda.Invoke logs:"; \
	docker compose logs localstack 2>/dev/null | grep -i "lambda.Invoke" | tail -5 || echo "  (No lambda.Invoke entries found)"; \
	echo ""; \
	echo "Note: If lambda.Invoke entries are not found, LocalStack may not be calling the Authorizer."; \
	echo "This is a known limitation of LocalStack. The Lambda function itself works correctly (see: make test-authorizer)"

# Lambda Authorizerを直接呼び出してテスト
test-authorizer:
	@echo "==> testing Lambda Authorizer directly"
	@echo "Checking if containers are running..."
	@if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^gateway-awscli$$"; then \
	  echo "ERROR: awscli container (gateway-awscli) is not running. Run 'docker compose up -d' first."; \
	  exit 1; \
	fi
	@echo "Testing Lambda Authorizer with valid token..."
	@docker exec gateway-awscli /bin/sh -c "echo '{\"type\":\"TOKEN\",\"authorizationToken\":\"Bearer allow\",\"methodArn\":\"arn:aws:execute-api:us-east-1:000000000000:test/test/GET\"}' > /tmp/payload1.json" && \
	docker exec gateway-awscli aws lambda invoke \
	  --function-name authz-go \
	  --cli-binary-format raw-in-base64-out \
	  --payload file:///tmp/payload1.json \
	  --endpoint-url=http://localstack:4566 \
	  /tmp/response1.json && \
	  echo "Response:" && \
	  docker exec gateway-awscli cat /tmp/response1.json | python3 -m json.tool 2>/dev/null || docker exec gateway-awscli cat /tmp/response1.json && \
	  echo ""
	@echo "Testing Lambda Authorizer with invalid token..."
	@docker exec gateway-awscli /bin/sh -c "echo '{\"type\":\"TOKEN\",\"authorizationToken\":\"Bearer invalid-token\",\"methodArn\":\"arn:aws:execute-api:us-east-1:000000000000:test/test/GET\"}' > /tmp/payload2.json" && \
	docker exec gateway-awscli aws lambda invoke \
	  --function-name authz-go \
	  --cli-binary-format raw-in-base64-out \
	  --payload file:///tmp/payload2.json \
	  --endpoint-url=http://localstack:4566 \
	  /tmp/response2.json && \
	  echo "Response:" && \
	  docker exec gateway-awscli cat /tmp/response2.json | python3 -m json.tool 2>/dev/null || docker exec gateway-awscli cat /tmp/response2.json && \
	  echo ""
	@echo "Testing Lambda Authorizer without token..."
	@docker exec gateway-awscli /bin/sh -c "echo '{\"type\":\"TOKEN\",\"authorizationToken\":\"\",\"methodArn\":\"arn:aws:execute-api:us-east-1:000000000000:test/test/GET\"}' > /tmp/payload3.json" && \
	docker exec gateway-awscli aws lambda invoke \
	  --function-name authz-go \
	  --cli-binary-format raw-in-base64-out \
	  --payload file:///tmp/payload3.json \
	  --endpoint-url=http://localstack:4566 \
	  /tmp/response3.json && \
	  echo "Response:" && \
	  docker exec gateway-awscli cat /tmp/response3.json | python3 -m json.tool 2>/dev/null || docker exec gateway-awscli cat /tmp/response3.json && \
	  echo ""

# LocalStackリソースのクリーンアップ
clean-all:
	@echo "==> cleaning up LocalStack resources"
	@echo "WARNING: This will delete all resources in LocalStack"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
	  docker exec gateway-awscli /bin/sh -c "\
	    aws lambda delete-function --function-name authz-go --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	    aws iam detach-role-policy --role-name lambda-authorizer-role --policy-arn \$$(aws iam list-policies --endpoint-url=http://localstack:4566 --query \"Policies[?PolicyName=='lambda-authorizer-policy'].Arn\" --output text | head -n1) --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	    aws iam delete-role --role-name lambda-authorizer-role --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	    aws iam delete-policy --policy-arn \$$(aws iam list-policies --endpoint-url=http://localstack:4566 --query \"Policies[?PolicyName=='lambda-authorizer-policy'].Arn\" --output text | head -n1) --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	    API_ID=\$$(aws apigateway get-rest-apis --endpoint-url=http://localstack:4566 --query \"items[?name=='local-gateway-api'].id\" --output text | head -n1); \
	    if [ -n \"\$$API_ID\" ]; then \
	      aws apigateway delete-rest-api --rest-api-id \$$API_ID --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	    fi; \
	    echo 'Cleanup completed'" || echo "ERROR: Container not running"; \
	else \
	  echo "Cancelled"; \
	fi
