# =============================================================
# alb.tf — ALB + Target Group(Blue/Green) + Listener
# Rollback = Target Group 전환 (배포성공=Green, 실패=Blue)
# C/E 트랙이 이 TG ARN 으로 전환 스크립트 작성
# 파일위치 : ~/project2-security/infra/terraform/alb.tf
# =============================================================

resource "aws_lb" "web_alb" {
  name               = "${var.project}-alb"
  internal           = false                          # 인터넷 대면(공개)
  load_balancer_type = "application"                  # L7 (HTTP/HTTPS)
  security_groups    = [aws_security_group.alb_sg.id] # 80/443 ← 인터넷 (방금 그 SG)
  subnets            = aws_subnet.public_subnet[*].id # ★ public 2개(2a·2c)

  tags = { Name = "${var.project}-alb" } # lb-alb
}

# ── Target Group : Blue / Green (배포 전환용) ──────────────
# blue  = 현 안정 버전(stable) — 평소 트래픽 수신
# green = 신버전 배포 후보(deploy candidate) — 검증 후 리스너를 green으로 전환, 실패 시 blue 복귀
# ※ 인스턴스 장애 대체·스케일아웃은 ASG 담당 (blue/green과 별개)
resource "aws_lb_target_group" "blue" { # green도 동일 설정
  name     = "${var.project}-tg-blue"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health" # ★★ 이 경로로 200이 와야 "정상"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15 # 15초마다 검사
    timeout             = 5
    healthy_threshold   = 2 # 2번 연속 OK → 정상 등록
    unhealthy_threshold = 3 # 3번 연속 실패 → 제외
  }

  tags = {
    Name  = "${var.project}-tg-blue"
    Color = "blue"
    Role  = "active-stable" # 현 안정 버전
  }
}

resource "aws_lb_target_group" "green" {
  name     = "${var.project}-tg-green"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name  = "${var.project}-tg-green"
    Color = "green"
    Role  = "deploy-candidate" # 신버전 배포 후보
  }
}

# ── Listener ──────────────────────────────────────────────
# HTTPS 사용 시: HTTP(80)→443 리다이렉트 + HTTPS(443) forward
# HTTP 전용 시:  HTTP(80) forward (count 로 listener 자체를 분기 → 견고)

# [HTTPS 모드] 80 → 443 redirect
resource "aws_lb_listener" "http_redirect" {
  count             = var.enable_https ? 1 : 0 # [HTTPS모드] 80→443 리다이렉트
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# [HTTP 전용 모드] 80 → forward blue
resource "aws_lb_listener" "http_forward" {
  count             = var.enable_https ? 0 : 1 # [HTTP모드]  80→blue forward
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

# [HTTPS 모드] 443 forward blue (Rollback 시 TG 전환)
resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0 # [HTTPS모드] 443→blue forward
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" # 최신 TLS 정책
  certificate_arn   = var.dns_provider == "none" ? aws_acm_certificate.cert[0].arn : one(aws_acm_certificate_validation.cert[*].certificate_arn)

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  # Rollback 전환은 운영 중 TG 변경 → default_action 변경 무시
  lifecycle {
    ignore_changes = [default_action] # ★ 런타임 TG 전환 보존
  }
}