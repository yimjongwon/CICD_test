# Nginx Security Layer

## 역할
- Reverse Proxy
- Rate Limit
- Access Log 생성
- Fail2ban 연계
- FastAPI 요청 전달

## 아키텍처
Client
↓
ALB + ACM
↓
Nginx Container
↓
FastAPI Container
↓
PostgreSQL

## 보안 기능

### Login Rate Limit
5 requests / minute

### Transfer Rate Limit
3 requests / minute

### API Rate Limit
10 requests / second

## 연계 시스템
- Fail2ban
- Prometheus
- Grafana
- Alertmanager