# =============================================================
# provider.tf — Terraform Provider 설정
# S3 remote backend 사용
# DNS provider 토글: route53(팀원) / cloudflare(신준한)
# 파일위치 : ~/project2-security/infra/terraform/provider.tf
# =============================================================
terraform {
  required_version = ">= 1.5.0, < 2.0.0" # 1.15.0 → 낮춰서 범용

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.16"
    }
  }
  # terraform 상태 관리를 위한 remote backend 설정
  backend "s3" {
    # bucketd은 외부 파일(terraform/hcl/backend.hcl)에서 채우기
    # bucket 은 개인별(S3 전역 고유) → -backend-config=hcl/backend.hcl 로 주입
    key            = "infra/terraform.tfstate" # /infra/하위에 만들어 지도록
    region         = "ap-northeast-2"
    dynamodb_table = "lb-tf-lock" # 미리 준비된 dynamodb 테이블의 이름을 명시하면 lock 상태가 자동으로 관리된다.
    encrypt        = true         # tfstate에는 민감한 정보가 있을 수 있기 때문에 암호화
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "Terraform"
      Track     = "A-Infra"
    }
  }
}

# route53/none 사용자용 cloudflare 더미 토큰.
locals {
  # Terraform은 미사용 provider도 configure하므로 형식(40자)·존재 검증 통과가 필요.
  # cloudflare 리소스는 count=0(dns_provider≠cloudflare)이라 더미로 실제 API 호출 없음.
  # range(40)으로 길이를 코드가 보장 → 0 개수 오타 위험 제거.
  cloudflare_dummy_token = join("", [for _ in range(40) : "0"])
  # (다른 간단 버전 코드) 
  # cloudflare_dummy_token = format("%040d", 0)   # 0을 40자리 zero-pad = "0"×40
}

# Cloudflare provider — dns_provider="cloudflare" 일 때만 실제 사용
# 토큰은 코드/tfvars 금지, 환경변수 TF_VAR_cloudflare_api_token 로 주입
provider "cloudflare" {
  api_token = var.cloudflare_api_token != "" ? var.cloudflare_api_token : local.cloudflare_dummy_token
}

# Tailscale provider — 키 생성·기기 승인용 (api_key 는 환경변수 권장)
provider "tailscale" {
  tailnet = var.tailnet_name
  api_key = var.tailscale_api_key
}