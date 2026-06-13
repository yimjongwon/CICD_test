import os
import secrets
import logging
import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.pool import ThreadedConnectionPool
from fastapi import FastAPI, Request, Form, Response, Cookie, Depends
from fastapi.responses import HTMLResponse, RedirectResponse, PlainTextResponse
from fastapi.templating import Jinja2Templates
import bcrypt
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
import socket
import urllib.request
from contextlib import contextmanager, asynccontextmanager
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_server_info():
    try:
        req = urllib.request.Request("http://169.254.169.254/latest/api/token", method="PUT")
        req.add_header("X-aws-ec2-metadata-token-ttl-seconds", "21600")
        with urllib.request.urlopen(req, timeout=1) as response:
            token = response.read().decode('utf-8')
            
        req2 = urllib.request.Request("http://169.254.169.254/latest/meta-data/local-ipv4")
        req2.add_header("X-aws-ec2-metadata-token", token)
        with urllib.request.urlopen(req2, timeout=1) as response:
            ip = response.read().decode('utf-8')
            return f"IP: {ip}"
    except:
        return f"Host: {socket.gethostname()}"

SERVER_INFO = get_server_info()

login_failed_total = Counter("login_failed_total", "Total failed login attempts")
transfer_requests_total = Counter("transfer_requests_total", "Total transfer requests")

# Database configurations from environment variables
DB_HOST_MAIN = os.getenv("DB_HOST_MAIN", "127.0.0.1")
DB_HOST_REPLICA = os.getenv("DB_HOST_REPLICA", "127.0.0.1")
DB_USER = os.getenv("DB_USER", "lb-user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "lb-user")
DB_NAME = os.getenv("DB_NAME", "lb-db")

# Session signing secret key
SECRET_KEY = os.getenv("SECRET_KEY", "change-me-in-production")
SESSION_MAX_AGE = 86400  # 24 hours
session_serializer = URLSafeTimedSerializer(SECRET_KEY)

# Dummy bcrypt hash to prevent username enumeration via timing attack
DUMMY_HASH = bcrypt.hashpw(b"dummy", bcrypt.gensalt()).decode('utf-8')

# Connection pool globals
main_pool = None
replica_pool = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global main_pool, replica_pool
    main_pool = ThreadedConnectionPool(
        1, 10,
        host=DB_HOST_MAIN, user=DB_USER, password=DB_PASSWORD, dbname=DB_NAME
    )
    replica_pool = ThreadedConnectionPool(
        1, 10,
        host=DB_HOST_REPLICA, user=DB_USER, password=DB_PASSWORD, dbname=DB_NAME
    )
    logger.info("Database connection pools initialized (main: %s, replica: %s)", DB_HOST_MAIN, DB_HOST_REPLICA)
    yield
    main_pool.closeall()
    replica_pool.closeall()
    logger.info("Database connection pools closed")

app = FastAPI(lifespan=lifespan)

templates = Jinja2Templates(directory="templates")
templates.env.globals['server_info'] = SERVER_INFO

@contextmanager
def get_db_connection(pool):
    conn = pool.getconn()
    try:
        yield conn
    except Exception:
        conn.rollback()
        raise
    finally:
        pool.putconn(conn)

def get_current_user(request: Request):
    token = request.cookies.get("session_token")
    if not token:
        return None
    try:
        user_id = session_serializer.loads(token, max_age=SESSION_MAX_AGE)
        return int(user_id)
    except (BadSignature, SignatureExpired):
        return None

def generate_csrf_token():
    return secrets.token_urlsafe(32)

def validate_csrf_token(request: Request, csrf_token_form: str) -> bool:
    csrf_token_cookie = request.cookies.get("csrf_token")
    if not csrf_token_cookie or not csrf_token_form:
        return False
    return secrets.compare_digest(csrf_token_cookie, csrf_token_form)

@app.get("/", response_class=HTMLResponse)
def read_root(request: Request):
    if get_current_user(request):
        return RedirectResponse(url="/dashboard", status_code=302)
    return RedirectResponse(url="/login", status_code=302)

@app.get("/login", response_class=HTMLResponse)
def login_page(request: Request, error: str = None):
    csrf_token = generate_csrf_token()
    response = templates.TemplateResponse(request, "login.html", {"request": request, "error": error, "csrf_token": csrf_token})
    response.set_cookie(key="csrf_token", value=csrf_token, httponly=True, secure=True, samesite="lax")
    return response

@app.post("/login")
def login(request: Request, response: Response, username: str = Form(...), password: str = Form(...), csrf_token: str = Form(...)):
    if not validate_csrf_token(request, csrf_token):
        return RedirectResponse(url="/login?error=Invalid request", status_code=302)
    try:
        # READ from Replica
        with get_db_connection(replica_pool) as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT id, username, password FROM users WHERE username = %s", (username,))
                user = cur.fetchone()

        # Always run bcrypt.checkpw to prevent timing-based username enumeration
        stored_hash = user['password'] if user else DUMMY_HASH
        password_valid = bcrypt.checkpw(password.encode('utf-8'), stored_hash.encode('utf-8'))

        if not user or not password_valid:
            client_ip = request.client.host
            logger.warning(f"[SECURITY] LOGIN_FAILURE - IP: {client_ip}, Username: {username}")
            login_failed_total.inc()
            return RedirectResponse(url="/login?error=Invalid username or password", status_code=302)
        
        # Simple session using cookie
        signed_token = session_serializer.dumps(user['id'])
        redirect = RedirectResponse(url="/dashboard", status_code=302)
        redirect.set_cookie(key="session_token", value=signed_token, httponly=True, secure=True, samesite="lax")
        return redirect

    except Exception as e:
        return RedirectResponse(url=f"/login?error={str(e)}", status_code=302)

@app.get("/logout")
def logout():
    redirect = RedirectResponse(url="/login", status_code=302)
    redirect.delete_cookie("session_token")
    return redirect

@app.get("/dashboard", response_class=HTMLResponse)
def dashboard(request: Request):
    user_id = get_current_user(request)
    if not user_id:
        return RedirectResponse(url="/login", status_code=302)
    
    try:
        # READ from Replica
        with get_db_connection(replica_pool) as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT username, balance FROM users WHERE id = %s", (user_id,))
                user = cur.fetchone()

                cur.execute("""
                    SELECT title, amount 
                    FROM transactions 
                    WHERE user_id = %s
                    ORDER BY created_at DESC
                    LIMIT 5
                """, (user_id,))
                transactions = cur.fetchall()
        
        return templates.TemplateResponse(request, "dashboard.html", {
            "request": request, 
            "username": user['username'], 
            "balance": f"{user['balance']:,}",
            "transactions": transactions
        })
    except Exception as e:
        return RedirectResponse(url=f"/login?error=Dashboard Error: {str(e)}", status_code=302)

@app.get("/transfer", response_class=HTMLResponse)
def transfer_page(request: Request, message: str = None, error: str = None):
    user_id = get_current_user(request)
    if not user_id:
        return RedirectResponse(url="/login", status_code=302)
    csrf_token = generate_csrf_token()
    response = templates.TemplateResponse(request, "transfer.html", {"request": request, "message": message, "error": error, "csrf_token": csrf_token})
    response.set_cookie(key="csrf_token", value=csrf_token, httponly=True, secure=True, samesite="lax")
    return response

@app.post("/transfer")
def process_transfer(request: Request, account: str = Form(...), amount: int = Form(...), csrf_token: str = Form(...)):
    if not validate_csrf_token(request, csrf_token):
        return RedirectResponse(url="/transfer?error=Invalid request", status_code=302)
    transfer_requests_total.inc()
    user_id = get_current_user(request)
    if not user_id:
        return RedirectResponse(url="/login", status_code=302)
    
    if amount <= 0:
        return RedirectResponse(url="/transfer?error=Invalid amount", status_code=302)

    try:
        # WRITE to Main DB
        with get_db_connection(main_pool) as conn:
            with conn:
                with conn.cursor(cursor_factory=RealDictCursor) as cur:
                    # First, look up receiver ID without locking
                    cur.execute("SELECT id FROM users WHERE account_number = %s", (account,))
                    receiver = cur.fetchone()
                    
                    if not receiver:
                        raise ValueError("Receiver not found")

                    if user_id == receiver['id']:
                        raise ValueError("Cannot transfer to yourself")
                    
                    # Lock rows in consistent ascending ID order to prevent deadlock
                    first_id, second_id = sorted([user_id, receiver['id']])
                    cur.execute("SELECT id, balance, account_number FROM users WHERE id IN (%s, %s) ORDER BY id FOR UPDATE", (first_id, second_id))
                    locked_users = {row['id']: row for row in cur.fetchall()}
                    
                    sender = locked_users.get(user_id)
                    
                    if not sender or sender['balance'] < amount:
                        raise ValueError("Insufficient funds")
                        
                    # Deduct from sender
                    cur.execute("UPDATE users SET balance = balance - %s WHERE id = %s", (amount, user_id))
                    
                    # Add to receiver
                    cur.execute("UPDATE users SET balance = balance + %s WHERE id = %s", (amount, receiver['id']))
                    
                    # Insert transaction record for sender
                    cur.execute("""
                        INSERT INTO transactions (user_id, target_account, title, amount) 
                        VALUES (%s, %s, %s, %s)
                    """, (user_id, account, '송금', -amount))
                    
                    # Add positive record for receiver
                    cur.execute("""
                        INSERT INTO transactions (user_id, target_account, title, amount) 
                        VALUES (%s, %s, %s, %s)
                    """, (receiver['id'], sender['account_number'], '입금', amount))
            
            return RedirectResponse(url="/dashboard", status_code=302)

    except ValueError as e:
        return RedirectResponse(url=f"/transfer?error={str(e)}", status_code=302)
    except Exception as e:
        return RedirectResponse(url=f"/transfer?error=Transfer failed: {str(e)}", status_code=302)

@app.get("/health")
def health_check():
    return {"status": "ok"}

@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)