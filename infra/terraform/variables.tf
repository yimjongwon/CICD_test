# =============================================================
# variables.tf — 전체 인프라 변수 (network/sg/alb/compute/dns 공용)
# 파일위치 : ~/project2-security/infra/terraform/variables.tf
# =============================================================

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "리소스 네임 prefix"
  type        = string
  default     = "lb"
}

# --- 네트워크 (멀티-AZ, ALB 2AZ 요건) ---
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  description = "가용영역 (ALB 2AZ)"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "app_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "db_subnet_cidrs" {
  description = "DB 서브넷 (단일 AZ; 복제 시 AZ-c 추가)"
  type        = list(string)
  default     = ["10.0.21.0/24"]
}

# --- 인스턴스 ---
variable "key_name" {
  description = "EC2 키페어 (lb-key)"
  type        = string
  default     = "lb-key"
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "nat_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "app_instance_type" {
  type    = string
  default = "t3.small"
}

variable "db_instance_type" {
  type    = string
  default = "t3.small"
}

# [선택/Packer] App ASG용 커스텀 AMI.
#  비우면 모든 팀원이 공용 SSM 최신 AL2023 사용 → 추가 작업 0 (공유 기본값).
#  개인이 시간 되면 Packer로 docker·tailscale·node_exporter 포함 AMI를 구워
#  이 값에 넣으면 ASG scale-out이 초 단위로 빨라짐(데모 가속).
#  ※ AMI는 계정·리전별이라 각자 자기 계정에 구워야 함(팀 공유 X). 순수 옵션.
variable "app_ami_id" {
  description = "App ASG 커스텀 AMI(비우면 SSM 최신 AL2023). Packer 데모 가속용, 선택"
  type        = string
  default     = ""
}

# --- Auto Scaling (Blue/Green 색상별 ASG) ---
variable "asg_min" {
  type    = number
  default = 1
}

variable "asg_max" {
  type    = number
  default = 3
}

variable "asg_desired" {
  type    = number
  default = 1
}

# =============================================================
# DNS / ACM (HTTPS) — provider 토글로 팀원/신준한 분기
# =============================================================

variable "enable_https" {
  description = "true=ACM+443 리스너, false=80만"
  type        = bool
  default     = true
}

# "route53" = 팀원(AWS Route53) / "cloudflare" = 신준한 / "none" = DNS 수동
variable "dns_provider" {
  description = "DNS 자동화 방식: route53 | cloudflare | none"
  type        = string
  default     = "route53"

  validation {
    condition     = contains(["route53", "cloudflare", "none"], var.dns_provider)
    error_message = "dns_provider 는 route53 | cloudflare | none 중 하나여야 합니다."
  }
}

variable "domain_name" {
  description = "ALB 연결 도메인 (예: lockbank.junhanshin.com)  tfvars 입력"
  type        = string
  default     = ""
}

# route53 전용 — 기존 호스팅 영역 이름 (예: junhanshin.com)
variable "route53_zone_name" {
  description = "dns_provider=route53 일 때 기존 Route53 호스팅 영역"
  type        = string
  default     = ""
}

# cloudflare 전용 — Zone ID + API 토큰 (토큰은 환경변수 권장)
variable "cloudflare_zone_id" {
  type        = string
  default     = ""
  description = "dns_provider=cloudflare 일 때 Cloudflare Zone ID"
}

variable "cloudflare_api_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Cloudflare API 토큰. 코드/tfvars 금지, 환경변수 TF_VAR_cloudflare_api_token 로 주입"
}

variable "tailnet_name" {
  description = "Tailscale tailnet 이름(가입 이메일). 예: you@gmail.com"
  type        = string
}

variable "tailscale_api_key" {
  description = "Tailscale API 키(provider 인증용). 환경변수 TF_VAR_tailscale_api_key 로 주입"
  type        = string
  sensitive   = true
}

variable "admin_ingress_cidr" {
  description = "Bastion SSH 허용 출처. 반드시 내 공인IP/32 로 지정 (tfvars)"
  type        = string
  # default 제거 → 미입력 시 에러로 강제 (0.0.0.0/0 사고 방지)
}

variable "app_image" {
  type    = string
  default = "lockandlock/lock-app:latest"
}