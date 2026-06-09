# =============================================================
# dns.tf — ACM 인증서 + DNS 검증/레코드 (route53 / cloudflare 분기)
# enable_https=true 일 때만 ACM 생성
# 검증·도메인 레코드는 dns_provider 에 따라 한쪽만 생성
# alb.tf 의 aws_lb.web_alb 을 참조 (같은 디렉토리)
# 파일위치 : ~/project2-security/infra/terraform/dns.tf
# =============================================================

# ── ACM 인증서 (DNS 검증) ─────────────────────────────────
resource "aws_acm_certificate" "cert" {
  count             = var.enable_https ? 1 : 0 # HTTPS일 때만 발급
  domain_name       = var.domain_name          # 단일 도메인
  validation_method = "DNS"                    # 도메인 소유 증명 = DNS 방식

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project}-acm" }
}

# 검증에 필요한 DNS 레코드 정보 (도메인당 1개)
locals {
  acm_dvo = var.enable_https ? tolist(aws_acm_certificate.cert[0].domain_validation_options)[0] : null
}

# ─────────────────────────────────────────────────────────
#  [A] route53 분기 (팀원용)
# ─────────────────────────────────────────────────────────
# 기존 호스팅 영역 조회
data "aws_route53_zone" "selected" {
  count        = var.enable_https && var.dns_provider == "route53" ? 1 : 0
  name         = var.route53_zone_name
  private_zone = false
}

# ACM 검증 CNAME (Route53)
resource "aws_route53_record" "cert_validation" {
  count   = var.enable_https && var.dns_provider == "route53" ? 1 : 0
  zone_id = data.aws_route53_zone.selected[0].zone_id
  name    = local.acm_dvo.resource_record_name
  type    = local.acm_dvo.resource_record_type
  records = [local.acm_dvo.resource_record_value]
  ttl     = 60
}

# 서비스 도메인 → ALB (Route53 Alias)
resource "aws_route53_record" "alb_alias" {
  count   = var.enable_https && var.dns_provider == "route53" ? 1 : 0
  zone_id = data.aws_route53_zone.selected[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.web_alb.dns_name
    zone_id                = aws_lb.web_alb.zone_id
    evaluate_target_health = true
  }
}

# ─────────────────────────────────────────────────────────
#  [B] cloudflare 분기 (신준한용)
#   ★ ACM 검증 CNAME 을 "실제 DNS(Cloudflare)" 에 넣어야 검증됨
#     (수업 때 Route53 에 넣어 안 됐던 부분을 여기서 해결)
# ─────────────────────────────────────────────────────────
# ACM 검증 CNAME (Cloudflare)
resource "cloudflare_record" "cert_validation" {
  count   = var.enable_https && var.dns_provider == "cloudflare" ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = local.acm_dvo.resource_record_name
  type    = local.acm_dvo.resource_record_type
  content = local.acm_dvo.resource_record_value
  ttl     = 60
  proxied = false # 검증 레코드는 반드시 DNS-only
}

# 서비스 도메인 → ALB (Cloudflare CNAME)
resource "cloudflare_record" "alb_cname" {
  count   = var.enable_https && var.dns_provider == "cloudflare" ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.domain_name
  type    = "CNAME"
  content = aws_lb.web_alb.dns_name
  ttl     = 1     # proxied=true 면 TTL 자동(1)
  proxied = false # ★ 최초엔 false(DNS-only) 권장: ACM·ALB 동작 확인 후 true 전환
}

# ─────────────────────────────────────────────────────────
#  ACM 검증 완료 대기 (route53 / cloudflare 공통)
#  cloudflare 는 provider 가 검증 레코드를 못 가리키므로 fqdn 수동 구성
# ─────────────────────────────────────────────────────────
resource "aws_acm_certificate_validation" "cert" {
  count           = var.enable_https && var.dns_provider != "none" ? 1 : 0
  certificate_arn = aws_acm_certificate.cert[0].arn

  validation_record_fqdns = var.dns_provider == "route53" ? [
    one(aws_route53_record.cert_validation[*].fqdn)
    ] : [
    try(local.acm_dvo.resource_record_name, "")
  ]

  depends_on = [
    cloudflare_record.cert_validation,  # ★ cloudflare 분기 race 차단 (핵심)
    aws_route53_record.cert_validation, # route53는 fqdn 참조로 이미 암묵 의존, 안전상 명시
  ]
}