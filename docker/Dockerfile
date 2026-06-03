# 1. 가벼운 파이썬 공식 이미지 사용
FROM python:3.11-slim

# 푸시한 사람의 아이디만 받아올 통로 하나만 개설
ARG GITHUB_ACTOR="unknown"

# 이미지 내부에 고유 설명 라벨 심기
LABEL description="FastAPI 가동용 앱 이미지"
LABEL 작성자="${GITHUB_ACTOR}"

# 2. 작업 디렉토리 설정
WORKDIR /app
# 3. 종속성 파일 먼저 복사 
COPY requirements.txt .
# 4. 패키지 설치
RUN pip install --no-cache-dir -r requirements.txt
# 5. 소스 코드 복사
COPY src/ .
# 6. 8080 port 를 사용한다고 명시하기
EXPOSE 8080
# 7. FastAPI 실행 (Uvicorn 사용)
# --host 0.0.0.0은 컨테이너 외부 연결을 위해 필수입니다!
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]