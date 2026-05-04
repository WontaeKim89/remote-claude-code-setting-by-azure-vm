# Claude Remote Dev Environment

Azure VM에 Claude Code를 올려두고, 맥북 없이 모바일만으로도 Claude 원격 개발을 돌리는 환경이다. VM은 테넌트 정책에 따라 매일 **19:00 KST에 자동 종료**되며, **19:10에 Azure Automation Runbook이 자동 기동 → VM 내부 systemd가 tmux/Claude 세션을 부활 → Telegram 봇이 새 Remote Control URL을 사용자에게 DM** 하는 구조다.

> 이 레포만 clone 받고 가이드대로 따라하면 누구나 동일한 환경을 1회 셋업으로 재현할 수 있다.

---

## 1. 이 레포가 하는 일 (30초 요약)

- **매일 19:00** 테넌트 정책이 VM을 내려버린다 (이건 우리가 못 막음)
- **매일 19:10** Azure Automation Account의 PowerShell Runbook이 VM을 다시 기동한다
- **부팅 직후** VM 내부 systemd user service 2종이 자동 기동한다
  - `claude-remote-control.service` → `tmux` 세션 `remote-control` 생성 + `claude remote-control` 실행 (stdout을 rc.log로 tee)
  - `claude-url-notifier.service` → rc.log에서 `https://claude.ai/code?environment=...` URL을 잡아 **Telegram 봇 DM 1회 전송**
- **사용자 경험**: 저녁에 Mac 켜지 않아도 됨 → 폰에 Telegram 알림이 오면 링크 탭 → 즉시 모바일 Claude 작업 이어가기

상세 설계: [`docs/superpowers/specs/2026-04-22-vm-autostart-and-resilient-session-design.md`](docs/superpowers/specs/2026-04-22-vm-autostart-and-resilient-session-design.md)

---

## 2. 아키텍처

```
┌──────────────────────── Azure ────────────────────────┐
│                                                       │
│  subscription: <var.subscription_id>                  │
│  resource_group: <var.resource_group_name>            │
│                                                       │
│  ┌───────────────────────┐                            │
│  │ Automation Account    │                            │
│  │ aa-<vm_name>-autostart│   System-Assigned          │
│  └───────────┬───────────┘───► Managed Identity       │
│              │                         │              │
│              │ linked                  │ RBAC:        │
│              ▼                         │ Virtual      │
│  ┌───────────────────────┐             │ Machine      │
│  │ Runbook (PowerShell)  │             │ Contributor  │
│  │ Start-AzureVM.ps1     │◄────────────┘ (scope: RG)  │
│  │ params: SubId, RG, Vm │                            │
│  └───────────┬───────────┘                            │
│              │ triggered by                           │
│              ▼                                        │
│  ┌───────────────────────┐       ┌──────────────────┐ │
│  │ Schedule (per VM)     │─────► │ VM (Linux)       │ │
│  │ daily @ 19:10 KST     │       │                  │ │
│  └───────────────────────┘       └────────┬─────────┘ │
│                                           │           │
└───────────────────────────────────────────┼───────────┘
                                            │ boot (19:10~)
                         ┌──────────────────▼───────────┐
                         │ systemd user services        │
                         │ (linger-enabled on azureuser)│
                         ├──────────────────────────────┤
                         │ 1) claude-remote-control     │
                         │    └─ tmux: remote-control   │
                         │        └─ claude remote-     │
                         │            control           │
                         │        └─ stdout ▸ rc.log    │
                         │                              │
                         │ 2) claude-url-notifier       │
                         │    └─ tail rc.log → URL      │
                         │       발견 시 Telegram API   │
                         │       로 사용자에게 DM 1회   │
                         └──────────────────────────────┘
                                            │
                                            ▼
                              ┌─────────────────────────┐
                              │ 모바일 Telegram         │
                              │ "🚀 Claude Remote ...   │
                              │  https://claude.ai/code?│
                              │  environment=env_..."   │
                              └─────────────────────────┘
```

---

## 3. 사전 준비

| 항목 | 확보 방법 |
|---|---|
| Azure CLI | `brew install azure-cli` → `az login` |
| Terraform | `brew install terraform` |
| Claude 계정 | Pro / Max 플랜 (remote-control 기능 필요) |
| Azure Subscription 권한 | `Contributor` 이상 (Automation Account/Role Assignment 생성) |
| Telegram 봇 | BotFather → `/newbot` → 봇 생성 + 토큰 발급 |
| Telegram chat_id | 발급된 봇에게 메시지 1건 전송 → `https://api.telegram.org/bot<TOKEN>/getUpdates` 응답 JSON에서 `chat.id` 복사 |
| GitHub repo | VM에서 작업할 private/public repo 1개 (URL 형식: `git@github.com:owner/repo.git`) |

---

## 4. 설치 가이드 (5단계, 처음 한 번만)

### 4-1. clone & tfvars 작성

```bash
git clone <this-repo>
cd claude-remote-env/terraform
cp terraform.tfvars.example terraform.tfvars
# 에디터로 terraform.tfvars 열어 subscription_id 등 값 입력
```

핵심 변수 설명:

| 변수 | 필수 | 설명 |
|---|---|---|
| `subscription_id` | 필수 | Azure 구독 ID |
| `resource_group_name` | 선택 | 사용할 RG 이름 (default: `rg-claude-remote`). 테넌트에 미리 생성된 RG가 있으면 그 이름을 그대로 적는다 (data 소스로 참조) |
| `vm_name` | 선택 | VM 이름 (default: `vm-claude-remote`) |
| `vm_size` | 선택 | VM 사이즈 (default: `Standard_B2s`) |
| `auto_shutdown_time` | 선택 | DevTest 자동 종료 시각 `HHMM` (default: 비활성). 테넌트 정책이 종료하는 경우 비워둠 |
| `autostart_targets` | 선택 | 자동 시작 대상 맵. default는 메인 VM 1개, **19:10 KST** 등록 |

### 4-2. Terraform apply

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

생성되는 리소스 요약:
- VM + VNet + NIC + NSG + Public IP + 자동 종료 스케쥴 (선택)
- **Automation Account** `aa-<vm_name>-autostart` + System-Assigned Managed Identity
- **PowerShell Runbook** `Start-AzureVM` (파라미터화, 멱등)
- **Schedule** `daily-main-1910` (매일 19:10 KST)
- **Job Schedule** (Runbook ↔ Schedule 연결 + 파라미터 주입)
- **Role Assignment** (Managed Identity에 대상 RG 범위 `Virtual Machine Contributor`)
- 로컬 파일 `.ssh/vm_claude_remote_key.pem` (VM SSH 키, 권한 0600 자동 설정)

> **기존 VM 보존**: `terraform/vm.tf`에 `lifecycle { ignore_changes = [custom_data] }`가 걸려 있어, `cloud-init.yaml`이 바뀌어도 이미 존재하는 VM은 재생성되지 않는다. 이 때문에 systemd unit 배포는 Terraform이 아니라 `start-remote.sh`의 `deploy_vm_services`가 scp로 직접 처리한다.

### 4-3. ~/.ssh/config에 claude-vm 호스트 등록

`terraform apply` 출력의 `ssh_config_entry`를 그대로 `~/.ssh/config`에 붙여 넣는다. 예시:

```ssh-config
Host claude-vm
    HostName 20.214.180.24
    User azureuser
    IdentityFile /Users/<you>/Desktop/...claude-remote-env/.ssh/vm_claude_remote_key.pem
    ServerAliveInterval 60
```

`ssh claude-vm` 한 번 실행해서 known_hosts에 등록 + 첫 로그인 확인.

### 4-4. VM에 Claude Code 로그인 (1회만)

```bash
ssh claude-vm
claude    # → /login 또는 표시되는 OAuth URL을 따라 인증
exit
```

VM의 `~/.claude/.credentials.json`에 OAuth 토큰이 저장된다. 이후 모든 자동화는 이 자격증명을 재사용한다.

### 4-5. start-remote.sh 실행 (원클릭 셋업)

```bash
# 형식: bash start-remote.sh <github-repo-url> [project-path]
bash start-remote.sh git@github.com:owner/repo.git
```

이 스크립트 1회 실행으로 다음이 모두 자동 처리된다.

| 단계 | 내용 |
|---|---|
| 1 | SSH 접속 확인 |
| 2 | VM 필수 패키지 설치 (tmux/node/claude/bun/git) |
| 3 | Claude Code 로그인 상태 확인 (4-4에서 완료) |
| 4 | **VM에 GitHub용 ed25519 SSH key 생성 + 공개키 출력**. GitHub Settings → SSH keys 또는 repo Deploy keys에 등록하라고 안내한다. 등록 후 Enter |
| 5 | 지정한 GitHub repo를 `~/project`에 clone (이미 있으면 fetch만) |
| 6 | **Telegram 봇 토큰/chat_id 입력** → VM에 `~/.config/claude-remote/notifier.env` 생성 (권한 0600). 비밀값이라 Git/Terraform에 절대 저장하지 않는다 |
| 7 | `~/.claude.json` pre-seed (`hasTrustDialogAccepted=true`, `remoteControlSpawnMode=same-dir`, `remoteDialogSeen=true`) — 다음 부팅 시 Claude 첫 실행 prompt가 안 뜨도록 미리 수락 |
| 8 | systemd unit 2종 + `notify-remote-url.sh`를 scp로 VM에 배포 (cloud-init이 이미 지나간 기존 VM도 덮어씀, 멱등) |
| 9 | systemd user service 기동. 이미 실행 중이면 유지/재시작/취소 선택 제공 |

완료되면 잠시 후 (1~3분) **Telegram 봇으로 Remote Control URL이 DM**으로 도착한다. URL을 모바일에서 탭하면 즉시 Claude 세션에 붙는다.

---

## 5. 일상 운영

### 표준 시나리오 (Mac 안 켬)

1. 저녁 19:00 — VM 자동 종료 (테넌트 정책)
2. 저녁 19:10 — Automation Runbook이 VM Start (Managed Identity로 인증)
3. 저녁 19:11~13 — VM 내부 systemd가 tmux + claude remote-control을 자동 부활
4. URL이 rc.log에 찍히면 notifier가 Telegram으로 DM 발송
5. 폰에서 링크 탭 → `claude.ai/code`에 Remote Control 세션 자동 등록 → 모바일에서 작업 이어가기

### Remote Control URL 다시 받고 싶을 때

```bash
ssh claude-vm 'systemctl --user restart claude-url-notifier.service'
# → rc.log를 다시 스캔하여 Telegram으로 URL 재전송
```

### 세션 리셋이 필요할 때

```bash
ssh claude-vm '
  : > ~/.local/share/claude-remote/rc.log
  systemctl --user restart claude-remote-control.service
  sleep 4
  systemctl --user restart claude-url-notifier.service
'
```

### tmux에 직접 붙고 싶을 때

```bash
ssh claude-vm -t 'tmux attach -t remote-control'
# 빠져나올 때: Ctrl+B → D (세션은 유지됨, claude는 백그라운드에서 계속 실행)
```

### 동작 점검

```bash
# linger 활성화 확인
ssh claude-vm 'loginctl show-user azureuser -p Linger'    # → Linger=yes

# 서비스 상태 확인
ssh claude-vm 'systemctl --user status claude-remote-control.service claude-url-notifier.service'

# tmux 세션 확인
ssh claude-vm 'tmux ls'    # → remote-control: 1 windows ...

# 종단간 테스트 — VM을 수동으로 껐다가 19:10을 기다리거나, Portal에서 Runbook을 "Start"로 즉시 실행
```

---

## 6. 커스터마이징

### VM 추가하기 (동일 구독)

`terraform.tfvars`의 `autostart_targets`에 entry 추가:

```hcl
autostart_targets = {
  main = {
    vm_name        = ""
    resource_group = ""
    start_time_kst = "19:10"
  }

  team_shared = {
    vm_name        = "vm-team-shared"
    resource_group = "rg-team"
    start_time_kst = "19:15"
  }
}
```

`terraform apply` 한 번으로 Schedule, Job Schedule, Role Assignment가 추가 생성된다.

### 시작 시각 변경

`autostart_targets.<key>.start_time_kst`를 `HH:MM` 형식으로 수정 후 `terraform apply`. Azure API는 `start_time`이 "현재 시각보다 미래"여야 하므로 Terraform이 내일 시각으로 설정한다.

### 알림 채널 교체 (Slack, Teams 등)

`terraform/vm/notify-remote-url.sh`의 `curl` 호출 부분만 대체한다. `notifier.env`의 환경변수도 대응 변경(`SLACK_WEBHOOK_URL` 등). systemd unit은 그대로 재사용 가능.

### 타 구독 VM 추가 (향후)

현재 구조는 동일 구독만 지원한다. 추후 azurerm provider alias를 `autostart.tf`에 추가하고 `role_assignment`에 alias를 지정하는 패턴이 필요하다.

---

## 7. 리소스 및 비용

| 항목 | 비용 (월) | 비고 |
|---|---|---|
| VM (B2s, 하루 4시간) | ~$5 | 테넌트 종료 후 19:10 부활 기준 |
| VM (B2s, 평일 10시간) | ~$9 | |
| VM (B2s, 24시간 상시) | ~$25 | |
| **Automation Account (Basic)** | **$0** | 500분/월 무료. 본 설계 사용량 ~60분/월 |
| Public IP (Standard, Static) | ~$3 | |

---

## 8. 프로젝트 구조

```
claude-remote-env/
├── README.md                                   # 이 문서
├── setup.sh                                    # 최초 셋업 원클릭 (legacy)
├── start-remote.sh                             # 원클릭 셋업 진입점 (5단계 가이드의 4-5)
├── docs/
│   ├── confluence-guide.md
│   ├── troubleshooting.md
│   └── superpowers/
│       └── specs/
│           └── 2026-04-22-vm-autostart-and-resilient-session-design.md
└── terraform/
    ├── main.tf                                 # provider
    ├── variables.tf                            # 모든 변수 정의 (default: 19:10 KST)
    ├── outputs.tf                              # SSH 명령, AA 이름, 다음 실행 시각
    ├── terraform.tfvars.example                # 복사 후 값 입력
    ├── vm.tf                                   # VM/네트워크/NSG + 자동 종료
    ├── autostart.tf                            # Automation Account/Runbook/Schedule/RBAC
    ├── cloud-init.yaml                         # VM 초기화 (systemd unit 2종 배치)
    ├── scripts/
    │   └── Start-AzureVM.ps1                   # Runbook 본문 (PowerShell 7.2)
    └── vm/
        ├── claude-remote-control.service       # systemd user unit
        ├── claude-url-notifier.service         # systemd user unit (oneshot)
        └── notify-remote-url.sh                # URL 파싱 + Telegram sendMessage
```

---

## 9. 트러블슈팅

| 증상 | 원인 / 조치 |
|------|------------|
| Runbook 실패 | Portal → Automation Account → Jobs → 에러 로그. 대부분 Managed Identity RBAC 전파 지연(apply 직후 ~1분) 또는 VM이 이미 running |
| Telegram 메시지 안 옴 | `ssh claude-vm 'journalctl --user -u claude-url-notifier.service -n 50'`로 로그 확인. `notifier.env` 토큰/chat_id 오타, 쌍따옴표 포함 여부 점검 |
| `notifier.env`가 docs URL 같은 잘못된 링크 발송 | 구버전 정규식 잔존. `terraform/vm/notify-remote-url.sh`의 grep 패턴이 `https://claude\.ai/code\?environment=[A-Za-z0-9_-]+`로 되어 있는지 확인. 다르면 `start-remote.sh` 재실행으로 덮어씀 |
| `Workspace not trusted` 에러 | claude.json pre-seed 미완. `start-remote.sh` 재실행. Step 7만 부분 실행하려면 VM에서 직접 `python3` 한 번 호출해 `projects.<absolute-project-path>.hasTrustDialogAccepted=true` 로 박는다 |
| 첫 실행 prompt에 막혀 tmux 세션이 멈춤 | `ssh claude-vm 'tmux send-keys -t remote-control "y" Enter'`로 수동 진행 가능. 다만 이후 부팅에선 4-5의 Step 7이 미리 수락 상태를 박았으므로 안 뜸 |
| GitHub clone 시 `Permission denied (publickey)` | VM 공개키 GitHub 미등록 또는 조직 SSO authorize 누락. `start-remote.sh` Step 4에서 출력된 공개키를 GitHub에 등록 후 SSO authorize까지 완료할 것. 조직 정책으로 deploy key가 막힌 경우엔 개인 SSH key로 등록 (계정 전체 권한이지만 VM 한정 키이므로 노출 영향 작음) |
| 기타 | [`docs/troubleshooting.md`](docs/troubleshooting.md) |

---

## 10. 변경 이력

| 날짜 | 요약 |
|---|---|
| 2026-05-04 | (1) 자동 시작 시각 19:20 → **19:10 KST**로 단축. (2) `claude --channels` 플래그가 claude 2.x에서 제거됨에 따라 `claude-telegram.service` 폐기 (Telegram 플러그인은 MCP로 자동 로드되므로 별도 세션 불필요). (3) `start-remote.sh` 리팩터: GitHub repo 자동 clone + ed25519 키 생성·등록 안내 + `claude.json` pre-seed(workspace trust + remote-control prompt 수락) 추가 → 진정한 1회 실행으로 셋업 완료. (4) notifier 정규식을 `https://claude.ai/code?environment=...`로 좁혀 docs URL 오인 발송 제거. |
| 2026-04-22 | VM 자동 시작(Automation Account) + systemd user service 기반 세션 부활 + Telegram URL 알림 아키텍처 도입. 설계 문서 `docs/superpowers/specs/2026-04-22-vm-autostart-and-resilient-session-design.md` 생성 |
| 2026-04-15 | 레포 초기 구성 (VM, Terraform, start-remote.sh) |

> 구조/방향이 변경되면 이 섹션과 위 설계 문서를 함께 업데이트한다.
