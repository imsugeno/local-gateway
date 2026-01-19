# DynamoDB テーブル定義
# AllowedTokens テーブル - Lambda Authorizer で使用される許可トークンを格納

resource "aws_dynamodb_table" "allowed_tokens" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "token"

  attribute {
    name = "token"
    type = "S"
  }

  tags = var.tags
}
