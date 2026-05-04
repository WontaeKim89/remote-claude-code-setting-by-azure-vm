# VM 자동 시작 + 세션 복원 자동화 설계

- **작성일**: 2026-04-22
- **대상 레포**: `claude-remote-env`
- **대상 VM**: `vm-remote-work-wt` (Subscription: `sub-open-axd-personal-01`, Resource Group: `azure_test-a89a8649-741-rg001`)
- **참고 패턴**: `PROJECT/HanwhaGeneralInsurance-Agent`에서 langfuse VM용으로 운영 중인 Azure Automation Account `aa-langfuse-autostart` + Runbook `Start-LangfuseVM`

---

## 1. 배경과 목표

테넌트 정책에 따라 대상 VM이 매일 **19:00 KST에 자동 종료**된다. 해당 VM은 Claude Code를 모바일/외부에서 원격 제어(`claude remote-control`)하기 위한 호스트이므로, 재시작 이후에도 **사용자 수동 조작 없이 모바일 전용 워크플로가 유지**되어야 한다.

기존 `start-remote.sh` 패턴은 다음 세 가지 수동 단계를 요구한다.

1. VM이 꺼진 상태에서 사용자가 Azure Portal 또는 `az vm start`로 기동
2. VM 내부 `tmux` 세션 2개(`remote-control`, `telegram`)가 소멸했으므로 SSH 접속 후 `start-remote.sh` 재실행
3. 모바일에서 새로 발급된 Remote Control URL을 다시 등록

이 모든 수동 단계를 제거해 **"저녁 19:20쯤 Telegram 메시지 도착 → 링크 탭 → 모바일 Claude 작업 시작"** 플로우를 만드는 것이 목표다.

---

## 2. 의사결정 요약

| 영역 | 선택지 | 확정안 | 사유 |
|---|---|---|---|
| VM 자동 시작 메커니즘 | (A) Logic App / (B) Automation Account Runbook / (C) GitHub Actions cron / (D) 로컬 crontab | **(B) Automation Account + PowerShell Runbook** | langfuse 기존 패턴과 동일, Managed Identity로 자격 증명 분리, 구독 내부에서 완결 |
| Automation Account 위치 | (1) 기존 `aa-langfuse-autostart` 재사용 / (2) VM과 같은 구독에 신규 생성 | **(2) `sub-open-axd-personal-01`에 신규 생성** | 구독·리소스 경계 분리, 최소권한 원칙, langfuse의 Portal-only 리소스 상태를 반복하지 않기 위함 |
| 관리 방식 | IaC (Terraform) / Portal | **Terraform** | 기존 레포가 이미 Terraform 기반. 재현 가능성, 리뷰 가능성, destroy 시 정리 용이 |
| 리소스 구조 | 단일 VM 전용 / `for_each` 범용 | **`for_each` 구조 + default로 메인 VM 자동 등록** | 레포를 fork한 사용자가 자기 VM 하나를 바로 쓸 수 있되, entry 추가만으로 N VM 확장 가능 |
| VM 내부 세션 부활 | (i) systemd user service + linger / (ii) crontab `@reboot` / (iii) VM Extension | **(i) systemd user service** | 표준 OS 메커니즘, 실패 시 자동 재시작, `journalctl` 로그 표준화 |
| Remote Control URL 재등록 문제 | (A) 방치 / (B) Telegram 봇 알림 | **(B) Telegram 봇** | 모바일 전용 워크플로의 핵심 UX. 봇 인프라는 이미 존재 |

---

## 3. 아키텍처

```
┌──────────────────────── Azure ────────────────────────┐
│                                                       │
│  subscription: sub-open-axd-personal-01               │
│  resource_group: azure_test-a89a8649-741-rg001        │
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
│  │ Schedule (per VM)     │─────► │ VM:              │ │
│  │ daily @ 19:20 KST     │       │ vm-remote-work-wt│ │
│  └───────────────────────┘       └────────┬─────────┘ │
│                                           │           │
└───────────────────────────────────────────┼───────────┘
                                            │ boot (19:20~)
                         ┌──────────────────▼───────────┐
                         │ systemd user services        │
                         │ (linger-enabled on azureuser)│
                         ├──────────────────────────────┤
                         │ 1) claude-remote-control     │
                         │    └─ tmux: remote-control   │
                         │        └─ claude remote-     │
                         │            control           │
                         │        └─ stdout ▸ log file  │
                         │                              │
                         │ 2) claude-telegram           │
                         │    └─ tmux: telegram         │
                         │        └─ claude --channels  │
                         │                              │
                         │ 3) claude-url-notifier       │
                         │    └─ tail log, URL 발견     │
                         │        시 Telegram API로     │
                         │        사용자에게 DM 1회     │
                         └──────────────────────────────┘
```

---

## 4. Azure 측 구성 (Terraform)

### 4.1 파일 구조 변경

| 경로 | 상태 | 역할 |
|---|---|---|
| `terraform/autostart.tf` | 신규 | Automation Account, Runbook, Schedule, Role Assignment |
| `terraform/scripts/Start-AzureVM.ps1` | 신규 | Runbook 본문 (`file()`로 주입) |
| `terraform/variables.tf` | 수정 | `autostart_targets` 변수 추가 |
| `terraform/terraform.tfvars.example` | 수정 | 예시 값 추가 |
| `terraform/outputs.tf` | 수정 | Automation Account 이름과 다음 실행 시각 출력 |

### 4.2 변수 정의

```hcl
variable "autostart_targets" {
  description = <<-EOT
    자동 시작 대상 VM 맵.
    default는 이 레포가 생성하는 메인 VM 하나이므로 아무 설정 없이 바로 동작.
    추가 VM을 스케쥴에 올리고 싶으면 이 변수에 entry를 늘리면 된다.

    key   = 스케쥴 식별용 슬러그(영문·하이픈 권장)
    value = {
      vm_name        : VM 리소스 이름 (빈 값이면 var.vm_name)
      resource_group : VM이 속한 RG 이름 (빈 값이면 이 레포가 만드는 RG)
      start_time_kst : "HH:MM" (Korea Standard Time)
    }
    제약: 현재는 Automation Account와 같은 구독 내 VM만 지원.
  EOT
  type = map(object({
    vm_name        = string
    resource_group = string
    start_time_kst = string
  }))
  default = {
    main = {
      vm_name        = ""
      resource_group = ""
      start_time_kst = "19:20"
    }
  }
}
```

### 4.3 리소스 블록 (핵심)

```hcl
locals {
  autostart_resolved = {
    for k, v in var.autostart_targets : k => {
      vm_name        = v.vm_name        != "" ? v.vm_name        : var.vm_name
      resource_group = v.resource_group != "" ? v.resource_group : azurerm_resource_group.main.name
      start_time_kst = v.start_time_kst
    }
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_automation_account" "autostart" {
  name                = "aa-${var.vm_name}-autostart"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Basic"
  identity { type = "SystemAssigned" }
}

resource "azurerm_automation_runbook" "start_vm" {
  name                    = "Start-AzureVM"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.autostart.name
  runbook_type            = "PowerShell"
  content                 = file("${path.module}/scripts/Start-AzureVM.ps1")
  log_progress            = true
}

resource "azurerm_automation_schedule" "per_vm" {
  for_each                = local.autostart_resolved
  name                    = "daily-${each.key}-${replace(each.value.start_time_kst, ":", "")}"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.autostart.name
  frequency               = "Day"
  interval                = 1
  timezone                = "Asia/Seoul"
  start_time = formatdate(
    "YYYY-MM-DD'T'${each.value.start_time_kst}:00'+09:00'",
    timeadd(timestamp(), "24h"),
  )
}

resource "azurerm_automation_job_schedule" "per_vm" {
  for_each                = local.autostart_resolved
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.autostart.name
  runbook_name            = azurerm_automation_runbook.start_vm.name
  schedule_name           = azurerm_automation_schedule.per_vm[each.key].name

  parameters = {
    subscriptionid = data.azurerm_client_config.current.subscription_id
    resourcegroup  = each.value.resource_group
    vmname         = each.value.vm_name
  }
}

resource "azurerm_role_assignment" "aa_vm_contrib" {
  for_each             = toset([for v in local.autostart_resolved : v.resource_group])
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${each.value}"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_automation_account.autostart.identity[0].principal_id
}
```

### 4.4 Runbook 본문 (`terraform/scripts/Start-AzureVM.ps1`)

```powershell
<#
.SYNOPSIS
  Azure VM 자동 시작 Runbook (Managed Identity 인증)
#>
param(
    [Parameter(Mandatory = $true)] [string] $SubscriptionId,
    [Parameter(Mandatory = $true)] [string] $ResourceGroup,
    [Parameter(Mandatory = $true)] [string] $VmName
)
$ErrorActionPreference = 'Stop'

Write-Output "[$(Get-Date -Format o)] Runbook 시작 · target=$VmName / rg=$ResourceGroup / sub=$SubscriptionId"

Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity -SubscriptionId $SubscriptionId | Out-Null
Write-Output "Managed Identity 인증 성공"

$status = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VmName -Status
$powerState = ($status.Statuses | Where-Object Code -like 'PowerState/*').Code
Write-Output "현재 PowerState = $powerState"

if ($powerState -eq 'PowerState/running') {
    Write-Output "VM이 이미 running 상태. 추가 조치 없이 종료."
    return
}

$result = Start-AzVM -ResourceGroupName $ResourceGroup -Name $VmName
if ($result.Status -ne 'Succeeded') {
    throw "Start-AzVM 실패: Status=$($result.Status)"
}
Write-Output "[$(Get-Date -Format o)] VM 기동 완료"
```

---

## 5. VM 내부 구성 (systemd + Telegram notifier)

### 5.1 파일 구조

| 경로 | 상태 | 역할 |
|---|---|---|
| `terraform/cloud-init.yaml` | 수정 | systemd unit 3개 배포 + linger 활성화 + notifier 스크립트 배포 |
| `terraform/vm/claude-remote-control.service` | 신규 | tmux 세션 `remote-control` 기동 |
| `terraform/vm/claude-telegram.service` | 신규 | tmux 세션 `telegram` 기동 |
| `terraform/vm/claude-url-notifier.service` | 신규 | Remote Control URL → Telegram 전송 |
| `terraform/vm/notify-remote-url.sh` | 신규 | URL 파싱 + Telegram Bot API 호출 |

### 5.2 systemd user unit 3종

```ini
# claude-remote-control.service
[Unit]
Description=Claude Code Remote Control (tmux session)
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStartPre=-/usr/bin/tmux kill-session -t remote-control
ExecStart=/usr/bin/tmux new-session -d -s remote-control -c %h/project \
  'claude remote-control --name "Remote Dev" 2>&1 | tee %h/.local/share/claude-remote/rc.log'
ExecStop=/usr/bin/tmux kill-session -t remote-control
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

```ini
# claude-telegram.service
[Unit]
Description=Claude Code Telegram Channel (tmux session)
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStartPre=-/usr/bin/tmux kill-session -t telegram
ExecStart=/usr/bin/tmux new-session -d -s telegram -c %h/project \
  'claude --channels plugin:telegram@claude-plugins-official'
ExecStop=/usr/bin/tmux kill-session -t telegram
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

```ini
# claude-url-notifier.service
[Unit]
Description=Telegram notifier for Claude Remote Control URL
After=claude-remote-control.service
Requires=claude-remote-control.service

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=%h/.config/claude-remote/notifier.env
ExecStart=%h/.local/bin/notify-remote-url.sh

[Install]
WantedBy=default.target
```

### 5.3 URL 파싱 + Telegram 전송 스크립트

```bash
#!/usr/bin/env bash
# notify-remote-url.sh — rc.log에서 첫 https:// URL 발견 → Telegram sendMessage
set -euo pipefail

LOG_FILE="${HOME}/.local/share/claude-remote/rc.log"
for _ in {1..60}; do
  [[ -f "$LOG_FILE" ]] && break
  sleep 1
done

URL=$(tail -F "$LOG_FILE" 2>/dev/null | grep -m1 -oE 'https://[[:alnum:]./?=_%:-]+' || true)
if [[ -z "$URL" ]]; then
  echo "URL을 찾지 못했습니다." >&2
  exit 1
fi

MESSAGE="🚀 <b>Claude Remote Control 준비 완료</b>%0A${URL}"
curl -fsS -X POST \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "parse_mode=HTML" \
  -d "text=${MESSAGE}" > /dev/null

echo "Telegram 전송 완료: ${URL}"
```

### 5.4 `cloud-init.yaml` 변경 (추가 블록)

```yaml
write_files:
  - path: /home/azureuser/.config/systemd/user/claude-remote-control.service
    content: |
      {unit 내용}
    owner: azureuser:azureuser
    permissions: '0644'
  # claude-telegram.service, claude-url-notifier.service 동일 방식
  - path: /home/azureuser/.local/bin/notify-remote-url.sh
    content: |
      {스크립트 내용}
    permissions: '0755'
    owner: azureuser:azureuser

runcmd:
  - loginctl enable-linger azureuser
  - mkdir -p /home/azureuser/.local/share/claude-remote /home/azureuser/.config/claude-remote
  - chown -R azureuser:azureuser /home/azureuser/.local /home/azureuser/.config
  - sudo -u azureuser XDG_RUNTIME_DIR=/run/user/$(id -u azureuser) systemctl --user daemon-reload
  - sudo -u azureuser XDG_RUNTIME_DIR=/run/user/$(id -u azureuser) systemctl --user enable claude-remote-control.service claude-telegram.service claude-url-notifier.service
```

### 5.5 공개값 / 비밀값 분리 정책

| 값 | 저장 위치 | 이유 |
|---|---|---|
| Terraform 변수 전반 (`vm_name`, `autostart_targets` 등) | `terraform.tfvars` | 비밀 아님, 버전 관리 대상 (단 `*.tfvars`는 `.gitignore`) |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | VM 내부 `~/.config/claude-remote/notifier.env` (권한 `600`) | 비밀. Terraform state·Git 오염 방지 |
| Claude Code 자격증명 | VM 내부 `~/.claude/` | Claude CLI가 자체 생성 · 사용자 계정 자산 |

`start-remote.sh`가 최초 1회 대화형으로 토큰/chat_id를 입력받아 `notifier.env`를 생성 → VM에 `scp`로 배치한다. Terraform은 이 값을 절대 보지 않는다.

---

## 6. `start-remote.sh` 리팩터링 방향

| 기능 | 기존 | 변경 후 |
|---|---|---|
| SSH 접속 확인 | 있음 | 유지 |
| VM 패키지 설치 | 있음 | 유지 |
| Claude Code 로그인 | 있음 | 유지 (필수 전제) |
| Telegram 플러그인 설치 + 봇 토큰 설정 | 있음 | 유지 |
| **Telegram `chat_id` 입력** | 없음 | 신규. `getUpdates`로 확인 가이드 함께 출력 |
| **`notifier.env` 배포** | 없음 | 신규. `scp`로 `~/.config/claude-remote/notifier.env` 생성 |
| **tmux 세션 직접 생성** | 있음 | **제거**. `systemctl --user start ...`로 대체 |
| 기존 세션 처리 | `tmux kill-session` | `systemctl --user restart ...` |

---

## 7. 검증 절차

| 단계 | 명령 | 기대 결과 |
|---|---|---|
| Terraform 리소스 | `terraform plan && terraform apply` | Automation Account, Runbook, Schedule, RoleAssignment 생성 성공 |
| RBAC 확인 | `az role assignment list --assignee <principalId>` | `Virtual Machine Contributor` · scope = 대상 RG |
| Runbook 수동 실행 | Portal "Start" 버튼 → Job 상태 확인 | Completed · 로그에 `VM 기동 완료` |
| 스케쥴 등록 | `az automation schedule list --automation-account-name aa-...` | 다음 실행 시각이 내일 19:20 KST로 표시 |
| linger 활성화 | `ssh claude-vm 'loginctl show-user azureuser -p Linger'` | `Linger=yes` |
| user unit 상태 | `ssh claude-vm 'systemctl --user status claude-remote-control.service'` | `Active: active (running)` |
| tmux 세션 | `ssh claude-vm 'tmux ls'` | `remote-control`, `telegram` 표시 |
| Telegram 수신 | VM 재시작 후 본인 Telegram 확인 | URL 메시지 도착 |
| 종단간 시나리오 | Azure Portal에서 VM Stop → 19:20 대기 → Telegram 도착 시각 측정 | 스케쥴 실행 후 2분 이내 메시지 도착 |

---

## 7.5 기존 VM 보존 전략 (중요)

`azurerm_linux_virtual_machine`의 `custom_data` 필드는 변경 시 Azure가 VM을 **강제 재생성**한다. cloud-init이 최초 부팅에만 실행되기 때문이다. 이 프로젝트에서 이미 프로비저닝된 VM의 `~/.claude/` 자격 파일, 프로젝트 파일, 컴퓨터 상태를 보존해야 하므로 다음 전략을 취한다.

- `terraform/vm.tf`의 VM 리소스에 다음 lifecycle 블록을 둔다.
  ```hcl
  lifecycle {
    ignore_changes = [custom_data]
  }
  ```
- Terraform은 `cloud-init.yaml`이 바뀌어도 기존 VM을 건드리지 않는다.
- 대신 `start-remote.sh`의 `deploy_vm_services()` 함수가 systemd unit 파일 3종과 `notify-remote-url.sh`를 SSH+scp로 직접 배포한다. 이 단계는 멱등하며 기존 VM에 대한 "수동 cloud-init 대체 경로"다.
- 새로 생성되는 VM은 갱신된 `cloud-init.yaml`이 그대로 적용되므로 이 수동 경로가 필요 없다 (단, 초기 부팅 이후 cloud-init 변경분은 여전히 반영되지 않으므로 장기적으로는 동일한 수동 배포 경로가 유지보수에도 쓰인다).

## 8. 리스크 및 한계

- **Claude Code 자격 파일 종속성**: `~/.claude/`가 없으면 systemd 서비스가 실패. 최초 1회 `start-remote.sh`로 로그인 필수.
- **Remote Control URL 패턴 변화**: `claude remote-control` 출력 포맷이 변경되면 `grep` 정규식 수정 필요. `notify-remote-url.sh` 한 줄 수정으로 해결 가능.
- **Telegram 토큰 유출 시**: VM 내부 `600` 권한 + Git 미커밋 보장. 유출 시 BotFather에서 토큰 재발급만 필요.
- **구독 경계**: 현재 구조는 Automation Account와 동일 구독 내 VM만 지원. 타 구독 VM 추가는 `azurerm` provider alias + 별도 role_assignment 필요 (README "확장 가이드"에 스니펫 예정).
- **Azure Automation 과금**: Basic SKU 기준 500분/월 무료. 현 설계(1 Runbook × 일 1회 × 2분)는 월 60분 → 무료 한도 내.
- **logrotate 미적용**: `rc.log`가 누적 증가. 장기 운영 시 `/etc/logrotate.d/claude-remote` 추가 권장 (선택).

---

## 9. 오픈 이슈 / 향후 작업

- [ ] 실패 알림 채널: Runbook Failed 시 자동 알림(Action Group 연동) 필요 여부
- [ ] 다중 구독 지원: azurerm alias 적용 시 Terraform 구조 확장
- [ ] logrotate: 선택 가이드만 README에 추가할지, 기본 포함할지 결정
- [ ] Telegram `chat_id` 자동 감지: 봇에 아무 메시지 → 자동으로 chat_id 추출 (현재는 수동)

---

## 10. 변경 이력

| 날짜 | 변경 | 작성자 |
|---|---|---|
| 2026-04-22 | 초안 작성 (섹션 1~5 브레인스토밍 확정본) | - |
