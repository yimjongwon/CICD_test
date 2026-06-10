# 1. 가벼운 파이썬 공식 이미지 사용
FROM python:3.11-slim

# 푸시한 사람의 아이디만 받아올 통로 하나만 개설
ARG GITHUB_ACTOR="unknown"

# 이미지 내부에 고유 설명 라벨 심기
LABEL description="FastAPI 가동용 앱 인프라 테스트 이미지"
LABEL author="${GITHUB_ACTOR}"

# ── 🎯 [여기 추가] OS 자체의 OpenSSL 취약점 강제 패치 ──
# 베이스 이미지의 OS(데비안) 패키지 저장소를 업데이트하고, 문제가 된 3개 라이브러리를 최신 버전으로 올립니다.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libssl3t64 \
    openssl \
    openssl-provider-legacy && \
    rm -rf /var/lib/apt/lists/*
# ──────────────────────────────────────────────────

# 2. 작업 디렉토리 설정
WORKDIR /app
# 3. 종속성 파일 먼저 복사 
COPY requirements.txt .

# 🎯 [수정] jaraco.context까지 포함해서 보안 패치 버전으로 한방에 업그레이드!
RUN pip install --no-cache-dir --upgrade pip setuptools wheel jaraco.context

# 4. 패키지 설치
RUN pip install --no-cache-dir -r requirements.txt
# 5. 소스 코드 복사
COPY app/ .
# 6. 8000 port 를 사용한다고 명시하기
EXPOSE 8000
# 7. FastAPI 실행 (Uvicorn 사용)
# --host 0.0.0.0은 컨테이너 외부 연결을 위해 필수입니다!
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
