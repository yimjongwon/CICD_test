#!/bin/bash
# =============================================================
# 파일위치 : ~/project2-security/setup.sh
# 팀 프로젝트 환경 설정 스크립트 (Lock & Lock)
# 대상 OS : Rocky Linux 8.x
# 목적    : AWS CLI v2 + Terraform + Ansible + Docker 설치·검증
#           (Tailscale/VXLAN 연결은 bootstrap_tailscale.sh 에서 별도 수행)
# 실행    : bash setup.sh
# =============================================================

set -e  # 오류 발생 시 즉시 중단

# OS 호환성 체크
if [ ! -f /etc/redhat-release ] && [ ! -f /etc/rocky-release ]; then
    echo "❌ 이 스크립트는 Rocky Linux 8 기반 환경만 지원합니다."
    echo "    다른 OS 환경에서는 아래 도구들을 수동으로 설치해 주세요:"
    echo "    - AWS CLI v2 / Terraform / Ansible / Docker"
    exit 1
fi

# ── 색상 출력 함수 ──────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC}   $1"; exit 1; }

echo ""
echo "============================================="
echo "  Lock & Lock 환경 설정 시작"
echo "  Rocky 8 | AWS CLI · Terraform · Ansible · Docker"
echo "============================================="
echo ""

# ── STEP 1 : 기존 설치 확인 ────────────────────────────────
info "STEP 1/6 : 기존 설치 여부 확인 중..."
AWS_INSTALLED=false; TF_INSTALLED=false; ANSIBLE_INSTALLED=false; DOCKER_INSTALLED=false
command -v aws       &>/dev/null && { warning "AWS CLI 이미 설치됨 → 건너뜀";   AWS_INSTALLED=true; }
command -v terraform &>/dev/null && { warning "Terraform 이미 설치됨 → 건너뜀"; TF_INSTALLED=true; }
command -v ansible   &>/dev/null && { warning "Ansible 이미 설치됨 → 건너뜀";   ANSIBLE_INSTALLED=true; }
command -v docker    &>/dev/null && { warning "Docker 이미 설치됨 → 건너뜀";    DOCKER_INSTALLED=true; }

# ── STEP 1.5 : make 설치 ───────────────────────────────────
info "STEP 1.5/6 : make 확인 중..."
if ! command -v make &>/dev/null; then
    sudo dnf install -y make -q || error "make 설치 실패"
    success "make 설치 완료"
else
    info "  make 이미 설치됨"
fi

# ── STEP 2 : AWS CLI v2 ────────────────────────────────────
if [ "$AWS_INSTALLED" = false ]; then
    info "STEP 2/6 : AWS CLI v2 설치 중..."
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    cd "$TMP_DIR"
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" || error "AWS CLI 다운로드 실패"
    sudo dnf install -y unzip -q
    unzip -q awscliv2.zip
    sudo ./aws/install
    cd ~
    rm -rf "$TMP_DIR"
    trap - EXIT
    command -v aws &>/dev/null && success "AWS CLI 설치 완료: $(aws --version 2>&1 | awk '{print $1}')" || error "AWS CLI 설치 실패"
else
    info "STEP 2/6 : AWS CLI 건너뜀"
fi

# ── STEP 2.5 : AWS 자격증명 확인/등록 ──────────────────────
# 동작:
#   - access_key / secret_key / region / output 4개가 모두 있으면 건너뜀
#   - 하나라도 없으면 aws configure 실행하여 입력받음
#   - 개인 계정 키 사용 (팀원 각자), region=ap-northeast-2 권장
info "STEP 2.5/6 : AWS 자격증명 확인..."

AWS_AKID=$(aws configure get aws_access_key_id     2>/dev/null || true)
AWS_SAK=$(aws configure get aws_secret_access_key   2>/dev/null || true)
AWS_REGION=$(aws configure get region               2>/dev/null || true)
AWS_OUTPUT=$(aws configure get output               2>/dev/null || true)

if [ -n "$AWS_AKID" ] && [ -n "$AWS_SAK" ] && [ -n "$AWS_REGION" ] && [ -n "$AWS_OUTPUT" ]; then
    # 자격증명이 실제로 유효한지까지 한 번 확인
    if aws sts get-caller-identity &>/dev/null; then
        info "  AWS 자격증명 이미 설정됨 (계정 $(aws sts get-caller-identity --query Account --output text), region=$AWS_REGION) → 건너뜀"
    else
        warning "AWS 설정값은 있으나 인증 실패(키 만료/오타 가능) → 재설정"
        echo "    입력값: Access Key / Secret Key / region=ap-northeast-2 / output=json"
        aws configure
    fi
else
    warning "AWS 자격증명 미설정 → aws configure 실행 (개인 키 입력)"
    echo "    입력값: Access Key / Secret Key / region=ap-northeast-2 / output=json"
    aws configure
    # region/output 이 비어 있으면 기본값 보정 (Enter로 건너뛴 경우 대비)
    [ -z "$(aws configure get region 2>/dev/null)" ] && aws configure set region ap-northeast-2
    [ -z "$(aws configure get output 2>/dev/null)" ] && aws configure set output json
fi

# region 이 서울이 아니면 경고
CUR_REGION=$(aws configure get region 2>/dev/null || true)
[ -n "$CUR_REGION" ] && [ "$CUR_REGION" != "ap-northeast-2" ] && \
    warning "현재 region=$CUR_REGION (서울 ap-northeast-2 권장)"

# ── STEP 3 : Terraform ─────────────────────────────────────
if [ "$TF_INSTALLED" = false ]; then
    info "STEP 3/6 : Terraform 설치 중..."
    sudo dnf install -y yum-utils -q
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo -q || true
    sudo dnf install -y terraform -q
    command -v terraform &>/dev/null && { success "Terraform 설치 완료: $(terraform -version | head -1)"; terraform -install-autocomplete 2>/dev/null || true; } || error "Terraform 설치 실패"
else
    info "STEP 3/6 : Terraform 건너뜀"
fi

# ── STEP 4 : Ansible ───────────────────────────────────────
if [ "$ANSIBLE_INSTALLED" = false ]; then
    info "STEP 4/6 : Ansible 설치 중..."
    sudo dnf install -y epel-release -q
    sudo dnf install -y ansible -q
    command -v ansible &>/dev/null && success "Ansible 설치 완료: $(ansible --version | head -1)" || error "Ansible 설치 실패"
else
    info "STEP 4/6 : Ansible 건너뜀"
fi

# ── STEP 5 : Docker (project2 신규) ────────────────────────
if [ "$DOCKER_INSTALLED" = false ]; then
    info "STEP 5/6 : Docker 설치 중..."
    sudo dnf remove -y podman buildah runc 2>/dev/null || true   # Rocky8 충돌 방지(수업: podman buildah)
    sudo dnf install -y yum-utils -q
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo -q 2>/dev/null || true
    sudo dnf makecache -q 2>/dev/null || true                    # 수업 설치법 반영(리포 캐시 갱신)
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -q || error "Docker 설치 실패"
    sudo systemctl enable --now docker
    sudo usermod -aG docker "${SUDO_USER:-$USER}"                # root 오등록 방지
    command -v docker &>/dev/null && success "Docker 설치 완료: $(docker --version)" || error "Docker 설치 실패"
    warning "docker 그룹 적용을 위해 재로그인 또는 'newgrp docker' 필요"
else
    info "STEP 5/6 : Docker 건너뜀"
fi

# ── STEP 5.5 : Docker Hub 로그인 (토큰 파일 자동 생성 + 로그인) ────
# 동작:
#   - ~/.dockerhub_token 이 없거나 값이 비어 있으면 → 입력받아 생성(chmod 600)
#   - 이미 값이 채워져 있으면 → 입력 건너뛰고 그대로 사용
#   - 토큰 발급: hub.docker.com → 계정 아이콘 → Account settings → Personal access tokens
info "STEP 5.5/6 : Docker Hub 로그인 확인..."

# 홈 디렉터리가 아닌 'project2-security 프로젝트 폴더' 내부에 저장
DOCKER_PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERHUB_TOKEN_FILE="${DOCKER_PROJECT_DIR}/.dockerhub_token"
PROJECT_DOCKER_CONFIG="${DOCKER_PROJECT_DIR}/.docker_config"

# 기존 파일이 있으면 먼저 로드
if [ -f "$DOCKERHUB_TOKEN_FILE" ]; then
    # shellcheck disable=SC1090
    source "$DOCKERHUB_TOKEN_FILE"
fi

# 값이 하나라도 비어 있으면 입력받아 (재)생성
if [ -z "${DOCKERHUB_USER:-}" ] || [ -z "${DOCKERHUB_TOKEN:-}" ]; then
    warning "~/.dockerhub_token 미설정 또는 비어 있음 → 개인 토큰 입력"
    echo "    (토큰 발급: hub.docker.com → Account settings → Personal access tokens)"
    read -rp  "    DOCKERHUB_USER (Docker Hub 아이디 입력 후 Enter): " DOCKERHUB_USER
    read -rsp "    DOCKERHUB_TOKEN (dckr_pat_...입력, 키복사 후 마우스 우클릭 후, Enter [화면 미표시]): " DOCKERHUB_TOKEN
    echo ""   # read -s 는 줄바꿈을 안 남기므로 수동 개행

    if [ -z "$DOCKERHUB_USER" ] || [ -z "$DOCKERHUB_TOKEN" ]; then
        warning "입력값이 비어 Docker Hub 로그인을 건너뜁니다 (나중에 재실행 가능)"
    else
       # 파일 생성 + 권한 600 (특수문자 안전 처리를 위해 declare -p 사용)
        declare -p DOCKERHUB_USER DOCKERHUB_TOKEN > "$DOCKERHUB_TOKEN_FILE"
        chmod 600 "$DOCKERHUB_TOKEN_FILE"
        success "~/.dockerhub_token 생성 완료 (chmod 600)"
    fi
else
    info "  ~/.dockerhub_token 이미 설정됨 → 입력 건너뜀 ($DOCKERHUB_USER)"
fi

# 값이 준비됐으면 로그인 시도
export DOCKERHUB_USER DOCKERHUB_TOKEN   # sg 서브셸 참조용
if [ -n "${DOCKERHUB_USER:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]; then
    
    # 프로젝트 폴더 내부에 전용 설정 폴더를 생성
    mkdir -p "$PROJECT_DOCKER_CONFIG"
  
    
    if docker info &>/dev/null; then
        echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin \
            && success "Docker Hub 로그인됨: $DOCKERHUB_USER" \
            || warning "Docker Hub 로그인 실패 → 토큰 확인"
            
    elif id -nG "${SUDO_USER:-$USER}" | grep -qw docker; then
        # 그룹은 추가됐으나 현재 셸 미반영 → sg 로 즉시 적용하여 로그인
        # 2. 그룹은 추가됐으나 현재 셸에 미반영된 상태라면 sg로 즉시 적용하여 로그인
        # ★ 핵심 수정: sg 서브셸 내부에서도 DOCKER_CONFIG 격리 경로를 강제로 지정해 줍니다.
         sg docker -c 'echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin' \
            && success "Docker Hub 로그인됨: $DOCKERHUB_USER" \
            || warning "Docker Hub 로그인 실패 → 재로그인 후 bash setup.sh 재실행"
    else
        warning "docker 권한 미반영 → newgrp docker 후 bash setup.sh 재실행"
    fi
fi

# ── STEP 6 : 최종 검증 ─────────────────────────────────────
info "STEP 6/6 : 설치 결과 최종 검증"
echo ""
echo "  ┌─────────────────────────────────────────┐"
command -v aws       &>/dev/null && echo "  │ ✅ AWS CLI   : $(aws --version 2>&1 | awk '{print $1}')" || echo "  │ ❌ AWS CLI   : 실패"
command -v terraform &>/dev/null && echo "  │ ✅ Terraform : $(terraform -version | head -1)"        || echo "  │ ❌ Terraform : 실패"
command -v ansible   &>/dev/null && echo "  │ ✅ Ansible   : $(ansible --version | head -1)"         || echo "  │ ❌ Ansible   : 실패"
command -v docker    &>/dev/null && echo "  │ ✅ Docker    : $(docker --version)"                    || echo "  │ ❌ Docker    : 실패"
echo "  └─────────────────────────────────────────┘"
echo ""

echo "============================================="
success "환경 설치 완료!"
echo "============================================="
echo ""
echo "  다음 단계:"
echo "   1) docker 그룹 적용:    newgrp docker  (또는 재로그인)"
echo "   2) AWS 자격증명 등록:    aws configure       # 개인 키 / region=ap-northeast-2 / output=json"
echo "   3) Docker Hub : setup.sh 실행 중 입력한 토큰으로 자동 로그인됨 (~/.dockerhub_token)"
echo "   4) Tailscale VPN 연결:   TAILSCALE_AUTHKEY=tskey-auth-xxxx ./bootstrap_tailscale.sh"
echo "        └ (Opt2) Bastion TS IP 확보 후 ENABLE_VXLAN=true 로 재실행하면 VXLAN 오버레이 구성"
echo "   5) 환경 점검:            make check"
echo ""

# ── ★ [수정 핵심부] 스마트 cd 자동 전환 기능 주입 ──────────────────────
if [ -d "$PROJECT_DOCKER_CONFIG" ]; then
    
    # 중복 주입 방지를 위해 함수 고유 주석 존재 여부 검사 후 주입
    if ! grep -qF "# 특정 폴더 진입 시 Docker Config 자동 격리 전환" ~/.bashrc; then
        cat << 'EOF' >> ~/.bashrc

# 특정 폴더 진입 시 Docker Config 자동 격리 전환
cd() {
    builtin cd "$@" || return
    if [[ "$PWD" == *"/project2-security"* ]]; then
        export DOCKER_CONFIG="$(dirname "$0")/.docker_config"
    else
        # 프로젝트 폴더를 벗어나면 격리 환경변수를 해제하여 원래 쓰던 yimjongwon 계정으로 복구
        unset DOCKER_CONFIG
    fi
}
EOF
        success "현재 터미널 세션 및 향후 세션에 스마트 cd 격리 기능 주입 완료!"
    else
        info "이미 .bashrc에 설정이 존재하여 추가하지 않고 건너뜁니다."
    fi
fi

# ── (맨 마지막) docker 그룹 즉시 적용 ──────────────────────
# 설치/키 입력이 모두 끝났고, docker 권한이 아직 현재 셸에 미반영이면
# 새 셸을 띄워 docker 그룹을 즉시 적용한다.
# ⚠️ newgrp 는 "새 셸 진입"이므로 반드시 모든 작업의 맨 끝에 위치해야 함.
# ── 프로젝트 전용 격리 환경 변수 자동 주입 ──────────────────────

if [ -t 0 ] && command -v docker &>/dev/null && ! docker info &>/dev/null \
   && id -nG "${SUDO_USER:-$USER}" | grep -qw docker; then
    info "docker 그룹을 즉시 적용합니다 (새 셸 진입). 종료하려면 'exit' 을 입력 후 Enter를 쳐주세요."
    exec newgrp docker
fi      