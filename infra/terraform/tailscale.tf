# =============================================================
# tailscale.tf — Tailscale 가입키 + 기기/라우트 자동 승인 
#  Bastion=서브넷 라우터(VPC 광고) / DB=노드(복제 직결용)
#  파일위치 : ~/project2-security/infra/terraform/tailscale.tf
# =============================================================

# EC2 공통 가입키 (preauthorized=자동승인, reusable=재생성 대비)
resource "tailscale_tailnet_key" "ec2_join" {
  reusable      = true  # 한 키로 여러 기기(bastion·db) 가입
  ephemeral     = false # 가입 기기는 영구(오프라인돼도 tailnet에 유지)
  preauthorized = true  # 자동 승인 (콘솔 수동 승인 없이 바로 합류)
  description   = "${var.project} EC2 join key"
}

# Bastion 기기 대기 → 광고한 VPC 라우트 자동 승인
# 테라폼이 기기를 찾고 라우팅을 승인하는 부분
data "tailscale_device" "bastion_device" {
  hostname   = "${var.project}-bastion" # user_data의 --hostname과 일치해야
  wait_for   = "180s"                   # 기기가 tailnet에 뜰 때까지 최대 180초 대기
  depends_on = [aws_instance.bastion]
}

# vpc 로 가는 길 뚫어 주기
resource "tailscale_device_subnet_routes" "approve_vpc_routes" {
  device_id = data.tailscale_device.bastion_device.id
  routes    = [var.vpc_cidr] # bastion이 광고한 VPC 경로를 tailnet에서 승인
}

# DB 기기 대기 (복제용 100.x IP 확보 → outputs 로 노출)
data "tailscale_device" "db_device" {
  hostname   = "${var.project}-db"
  wait_for   = "300s"                              # 180 → 300 (NAT 교체+DB 복구 시간 확보)        
  depends_on = [aws_instance.db, aws_instance.nat] # ★ aws_instance.nat 추가
}

# App ASG 전용 ephemeral 가입키 (스케일인 시 tailnet에서 자동 삭제)
resource "tailscale_tailnet_key" "app_join" {
  reusable      = true        # ASG 전 인스턴스가 한 키로 가입
  ephemeral     = true        # ★ 오프라인(스케일인) 시 노드 자동 제거 → 찌꺼기 0
  preauthorized = true        # 콘솔 수동 승인 없이 합류
  tags          = ["tag:app"] # ★ 이 키로 가입한 기기엔 tag:app 자동 부여 → ACL·디스커버리 필터
  description   = "${var.project} App ASG ephemeral join key"
}