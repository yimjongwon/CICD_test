from fastapi import FastAPI
import psycopg2
from psycopg2.extras import RealDictCursor
import os
import socket

app = FastAPI()

# 5432 포트로 뚫어놓은 도커 DB 매핑
DB_URL = os.getenv("DB_URL", "postgresql://scott:tiger@localhost:5432/scott_db")

@app.get("/")
def get_index():
    # 현재 실행중인 node의 hostname 읽어오기
    hostname=socket.gethostname()

    # hostname 도 같이 응답하기
    return {"status":"success","data":"hello fastapi!", "hostname":hostname}

@app.get("/fortune")
def read_fortune():
    return {"message": "동쪽으로 가면 귀인을 만나요"}

@app.get("/members")
def get_posts():
    # 데이터베이스 장부 연결 및 커서 개설 (딕셔너리 형태로 변환 래핑)
    conn = psycopg2.connect(DB_URL)
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    # member 레코드 긁어오기
    cursor.execute("SELECT * FROM member;")
    rows = cursor.fetchall()
    
    cursor.close()
    conn.close()
    return {"status": "success", "data": rows}