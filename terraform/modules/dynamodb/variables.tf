# DynamoDB モジュールの変数定義

variable "table_name" {
  description = "DynamoDB テーブル名"
  type        = string
  default     = "AllowedTokens"
}

variable "tags" {
  description = "リソースに付与するタグ"
  type        = map(string)
  default     = {}
}
