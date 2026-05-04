# Azure VM + Claude Code 원격 개발 환경 구축 가이드

> 맥북 없이 아이폰/PC 브라우저만으로 Claude Code를 사용할 수 있는 원격 개발 환경 구축 방법을 공유합니다.

---

## 이런 분께 추천합니다

- 이동 중(출퇴근, 외근)에도 Claude Code로 작업하고 싶은 분
- 맥북을 열 수 없는 상황에서 모바일로 코드 리뷰/수정이 필요한 분
- 항상 켜져있는 원격 개발 서버가 필요한 분

## 구성 개요

```
내 아이폰/PC 브라우저
    │
    │  claude.ai/code 접속
    │
    ▼
Azure VM (항상 켜져있음)
    ├── Claude Code (remote-control 모드)
    ├── tmux (세션 유지)
    └── 프로젝트 코드
```

핵심: Azure VM에서 Claude Code가 돌아가고, 나는 어디서든 웹 브라우저로 접속해서 작업하는 구조입니다.

---

## Step 1. Azure VM 생성

### 1-1. 포털에서 VM 만들기

Azure Portal > **Virtual machines** > **Create** > **Virtual machine**

### 1-2. 설정값

| 항목 | 값 | 비고 |
|------|-----|------|
| Image | Ubuntu Server 24.04 LTS | |
| Size | **Standard_B2s** (2 vCPU / 4GB) | 아래 참고 |
| Authentication | SSH public key | 생성 시 pem 파일 다운로드 |
| Region | Korea Central | |

### 1-3. 왜 B2s인가

B 시리즈는 **버스트(burst)** 방식입니다. 평소 idle 상태에서 CPU 크레딧이 쌓이고, npm install이나 빌드처럼 순간적으로 CPU가 필요할 때 크레딧을 소모합니다. Claude Code는 대부분 시간에 idle이므로 B 시리즈가 가성비 최적입니다.

### 1-4. 비용

| 운용 방식 | 월 비용 |
|-----------|---------|
| 하루 4시간 | ~$5 |
| 평일 10시간 | ~$9 |
| 24시간 상시 | ~$25 |

> 사이즈는 나중에 변경 가능합니다 (VM 중지 > 사이즈 변경 > 재시작, 데이터 유지).

---

## Step 2. SSH 접속 설정

VM 생성 시 다운로드한 pem 파일로 SSH를 설정합니다.

### 2-1. 키 파일 준비

```bash
# pem 파일을 ~/.ssh/로 이동
mv ~/Downloads/<VM이름>_key.pem ~/.ssh/

# 권한 설정 (필수 - 안 하면 "too open" 에러로 접속 거부됨)
chmod 600 ~/.ssh/<VM이름>_key.pem
```

### 2-2. SSH config 등록

`~/.ssh/config` 파일에 아래를 추가하면 매번 키 경로를 입력하지 않아도 됩니다:

```
Host claude-vm
    HostName <VM_PUBLIC_IP>
    User azureuser
    IdentityFile ~/.ssh/<VM이름>_key.pem
    ServerAliveInterval 60
```

- `HostName`: 포털 > VM > Overview > **Public IP address**
- `ServerAliveInterval 60`: 60초마다 keepalive 전송으로 SSH 끊김 방지

### 2-3. 접속 확인

```bash
ssh claude-vm
```

> **주의**: 회사 VPN이 켜져있으면 SSH 포트(22)가 차단될 수 있습니다. timeout 발생 시 VPN을 끄고 재시도하세요.

---

## Step 3. VM 내부 패키지 설치

SSH로 VM에 접속한 후 아래를 순서대로 실행합니다.

### 3-1. Node.js

```bash
# Node.js 22.x 설치 (Claude Code 실행에 필요)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### 3-2. Claude Code

```bash
# Claude Code CLI 설치 (sudo 필수)
sudo npm install -g @anthropic-ai/claude-code

# 확인
claude --version
```

### 3-3. tmux

```bash
# tmux: SSH 끊겨도 프로세스를 유지하는 도구
sudo apt-get install -y tmux
```

---

## Step 4. Claude Code 로그인

```bash
claude login
```

VM에는 브라우저가 없으므로 **device code 방식**으로 진행됩니다:

1. 터미널에 URL이 출력됨
2. 해당 URL을 **본인 PC나 모바일 브라우저**에서 열기
3. Anthropic 계정으로 인증
4. VM 터미널에 로그인 완료 표시

> **Tip**: URL이 터미널에서 줄바꿈으로 잘리면 `c` 키를 눌러 전체 URL을 복사하세요.

### workspace trust 승인

프로젝트 디렉토리에서 `claude`를 최초 1회 실행하여 trust를 승인해야 합니다:

```bash
cd ~/project
claude            # trust 승인 팝업 → 승인
/exit             # 나오기
```

---

## Step 5. Remote Control 실행

### 5-1. tmux가 필요한 이유

SSH 세션이 끊어지면 그 안의 모든 프로세스가 함께 종료됩니다. tmux를 사용하면 SSH가 끊겨도 프로세스가 유지됩니다.

```
SSH 직접 실행:  SSH 끊김 → claude 종료 (죽음)
tmux 사용:      SSH 끊김 → tmux 유지 → claude 계속 실행 (살아있음)
```

### 5-2. 실행

```bash
# tmux 세션 생성
tmux new-session -s remote-control

# 프로젝트 디렉토리 이동
cd ~/project

# Remote Control 시작
# --name: 세션 식별 이름
# --permission-mode auto: 권한 자동 승인 (모바일에서 매번 팝업 안 뜸)
claude remote-control --name "my-project" --permission-mode auto
```

QR코드 + URL이 화면에 표시됩니다.

### 5-3. 모바일/PC에서 접속

터미널에 표시된 URL을 브라우저에서 열거나, **claude.ai/code**에 접속하면 세션 목록에 보입니다.

> **주의**: 아이폰 기본 카메라로 QR 스캔 시 일반 Claude 대화창으로 열릴 수 있습니다. **URL을 직접 브라우저에 입력**하는 것이 확실합니다.

### 5-4. tmux 빠져나오기

| 방법 | 동작 | 결과 |
|------|------|------|
| **`Ctrl+B` → `D`** | **Detach (세션 유지)** | 프로세스 계속 실행, 나중에 다시 접속 가능 |
| `exit` 또는 `Ctrl+D` | 세션 종료 | 프로세스 전부 종료, 복구 불가 |

**remote-control을 유지하려면 반드시 `Ctrl+B → D`로 빠져나오세요.**

### 5-5. 나중에 다시 접속

```bash
ssh claude-vm
tmux attach -t remote-control
```

---

## tmux 단축키 요약

모든 단축키는 `Ctrl+B`를 먼저 누른 후 다음 키를 누릅니다.

### 세션

| 키 | 동작 |
|----|------|
| `Ctrl+B` → `D` | 세션 유지하며 빠져나오기 (detach) |

### 창 (탭과 비슷)

| 키 | 동작 |
|----|------|
| `Ctrl+B` → `C` | 새 창 생성 |
| `Ctrl+B` → `N` / `P` | 다음 / 이전 창 |
| `Ctrl+B` → `0~9` | 번호로 창 이동 |

### 화면 분할

| 키 | 동작 |
|----|------|
| `Ctrl+B` → `%` | 좌우 분할 |
| `Ctrl+B` → `"` | 상하 분할 |
| `Ctrl+B` → `방향키` | 분할된 화면 간 이동 |
| `Ctrl+B` → `X` | 현재 화면 닫기 |

### 기타

| 키 | 동작 |
|----|------|
| `Ctrl+B` → `[` | 스크롤 모드 (q로 종료) |

---

## 자주 묻는 질문

### Q. VM이 자동으로 꺼졌어요
포털 > VM > **Activity log**에서 "Deallocate Virtual Machine" 이벤트의 **Initiated by**를 확인하세요. "Azure Lab Services"나 "Auto-shutdown"이 원인일 수 있습니다.

**Auto-shutdown 끄기**: 포털 > VM > Operations > **Auto-shutdown** > Off로 변경

### Q. SSH 접속 시 Permission denied
pem 키 파일을 지정하지 않았거나, 권한이 잘못된 경우입니다:
```bash
chmod 600 ~/.ssh/<VM이름>_key.pem
ssh -i ~/.ssh/<VM이름>_key.pem azureuser@<IP>
```

### Q. VPN 켜면 SSH가 안 돼요
회사 VPN이 outbound 22번 포트를 차단하는 경우입니다. VPN을 끄고 재시도하세요.

### Q. VM 재시작하면 remote-control이 사라져요
tmux 세션은 메모리에만 존재하므로 VM 재시작 시 소멸됩니다. 재시작 후 Step 5를 다시 실행하면 됩니다. (코드, 설정, 로그인 상태는 유지)

### Q. Claude Code 설치 시 EACCES 에러
`sudo`를 붙이세요: `sudo npm install -g @anthropic-ai/claude-code`

---

## 참고

- Claude Code Remote Control 공식 문서: https://code.claude.com/docs/en/remote-control
- Claude Code 요구사항: **Pro / Max 플랜** 계정 필요 (API 키 방식 미지원)
