# 本番環境用 AWS プロバイダー設定

provider "aws" {
  region = "ap-northeast-1"

  # 認証は環境変数または IAM ロールで行う
  # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  # または IAM Instance Profile / ECS Task Role など

  default_tags {
    tags = {
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}
