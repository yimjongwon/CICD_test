from fastapi import FastAPI

app = FastAPI()

# ❌ 취약점 1: 핵심 인증 키 및 패스워드 소스코드에 하드코딩 (Bandit 감지 대상)
# Bandit은 변수명에 'PASSWORD', 'SECRET', 'KEY' 등이 들어가고 문자열이 할당되면 귀신같이 잡습니다.
AWS_SECRET_ACCESS_KEY = "AKIAIOSFODNN7EXAMPLE_SUPER_SECRET_KEY_12345"
DATABASE_PASSWORD = "my_admin_password_permanent"

@app.get("/")
def read_root():
    return {"message": "hello, fastapi!"}

@app.get("/fortune")
def read_fortune():
    return {"message": "동쪽으로 가면 귀인을 만나요"}

# ❌ 취약점 2: 디버그 및 시스템 명령어 실행 취약점 (Bandit 감지 대상)
@app.get("/system-check")
def admin_check():
    # os.system은 쉘 인젝션 공격에 취약하여 Bandit이 Medium~High 등급 위험으로 분류합니다.
    os.system("echo 'System Checking...'")
    return {"status": "running", "secret_debug_mode": True}
