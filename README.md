# CICD 테스트


## 금융 서비스 기반 보안 이벤트 탐지 및 자동 대응 클라우드 인프라 구축
### 🗨️ 프로젝트 소개

> 
> 
> 
> 본 프로젝트는 AWS 기반 클라우드 환경에서 금융 서비스 형태의 데모 애플리케이션을 컨테이너로 배포하고, 로그인 실패 및 이체 요청 폭주와 같은 보안 이벤트를 실시간으로 탐지·시각화·알림·대응하는 운영 보안 자동화하는 DevSecOps 시스템을 구현하는 것을 목표로 함.
> 
> 단순한 웹 서비스 개발이 아니라, 클라우드 인프라 환경에서 서비스 운영 중 발생할 수 있는 이상 트래픽과 보안 이벤트를 감지하고, 자동 대응 및 복구 흐름까지 연결하는 데 중점을 둠.
> 

서비스 배포를 넘어, 보안 이벤트 발생 시 자동으로 탐지·대응·복구하는 클라우드 운영 보안 플랫폼을 구축함.

### 💠 팀명

- Lock & Lock

### 💠 팀원

- 신준한(팀장), 박정은, 이지윤, 임종원, 최상우

### 💠 역할 분담

`각 팀원의 역할과 책임`

- 신준한/박정은: AWS, Terraform, Security Group, Auto Scaling
- 최상우/임종원: FastAPI, PostgreSQL, Prometheus Custom Metrics, Dockerfile + ansible
- 임종원/신준한: GitHub Actions, Docker Hub/GHCR, Blue-Green, SAST(Bandit) + Trivy + DAST(ZAP) + 워크플로 통합
- 이지윤/박정은: Prometheus, Grafana, Alertmanager, Telegram, Dashboard, Alert Rule
- 박정은/이지윤: Locust 부하 공격, Nginx Rate Limit, fail2ban, 보안 이벤트 검증, 탐지→알림→대응 흐름 테스트, Health Check, 전환 및 Rollback 스크립트

### 💠 사용 기술 및 도구

`사용 예정인 기술, 툴, 프레임워크 등`

- **기술 스택**

- **사용 도구**

### Convention

## Github

### Issue
**템플릿을 준수**
이슈 타이틀 형태: `[카테고리]: 이슈 제목`

카테고리
- Feature: 기능 추가, 기능 변경
- Refactor: 리팩토링, 구조 변경
- Bug: 발생한 버그 목록
- Chore: 의존성, 문서 작업 등 코드 외 작업 (별도의 의존성 작업만 추가할 경우)

EX
`[Feature] Docker 컨테이너 추가`
`[Refactor] Ansible 모듈 리팩토링`

### Branch
브랜치 이름 형태: `카테고리/#이슈번호/브랜치명`

카테고리
- feature: 기능 추가, 기능 변경
- refactor: 리팩토링, 구조 변경
- fix: 버그 수정
- chore: 의존성, 문서 작업 등 코드 외 작업 (별도의 의존성 작업만 추가할 경우)

브랜치명
- <트랙> : (예: A — 인프라·IaC)


### Commit
커밋 메시지 형태: `[카테고리]: 커밋 내용`

카테고리
- FEAT: 기능 추가, 기능 변경
- REFAC: 리팩토링, 구조 변경
- FIX: 버그 수정, 오류 수정
- CHORE: 의존성 추가, 코드 외 작업

EX
`[FEAT]: OAuth2.0 추가 - Google, Naver Authentication`
`[CHORE]: pytest 의존성 추가`

### PR 컨벤션
**템플릿을 준수**

제목 형태: `[카테고리#이슈번호] PR 제목`

카테고리
- FEAT: 기능 추가, 기능 변경
- REFAC: 리팩토링, 구조 변경
- FIX: 버그 수정, 오류 수정
- CHORE: 의존성 추가, 코드 외 작업
**카테고리는 커밋과 동일**

EX
`[FEAT#18] Google, Naver OAuth 2.0 추가`

### 아키텍처 다이어그램

### 인프라 재현 방법(How to run)


### 환경 변수 설정

#### GitHub Actions Secrets 설정 예시

