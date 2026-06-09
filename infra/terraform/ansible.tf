# =============================================================
# ansible.tf — Ansible 인벤토리/설정 자동 생성 (DB 정적 티어 배포용)
#  ▸ Terraform은 inventory.yml·ansible.cfg "파일만 생성"한다.
#    ansible-playbook 실행은 proj-mgmt에서 `make deploy-db`로 별도 수행.
#  ▸ DB는 Tailscale 노드 → proj-mgmt가 100.x로 직접 접속(bastion 불필요).
#  ▸ ★ 반드시 proj-mgmt 로컬 apply에서 의미 있음:
#     CI 러너는 tailnet에 없어 DB 100.x에 못 닿고, local_file은 apply가
#     도는 곳에 떨어지기 때문. (CI apply 시엔 파일만 생기고 미사용)
#  파일위치 : ~/project2-security/infra/terraform/ansible.tf
# =============================================================

locals {
  db_ts_ip = try(data.tailscale_device.db_device.addresses[0], "")
}

# ── 인벤토리 (DB 정적 타깃) ───────────────────────────────
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory.yml"
  file_permission = "0644"
  content         = <<-EOT
    all:
      children:
        database:
          hosts:
            db:
              ansible_host: ${local.db_ts_ip}
              ansible_user: ec2-user
              ansible_ssh_private_key_file: ${abspath(local_file.ssh_key.filename)}
      vars:
        project: ${var.project}
        db_backup_bucket: ${aws_s3_bucket.db_backup.bucket}
        ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
  EOT
}

# ── ansible.cfg ───────────────────────────────────────────
resource "local_file" "ansible_cfg" {
  filename        = "${path.module}/../ansible/ansible.cfg"
  file_permission = "0644"
  content         = <<-EOT
    [defaults]
    inventory           = ./inventory.yml
    host_key_checking   = False
    retry_files_enabled = False
    interpreter_python  = auto_silent
  EOT
}