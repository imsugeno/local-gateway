# Lambda モジュール変数定義

variable "function_name" {
  description = "Lambda 関数名"
  type        = string
}

variable "handler" {
  description = "Lambda ハンドラー"
  type        = string
  default     = "bootstrap"
}

variable "runtime" {
  description = "Lambda ランタイム"
  type        = string
  default     = "provided.al2023"
}

variable "timeout" {
  description = "Lambda タイムアウト（秒）"
  type        = number
  default     = 30
}

variable "zip_path" {
  description = "Lambda 関数の zip ファイルパス"
  type        = string
}

variable "iam_role_name" {
  description = "IAM ロール名（省略時は {function_name}-role）"
  type        = string
  default     = null
}

variable "iam_policy_name" {
  description = "IAM ポリシー名（省略時は {function_name}-policy）"
  type        = string
  default     = null
}

variable "enable_dynamodb_policy" {
  description = "DynamoDB アクセス用の IAM ポリシーを作成するかどうか"
  type        = bool
  default     = false
}

variable "dynamodb_table_name" {
  description = "DynamoDB テーブル名（環境変数用）"
  type        = string
  default     = ""
}

variable "dynamodb_table_arn" {
  description = "DynamoDB テーブルの ARN（IAM ポリシー用）"
  type        = string
  default     = ""
}

variable "environment_variables" {
  description = "Lambda 関数の追加環境変数"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "リソースに付与するタグ"
  type        = map(string)
  default     = {}
}
