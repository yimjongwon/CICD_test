from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def read_root():
    return {"message": "hello, fastapi!"}

@app.get("/fortune")
def read_fortune():
    return {"message": "동쪽으로 가면 귀인을 만나요"}
