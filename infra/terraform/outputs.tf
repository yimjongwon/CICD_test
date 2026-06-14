# =============================================================
# outputs.tf — 타 트랙 인터페이스 (E파트 "A가 줘야 할 것")
# 파일위치 : ~/project2-security/infra/terraform/outputs.tf
# =============================================================

output "alb_dns_name" {
  description = "ALB DNS (B·C·E: 서비스 접근/배포 검증)"
  value       = aws_lb.web_alb.dns_name
}

output "service_domain" {
  description = "서비스 도메인 (enable_https=true 시)"
  value       = var.enable_https ? var.domain_name : "N/A (HTTP only)"
}

output "tg_blue_arn" {
  description = "Blue Target Group ARN (C·E: Rollback 전환)"
  value       = aws_lb_target_group.blue.arn
}

output "tg_green_arn" {
  description = "Green Target Group ARN (C·E: 배포 성공 시 전환)"
  value       = aws_lb_target_group.green.arn
}

output "bastion_public_ip" {
  description = "Bastion 공인 IP (SSH 관문)"
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Bastion 사설 IP"
  value       = aws_instance.bastion.private_ip
}

output "db_private_ip" {
  description = "DB EC2 사설 IP (B·D)"
  value       = aws_instance.db.private_ip
}

output "nat_public_ip" {
  description = "NAT instance 공인 IP"
  value       = aws_instance.nat.public_ip
}

output "sg_ids" {
  description = "Security Group ID 모음 (전 트랙 참조)"
  value = {
    alb     = aws_security_group.alb_sg.id
    app     = aws_security_group.app_sg.id
    db      = aws_security_group.db_sg.id
    bastion = aws_security_group.bastion_sg.id
    nat     = aws_security_group.nat_sg.id
  }
}

output "asg_names" {
  description = "Blue/Green ASG 이름 (C: 배포 대상)"
  value = {
    blue  = aws_autoscaling_group.blue.name
    green = aws_autoscaling_group.green.name
  }
}

# bastion_ts_ip : Tailscale 가입 후 동적 할당 → apply 후 bastion 에서 확인
# (terraform 으로는 못 잡으므로 별도 output 없음. bootstrap_tailscale.sh 참조)

output "db_backup_bucket" {
  description = "pg_dump 백업 S3 버킷 (DB 백업 스크립트)"
  value       = aws_s3_bucket.db_backup.bucket
}

output "alerts_sns_arn" {
  description = "CloudWatch 알람 SNS 토픽 ARN (D: 알림 연동)"
  value       = aws_sns_topic.alerts.arn
}

output "grafana_cw_access_key_id" {
  description = "Grafana CloudWatch datasource Access Key ID (D 전달)"
  value       = aws_iam_access_key.grafana_cw.id
}

output "grafana_cw_secret_access_key" {
  description = "Grafana CloudWatch datasource Secret (D 전달) — terraform output -raw 로 확인"
  value       = aws_iam_access_key.grafana_cw.secret
  sensitive   = true
}

output "db_tailscale_ip" {
  description = "DB Tailscale IP (proj-mgmt replica 가 이 100.x:5432 로 복제)"
  value       = data.tailscale_device.db_device.addresses
}