# リモートステート設定（本番環境用）
#
# 使用する前に以下を準備してください：
# 1. S3 バケットを作成
# 2. DynamoDB テーブルを作成（ロック用）
#
# 準備ができたらコメントを解除して使用してください。

# terraform {
#   backend "s3" {
#     bucket         = "your-terraform-state-bucket"
#     key            = "production/terraform.tfstate"
#     region         = "ap-northeast-1"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }
