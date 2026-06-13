-- init.sql 파일

-- 테이블이 없을 경우 users 테이블 생성
CREATE TABLE IF NOT EXISTS users (
    id             SERIAL PRIMARY KEY,              -- 고유 번호 (자동 증가)
    username       VARCHAR(50) UNIQUE NOT NULL,     -- 로그인 아이디 (예: admin)
    password       VARCHAR(255) NOT NULL,           -- 비밀번호 (애플리케이션 단에서 암호화 저장 추천)
    account_number VARCHAR(20) UNIQUE NOT NULL,     -- 계좌 번호
    balance        BIGINT NOT NULL DEFAULT 0        -- 계좌 잔액 (₩ 원화 표시용)
);

-- 테이블이 없을 경우 transactions 테이블 생성 (users 테이블의 id를 참조)
CREATE TABLE IF NOT EXISTS transactions (
    id              SERIAL PRIMARY KEY,             -- 거래 고유 번호
    user_id         INT REFERENCES users(id),       -- 거래 주체 사용자 번호
    target_account  VARCHAR(20) NOT NULL,           -- 송금받은 계좌 번호
    title           VARCHAR(100) NOT NULL,          -- 내역 표기명 (예: "Netflix", "Coffee", "이체")
    amount          BIGINT NOT NULL,                -- 거래 금액 (출금은 마이너스, 입금은 플러스)
    created_at      TIMESTAMP DEFAULT NOW()         -- 이체 시간
);

-- 테이블 및 컬럼 설명 추가
COMMENT ON TABLE users IS '락뱅크 프로젝트 회원 및 계좌 정보 테이블';
COMMENT ON COLUMN users.id IS '고유 번호 (PK)';
COMMENT ON COLUMN users.username IS '로그인 아이디';
COMMENT ON COLUMN users.password IS '암호화된 비밀번호';
COMMENT ON COLUMN users.account_number IS '계좌 번호';
COMMENT ON COLUMN users.balance IS '계좌 잔액 (단위: ₩)';

-- transactions 테이블 및 컬럼 설명 추가
COMMENT ON TABLE transactions IS '락뱅크 프로젝트 거래 내역 정보 테이블';
COMMENT ON COLUMN transactions.id IS '거래 고유 번호 (PK)';
COMMENT ON COLUMN transactions.user_id IS '거래 주체 사용자 번호 (FK: users.id 참조)';
COMMENT ON COLUMN transactions.target_account IS '송금받은 상대방 계좌 번호';
COMMENT ON COLUMN transactions.title IS '내역 표기명 (예: "Netflix", "Coffee", "이체")';
COMMENT ON COLUMN transactions.amount IS '거래 금액 (출금은 마이너스, 입금은 플러스)';
COMMENT ON COLUMN transactions.created_at IS '이체 및 거래 시간';

-- users 샘플 데이터 데이터 샘플 삽입
-- 💡 각 유저의 로그인 비밀번호는 [ lb-user ] 입니다.
INSERT INTO users (username, password, account_number, balance)
VALUES 
-- 💰 모든 유저의 계좌 잔액은 1,000,000원(백만 원)으로 통일
    -- 1) 신준한 (비밀번호: lb-user)
    ('junhan', '$2b$12$JcWi5Kysv7oxoTuSKcaxLOOeN/jDqIthPDAOivEvd6XVIuYgB6WTS', '1002-001', 1000000),
    
    -- 2) 임종원 (비밀번호: lb-user)
    ('jongwon', '$2b$12$JcWi5Kysv7oxoTuSKcaxLOOeN/jDqIthPDAOivEvd6XVIuYgB6WTS', '1002-002', 1000000),
    
    -- 3) 최상우 (비밀번호: lb-user)
    ('sangwoo', '$2b$12$JcWi5Kysv7oxoTuSKcaxLOOeN/jDqIthPDAOivEvd6XVIuYgB6WTS', '1002-003', 1000000),
    
    -- 4) 이지윤 (비밀번호: lb-user)
    ('jiyoon', '$2b$12$JcWi5Kysv7oxoTuSKcaxLOOeN/jDqIthPDAOivEvd6XVIuYgB6WTS', '1002-004', 1000000),
    
    -- 5) 박정은 (비밀번호: lb-user)
    ('jungeun', '$2b$12$JcWi5Kysv7oxoTuSKcaxLOOeN/jDqIthPDAOivEvd6XVIuYgB6WTS', '1002-005', 1000000)
ON CONFLICT (username) DO NOTHING;

-- transactions 샘플 데이터 5개 삽입 (외래키 id 자동 조회를 위해 서브쿼리 사용)
INSERT INTO transactions (user_id, target_account, title, amount) VALUES
((SELECT id FROM users WHERE username='junhan'), '1002-002', '송금', 10000),
((SELECT id FROM users WHERE username='jongwon'), '1002-003', '용돈', 50000),
((SELECT id FROM users WHERE username='sangwoo'), '1002-004', '식비 정산', 15000),
((SELECT id FROM users WHERE username='jiyoon'), '1002-005', '중고 물품 거래', 200000),
((SELECT id FROM users WHERE username='jungeun'), '1002-001', '커피 기프티콘', 5000);
