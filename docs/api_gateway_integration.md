# API Gateway統合設定の理解

## 概要

このドキュメントでは、API Gatewayの統合設定（MOCK統合、Lambda統合（非プロキシ））と、LocalStackでの動作について説明します。

## 統合設定の種類

### 1. MOCK統合

**役割**: バックエンド統合の種類と動作を定義

- **何を設定するか**: バックエンド（Lambda、HTTP、MOCKなど）との接続方法
- **動作**: 実際のバックエンドを呼ばずに、API Gateway内で固定レスポンスを返す
- **request-templates**: リクエストをバックエンドに渡す前に変換するテンプレート（MOCKでは使用されない）

**特徴**:
- 常に同じ固定レスポンスを返す
- バックエンド（Lambda/HTTP）は呼ばない
- テストやプロトタイプに適している

```
※現状では設定していない
```

### 2. 統合レスポンス（Integration Response）

**役割**: バックエンドからのレスポンスを処理・変換

- **何を設定するか**: 統合からの生レスポンスをクライアント向けに変換する方法
- **処理の流れ**: バックエンド → 統合レスポンス（変換） → メソッドレスポンス
- **response-templates**: レスポンスを変換するテンプレート

**注意**: Lambda統合（非プロキシ）では統合レスポンスが必要（レスポンス変換が必要なため）

```
※現状では200のみ設定
Authorizationヘッダーの書き換えに合わせて統合レスポンスを設定している
```

### 3. メソッドレスポンス（Method Response）

**役割**: クライアントに返すレスポンスの「契約」を定義

- **何を設定するか**: クライアントが受け取る可能性のあるレスポンスの構造
- **処理の流れ**: 統合レスポンス → メソッドレスポンス（検証） → クライアント

**注意**: Lambda統合（非プロキシ）ではメソッドレスポンスが必要（レスポンス契約が必要なため）

```
※現状では200のみ設定
```

## 処理の流れ

### MOCK統合の場合

```
クライアントリクエスト
    ↓
メソッド（GET）← メソッドレスポンスで定義された形式を期待
    ↓
統合（MOCK）← 統合レスポンスで変換
    ↓
クライアントレスポンス ← メソッドレスポンスで定義された形式で返す
```

### Lambda統合（非プロキシ）+マッピングテンプレートの場合

```
クライアントリクエスト
    ↓
【Authorizer実行】authz-goが呼び出される（認証・認可）
    ↓
【認証成功時のみ】メソッド（GET）が実行される
    ↓
【Lambda統合（非プロキシ）】マッピングテンプレートでAuthorizationヘッダーをinternal_tokenに置換したイベントが
test-function Lambda関数に渡される
    ↓
クライアントレスポンス ← 統合レスポンスでLambda関数のレスポンスを変換して返る
```

## curlコマンド実行時の処理フロー

```
1. クライアント（curl）からのリクエスト
   curl -H 'Authorization: Bearer allow' http://.../test/test
   
2. API Gateway（LocalStack）がリクエストを受信
   - URL: /test/test (GET)
   - ヘッダー: Authorization: Bearer allow
   
3. 【Authorizer実行】Lambda関数（authz-go）が呼び出される
   - identity-source: method.request.header.Authorization
   - Authorizationヘッダーから "Bearer allow" を取得
   - "allow" をトークンとして抽出
   - DynamoDB（AllowedTokensテーブル）でトークンを検証
     * トークンが存在し、active=true なら → Allow
     * トークンが存在しない、またはactive=false なら → Deny
   
4. 【認証成功時】AuthorizerがIAMポリシーを返す
   - Effect: "Allow"
   - PrincipalID: "user"
   - Resource: メソッドARN
   - Context: { "token": "allow", "internal_token": "internal-allow" }
   
5. 【認証失敗時】AuthorizerがDenyポリシーを返す
   - Effect: "Deny"
   - API Gatewayが403 Forbiddenを返して終了（実際のAWS環境）
   
6. 【認証成功時のみ】メソッド（GET）が実行される
   - リソース: /test
   - HTTPメソッド: GET
   
7. 【Lambda統合（非プロキシ）】マッピングテンプレートでAuthorizationヘッダーをinternal_tokenに書き換え
   - 書き換え後のイベントがtest-function Lambda関数に渡される
   
8. クライアントにレスポンスが返る
   {
     "message": "Hello from test-function!",
     "status": "success"
   }
```

## 現在の実装

### 実装方針

現在の実装では、**Lambda統合（非プロキシ）+リクエストマッピングテンプレート**を使用しています。MOCK統合は設定していません。

### 実装の流れ

1. **既存の統合レスポンスとメソッドレスポンスを削除**
   - MOCK統合の残骸をクリーンアップ
   - 複数のステータスコード（200, 400, 500など）を削除

2. **test-function Lambda関数のARNを取得**
   - `test-function` が存在するか確認

3. **Lambda統合（非プロキシ）+リクエストマッピングテンプレートを設定（test-functionが見つかった場合のみ）**
   - `test-function` Lambda関数のARNを取得
   - `test-function` にAPI Gatewayからの呼び出し権限を付与
   - `--type AWS` でLambda関数を呼び出す統合を設定
   - Authorizationヘッダーをinternal_tokenに書き換えるテンプレートを設定

4. **メソッドレスポンスと統合レスポンスを設定**
   - 200のみ定義（シンプルな変換）

5. **test-functionが見つからない場合**
   - 警告メッセージを表示
   - 利用可能なLambda関数の一覧を表示
   - 統合設定をスキップ（統合が設定されない状態になる）

### 実装の詳細

**統合レスポンスとメソッドレスポンスの削除**:
- 既存の設定をクリーンアップ
- ステータスコード200, 400, 500を削除
- エラーは無視（既に存在しない場合もあるため）

**Lambda統合（非プロキシ）の設定**:
- `test-function` が見つかった場合のみ実行
- Authorizationヘッダーを書き換えるリクエストテンプレートを設定
- 200のメソッドレスポンス/統合レスポンスを設定

### 実装コード（抜粋）

```bash
# Lambda統合（非プロキシ） + request templates
aws apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method "$HTTP_METHOD" \
  --type AWS \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${TEST_FUNCTION_ARN}/invocations" \
  --request-templates "file://$REQUEST_TEMPLATE_FILE" \
  --endpoint-url="$ENDPOINT" >/dev/null

# 200のメソッドレスポンスと統合レスポンス
aws apigateway put-method-response \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method "$HTTP_METHOD" \
  --status-code 200 \
  --response-models "application/json=Empty" \
  --endpoint-url="$ENDPOINT" >/dev/null

aws apigateway put-integration-response \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method "$HTTP_METHOD" \
  --status-code 200 \
  --response-templates "file://$RESPONSE_TEMPLATE_FILE" \
  --endpoint-url="$ENDPOINT" >/dev/null
```

### 注意点

- **test-functionが見つからない場合**: 統合が設定されないため、API Gatewayのメソッドに統合が存在しない状態になります。この場合、リクエストはエラーになる可能性があります。
- **統合レスポンスとメソッドレスポンス**: 200のみ設定し、Lambdaのレスポンスをクライアント向けに変換します。

## 統合タイプの比較

| 統合タイプ | 動作 | レスポンス | 統合レスポンス設定 | メソッドレスポンス設定 |
|-----------|------|-----------|------------------|---------------------|
| **MOCK** | バックエンドを呼ばない | 固定レスポンス（常に同じ） | 必要 | 必要 |
| **Lambda（非プロキシ）** | マッピングテンプレートでイベントを作成 | 統合レスポンスで変換 | 必要 | 必要 |
| **AWS_PROXY** | Lambda関数を呼び出す（参考） | Lambda関数のレスポンス（動的） | 不要 | 不要 |

## LocalStackでの動作と制限

### Authorizerの動作確認

Lambda関数（authz-go）を直接テストすると、正しく動作していることが確認できます：

**無効なトークン（TOKEN=a）の場合**:
```json
{
    "principalId": "user",
    "policyDocument": {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Deny",
                "Resource": ["arn:aws:execute-api:us-east-1:000000000000:test/test/GET"]
            }
        ]
    },
    "context": {
        "reason": "token_not_found"
    }
}
```

**有効なトークン（TOKEN=allow）の場合**:
```json
{
    "principalId": "user",
    "policyDocument": {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Resource": ["arn:aws:execute-api:us-east-1:000000000000:test/test/GET"]
            }
        ]
    },
    "context": {
        "token": "allow",
        "internal_token": "internal-allow"
    }
}
```

### LocalStackの制限

**問題**: LocalStackのAPI GatewayのAuthorizer実装に問題がある可能性があります。

- **期待される動作**: AuthorizerがDenyを返す場合、API Gatewayは403 Forbiddenを返すべき
- **実際の動作（LocalStack）**: AuthorizerがDenyを返しても、API Gatewayは200 OKを返し、バックエンドが呼ばれる

**確認方法**:
```bash
# 無効なトークンで実行
make exec-curl TOKEN=a
# 期待: 403 Forbidden
# 実際（LocalStack）: 200 OK（test-functionが呼ばれる）

# 有効なトークンで実行
make exec-curl TOKEN=allow
# 期待: 200 OK（test-functionが呼ばれる）
# 実際（LocalStack）: 200 OK（test-functionが呼ばれる）
```

### Authorizerのキャッシュ設定

`authorizer-result-ttl-in-seconds` は、Authorizerの結果をキャッシュする時間を秒単位で指定します。

- **デフォルト**: 300秒（5分）
- **検証用設定**: 1秒（キャッシュの問題を排除するため）

```bash
--authorizer-result-ttl-in-seconds 1
```

## 実際のAWS環境との違い

### 実際のAWS環境での動作

**無効なトークン（TOKEN=a）の場合**:
```
TOKEN=a (無効)
  ↓
Authorizer: Denyポリシーを返す
  ↓
API Gateway: 403 Forbiddenを返す
  ↓
test-function: 呼ばれない
```

**有効なトークン（TOKEN=allow）の場合**:
```
TOKEN=allow (有効)
  ↓
Authorizer: Allowポリシーを返す
  ↓
API Gateway: リクエストを許可
  ↓
test-function: 呼ばれる → 200 OK
```

### LocalStackでの動作

**無効なトークンでも**:
```
TOKEN=a (無効)
  ↓
Authorizer: Denyポリシーを返す（正しい）
  ↓
API Gateway: 200 OKを返す（問題あり）
  ↓
test-function: 呼ばれる（本来は呼ばれるべきではない）
```

## まとめ

### 重要なポイント

1. **現在の実装**
   - **MOCK統合**: 設定していない（削除済み）
   - **Lambda統合（非プロキシ）**: 使用中（request templatesでAuthorizationヘッダーをinternal_tokenに書き換え）
   - **統合レスポンス**: 200のみ設定
   - **メソッドレスポンス**: 200のみ設定

2. **統合レスポンスとメソッドレスポンス**
   - MOCK統合: 必要（固定レスポンスを返すため）
   - Lambda統合（非プロキシ）: 必要（レスポンス変換のため）
   - 現在の実装: 200のみ定義

3. **test-functionの要件**
   - `test-function` Lambda関数が存在する必要がある
   - 存在しない場合、統合が設定されず、API Gatewayのメソッドに統合が存在しない状態になる
   - `make deploy` を実行すると、`lambda/test-function/function.zip` が存在する場合、自動的にデプロイされる

4. **LocalStackの制限**
   - AuthorizerのDenyポリシーが正しく処理されない可能性がある
   - 実際のAWS環境では正しく動作するはず

5. **デプロイ手順**
   ```bash
   make clean-localstack  # 既存のリソースをクリーンアップ
   make deploy            # 再デプロイ（test-functionも含めてすべてのLambda関数をビルド＆デプロイ）
   ```

### 推奨事項

- LocalStackは開発・テスト用のツールであり、一部の機能で完全な互換性がない場合がある
- 本番環境や実際のAWS環境での動作確認が重要
- Authorizerの動作を確認する場合は、Lambda関数を直接テストする

## 参考

- [AWS API Gateway統合タイプ](https://docs.aws.amazon.com/ja_jp/apigateway/latest/developerguide/api-gateway-api-integration-types.html)
- [Lambda Authorizer](https://docs.aws.amazon.com/ja_jp/apigateway/latest/developerguide/apigateway-use-lambda-authorizer.html)
- [LocalStack Documentation](https://docs.localstack.cloud/)
