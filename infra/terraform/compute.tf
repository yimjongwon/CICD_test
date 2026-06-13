# =============================================================
# compute.tf — NAT instance / Bastion / App ASG(Blue·Green) / DB
# AMI: Amazon Linux 2023 (SSM 파라미터로 최신 조회)
# Bastion = Tailscale 서브넷 라우터, App = Swarm 노드
# 파일위치 : ~/project2-security/infra/terraform/compute.tf
# =============================================================

# ── SSH 키페어 (Terraform이 생성·관리) ────────────────────
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kp" {
  key_name   = "${var.project}-key" # lb-key
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "ssh_key" {
  filename        = "${path.module}/${var.project}-key.pem"
  content         = tls_private_key.pk.private_key_pem
  file_permission = "0600"
}

# ── 최신 AMI (Amazon Linux 2023) ──────────────────────────
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ── NAT instance (비용 절감: NAT GW 대신 t3.micro) ────────
resource "aws_instance" "nat" {
  ami                         = data.aws_ssm_parameter.al2023.value # AL2023 재사용
  instance_type               = var.nat_instance_type
  subnet_id                   = aws_subnet.public_subnet[0].id
  vpc_security_group_ids      = [aws_security_group.nat_sg.id]
  associate_public_ip_address = true
  source_dest_check           = false
  key_name                    = aws_key_pair.kp.key_name
  user_data_replace_on_change = true # ★ user_data 변경 시 인스턴스 자동 교체

  user_data = <<-EOF
    #!/bin/bash
    set -uxo pipefail
    exec > >(tee -a /var/log/user_data_nat.log) 2>&1

    # ★ AL2023는 iptables 미설치 → 반드시 먼저 설치 (iptables-services는 불필요)
    dnf install -y iptables

    # IP 포워딩 활성화
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-nat.conf
    sysctl -p /etc/sysctl.d/99-nat.conf

    # 현재 부팅 즉시 적용 (단일 NIC라 -o 생략 = egress IF 자동 선택, ens5/eth0 무관)
    iptables -P FORWARD ACCEPT
    iptables -t nat -A POSTROUTING -s ${var.vpc_cidr} -j MASQUERADE
    iptables -t mangle -A FORWARD -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

    # 재부팅 시 재적용 (iptables-services 대체용 oneshot, 중복 방지 -C||-A)
    cat <<'SYSTEMD' > /etc/systemd/system/nat.service
    [Unit]
    Description=NAT Instance MASQUERADE
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/sbin/iptables -P FORWARD ACCEPT
    ExecStart=/sbin/iptables -I FORWARD -j ACCEPT
    ExecStart=/bin/bash -c '/usr/sbin/iptables -t nat -C POSTROUTING -s ${var.vpc_cidr} -j MASQUERADE 2>/dev/null || /usr/sbin/iptables -t nat -A POSTROUTING -s ${var.vpc_cidr} -j MASQUERADE'
    ExecStart=/usr/sbin/iptables -t mangle -A FORWARD -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

    [Install]
    WantedBy=multi-user.target
    SYSTEMD

    systemctl daemon-reload
    systemctl enable nat.service
  EOF

  tags = { Name = "${var.project}-nat" } # lb-nat
}

# 프라이빗(App) 0.0.0.0/0 → NAT instance
resource "aws_route" "app_nat" {
  route_table_id         = aws_route_table.app_rt.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

# 프라이빗(DB) 0.0.0.0/0 → NAT instance (egress-only)
resource "aws_route" "db_nat" {
  route_table_id         = aws_route_table.db_rt.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

# =============================================================
# compute.tf 파일 내부의 Bastion 블록 교체본
# =============================================================

# ── Bastion (public, Tailscale 서브넷 라우터) ─────────────
resource "aws_instance" "bastion" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public_subnet[0].id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.kp.key_name
  source_dest_check           = false # ← 서브넷 라우터 가동을 위한 필수 설정

  user_data = <<-EOF
    #!/bin/bash
    # 로그 파일 생성 및 모든 출력 기록
    exec > >(tee -a /var/log/user_data_tailscale.log) 2>&1
    
    # 1. 호스트네임 및 시스템 기본 설정
    hostnamectl set-hostname "${var.project}-bastion"
    
    # 외부망 통신 대기
    until ping -c 1 8.8.8.8 &> /dev/null; do sleep 5; done
    
    # Tailscale 설치 및 서비스 가동
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
    
    # IP 포워딩 활성화 (서브넷 라우팅 필수 커널 파라미터)
    cat <<EOT > /etc/sysctl.d/99-tailscale.conf
    net.ipv4.ip_forward = 1
    net.ipv6.conf.all.forwarding = 1
    EOT
    sysctl -p /etc/sysctl.d/99-tailscale.conf
    
    # Tailscale 가상망 조인 및 AWS VPC 라우트 광고
    tailscale up --authkey=${tailscale_tailnet_key.ec2_join.key} \
      --advertise-routes=${var.vpc_cidr} --accept-routes \
      --hostname=${var.project}-bastion
      
    # Docker Engine 기본 설치
    dnf install -y docker && systemctl enable --now docker
  EOF

  tags = { Name = "${var.project}-bastion" }
}

# ── App Launch Template (Blue/Green 공용 베이스) ──────────
resource "aws_launch_template" "app" {
  name_prefix = "${var.project}-app-"
  # 비우면 SSM 최신 AL2023(공유 기본), app_ami_id 채우면 Packer AMI(데모 가속, 선택)
  image_id      = var.app_ami_id != "" ? var.app_ami_id : data.aws_ssm_parameter.al2023.value
  instance_type = var.app_instance_type
  key_name      = aws_key_pair.kp.key_name

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  # 최소 부트스트랩(Docker). 앱 배포는 B/C 트랙이 Ansible/Actions 로 수행.
  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -uxo pipefail
    # 로그 파일 생성 및 모든 출력 기록
    exec > >(tee -a /var/log/user_data_app.log) 2>&1

    # 1) Tailscale 노드 가입 (node-to-node, accept-routes=false)
    #    네트워크 egress 준비될 때까지 설치 재시도 + IMDSv2 토큰 재시도 (early-boot 안전)
    dnf install -y iptables
    until curl -fsSL https://tailscale.com/install.sh | sh; do sleep 3; done
    systemctl enable --now tailscaled
    until TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 300"); do sleep 2; done
    IID=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/instance-id)
    HN="${var.project}-app-$IID"
    tailscale up \
      --authkey=${tailscale_tailnet_key.app_join.key} \
      --accept-routes=false \
      --hostname="$HN" \
      --ssh                       # 선택: tailscale ssh break-glass (ACL ssh 섹션 필요)

    # 2) 도커 엔진 기본 설치
    dnf update -y
    dnf install -y docker && systemctl enable --now docker

    # 3) Nginx와 app이 서로 통신할 가상 브리지 네트워크 구축
    # docker network create lockbank-net || true

    # 4) [App 컨테이너 가동] 이름을 lockbank-app으로 단일화하고 가상망 탑승 및 DB 환경변수 주입
    docker pull ${var.app_image} || true
    docker run -d --restart=always \
      # --net lockbank-net \
      --name lockbank-app \
      -p 8080:8080 \
      -e DB_HOST_MAIN="${aws_instance.db.private_ip}" \
      -e DB_HOST_REPLICA="${var.db_host_replica}" \
      -e DB_USER="${var.db_user}" \
      -e DB_PASSWORD="${var.db_password}" \
      -e DB_NAME="${var.db_name}" \
       ${var.app_image}

    # 5) 익스포터 — ★0.0.0.0 바인딩이어야 100.x로 긁힘 (B 트랙)
    docker run -d --restart=always --net=host --name node-exporter \
      quay.io/prometheus/node-exporter
  USERDATA
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project}-app" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── App ASG : Blue ────────────────────────────────────────
resource "aws_autoscaling_group" "blue" {
  name                      = "${var.project}-asg-blue"
  min_size                  = var.asg_min
  max_size                  = var.asg_max
  desired_capacity          = var.asg_desired
  vpc_zone_identifier       = aws_subnet.app_subnet[*].id
  target_group_arns         = [aws_lb_target_group.blue.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 90 # ← 이 줄 추가 (교체 인스턴스 부팅 여유, 데모용 90s)

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Color"
    value               = "blue"
    propagate_at_launch = true
  }

  depends_on = [aws_route.app_nat]
}

# ── App ASG : Green (초기 desired=0, 전환 시 확장) ────────
resource "aws_autoscaling_group" "green" {
  name                      = "${var.project}-asg-green"
  min_size                  = 0
  max_size                  = var.asg_max
  desired_capacity          = 0
  vpc_zone_identifier       = aws_subnet.app_subnet[*].id
  target_group_arns         = [aws_lb_target_group.green.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 90 # ◀ 이 줄을 추가하여 초기 컨테이너 구동 시간 확보
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Color"
    value               = "green"
    propagate_at_launch = true
  }

  depends_on = [aws_route.app_nat]
}

# ── DB EC2 (PostgreSQL 컨테이너 호스트) ───────────────────
resource "aws_instance" "db" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.db_subnet[0].id
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  key_name               = aws_key_pair.kp.key_name
  iam_instance_profile   = aws_iam_instance_profile.db.name

  user_data = <<-EOF
    #!/bin/bash
    exec > >(tee -a /var/log/user_data_tailscale.log) 2>&1
    hostnamectl set-hostname "${var.project}-db"
    until ping -c 1 -w 1 8.8.8.8 &> /dev/null; do sleep 3; done
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
    tailscale up --authkey=${tailscale_tailnet_key.ec2_join.key} \
      --accept-routes=false --hostname=${var.project}-db
    dnf install -y docker && systemctl enable --now docker
  EOF

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${var.project}-db" }

  depends_on = [aws_route.db_nat]
}