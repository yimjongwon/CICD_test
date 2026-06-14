#!/bin/bash
# =============================================================
# 파일위치 : ~/project2-security/check.sh
# 환경·자격증명·연결 상태 확인 (Lock & Lock)
# 실행 : bash check.sh  또는  make check
# =============================================================

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
fail() { echo -e "  ${RED}❌ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }

echo ""
echo "============================================="
echo "  Lock & Lock 환경 상태 확인"
echo "============================================="
echo ""

# ── 1. 필수 도구 ───────────────────────────────────────────
echo "[ 1 ] 필수 도구 설치 확인"
command -v aws       &>/dev/null && ok "AWS CLI : $(aws --version 2>&1 | awk '{print $1}')"  || fail "AWS CLI 미설치 → bash setup.sh"
command -v terraform &>/dev/null && ok "Terraform : $(terraform -version | head -1)"          || fail "Terraform 미설치 → bash setup.sh"
command -v ansible   &>/dev/null && ok "Ansible : $(ansible --version | head -1)"             || fail "Ansible 미설치 → bash setup.sh"
command -v docker    &>/dev/null && ok "Docker : $(docker --version)"                         || fail "Docker 미설치 → bash setup.sh"
echo ""

# ── 2. Docker 데몬·권한·로그인 ─────────────────────────────
echo "[ 2 ] Docker 상태 확인"
if command -v docker &>/dev/null; then
    if systemctl is-active --quiet docker 2>/dev/null; then
        ok "docker 데몬 실행 중"
    else
        fail "docker 데몬 미실행 → sudo systemctl start docker"
    fi
    if docker info &>/dev/null; then
        ok "현재 사용자로 docker 사용 가능"
    else
        warn "docker 권한 없음 → newgrp docker 또는 재로그인 필요"
    fi
    DOCKER_USER=$(docker info 2>/dev/null | grep "Username:" | awk '{print $2}')
    if [ -n "$DOCKER_USER" ]; then
        ok "Docker Hub 로그인됨: $DOCKER_USER"
    else
        warn "Docker Hub 미로그인 → ~/.dockerhub_token 설정 후 bash setup.sh (또는 docker login)"
    fi
fi
echo ""

# ── 3. AWS 자격증명 (개인 계정) ────────────────────────────
echo "[ 3 ] AWS 자격증명 확인"
if ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
    REGION=$(aws configure get region)
    ok "자격증명 유효 (계정 $ACCOUNT)"
    [ "$REGION" = "ap-northeast-2" ] && ok "리전 정상 : ap-northeast-2" || warn "리전이 ap-northeast-2(서울)이 아님: $REGION"
else
    fail "자격증명 없음/만료 → aws configure"
fi
echo ""

# ── 4. Tailscale VPN (하이브리드 언더레이) ─────────────────
echo "[ 4 ] Tailscale VPN 상태 확인"
if command -v tailscale &>/dev/null; then
    if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
        warn "tailscaled 데몬 미실행 → sudo systemctl start tailscaled"
    else
        TS_STATUS=$(tailscale status 2>/dev/null || echo "")
        if [ -z "$TS_STATUS" ] || echo "$TS_STATUS" | grep -qiE "logged out|NeedsLogin"; then
            fail "Tailscale 로그아웃 상태 → ./bootstrap_tailscale.sh"
        else
            ok "Tailscale 연결됨 (IP: $(tailscale ip -4 2>/dev/null | head -1))"
            # advertise-routes(172.16.1.0/24) 광고 여부 (project1 검증값)
            if sudo tailscale debug prefs 2>/dev/null | grep -A2 "AdvertiseRoutes" | grep -q "172.16.1.0/24"; then
                ok "서브넷 광고 : 172.16.1.0/24 (proj-mgmt)"
            else
                warn "172.16.1.0/24 광고 미확인 (Admin 콘솔 승인/Pre-approved 확인)"
            fi
        fi
    fi
else
    fail "Tailscale 미설치 → ./bootstrap_tailscale.sh"
fi
echo ""

# ── 5. 비용 안내 ───────────────────────────────────────────
echo "[ 5 ] 비용 안내"
echo "  - 개인 AWS 계정 사용 → 실습 후 반드시 make destroy"
echo "  - destroy 전 'make backup' 으로 DB dump → S3 보존 (데이터 유실 방지)"
echo ""

echo "============================================="
echo "  확인 완료"
echo "============================================="
echo ""