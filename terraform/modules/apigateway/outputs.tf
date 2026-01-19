# API Gateway モジュール出力定義

output "api_id" {
  description = "REST API ID"
  value       = aws_api_gateway_rest_api.api.id
}

output "api_name" {
  description = "REST API 名"
  value       = aws_api_gateway_rest_api.api.name
}

output "api_execution_arn" {
  description = "REST API の実行 ARN"
  value       = aws_api_gateway_rest_api.api.execution_arn
}

output "stage_name" {
  description = "デプロイステージ名"
  value       = aws_api_gateway_stage.stage.stage_name
}

output "invoke_url" {
  description = "API の呼び出し URL"
  value       = aws_api_gateway_stage.stage.invoke_url
}
