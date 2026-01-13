FROM --platform=linux/arm64 golang:1.21-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    zip unzip curl jq git ca-certificates bash \
  && rm -rf /var/lib/apt/lists/*

# awscli v2
RUN curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o /tmp/awscliv2.zip \
  && unzip -q /tmp/awscliv2.zip -d /tmp \
  && /tmp/aws/install \
  && rm -rf /tmp/aws /tmp/awscliv2.zip

# 使いやすいデフォルト
ENV AWS_DEFAULT_REGION=us-east-1
