terraform {
    required_version = "~>1.14.0"
    required_providers {
      aws = {
            source = "hashicorp/aws"
            version = "~> 6.0" 
      }
    }
}

# 1. provider 설정
provider "aws" {
    region = "ap-northeast-2" # 서울 리전
}

# 2. vpc 및 네트워크 생성 (인프라 기초 공식)
resource "aws_vpc" "main" {
    cidr_block              = "10.0.0.0/16"
    enable_dns_hostnames    = true
    tags = { Name           = "lecture-vpc" }
}

# 인터넷 게이트 웨이
resource "aws_internet_gateway" "igw" {
    # 위에서 만들어진 vpc
    vpc_id          = aws_vpc.main.id
    tags = { Name   = "lecture-igw" }
}

# 현재 리전에서 사용가능한(available) 가용 영역 데이터 가져오기
data "aws_availability_zones" "available" {
    state = "available"
}

# public subnet
resource "aws_subnet" "public_subnet" {
    vpc_id                  = aws_vpc.main.id
    cidr_block              = "10.0.1.0/24" # 256개의 ip를 이방에 할당
    
    # data.aws_availability_zones.available.names 는 배열인데 거기에는 여러개의 가용영역 데이터가 들어있다.    
    # 그중에서 0번 방에 있는 데이터를 연결한다
    availability_zone       = data.aws_availability_zones.available.names[0]
    
    map_public_ip_on_launch = true  # 이방에 생기는 서버는 무조건 공인 ip받는다. 
    
    tags = {
        Name = "lecture-subnet"
    }
}

# 라우팅 테이블 : 트레픽 이정표
resource "aws_route_table" "public_rt" {
    # 어떤 vpc의 소속인지 설정
    vpc_id = aws_vpc.main.id
    # 라우팅 규칙 (0.0.0.0/0)으로 가는 트래픽은 인터넷게이트(igw) 웨이로 보내라
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }

}

# public subnet 을 위의 라우팅 테이블로 연결
resource "aws_route_table_association" "a" {
    subnet_id       = aws_subnet.public_subnet.id # 우리가 만든 퍼블릿 서브넷은
    route_table_id  = aws_route_table.public_rt.id # 위에서 만든 라우팅 테이블로 연결
}

# pem 파일 관련 작업
resource "tls_private_key" "pk" {
    algorithm = "RSA"
    rsa_bits = 4096
}

# 키등록
resource "aws_key_pair" "kp" {
    key_name    = "lecture-key"
    public_key  = tls_private_key.pk.public_key_openssh
}

# 개인키를 가져오기
# 'local_file' resource 를 이용하면 파일을 생성할 수 있다.
resource "local_file" "ssh_key" {
    # ${path.module}은 현재 실행경로를 의미한다.
    filename        = "${path.module}/lecture-key.pem"
    content         = tls_private_key.pk.private_key_pem
    file_permission = "0600" # 파일 권한 설정
}

# 보안그룹
resource "aws_security_group" "ssh_sg" {
    # 보안 그룹의 이름은 겹치지 않게 유일하게 식별되는 이름을 지어야 한다.
    name    = "allow-ssh"
    vpc_id  = aws_vpc.main.id

    # 밖에서 안으로 들어오는 규칙 ingress
    ingress {
        from_port   = 22           
        to_port     = 22            
        protocol    = "tcp"       
        cidr_blocks = ["0.0.0.0/0"] 
    }

    # 밖에서 안으로 들어오는 규칙 ingress
    ingress {
        from_port   = 5432            
        to_port     = 5432            
        protocol    = "tcp"         
        cidr_blocks = ["0.0.0.0/0"] 
    }

    # 안에서 밖으로 나가는 규칙 egress
    egress {
        from_port   = 0             # 0번부터
        to_port     = 0             # 0번까지 (모든 포트)
        protocol    = "-1"          # 모든 프로토콜
        cidr_blocks = ["0.0.0.0/0"]
    }

}

# ec2 에 설치할 amazon linux 최신 이미지 검색
data "aws_ami" "latest_al2023" {
    most_recent = true
    owners      = ["amazon"]
    filter {
        name    = "name"
        values  = ["al2023-ami-*-x86_64"] # 이름이 이렇게 시작하는 것들 중에서 최신 이미지 검색
    }
}

# ec2 만들기
resource "aws_instance" "my_ec2" {
    ami                     = data.aws_ami.latest_al2023.id # 검색된 최신 os 이미지 id
    instance_type           = "t3.micro"                    # 서버사양
    subnet_id               = aws_subnet.public_subnet.id   # 위에서 미리 준비한 public subnet id
    vpc_security_group_ids  = [aws_security_group.ssh_sg.id]   # 보안그룹 (여러개 등록할 수 있다)
    key_name                = aws_key_pair.kp.key_name      # 위에서 미리 준비한 key pair 이름
    tags = {
        Name = "my-ec2"
    }
}

# 생성된 ec2의 public ip 를 출력
output "instance_public_ip" {
    description = "만들어진 ec2의 public ipv4 주소"
    value = aws_instance.my_ec2.public_ip
}

# 생성된 ec2의 private ip 를 출력
output "instance_private_ip" {
    description = "만들어진 ec2의 private ipv4 주소"
    # .private_ip 하면 참조가 가능
    value = aws_instance.my_ec2.private_ip
}

# public ip 를 이용해서 inventory.yml 파일 만들기
resource "local_file" "ansible_inventory" {
    # 파일의 경로와 파일명
    filename = "${path.module}/inventory.yml"
    # 파일의 내용을 map 객체를 이용해서 구성하기
    content = yamlencode({
        all = {
            hosts = {
                "${aws_instance.my_ec2.public_ip}" = {
                    ansible_user = "ec2-user"
                    ansible_ssh_private_key_file = "${path.module}/lecture-key.pem"
                }
            }
        }
    })
}

# ansible.cfg 파일 생성
resource "local_file" "ansible_config" {
    filename = "${path.module}/ansible.cfg"
    # inventory 파일의 경로와 ssh 보안 확인(Host key Checking)을 자동으로 설정
    content = <<-EOF
        [defaults]
        inventory = ./inventory.yml
        host_key_checking = False
    EOF
}

# 1. 인프라 생성후 ansible play book 을 실행 가능한 시간 만큼 대기한다.
resource "terraform_data" "wait_for_instance" {
    # 서버, 인벤토리, 설정 파일이 모두 준비된 이후에 이 블럭이 실행되도록 순서 보장
    depends_on = [aws_instance.my_ec2, local_file.ansible_inventory, local_file.ansible_config]

    # ec2 인스턴스의 id가 변경된다면 다시 대기 실행하도록 방아쇠를 설치한다 ()
    # 즉 ec2가 새롭게 만들어지면 이블럭이 다시 실행되고 결과적으로 sleep 30 이 다시 실행된다. 
    triggers_replace = aws_instance.my_ec2.id

    # local computer (rocky linux)에서 실행할 명령
    provisioner "local-exec" {
        command = "sleep 30"
    }
}

# 2. ansible 플레이북 실행
resource "terraform_data" "ansible_run" {
    depends_on = [ terraform_data.wait_for_instance ]

    # ec2가 바뀔때 또다시 ansible playbook을 실행하도록 여기에 방아쇠를 걸어 놓는다.
    triggers_replace = {
        instance_id = aws_instance.my_ec2.id
        always_run = "${timestamp()}" # 실행할때 마다 시간이 달라지므로 무조건 플레이북이 실행된다.
    }

    provisioner "local-exec" {
        # DB 설치하고 파일 copy 하고 권한변경이 잦고 하면 에러가 날 수 있기 때문에 안정적으로 실행하기 위해
        # ANSIBLE_SSH_PIPELINING=1 라는 임시 환경 변수를 추가한다.
        # 해당 환경변수는 ansible playbook이 실행될때에 한해서 ansible이 사용하는 일시적인 환경변수
        command = "ANSIBLE_SSH_PIPELINING=1 ansible-playbook site.yml"
    }
}

