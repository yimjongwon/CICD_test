#!/bin/bash
# =============================================================
# 파일위치 : ~/project2-security/bootstrap_tailscale.sh
# 목적     : proj-mgmt(VMware) Tailscale 연결 + 172.16.1.0/24 서브넷 광고
# 대상     : Rocky/RHEL 8 (proj-mgmt)
# 키       : 개인 Tailscale 키 사용 (~/.tailscale_key 단일 파일로 통합 관리)
#            - TAILSCALE_AUTHKEY (필수)  / TAILSCALE_API_KEY·TAILNET_NAME (선택)
# 실행     :
#   [방법1] ./bootstrap_tailscale.sh            (없으면 실행 중 키 입력받아 ~/.tailscale_key 생성)
#   [방법2] TAILSCALE_AUTHKEY=tskey-auth-xxxxx ./bootstrap_tailscale.sh   (1회성)
#
# [연결 구조 — VXLAN 폐기, 순수 Tailscale 노드-투-노드(L3)]
#   proj-mgmt(100.x) ── Tailscale 암호화 터널(WireGuard, L3) ── AWS 노드(100.x)
#   · DB 복제: proj-mgmt(replica) → AWS DB(100.x):5432 노드 직결 (L3, VXLAN 불필요)
#   · 노드 간 100.x 메시는 accept-routes 와 무관하게 항상 살아있음
# =============================================================

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────
#  환경값 (★ 수업 mgmt 가 172.16.8.0/24 를 이미 광고 중이라
#           proj-mgmt 는 충돌 방지를 위해 172.16.1.0/24 를 광고한다)
# ──────────────────────────────────────────────────────────────────────
VMWARE_CIDR="172.16.1.0/24"          # proj-mgmt host-only 대역 (서브넷 광고용)
SYSCTL_CONF="/etc/sysctl.d/99-tailscale.conf"

# Tailscale 에 등록할 이 머신의 hostname
#   기본값 = 현재 머신의 실제 hostname (팀원마다 자동으로 본인 것 사용 → 하드코딩 제거).
#   고정하고 싶으면 TS_HOSTNAME="proj-mgmt" 처럼 직접 지정도 가능.
TS_HOSTNAME="$(hostname -s)"

# ─────────────────────────────────────────────────────────────
echo "============================================="
echo "  ${TS_HOSTNAME} → Tailscale 서브넷 라우터 설정"
echo "============================================="

# 1. OS 확인 (RHEL/Rocky 기반)
if [ ! -f /etc/redhat-release ]; then
    echo "[Error] 이 스크립트는 RHEL/Rocky Linux 전용입니다."
    exit 1
fi

# 2. Tailscale 키 확보 (단일 파일 ~/.tailscale_key 로 통합 관리)
#    파일 안에서 아래 3개를 관리 (API/ TAILNET 은 선택):
#      TAILSCALE_AUTHKEY=tskey-auth-xxxxx     (필수: 연결용)
#      TAILSCALE_API_KEY=tskey-api-xxxxx      (선택: 서브넷 라우트 자동승인용)
#      TAILNET_NAME=you@example.com           (선택: API 사용 시 함께 필요)
#    동작:
#      - 환경변수에 이미 있으면 그대로 사용 (1회성 실행 호환)
#      - ~/.tailscale_key 파일이 있으면 로드
#      - AUTHKEY 가 비어 있으면 입력받아 파일 생성(chmod 600)
#        (API_KEY/TAILNET 은 빈값 허용 → 비어 있으면 수동 승인으로 폴백)
KEY_FILE="${HOME}/.tailscale_key"

# 2-1. 환경변수에 없으면 파일에서 로드
if [ -f "$KEY_FILE" ]; then
    # shellcheck disable=SC1090
    source "$KEY_FILE"
fi

# 2-2. AUTHKEY(필수) 가 비어 있으면 입력받아 파일 생성
if [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
    echo "[INFO] ~/.tailscale_key 미설정 또는 AUTHKEY 비어 있음 → 키 입력"
    echo "       - TAILSCALE_AUTHKEY : Admin → Settings → Keys → 'Auth keys' → Generate"
    echo "                             (Reusable ON, Pre-approved ON 권장 → 라우트 자동 승인됨)"
    read -rsp "       TAILSCALE_AUTHKEY (tskey-auth-... 입력 [화면 미표시]): " TAILSCALE_AUTHKEY
    echo ""
    if [ -z "$TAILSCALE_AUTHKEY" ]; then
        echo "[Error] Auth Key 가 비어 있어 종료합니다."
        exit 1
    fi

    # API 키 입력
    echo ""
    echo "       서브넷 라우트 '자동 승인'을 원하면 API 키 + tailnet 이름 입력"
    echo "              (원치 않으면 Enter 로 건너뛰고 → 나중에 Admin 콘솔에서 수동 체크)"
    echo "       - TAILSCALE_API_KEY : Admin → Settings → Keys → 'API access tokens' 에서 발급 (tskey-api-...)"
    read -rsp "       TAILSCALE_API_KEY (tskey-api-... / 미사용 시 Enter): " TAILSCALE_API_KEY
    echo ""
    if [ -n "$TAILSCALE_API_KEY" ]; then
        echo "       - TAILNET_NAME : tailscale 가입 계정명(이메일 주소). 'tailscale status' 에서 노드 옆에 보이는 값"
        read -rp "       TAILNET_NAME (가입한 이메일 주소 입력 : xxxx@gmail.com): " TAILNET_NAME
    fi

    # 파일 생성 + 권한 600 (빈 선택값도 키만 남겨 두어 다음 실행 때 식별 가능)
    (
        TAILSCALE_AUTHKEY="$TAILSCALE_AUTHKEY"
        TAILSCALE_API_KEY="${TAILSCALE_API_KEY:-}"
        TAILNET_NAME="${TAILNET_NAME:-}"
        declare -p TAILSCALE_AUTHKEY TAILSCALE_API_KEY TAILNET_NAME
    ) > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
else
    echo "[OK] Tailscale 키 확인됨 (~/.tailscale_key)"
fi

# 3. Tailscale 설치 (idempotent)
#    repo 는 rhel/8 사용 — Tailscale 바이너리는 정적 링크라 Rocky8 에서도 동작(project1 검증).
if ! command -v tailscale &>/dev/null; then
    echo "[INFO] Tailscale 리포 등록 및 설치"
    sudo dnf config-manager --add-repo https://pkgs.tailscale.com/stable/rhel/8/tailscale.repo || true
    sudo dnf install -y tailscale
else
    echo "[OK] Tailscale 이미 설치됨: $(tailscale version | head -1)"
fi

# 4. IP Forwarding 활성화 (idempotent)
#    서브넷 라우터(광고한 172.16.1.0/24 로 패킷 전달)에 필요.
echo "[INFO] IP forwarding 설정 적용"
sudo tee "$SYSCTL_CONF" >/dev/null <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl -p "$SYSCTL_CONF"

# 5. tailscaled 서비스 시작
sudo systemctl enable --now tailscaled

# 6. Tailscale 가입 + 서브넷 광고  (★ project1 검증값 그대로)
#  --advertise-routes : 이 머신의 host-only 대역(172.16.1.0/24)을 tailnet 에 광고
#                       → AWS 쪽에서 이 대역의 VMware 장비에 접근 가능
#  --accept-dns=false : Tailscale 의 MagicDNS 가 로컬 DNS 를 가로채지 않게 함(트러블 예방)
#  --accept-routes=false : ★중요★ 다른 노드가 광고한 "서브넷 경로"를 수신하지 않음.
#       이유) accept-routes=true 로 켜면 AWS VPC(10.0.0.0/16) 등 경로가 라우팅 테이블에
#             주입되면서 VSCode Remote-SSH 세션이 끊기는 트러블이 있었음(project1 PR 이슈).
#       DB 복제는 "서브넷 경로"가 아니라 AWS DB 의 노드 IP(100.x)로 직접 연결되므로,
#       accept-routes=false 여도 proj-mgmt ↔ DB 100.x:5432 직결은 정상 동작함.
#  --reset : 이전 잔여 설정을 초기화하고 위 플래그를 깨끗하게 적용
echo "[INFO] Tailscale 가입 및 라우트 광고 (hostname=${TS_HOSTNAME})"
sudo tailscale up \
    --authkey="$TAILSCALE_AUTHKEY" \
    --advertise-routes="$VMWARE_CIDR" \
    --accept-dns=false \
    --accept-routes=false \
    --hostname="$TS_HOSTNAME" \
    --reset

# 6-1. AdvertiseRoutes 설정 적용 (idempotent — tailscale set 은 멱등)
#      (--reset 이 드물게 --advertise-routes 를 무력화하는 quirk 가 있어 재설정 보강)
echo "[INFO] Advertise routes 설정 적용"
sudo tailscale set --advertise-routes="$VMWARE_CIDR"
sleep 5

echo ""
echo "[OK] Tailscale 연결 완료 — 내 TS IP: $(tailscale ip -4 | head -1)"
sudo tailscale status | head -n 10
echo ""
echo "📌 라우트 승인: Pre-approved 미사용 시 Admin 콘솔에서 수동 승인"
echo "   https://login.tailscale.com/admin/machines → ${TS_HOSTNAME} → Edit route settings → $VMWARE_CIDR 체크"

# ── 6-2. API 키로 서브넷 라우트 자동 승인 ───────────
#   ~/.tailscale_key 에 TAILSCALE_API_KEY + TAILNET_NAME 이 채워져 있을 때만 동작.
#   없으면 건너뛰고 위 '📌 라우트 승인' 수동 안내로 폴백.
if [ -n "${TAILSCALE_API_KEY:-}" ] && [ -n "${TAILNET_NAME:-}" ]; then
    echo "[INFO] API 로 ${TS_HOSTNAME} 서브넷 라우트 자동 승인 시도..."
    DEV_ID=$(curl -s -u "${TAILSCALE_API_KEY}:" \
        "https://api.tailscale.com/api/v2/tailnet/${TAILNET_NAME}/devices" \
        | python3 -c "import sys, json; print(next((d.get('id', '') for d in json.load(sys.stdin).get('devices', []) if d.get('hostname') == '${TS_HOSTNAME}'), ''))" \
        || true)
    if [ -n "$DEV_ID" ]; then
        curl -s -u "${TAILSCALE_API_KEY}:" -X POST \
            "https://api.tailscale.com/api/v2/device/${DEV_ID}/routes" \
            -H 'Content-Type: application/json' \
            -d "{\"routes\":[\"${VMWARE_CIDR}\"]}" >/dev/null \
            && echo "[OK] ${VMWARE_CIDR} 라우트 자동 승인 완료" \
            || echo "[WARN] 자동 승인 실패 → 위 수동 절차로 진행"
    else
        echo "[WARN] ${TS_HOSTNAME} 디바이스 ID 조회 실패 → 수동 승인 필요"
    fi
fi

echo ""
echo "============================================="
echo "✅ 완료 — 점검: bash check.sh"
echo "============================================="