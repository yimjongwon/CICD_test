# 상태 관리
terraform {
    required_version = ">= 1.14.0" # github action 에서 에러나지 않게 일부 수정
    required_providers {
      aws = {
            source  = "hashicorp/aws"
            version = "~> 6.0" 
      }
    }
    # terraform 상태 관리를 위한 remote 백엔드 설정
    backend "s3" {
        # 비워둔 값은 외부 파일(backend.hcl)에서 채우기
        bucket              = ""                                # 미리 생성한 s3 버킷의 이름
        key                 = "lock-and-lock/terraform.tfstate" # /lock-and-lock/하위에 만들어 지도록
        region              = "ap-northeast-2"
        dynamodb_table      = ""                                # 미리 준비된 dynamodb 테이블의 이름을 명시하면 lock 상태가 자동으로 관리된다.
        encrypt             = true                              # tfstate에는 민감한 정보가 있을 수 있기 때문에 암호화
    }
}


# 파일 위치: ./infra/terraform/main.tf

provider "aws" {
  region = "ap-northeast-2"
}

# 기본 VPC 및 퍼블릭 서브넷 (기존에 있다면 data 소스로 대체 가능)
resource "aws_vpc" "mini_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "mini-vpc" }
}

resource "aws_subnet" "public_sub" {
  vpc_id                  = aws_vpc.mini_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-2a"
  tags                    = { Name = "mini-public-subnet" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.mini_vpc.id
  tags   = { Name = "mini-igw" }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.mini_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.public_sub.id
  route_table_id = aws_route_table.rt.id
}

# ── 공통 보안 그룹 ───────────────────────────────────────
resource "aws_security_group" "mini_sg" {
  name   = "mini-sg"
  vpc_id = aws_vpc.mini_vpc.id

  # 앤서블 접속용 SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 테스트 후 본인 IP로 제한 추천
  }

  # Nginx 리버스 프록시 접속용 HTTP 80번 포트 오픈!
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  # FastAPI 접속용
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # PostgreSQL 접속용 (실무에선 DB를 프라이빗에 두고 App SG만 허용하지만, 미니 테스트용으로 오픈)
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── 최신 Amazon Linux 2023 AMI 조회 ─────────────────────
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ── 1번만 실행할 핵심 기반 세팅 (User Data) ───────────────
locals {
  docker_userdata = <<-EOF
    #!/bin/bash
    dnf install -y docker
    systemctl enable --now docker
  EOF
}

# ── App 인스턴스 ──────────────────────────────────────────
resource "aws_instance" "app_server" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_sub.id
  vpc_security_group_ids = [aws_security_group.mini_sg.id]
  key_name               = "lb-key" # 본인의 AWS Key Pair 이름 입력
  user_data              = local.docker_userdata

  tags = { Name = "mini-app-server" }
}

# ── DB 인스턴스 ───────────────────────────────────────────
resource "aws_instance" "db_server" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_sub.id
  vpc_security_group_ids = [aws_security_group.mini_sg.id]
  key_name               = "lb-key" # 본인의 AWS Key Pair 이름 입력
  user_data              = local.docker_userdata

  tags = { Name = "mini-db-server" }
}

# 앤서블 인벤토리에 적어넣을 Public IP 출력구문
output "app_public_ip" { value = aws_instance.app_server.public_ip }
output "db_public_ip"  { value = aws_instance.db_server.public_ip }


# ── 기존 main.tf 맨 아래에 추가 ──────────────────────────

resource "local_file" "ansible_inventory" {
  # 생성될 앤서블 hosts 파일의 경로를 지정합니다.
  filename = "${path.module}/../ansible/hosts" 

  # 파일에 들어갈 내용을 템플릿 형태로 작성합니다.
  content = <<-EOT
    [app]
    app_server ansible_host=${aws_instance.app_server.public_ip} ansible_user=ec2-user ansible_ssh_common_args='-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'

    [db]
    db_server ansible_host=${aws_instance.db_server.public_ip} ansible_user=ec2-user ansible_ssh_common_args='-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'
  EOT

  # 인스턴스가 다 켜지고 IP가 완전히 확정된 후에 파일이 써지도록 안전장치를 겁니다.
  depends_on = [
    aws_instance.app_server,
    aws_instance.db_server
  ]
}

