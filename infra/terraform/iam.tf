# =============================================================
# iam.tf — IAM 역할/정책
#  1) DB EC2 → S3(pg_dump) 업로드 권한 (인스턴스 프로파일)
#  2) Grafana(온프레) → CloudWatch 읽기 전용 (D 트랙 datasource)
# 파일위치 : ~/project2-security/infra/terraform/iam.tf
# =============================================================

# ── 1) DB EC2 instance profile (compute.tf 의 db 가 참조) ──
resource "aws_iam_role" "db" {
  name = "${var.project}-db-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "db_s3" {
  name = "${var.project}-db-s3"
  role = aws_iam_role.db.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.db_backup.arn,
        "${aws_s3_bucket.db_backup.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "db" {
  name = "${var.project}-db-profile"
  role = aws_iam_role.db.name
}

# ── 2) Grafana CloudWatch 읽기 전용 사용자 (D 트랙 전달용) ──
# 유저(외부 앱 대표)
resource "aws_iam_user" "grafana_cw" {
  name = "${var.project}-grafana-cloudwatch"
}
# CloudWatch 읽기 전용
resource "aws_iam_user_policy" "grafana_cw" {
  name = "${var.project}-grafana-cw-read"
  user = aws_iam_user.grafana_cw.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "cloudwatch:DescribeAlarms",
        "ec2:DescribeInstances",
        "tag:GetResources"
      ]
      Resource = "*"
    }]
  })
}
# 액세스 키(id+secret)
resource "aws_iam_access_key" "grafana_cw" {
  user = aws_iam_user.grafana_cw.name
}