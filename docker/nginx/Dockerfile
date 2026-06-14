# security/nginx/Dockerfile
# 보안 정책이 내장된 프로젝트용 Nginx Gateway
#
# 기능
# Reverse Proxy, Security Header, Login Rate Limit
# API Rate Limit, JSON Log 생성, fail2ban 연계
# Grafana/Loki 연계, Health Check 지원

FROM nginx:1.25-alpine

LABEL description="LOCK&LOCK Security Nginx Gateway"
LABEL role="reverse-proxy-rate-limit-json-log"

# 기존 설정 제거
RUN rm -f /etc/nginx/nginx.conf \
    && rm -f /etc/nginx/conf.d/default.conf \
    && mkdir -p /var/log/nginx

# Nginx 경로에 설정 파일 복사
COPY nginx.conf /etc/nginx/nginx.conf
COPY log-format.conf /etc/nginx/conf.d/log-format.conf
COPY rate-limit.conf /etc/nginx/conf.d/rate-limit.conf


EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
