# DynamoDB モジュールの出力定義

output "table_name" {
  description = "DynamoDB テーブル名"
  value       = aws_dynamodb_table.allowed_tokens.name
}

output "table_arn" {
  description = "DynamoDB テーブルの ARN"
  value       = aws_dynamodb_table.allowed_tokens.arn
}

output "table_id" {
  description = "DynamoDB テーブルの ID"
  value       = aws_dynamodb_table.allowed_tokens.id
}
