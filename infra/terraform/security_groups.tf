# ================================================================
# security_groups.tf — 계층별 SG (최소 권한 원칙)
# ALB → App → DB 단방향, Bastion=SSH 관문, NAT=App 아웃바운드
# 앱은 compose(단일 호스트), Swarm 미사용
# 파일위치 : ~/project2-security/infra/terraform/security_groups.tf
# ================================================================

# ── ALB SG : 인터넷 → 80/443 ──────────────────────────────
resource "aws_security_group" "alb_sg" {
  name        = "${var.project}-alb-sg"
  description = "ALB ingress 80/443 from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.enable_https ? [1] : []
    content {
      description = "HTTPS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-alb-sg" } # lb-alb-sg
}

# ── Bastion SG : 관리자 IP → SSH ──────────────────────────
resource "aws_security_group" "bastion_sg" {
  name        = "${var.project}-bastion-sg"
  description = "Bastion SSH from admin"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ingress_cidr]
  }

  # Tailscale: 인바운드 포트 개방 불필요 (아웃바운드 UDP/443 으로 NAT 통과)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-bastion-sg" } # lb-bastion-sg
}

# ── App SG : ALB → 80, Bastion → SSH ──
resource "aws_security_group" "app_sg" {
  name        = "${var.project}-app-sg"
  description = "App tier: from ALB, Bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-app-sg" } # lb-app-sg
}

# ── DB SG : App → 5432, Bastion → SSH ──
resource "aws_security_group" "db_sg" {
  name        = "${var.project}-db-sg"
  description = "DB tier: PostgreSQL from App only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from App"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-db-sg" } # lb-db-sg
}

# ── NAT instance SG : App 서브넷 → 인터넷 중계 ─────────────
resource "aws_security_group" "nat_sg" {
  name        = "${var.project}-nat-sg"
  description = "NAT instance: forward private subnet egress"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "from app subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    # DB의 S3 백업·패키지 업데이트 egress 통로
    cidr_blocks = concat(var.app_subnet_cidrs, var.db_subnet_cidrs)
  }

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-nat-sg" } # lb-nat-sg
}