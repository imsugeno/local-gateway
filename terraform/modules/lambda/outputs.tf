# Lambda モジュール出力定義

output "function_name" {
  description = "Lambda 関数名"
  value       = aws_lambda_function.function.function_name
}

output "function_arn" {
  description = "Lambda 関数の ARN"
  value       = aws_lambda_function.function.arn
}

output "invoke_arn" {
  description = "Lambda 関数の Invoke ARN"
  value       = aws_lambda_function.function.invoke_arn
}

output "role_arn" {
  description = "IAM ロールの ARN"
  value       = aws_iam_role.lambda_role.arn
}

output "role_name" {
  description = "IAM ロール名"
  value       = aws_iam_role.lambda_role.name
}
