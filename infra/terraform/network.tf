# =============================================================
# network.tf — VPC / 서브넷(멀티-AZ) / IGW / 라우팅
# 프라이빗 0.0.0.0/0 → NAT instance 경로는 compute.tf 에서 추가
# 파일위치 : ~/project2-security/infra/terraform/network.tf
# =============================================================

locals {
  # az 끝 글자 추출: "ap-northeast-2a" → "a"
  az_suffix = [for az in var.azs : replace(az, var.aws_region, "")]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" } # lb-vpc
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" } # lb-igw
}

# --- 서브넷 ---
resource "aws_subnet" "public_subnet" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = { # lb-public-a / lb-public-c
    Name = "${var.project}-public-${local.az_suffix[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "app_subnet" {
  count             = length(var.app_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = { # lb-app-a / lb-app-c
    Name = "${var.project}-app-${local.az_suffix[count.index]}"
    Tier = "app"
  }
}

resource "aws_subnet" "db_subnet" {
  count             = length(var.db_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = { # lb-db-a
    Name = "${var.project}-db-${local.az_suffix[count.index]}"
    Tier = "db"
  }
}

# --- 퍼블릭 라우팅 (IGW) ---
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.project}-public-rt" } # lb-public-rt
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public_subnet)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# --- 프라이빗(App) 라우팅: NAT instance 경유 ---
# 0.0.0.0/0 → NAT 경로는 compute.tf 에서 aws_route 로 추가 (NAT instance 생성 후)
resource "aws_route_table" "app_rt" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-app-rt" } # lb-app-rt
}

resource "aws_route_table_association" "app_assoc" {
  count          = length(aws_subnet.app_subnet)
  subnet_id      = aws_subnet.app_subnet[count.index].id
  route_table_id = aws_route_table.app_rt.id
}

# --- 프라이빗(DB) 라우팅 ---
# 인바운드 인터넷 없음(보안 격리). 아웃바운드만 compute.tf db_nat 로 NAT 경유(egress-only)
# App→DB 통신은 VPC 내장 local 경로 + SG(5432←App) 로 처리
resource "aws_route_table" "db_rt" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-db-rt" } # lb-db-rt
}

resource "aws_route_table_association" "db_assoc" {
  count          = length(aws_subnet.db_subnet)
  subnet_id      = aws_subnet.db_subnet[count.index].id
  route_table_id = aws_route_table.db_rt.id
}