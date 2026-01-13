---
name: Lambda Authorizer PoC実装
overview: LocalStack環境でJWTベース認証におけるDynamoDBでの認可判断を検証するPoCを実装します。TOKEN Authorizerを使用し、docker-composeで一括起動できる構成にします。
todos:
  - id: env_file
    content: .env.exampleファイルを作成（環境変数テンプレート）
    status: completed
  - id: lambda_deploy_script
    content: init/01_lambda.shを作成（IAM Role/Policy作成、Lambda関数デプロイ）
    status: completed
  - id: apigateway_script
    content: init/02_api_gateway.shを作成（REST API作成、Authorizer設定、MOCK統合）
    status: completed
  - id: makefile_extend
    content: Makefileにdeploy、test、clean-allターゲットを追加
    status: completed
  - id: readme
    content: README.mdを作成（セットアップ手順、使用方法、動作確認方法）
    status: completed
  - id: go_mod_check
    content: lambda/authz-go/go.modの存在と依存関係を確認
    status: completed
---

# Lambda Authorizer

PoC実装計画

## アーキテクチャ概要

```javascript
ブラウザ → API Gateway (REST) → Lambda Authorizer (TOKEN) → DynamoDB
                                              ↓
                                         Allow/Deny判定
```

## 実装内容

### 1. 環境変数設定ファイル

- `.env.example` を作成（環境変数のテンプレート）
- 必要な変数: `LOCALSTACK_SERVICES`, `AWS_DEFAULT_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` など

### 2. Lambda関数のデプロイ

- `init/01_lambda.sh` を作成
- IAM RoleとPolicyの作成（DynamoDB読み取り権限）
- Lambda関数の作成/更新
- 環境変数の設定（`ALLOWED_TOKENS_TABLE`, `AWS_REGION`, `LOCALSTACK_HOSTNAME`）

### 3. API Gatewayの設定

- `init/02_api_gateway.sh` を作成
- REST APIの作成
- リソースとメソッドの作成（例: `/test` GET）
- TOKEN Authorizerの作成とメソッドへの紐付け
- MOCK統合の設定
- APIのデプロイ

### 4. Makefileの拡張

- `deploy` ターゲットを追加（LambdaとAPI Gatewayのデプロイ）
- `test` ターゲットを追加（API Gatewayへのリクエストテスト）
- `clean-all` ターゲットを追加（LocalStackリソースのクリーンアップ）

### 5. ドキュメント

- `README.md` を作成
- セットアップ手順
- 使用方法（docker-compose起動、テスト方法）
- DynamoDBでの認可情報編集方法

## ファイル構成

```javascript
.
├── docker-compose.yml          # 既存（確認済み）
├── Makefile                    # 既存（拡張）
├── go.work                     # 既存
├── .env.example                # 新規作成
├── README.md                   # 新規作成
├── init/
│   ├── 00_dynamodb.sh         # 既存（確認済み）
│   ├── 01_lambda.sh           # 新規作成
│   └── 02_api_gateway.sh      # 新規作成
└── lambda/
    └── authz-go/
        ├── main.go            # 既存（確認済み）
        ├── go.mod             # 確認が必要
        └── function.zip       # ビルド成果物
```
