# =============================================================
# storage.tf — S3 (DB pg_dump 백업)
# 구현방안1(Terraform 범위에 S3) + 구현방안3(pg_dump→S3) 반영
# 파일위치 : ~/project2-security/infra/terraform/storage.tf
# =============================================================

# 계정 ID 조회 → 버킷명 전역 고유화
data "aws_caller_identity" "me" {}

# 백업 버킷
resource "aws_s3_bucket" "db_backup" {
  bucket        = "${var.project}-db-backup-${data.aws_caller_identity.me.account_id}"
  force_destroy = true # 데모: destroy 시 백업까지 정리(백업은 재생성 가능). 운영이면 false
  tags          = { Name = "${var.project}-db-backup" }
}

# 버저닝 Enabled — 백업 덮어쓰기/실수 대비
resource "aws_s3_bucket_versioning" "db_backup" {
  bucket = aws_s3_bucket.db_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 퍼블릭 전면 차단
resource "aws_s3_bucket_public_access_block" "db_backup" {
  bucket                  = aws_s3_bucket.db_backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# AES256 저장 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "db_backup" {
  bucket = aws_s3_bucket.db_backup.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ======================================================================
# storage.tf 파일 내부의 수명주기 설정 블록 교체본 (예시)
# ======================================================================
# 7일 만료 + 구버전 7일 만료
resource "aws_s3_bucket_lifecycle_configuration" "db_backup_policy" {
  bucket = aws_s3_bucket.db_backup.id

  rule {
    id     = "db-backup-retention"
    status = "Enabled"

    # ◀ 이 자리에 빈 filter 블록을 추가하여 버킷 전체 적용임을 명시합니다.
    filter {}
    # 데모/과제 요건에 맞게 일수 설정 (예: 7일 후 자동 삭제)
    expiration { days = 7 }
    # 구버전도 7일 후 삭제
    noncurrent_version_expiration { noncurrent_days = 7 }
  }
}