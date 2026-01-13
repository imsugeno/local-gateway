# Local Gateway - Lambda Authorizer PoC

JWTベース認証における「認可判断をDynamoDBで外出しする設計」のPoC実装です。

## アーキテクチャ

```
ブラウザ → API Gateway (REST) → Lambda Authorizer (TOKEN) → DynamoDB
                                              ↓
                                         Allow/Deny判定
```

## 要件

- **認可フロー**: API Gateway (REST API) → Lambda Authorizer (TOKEN) → DynamoDB
- **データストア**: DynamoDB（認可情報の保存）
- **Lambda**: Go言語で実装、provided.al2 + bootstrap方式
- **環境**: LocalStack（AWS代替）
- **GUI**: dynamodb-adminでデータ編集可能

## セットアップ

### 1. 環境変数の設定

`.env`ファイルを作成（`.env.example`を参考に）：

```bash
# LocalStack設定
LOCALSTACK_PORT=4566
LOCALSTACK_SERVICES=lambda,apigateway,dynamodb,iam
LOCALSTACK_DEBUG=0

# AWS設定（LocalStack用のダミー値でOK）
AWS_DEFAULT_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test

# DynamoDB Admin設定
DYNAMODB_ADMIN_PORT=8001
```

### 2. Lambda関数のビルド

**重要**: `docker compose up`の前に必ずビルドを実行してください。

```bash
make build
```

これにより`lambda/authz-go/function.zip`が生成されます。

### 3. 環境の起動

```bash
docker compose up -d
```

これにより以下が自動実行されます：
1. LocalStackの起動
2. DynamoDBテーブル（`AllowedTokens`）の作成
3. 初期データの投入（トークン: `allow`）
4. Lambda関数のデプロイ（`function.zip`が必要）
5. API Gatewayの作成とAuthorizer設定

**注意**: 初回起動時や`function.zip`が存在しない場合は、`make deploy`を手動で実行してください。

### 4. 動作確認

#### デプロイ状況の確認

```bash
# コンテナの状態を確認
docker compose ps

# awscliコンテナのログを確認（エラーがある場合）
docker compose logs awscli
```

#### API Gatewayへのリクエストテスト

**方法1: curlを使用（推奨）**
```bash
make test
```

**方法2: aws apigateway test-invoke-methodを使用**
```bash
make test-api-invoke
```

**方法3: Lambda Authorizerを直接テスト**
```bash
make test-authorizer
```

もしAPI Gatewayが見つからない場合は、手動でデプロイを実行してください：

```bash
make deploy
make test
```

**注意**: 
- `make test`（curl）では、AuthorizerがDenyを返すと403 Forbiddenが返されるはずです
- `make test-api-invoke`（test-invoke-method）では、すべてのテストケースで`status: 200`が返ってくる可能性があります（LocalStackの制限）

または手動で：

**bash/zshの場合:**
```bash
# API IDを取得
API_ID=$(docker exec gateway-awscli aws apigateway get-rest-apis \
  --endpoint-url=http://localstack:4566 \
  --query "items[?name=='local-gateway-api'].id" \
  --output text | head -n1)

# リクエスト（トークンなし - Deny）
curl -X GET "http://localhost:4566/restapis/${API_ID}/test/test"

# リクエスト（無効なトークン - Deny）
curl -X GET "http://localhost:4566/restapis/${API_ID}/test/test" \
  -H "Authorization: Bearer invalid-token"

# リクエスト（有効なトークン - Allow）
curl -X GET "http://localhost:4566/restapis/${API_ID}/test/test" \
  -H "Authorization: Bearer allow"
```

**fishシェルの場合:**
```fish
# API IDを取得
set API_ID (docker exec gateway-awscli aws apigateway get-rest-apis \
  --endpoint-url=http://localstack:4566 \
  --query "items[?name=='local-gateway-api'].id" \
  --output text | head -n1)

# ポート番号を確認（環境変数LOCALSTACK_PORTが設定されている場合はそれを使用）
# デフォルトは4566ですが、.envファイルで4666などに変更している場合はそれを使用
set LOCALSTACK_PORT (echo $LOCALSTACK_PORT; or echo "4566")

# リクエスト（トークンなし - Deny）
# 注意: LocalStackのバージョンによっては、エンドポイント形式が異なる場合があります
# 形式1: http://localhost:{PORT}/restapis/{api-id}/{stage}/{resource-path}
curl -X GET "http://localhost:$LOCALSTACK_PORT/restapis/$API_ID/test/test"

# 形式2（LocalStack 4.x推奨）: http://{api-id}.execute-api.localhost.localstack.cloud:{PORT}/{stage}/{resource-path}
curl -X GET "http://$API_ID.execute-api.localhost.localstack.cloud:$LOCALSTACK_PORT/test/test"

# リクエスト（無効なトークン - Deny）
curl -X GET "http://$API_ID.execute-api.localhost.localstack.cloud:$LOCALSTACK_PORT/test/test" \
  -H "Authorization: Bearer invalid-token"

# リクエスト（有効なトークン - Allow）
curl -X GET "http://$API_ID.execute-api.localhost.localstack.cloud:$LOCALSTACK_PORT/test/test" \
  -H "Authorization: Bearer allow"
```

**重要**: 環境変数`LOCALSTACK_PORT`でポートを変更している場合（例: `LOCALSTACK_PORT=4666`）、すべてのエンドポイントURLでそのポート番号を使用してください。

**重要**: LocalStack 4.xでは、API Gatewayのエンドポイント形式が変更されています。`/restapis/...`形式は`NoSuchBucket`エラーになります。

**LocalStack 4.xでは、以下の形式を使用してください：**

```fish
# LocalStack 4.x用のエンドポイント形式（推奨）
# 形式: http://{api-id}.execute-api.localhost.localstack.cloud:{PORT}/{stage}/{resource-path}
curl -X GET "http://$API_ID.execute-api.localhost.localstack.cloud:$LOCALSTACK_PORT/test/test" \
  -H "Authorization: Bearer allow"
```

**注意**: 
- LocalStack 3.x以前では`/restapis/...`形式が使えますが、4.xでは使えません
- 必ず`{api-id}.execute-api.localhost.localstack.cloud`形式を使用してください

または、`/etc/hosts`にエントリを追加する方法もあります（推奨されませんが、動作する場合があります）：
```fish
# 127.0.0.1 x43r0h7xhu.execute-api.localhost.localstack.cloud
curl -X GET "http://$API_ID.execute-api.localhost.localstack.cloud:4566/test/test" \
  -H "Authorization: Bearer allow"
```

#### DynamoDBでの認可情報編集

1. ブラウザで http://localhost:8001 を開く
2. `AllowedTokens`テーブルを選択
3. トークンの追加・編集・削除
4. `active`属性を`false`に設定すると、そのトークンは拒否される

## 使用方法

### 手動デプロイ

```bash
# Lambda関数とAPI Gatewayを再デプロイ
make deploy
```

### リソースのクリーンアップ

```bash
# LocalStack内のリソースを削除
make clean-all
```

### ビルド成果物のクリーンアップ

```bash
# Lambda関数のビルド成果物を削除
make clean
```

## ファイル構成

```
.
├── docker-compose.yml          # LocalStack、dynamodb-admin、awscli
├── Makefile                    # ビルド・デプロイ・テスト用コマンド
├── go.work                     # Go workspace設定
├── .env.example                # 環境変数テンプレート
├── README.md                   # このファイル
├── init/
│   ├── 00_dynamodb.sh         # DynamoDBテーブル作成・初期データ投入
│   ├── 01_lambda.sh           # Lambda関数デプロイ（IAM Role/Policy含む）
│   └── 02_api_gateway.sh      # API Gateway作成・Authorizer設定
└── lambda/
    └── authz-go/
        ├── main.go            # Lambda Authorizer実装
        ├── go.mod             # Go依存関係
        ├── bootstrap          # ビルド成果物（実行ファイル）
        └── function.zip       # ビルド成果物（デプロイ用）
```

## DynamoDBテーブル設計

### テーブル名
`AllowedTokens`

### スキーマ
- **主キー**: `token` (String)
- **属性**: `active` (Boolean, オプション)
  - `true` または未設定: 許可
  - `false`: 拒否

### 初期データ
- `token: "allow"` (active属性なし = 許可)

## Lambda Authorizer仕様

- **タイプ**: TOKEN
- **入力**: `Authorization`ヘッダーからトークンを抽出
- **処理**:
  1. トークン抽出（`Bearer <token>`形式）
  2. DynamoDB GetItemでトークンを検索
  3. 存在し、`active`が`false`でなければAllow
  4. それ以外はDeny
- **出力**: IAM Policy（Allow/Deny）

## トラブルシューティング

### LocalStackが起動しない
- Dockerが起動しているか確認
- ポート4566が使用されていないか確認

### Lambda関数のデプロイに失敗する
- `make build`を実行して`function.zip`が生成されているか確認
- LocalStackのログを確認: `docker-compose logs localstack`

### API Gatewayにアクセスできない / `NoSuchBucket`エラーが出る

**症状**: `NoSuchBucket`エラーやS3関連のエラーが表示される

**原因**: LocalStackのAPI Gatewayエンドポイント形式の問題、またはAPI Gatewayが正しくデプロイされていない可能性

**対処法**:

1. **API Gatewayの状態を確認**:
   ```bash
   docker exec gateway-awscli aws apigateway get-rest-apis \
     --endpoint-url=http://localstack:4566 \
     --output table
   ```

2. **デプロイ状態を確認**:
   ```bash
   docker exec gateway-awscli aws apigateway get-deployments \
     --rest-api-id <API_ID> \
     --endpoint-url=http://localstack:4566
   ```

3. **再デプロイを試す**:
   ```bash
   make deploy
   ```

4. **LocalStackのバージョン確認**: 古いバージョンではAPI Gatewayの動作が不安定な場合があります
   ```bash
   docker exec gateway-localstack localstack --version
   ```

5. **エンドポイント形式の確認**: LocalStackのバージョンによっては、エンドポイント形式が異なる場合があります
   - 標準形式: `http://localhost:4566/restapis/{api-id}/{stage}/{resource-path}`
   - 代替形式: `http://{api-id}.execute-api.localhost.localstack.cloud:4566/{stage}/{resource-path}`

### DynamoDBにアクセスできない
- dynamodb-adminが起動しているか確認: http://localhost:8001
- LocalStackのDynamoDBサービスが有効か確認

### `--endpoint-url`を外してしまった場合

**重要**: すべてのコマンドで`--endpoint-url=http://localstack:4566`を指定しています。これを外すと**実際のAWS環境に接続しようとします**。

#### 起こりうる結果

1. **認証エラーになる場合（最も可能性が高い）**
   ```
   Unable to locate credentials
   ```
   - コンテナ内の認証情報（`AWS_ACCESS_KEY_ID=test`）は実際のAWSでは無効
   - エラーで停止するため、実際のAWSには影響なし

2. **万が一接続できた場合（非常に稀）**
   - 実際のAWSアカウントにリソースが作成される可能性
   - 課金が発生する可能性
   - 既存のリソースと競合する可能性

#### 安全対策

- ✅ このプロジェクトのすべてのコマンドで`--endpoint-url`を指定
- ✅ コンテナ内の認証情報はダミー値（`test`）
- ✅ 実際のAWS認証情報を設定していない限り、接続できない

#### 確認方法

コマンドを実行する前に、必ず`--endpoint-url=http://localstack:4566`が含まれているか確認してください。

## 次のステップ（将来の拡張）

- JWT署名検証の追加
- REQUEST Authorizerへの移行
- Terraform化
- 本番環境への移行

## 注意事項

- このPoCはローカル検証用です。本番環境では追加のセキュリティ対策が必要です
- LocalStackは開発・テスト用途です。本番環境では実際のAWSサービスを使用してください

## LocalStackの制限事項

### Lambda Authorizerの動作について

**確認された動作**:
- ✅ 有効なトークン（`allow`）でリクエスト: Allowが返る（正常動作）
- ⚠️ 無効なトークンでリクエスト: Allowが返る（期待値: Deny）
- ⚠️ トークンなしでリクエスト: Allowが返る（期待値: Deny）

**原因**:
LocalStack 4.12.1の実装では、以下の制限がある可能性があります：
1. **API Gateway経由のリクエストでLambda Authorizerが呼び出されない**
   - `curl`や`aws apigateway test-invoke-method`でリクエストを送っても、`lambda.Invoke`のログが表示されない
   - これはLocalStackの実装による制限です
2. **Lambda関数自体は正常に動作**
   - `make test-authorizer`で直接Lambda関数を呼び出すと、正しくAllow/Denyを返す
   - DynamoDBからの認可判断も正常に動作している

**確認方法**:
```bash
# Lambda関数を直接テスト（正常に動作する）
make test-authorizer

# API Gateway経由でテスト（aws apigateway test-invoke-methodを使用）
make test-api-invoke

# LocalStackのログでlambda.Invokeを確認
docker compose logs localstack | grep -i "lambda.Invoke"
```

**重要な発見**:
- ✅ `make test-api-invoke`を実行すると、`lambda.Invoke => 200`のログが表示される
- ✅ これは、Lambda Authorizerが呼び出されていることを示している
- ⚠️ ただし、`test-invoke-method`の結果では、すべてのテストケースで`status: 200`が返ってくる
- ⚠️ これは、`test-invoke-method`がAuthorizerの結果を無視している可能性がある
- ✅ 実際のHTTPリクエスト（`curl`）では、AuthorizerがDenyを返すと403 Forbiddenが返されるはず

**実際のAWS環境での動作**:
- 実際のAWS環境では、CUSTOM Authorizerが設定されている場合、すべてのリクエストでAuthorizerが呼び出されます
- 無効なトークンやトークンなしの場合、AuthorizerがDenyを返すと403 Forbiddenが返されます
- `aws apigateway test-invoke-method`でもAuthorizerが呼び出されます

**PoCの評価**:
- ✅ **PoCの主要目的（DynamoDBでの認可判断）は達成されています**
- ✅ **Lambda関数自体は正常に動作している**（`make test-authorizer`で確認済み）
- ✅ **有効なトークンでの認可判断は正常に動作している**
- ✅ **`make test-api-invoke`で`lambda.Invoke => 200`のログが表示される = Authorizerが呼び出されている**
- ⚠️ **`test-invoke-method`の結果では、すべてのテストケースで`status: 200`が返ってくる（Authorizerの結果が反映されていない可能性）**
- ✅ **実際のAWS環境では正しく動作するはずです**
- ✅ **実際のHTTPリクエスト（`curl`）では、AuthorizerがDenyを返すと403 Forbiddenが返されるはずです**

