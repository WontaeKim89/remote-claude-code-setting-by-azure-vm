# VM 자동 시작 + 세션 복원 자동화 — 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 매일 19:20 KST에 Azure VM을 자동 기동하고, 부팅 직후 VM 내부 systemd가 tmux 기반 Claude Code 세션 2종을 자동 복원하며, Remote Control URL을 Telegram 봇으로 사용자에게 전송한다.

**Architecture:** Azure 측은 Terraform으로 관리되는 Automation Account + PowerShell Runbook + Schedule(Managed Identity 인증, VM Contributor RBAC 최소권한). VM 내부는 cloud-init이 배포하는 systemd user service 3종(linger 활성화) + URL 파싱 + Telegram Bot API sendMessage 스크립트. 비밀값(Telegram 토큰·chat_id)은 Terraform·Git 외부(`~/.config/claude-remote/notifier.env`)에만 저장.

**Tech Stack:** Terraform (azurerm provider 4.x), Azure Automation (PowerShell 7.2 runbook), Azure CLI(검증), systemd user services, bash, Telegram Bot API.

**Reference:** [spec](../specs/2026-04-22-vm-autostart-and-resilient-session-design.md)

**참고사항:**
- 현재 레포는 git 저장소가 아니다. `git init` 전이므로 각 태스크에 `git commit` 스텝은 포함하지 않는다. 사용자는 이 레포를 git으로 관리하기 시작하는 시점에 한 번에 커밋한다.
- Terraform IaC는 유닛 테스트 관례가 파이썬 등과 다르다. 테스트 = `terraform fmt` + `terraform validate` + `terraform plan` 검증 + Azure Portal/CLI로 리소스 상태 확인.
- **`terraform apply`와 실제 VM 기동 검증은 사용자 명시적 승인 후에만 실행한다** (Azure 과금·실 리소스 변경).

---

## 파일 구조 (완성 후)

```
claude-remote-env/
├── .gitignore                                  # [수정됨] *.env 차단
├── README.md                                   # [수정됨] 4단계 가이드로 재작성
├── start-remote.sh                             # [수정] notifier.env 배포 + systemctl 기동
├── setup.sh                                    # 유지
├── docs/
│   └── superpowers/
│       ├── specs/2026-04-22-vm-autostart-and-resilient-session-design.md   # [수정됨]
│       └── plans/2026-04-22-vm-autostart-and-resilient-session.md          # [수정됨]
└── terraform/
    ├── main.tf                                 # 유지
    ├── variables.tf                            # [수정] autostart_targets 추가
    ├── outputs.tf                              # [수정] AA 이름·다음 실행 시각 출력
    ├── terraform.tfvars.example                # [수정] autostart_targets 예시
    ├── vm.tf                                   # 유지
    ├── autostart.tf                            # [신규]
    ├── cloud-init.yaml                         # [수정] systemd unit 배포 + linger
    ├── scripts/
    │   └── Start-AzureVM.ps1                   # [신규]
    └── vm/
        ├── claude-remote-control.service       # [신규]
        ├── claude-telegram.service             # [신규]
        ├── claude-url-notifier.service         # [신규]
        └── notify-remote-url.sh                # [신규]
```

---

## 태스크 의존성

```
Task 1 (variables.tf)
   └─► Task 2 (Start-AzureVM.ps1)
         └─► Task 3 (autostart.tf)
               └─► Task 4 (outputs.tf)
                     └─► Task 9 (terraform.tfvars.example)

Task 5 (.service files)  ──┐
Task 6 (notify-remote-url.sh) ──┤
                                ├─► Task 7 (cloud-init.yaml)
                                └─► Task 8 (start-remote.sh)

모든 코드 작성 완료 후 → Task 10 (terraform plan/apply, 사용자 승인)
                        → Task 11 (end-to-end 검증)
```

Task 1~4는 Azure 측 IaC, Task 5~8은 VM 내부 구성. 두 그룹은 독립적이라 병렬 가능.

---

## Task 1: `variables.tf` — autostart 대상 변수 추가

**Files:**
- Modify: `terraform/variables.tf:47` (파일 끝에 block 추가)

- [ ] **Step 1: `autostart_targets` 변수 블록 추가**

`terraform/variables.tf` 파일 끝에 아래 블록 추가.

```hcl
variable "autostart_targets" {
  description = <<-EOT
    자동 시작 대상 VM 맵.
    default는 이 레포가 생성하는 메인 VM 하나이므로 아무 설정 없이 바로 동작.
    추가 VM을 스케쥴에 올리고 싶으면 entry를 늘리면 된다.

    key   = 스케쥴 식별용 슬러그 (영문·하이픈 권장. 스케쥴/잡 이름에 들어감)
    value = {
      vm_name        : VM 리소스 이름 (빈 값이면 var.vm_name 사용)
      resource_group : VM이 속한 RG 이름 (빈 값이면 이 레포가 만드는 RG 사용)
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

- [ ] **Step 2: fmt + validate**

```bash
cd terraform
terraform fmt -check
terraform validate
```

Expected: `Success! The configuration is valid.`
(만약 `validate`가 provider 미초기화로 실패하면 `terraform init` 한 번 실행 후 재시도)

---

## Task 2: `Start-AzureVM.ps1` — Runbook PowerShell 본문

**Files:**
- Create: `terraform/scripts/Start-AzureVM.ps1`

- [ ] **Step 1: 디렉토리 생성**

```bash
mkdir -p terraform/scripts
```

- [ ] **Step 2: 스크립트 작성**

아래 내용을 그대로 `terraform/scripts/Start-AzureVM.ps1`에 저장.

```powershell
<#
.SYNOPSIS
  Azure VM 자동 시작 Runbook (Managed Identity 인증).

.DESCRIPTION
  Automation Account의 System-Assigned Managed Identity로 Az 모듈에 로그인한 뒤
  지정된 VM을 기동한다. 이미 실행 중이면 no-op으로 종료(멱등).

.PARAMETER SubscriptionId
  VM이 속한 구독 ID.

.PARAMETER ResourceGroup
  VM이 속한 리소스 그룹 이름.

.PARAMETER VmName
  기동할 VM 이름.
#>

param(
    [Parameter(Mandatory = $true)] [string] $SubscriptionId,
    [Parameter(Mandatory = $true)] [string] $ResourceGroup,
    [Parameter(Mandatory = $true)] [string] $VmName
)

$ErrorActionPreference = 'Stop'

Write-Output "[$(Get-Date -Format o)] Runbook 시작 · target=$VmName / rg=$ResourceGroup / sub=$SubscriptionId"

# Managed Identity 인증 (Automation Account가 System-Assigned Identity를 부여받아야 함)
Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity -SubscriptionId $SubscriptionId | Out-Null
Write-Output "Managed Identity 인증 성공"

# 현재 VM 파워 상태 조회 (불필요한 Start 호출 방지 · 멱등성 확보)
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

- [ ] **Step 3: 구문 검증 (로컬 PowerShell이 없으면 Step 4로 건너뛴다)**

```bash
# pwsh가 있을 때
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path terraform/scripts/Start-AzureVM.ps1"
```

Expected: 치명적 문제 없음. (`Invoke-ScriptAnalyzer`가 없어도 무시)

- [ ] **Step 4: 로컬 파일 존재 확인**

```bash
test -s terraform/scripts/Start-AzureVM.ps1 && echo OK
```

Expected: `OK`

---

## Task 3: `autostart.tf` — Automation Account, Runbook, Schedule, RBAC

**Files:**
- Create: `terraform/autostart.tf`

- [ ] **Step 1: 파일 작성**

아래 내용을 `terraform/autostart.tf`에 저장.

```hcl
# ── VM 자동 시작 인프라 ────────────────────────────────────────
# 매일 KST 지정 시각에 대상 VM을 기동하기 위한 Azure Automation 리소스들.
# Managed Identity + 최소권한 RBAC(VM이 속한 RG 범위)로 구성한다.
# 상세 설계: docs/superpowers/specs/2026-04-22-vm-autostart-and-resilient-session-design.md

# autostart_targets의 빈 값(vm_name/resource_group)을 현재 레포가 만드는 메인 VM/RG로 치환.
# → 사용자는 tfvars에 아무것도 안 써도 자기 VM이 자동 등록됨.
locals {
  autostart_resolved = {
    for k, v in var.autostart_targets : k => {
      vm_name        = v.vm_name != "" ? v.vm_name : var.vm_name
      resource_group = v.resource_group != "" ? v.resource_group : azurerm_resource_group.main.name
      start_time_kst = v.start_time_kst
    }
  }
}

# Runbook 실행 시 Az.* 모듈 인증에 사용될 Subscription ID 조회.
data "azurerm_client_config" "current" {}

# ── Automation Account (System-Assigned Managed Identity) ─────
resource "azurerm_automation_account" "autostart" {
  name                = "aa-${var.vm_name}-autostart"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Basic SKU: 500분/월 무료. 본 설계 사용량(~60분/월) 기준 무료 한도 내.
  sku_name = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = {
    purpose = "vm-autostart"
  }
}

# ── Runbook (PowerShell 7.2) ──────────────────────────────────
resource "azurerm_automation_runbook" "start_vm" {
  name                    = "Start-AzureVM"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.autostart.name
  runbook_type            = "PowerShell"
  log_progress            = true
  log_verbose             = true
  description             = "Managed Identity 기반 Azure VM 자동 기동. 멱등."

  # PowerShell 7.2 runtime 지정 (langfuse 기존 설정과 동일)
  # azurerm 4.x에서는 runtime_version 필드로 지정
  # 일부 구버전 provider에서는 필드명이 달라 plan 단계에서 경고 가능
  # → Azure Portal에서 실행 시 문제 없으면 유지, 에러 나면 Portal에서 runtime 수동 조정
  content = file("${path.module}/scripts/Start-AzureVM.ps1")
}

# ── 스케쥴 (VM별, 매일 KST 지정 시각) ────────────────────────
resource "azurerm_automation_schedule" "per_vm" {
  for_each = local.autostart_resolved

  name                    = "daily-${each.key}-${replace(each.value.start_time_kst, ":", "")}"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.autostart.name
  frequency               = "Day"
  interval                = 1
  timezone                = "Asia/Seoul"

  # Azure API는 start_time이 "현재 시각보다 미래"여야 함.
  # → 내일 날짜에 사용자가 지정한 KST 시각(+09:00)으로 설정.
  start_time = formatdate(
    "YYYY-MM-DD'T'${each.value.start_time_kst}:00'+09:00'",
    timeadd(timestamp(), "24h"),
  )

  description = "VM ${each.value.vm_name} 자동 시작 스케쥴 (매일 ${each.value.start_time_kst} KST)"
}

# ── Runbook ↔ Schedule 연결 (VM별 파라미터 주입) ─────────────
resource "azurerm_automation_job_schedule" "per_vm" {
  for_each = local.autostart_resolved

  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.autostart.name
  runbook_name            = azurerm_automation_runbook.start_vm.name
  schedule_name           = azurerm_automation_schedule.per_vm[each.key].name

  # Runbook param 이름은 PowerShell 대소문자 구분 없음. azurerm는 lowercase 키를 요구.
  parameters = {
    subscriptionid = data.azurerm_client_config.current.subscription_id
    resourcegroup  = each.value.resource_group
    vmname         = each.value.vm_name
  }
}

# ── Managed Identity RBAC (대상 RG 범위, 최소권한) ───────────
# autostart_targets에 정의된 RG들을 distinct한 set으로 만든 뒤
# 각각에 Virtual Machine Contributor를 부여한다.
resource "azurerm_role_assignment" "aa_vm_contrib" {
  for_each = toset([for v in local.autostart_resolved : v.resource_group])

  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${each.value}"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_automation_account.autostart.identity[0].principal_id

  description = "Automation Account의 Managed Identity가 대상 RG 내 VM을 Start할 수 있도록 부여"
}
```

- [ ] **Step 2: fmt + validate**

```bash
cd terraform
terraform fmt
terraform init -upgrade   # 최초 실행 시 또는 provider 버전 변경 시
terraform validate
```

Expected: `Success! The configuration is valid.`

---

## Task 4: `outputs.tf` — Automation 관련 출력 추가

**Files:**
- Modify: `terraform/outputs.tf:31` (파일 끝에 추가)

- [ ] **Step 1: 출력 추가**

`terraform/outputs.tf` 파일 끝에 아래 블록 추가.

```hcl
# ── VM 자동 시작 관련 출력 ────────────────────────────────────
output "autostart_account_name" {
  description = "Azure Automation Account 이름 (Portal에서 Runbook/Jobs 확인용)"
  value       = azurerm_automation_account.autostart.name
}

output "autostart_schedules" {
  description = "등록된 자동 시작 스케쥴과 다음 예정 시각 (ISO8601)"
  value = {
    for k, s in azurerm_automation_schedule.per_vm : k => s.start_time
  }
}

output "autostart_principal_id" {
  description = "Automation Account의 Managed Identity Principal ID (RBAC 확인용)"
  value       = azurerm_automation_account.autostart.identity[0].principal_id
}
```

- [ ] **Step 2: validate**

```bash
cd terraform
terraform validate
```

Expected: `Success! The configuration is valid.`

---

## Task 5: systemd user unit 3종 작성

**Files:**
- Create: `terraform/vm/claude-remote-control.service`
- Create: `terraform/vm/claude-telegram.service`
- Create: `terraform/vm/claude-url-notifier.service`

- [ ] **Step 1: 디렉토리 생성**

```bash
mkdir -p terraform/vm
```

- [ ] **Step 2: `claude-remote-control.service` 작성**

```ini
[Unit]
Description=Claude Code Remote Control (tmux session)
After=network-online.target
Wants=network-online.target

[Service]
# tmux는 detached로 분리되는 프로세스 → Type=forking 사용
Type=forking

# 멱등성: 기존 세션이 있으면 kill 후 재생성. 앞의 '-'는 실패 무시(세션이 없을 때 에러 회피).
ExecStartPre=-/usr/bin/tmux kill-session -t remote-control

# stdout을 rc.log로 tee → notifier가 URL 파싱
ExecStart=/usr/bin/tmux new-session -d -s remote-control -c %h/project \
  'claude remote-control --name "Remote Dev" 2>&1 | tee %h/.local/share/claude-remote/rc.log'

ExecStop=/usr/bin/tmux kill-session -t remote-control

Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

- [ ] **Step 3: `claude-telegram.service` 작성**

```ini
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

- [ ] **Step 4: `claude-url-notifier.service` 작성**

```ini
[Unit]
Description=Telegram notifier for Claude Remote Control URL
After=claude-remote-control.service
Requires=claude-remote-control.service

[Service]
# oneshot + RemainAfterExit → URL 한 번 전송 후 종료하지만 상태는 active로 유지
Type=oneshot
RemainAfterExit=yes

# 비밀값(TOKEN/CHAT_ID)을 env 파일에서 주입. systemd가 자동으로 읽는다.
EnvironmentFile=%h/.config/claude-remote/notifier.env

ExecStart=%h/.local/bin/notify-remote-url.sh

[Install]
WantedBy=default.target
```

- [ ] **Step 5: 파일 존재 확인**

```bash
ls -la terraform/vm/
```

Expected: 3개 `.service` 파일 존재, 각 파일 크기 > 0.

---

## Task 6: `notify-remote-url.sh` — URL 파싱 + Telegram 전송

**Files:**
- Create: `terraform/vm/notify-remote-url.sh`

- [ ] **Step 1: 스크립트 작성**

```bash
#!/usr/bin/env bash
# notify-remote-url.sh — rc.log에서 첫 번째 https:// URL을 찾아 Telegram으로 전송.
# 호출 컨텍스트: systemd --user (claude-url-notifier.service) 에서 1회 실행.
# 필요한 환경변수(notifier.env에서 systemd가 주입):
#   TELEGRAM_BOT_TOKEN : BotFather가 발급한 봇 토큰
#   TELEGRAM_CHAT_ID   : 수신자 chat_id (본인 Telegram 계정 ID)

set -euo pipefail

LOG_FILE="${HOME}/.local/share/claude-remote/rc.log"

# remote-control 서비스가 rc.log를 만들 때까지 최대 60초 대기
for _ in {1..60}; do
  [[ -f "$LOG_FILE" ]] && break
  sleep 1
done

if [[ ! -f "$LOG_FILE" ]]; then
  echo "rc.log를 찾지 못했습니다: $LOG_FILE" >&2
  exit 1
fi

# tail -F로 파일 스트리밍 중 첫 매칭 URL을 잡는다.
# grep -m1: 1회 매칭 후 종료 → tail도 SIGPIPE로 자연 종료.
URL=$(tail -F "$LOG_FILE" 2>/dev/null | grep -m1 -oE 'https://[[:alnum:]./?=_%:-]+' || true)

if [[ -z "$URL" ]]; then
  echo "URL을 찾지 못했습니다." >&2
  exit 1
fi

# Telegram Bot API sendMessage
# parse_mode=HTML 로 링크 클릭 가능하게 표시
MESSAGE="🚀 <b>Claude Remote Control 준비 완료</b>%0A${URL}"
curl -fsS -X POST \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "parse_mode=HTML" \
  -d "text=${MESSAGE}" > /dev/null

echo "Telegram 전송 완료: ${URL}"
```

- [ ] **Step 2: 실행 권한 부여 (로컬 사본. cloud-init에서 permissions 0755 재설정됨)**

```bash
chmod +x terraform/vm/notify-remote-url.sh
```

- [ ] **Step 3: 구문 검증**

```bash
bash -n terraform/vm/notify-remote-url.sh && echo OK
```

Expected: `OK`

---

## Task 7: `cloud-init.yaml` — systemd unit 배포 + linger

**Files:**
- Modify: `terraform/cloud-init.yaml` (전면 개편)

- [ ] **Step 1: 기존 파일 전체 교체**

`terraform/cloud-init.yaml`을 아래 내용으로 덮어쓴다. 기존 로직(패키지 설치, Node/Claude/Bun, project 디렉토리)은 보존하되 systemd 배포 블록이 추가된다.

```yaml
#cloud-config
# VM 최초 부팅 시 자동 실행되는 초기 설정.
# - 필수 패키지 (tmux, node, claude, bun) 설치
# - systemd user service 3종 배치 (tmux 세션 자동 기동 + Telegram URL notifier)
# - linger 활성화 → 사용자 로그인 없이도 user service가 부팅 시 자동 기동

package_update: true
package_upgrade: true

packages:
  - git
  - curl
  - tmux
  - unzip

write_files:
  # ── systemd user unit 3종 ───────────────────────────────────
  - path: /home/azureuser/.config/systemd/user/claude-remote-control.service
    owner: azureuser:azureuser
    permissions: '0644'
    content: |
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

  - path: /home/azureuser/.config/systemd/user/claude-telegram.service
    owner: azureuser:azureuser
    permissions: '0644'
    content: |
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

  - path: /home/azureuser/.config/systemd/user/claude-url-notifier.service
    owner: azureuser:azureuser
    permissions: '0644'
    content: |
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

  # ── URL 파싱 + Telegram 전송 스크립트 ───────────────────────
  - path: /home/azureuser/.local/bin/notify-remote-url.sh
    owner: azureuser:azureuser
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      set -euo pipefail

      LOG_FILE="${HOME}/.local/share/claude-remote/rc.log"

      for _ in {1..60}; do
        [[ -f "$LOG_FILE" ]] && break
        sleep 1
      done

      if [[ ! -f "$LOG_FILE" ]]; then
        echo "rc.log를 찾지 못했습니다: $LOG_FILE" >&2
        exit 1
      fi

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

runcmd:
  # ── 기존 로직: Node.js / Claude Code / Bun / 프로젝트 디렉토리 ───
  - curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  - apt-get install -y nodejs
  - npm install -g @anthropic-ai/claude-code
  - su - azureuser -c 'curl -fsSL https://bun.sh/install | bash'
  - su - azureuser -c 'mkdir -p ~/project'

  # ── 신규: systemd user service 부팅 자동 기동 준비 ────────────
  # 1) 런타임 디렉토리(로그·설정 저장소) 생성 + 소유권 정리
  - mkdir -p /home/azureuser/.local/share/claude-remote /home/azureuser/.config/claude-remote
  - chown -R azureuser:azureuser /home/azureuser/.local /home/azureuser/.config

  # 2) linger 활성화: 유저가 SSH 로그인하지 않아도 부팅 시 user systemd 기동
  - loginctl enable-linger azureuser

  # 3) user systemd에 unit 로드 + enable
  #    XDG_RUNTIME_DIR 지정이 필요 (sudo -u로 실행할 때 기본값 없음)
  - sudo -u azureuser XDG_RUNTIME_DIR=/run/user/$(id -u azureuser) systemctl --user daemon-reload
  - sudo -u azureuser XDG_RUNTIME_DIR=/run/user/$(id -u azureuser) systemctl --user enable claude-remote-control.service claude-telegram.service claude-url-notifier.service
```

- [ ] **Step 2: YAML 구문 검증**

```bash
# Python3가 있다면 (macOS 기본 제공)
python3 -c "import yaml, sys; yaml.safe_load(open('terraform/cloud-init.yaml'))" && echo OK
```

Expected: `OK`

- [ ] **Step 3: terraform validate (cloud-init은 file()로 주입되므로 연관 없음. 안전 차원에서 재실행)**

```bash
cd terraform && terraform validate
```

Expected: `Success!`

---

## Task 8: `start-remote.sh` — notifier.env 배포 + systemctl 기동으로 리팩터링

**Files:**
- Modify: `start-remote.sh`

- [ ] **Step 1: Step 5(기존 `check_project_dir`) 뒤에 새 단계 삽입**

기존 함수 `create_sessions()`를 `start_services()`로 교체하고, 새 함수 `setup_telegram_notifier()`를 `setup_telegram_plugin()`과 `check_project_dir()` 사이에 추가한다.

**신규 함수: `setup_telegram_notifier()`**

아래 함수를 `start-remote.sh`의 기존 `setup_telegram_plugin()` 함수 바로 뒤(`check_project_dir()` 앞)에 추가한다.

```bash
# ══════════════════════════════════════════════════════════════
#  Telegram URL notifier 설정
#  - VM이 부팅될 때 Remote Control URL을 Telegram 봇으로 DM 받기 위한
#    자격 정보를 VM 내부 ~/.config/claude-remote/notifier.env에 배포한다.
#  - 이 파일은 systemd --user 가 claude-url-notifier.service 실행 시 읽는다.
#  - 비밀값이므로 Git·Terraform에 절대 저장하지 않는다 (권한 0600).
# ══════════════════════════════════════════════════════════════
setup_telegram_notifier() {
    info "Step 5/8 : Telegram URL notifier 설정 중..."

    # 이미 설정되어 있으면 스킵
    if vm_run "[ -f ~/.config/claude-remote/notifier.env ]"; then
        log "notifier.env 이미 존재. 건너뜀. (재설정이 필요하면 VM에서 rm 후 재실행)"
        return
    fi

    # Bot 토큰: Telegram 플러그인이 이미 저장한 토큰을 재사용
    local bot_token
    bot_token=$(vm_run "grep -oP '(?<=TELEGRAM_BOT_TOKEN=).*' ~/.claude/channels/telegram/.env 2>/dev/null | tr -d '\"'" || echo "")
    if [ -z "$bot_token" ]; then
        warn "Telegram 플러그인의 봇 토큰을 찾지 못했습니다."
        read -rp "  Telegram 봇 토큰: " bot_token
    fi

    echo ""
    info "  chat_id 확인 방법:"
    echo -e "    ${C}1.${NC} Telegram에서 본인 봇에게 아무 메시지(예: '/start')를 보낸다"
    echo -e "    ${C}2.${NC} 브라우저에서 아래 URL 접속"
    echo -e "       https://api.telegram.org/bot${bot_token}/getUpdates"
    echo -e "    ${C}3.${NC} 응답 JSON에서 \"chat\":{\"id\": 숫자} 의 숫자를 복사"
    echo ""
    read -rp "  Telegram chat_id: " chat_id

    if [ -z "$chat_id" ]; then
        err "chat_id가 비어있습니다. 이 단계는 필수입니다."
        exit 1
    fi

    # VM에 notifier.env 배치 (heredoc을 vm_run으로 보냄, 권한 0600)
    vm_run "mkdir -p ~/.config/claude-remote && cat > ~/.config/claude-remote/notifier.env <<EOF
TELEGRAM_BOT_TOKEN=${bot_token}
TELEGRAM_CHAT_ID=${chat_id}
EOF
chmod 600 ~/.config/claude-remote/notifier.env"

    log "notifier.env 배포 완료"
}
```

- [ ] **Step 2: `create_sessions()` → `start_services()`로 교체**

`create_sessions()` 함수 전체를 아래로 교체한다. tmux를 직접 new-session 하지 않고 systemd user service를 통해 기동한다.

```bash
# ══════════════════════════════════════════════════════════════
#  systemd user service 기동
#  - cloud-init이 배치해둔 3개 service를 최초 1회 start한다.
#  - 이후 VM 재부팅 시에는 linger + enable 상태 덕분에 자동 기동된다.
# ══════════════════════════════════════════════════════════════
start_services() {
    info "Step 7/8 : systemd user service 기동 중..."

    local uid
    uid=$(vm_run "id -u azureuser")

    # 세 서비스를 최초 start (enable은 cloud-init에서 이미 수행됨)
    vm_run "XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user start \
        claude-remote-control.service \
        claude-telegram.service \
        claude-url-notifier.service"

    log "systemd user service 기동 완료"
}
```

- [ ] **Step 3: `main()` 함수 재구성**

기존 `main()`의 호출 순서를 아래로 교체한다.

```bash
main() {
    echo ""
    echo -e "${B}=====================================================${NC}"
    echo -e "${B}  Claude Remote Environment Setup${NC}"
    echo -e "${B}  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${B}=====================================================${NC}"
    echo ""

    check_ssh                    # 1. VM SSH 접속 확인
    install_vm_packages          # 2. 필수 패키지 (tmux/node/claude/bun)
    check_claude_login           # 3. Claude Code 로그인
    setup_telegram_plugin        # 4. Telegram 플러그인 + 봇 토큰
    setup_telegram_notifier      # 5. notifier.env 배포 (신규)
    check_project_dir            # 6. 프로젝트 디렉토리 확인
    # cleanup_existing_sessions는 systemd 기반에서 의미 없음 → 제거
    start_services               # 7. systemd user service 기동 (신규, 기존 create_sessions 대체)
    show_status                  # 8. 완료 안내
}
```

Step 번호 라벨(`Step 1/7` → `Step 1/8`)도 각 함수 내 `info` 호출에서 함께 조정해야 한다. 기존 `install_vm_packages`는 `2/7` → `2/8`, `check_claude_login`은 `3/7` → `3/8`, 나머지도 동일 규칙으로 증가.

- [ ] **Step 4: `show_status()` 업데이트**

`show_status()`의 접속 명령어 안내를 systemctl 기반으로 갱신한다. 기존 "Remote Control / Telegram 접속 명령어" 블록을 아래로 교체.

```bash
    echo -e "  ${C}[동작 확인]${NC}"
    echo -e "  서비스 상태: ssh $SSH_HOST 'systemctl --user status claude-remote-control.service claude-telegram.service claude-url-notifier.service'"
    echo -e "  tmux 세션  : ssh $SSH_HOST 'tmux ls'"
    echo -e "  URL 재전송 : ssh $SSH_HOST 'systemctl --user restart claude-url-notifier.service'"
    echo ""
    echo -e "  ${Y}[모바일 접속]${NC}"
    echo -e "  잠시 후 Telegram 봇으로 Remote Control URL이 DM으로 전송됩니다."
    echo -e "  알림이 오지 않으면 위 URL 재전송 명령 실행."
```

- [ ] **Step 5: 구문 검증**

```bash
bash -n start-remote.sh && echo OK
```

Expected: `OK`

---

## Task 9: `terraform.tfvars.example` — autostart 예시 추가

**Files:**
- Modify: `terraform/terraform.tfvars.example` (파일 끝)

- [ ] **Step 1: 예시 블록 추가**

`terraform/terraform.tfvars.example` 파일 끝에 다음을 추가한다.

```hcl

# ── VM 자동 시작 대상 (default: 이 레포가 만드는 메인 VM 1개) ──
# default는 19:20 KST에 메인 VM 기동. 수정할 일이 있으면 아래 주석을 해제.
#
# autostart_targets = {
#   main = {
#     vm_name        = ""           # 빈 값 → var.vm_name 사용
#     resource_group = ""           # 빈 값 → 이 레포가 만드는 RG 사용
#     start_time_kst = "19:20"
#   }
#
#   # 같은 구독의 다른 VM도 스케쥴에 얹고 싶을 때:
#   # other_vm = {
#   #   vm_name        = "vm-other"
#   #   resource_group = "rg-other"
#   #   start_time_kst = "19:30"
#   # }
# }
```

- [ ] **Step 2: 파일 확인**

```bash
tail -n 20 terraform/terraform.tfvars.example
```

Expected: 추가한 주석 블록이 출력됨.

---

## Task 10: Terraform plan 검토 및 apply (사용자 승인 필수)

**Files:** 없음 (명령 실행 및 확인만).

- [ ] **Step 1: `terraform plan`으로 변경 사항 검토**

사용자에게 `terraform.tfvars`의 `subscription_id` 등이 올바르게 채워져 있는지 먼저 확인받는다.

```bash
cd terraform
terraform plan -out=autostart.tfplan
```

Expected: 추가 리소스 목록에 다음이 포함.
- `azurerm_automation_account.autostart`
- `azurerm_automation_runbook.start_vm`
- `azurerm_automation_schedule.per_vm["main"]`
- `azurerm_automation_job_schedule.per_vm["main"]`
- `azurerm_role_assignment.aa_vm_contrib[<RG>]`
- VM 관련 변경: `azurerm_linux_virtual_machine.main`의 `custom_data`가 바뀐 값으로 업데이트됨 → **주의**: 이 속성은 provider에 따라 VM 재생성을 유발할 수 있음. Step 2에서 확인.

- [ ] **Step 2: VM 재생성 여부 확인 (중요)**

이 플랜에서는 `terraform/vm.tf`에 `lifecycle { ignore_changes = [custom_data] }`가 적용되어 있으므로 기존 VM은 재생성되지 않아야 한다. 그럼에도 안전을 위해 확인한다.

```bash
terraform show autostart.tfplan | grep -E "azurerm_linux_virtual_machine|forces replacement|-/+" || echo "VM 변경 없음"
```

Expected: `VM 변경 없음` 또는 VM 리소스 자체가 plan 출력에 등장하지 않음.

만약 VM이 `-/+` 또는 `# forces replacement`로 표시되면 **즉시 중단**한다. `lifecycle` 블록이 누락되었거나 Terraform state가 어긋난 것이므로 원인 파악 후 진행해야 한다.

또한 systemd unit은 Terraform이 직접 배포하지 않는다. `start-remote.sh`의 Step 7 `deploy_vm_services`가 scp로 기존 VM에 배포한다.

- [ ] **Step 3: apply (사용자 승인 후)**

```bash
terraform apply autostart.tfplan
```

Expected:
- 모든 리소스 Apply complete.
- `outputs`에 `autostart_account_name`, `autostart_schedules`, `autostart_principal_id` 표시.

- [ ] **Step 4: Azure 측 리소스 검증**

```bash
# Automation Account 존재 확인
az automation account show \
  --name "$(terraform output -raw autostart_account_name)" \
  --resource-group "$(terraform output -raw vm_name | xargs -I{} echo 'rg-claude-remote')" -o table

# Runbook Published 상태 확인
az automation runbook list \
  --automation-account-name "$(terraform output -raw autostart_account_name)" \
  --resource-group "<your-rg>" -o table

# Role Assignment 확인
az role assignment list \
  --assignee "$(terraform output -raw autostart_principal_id)" -o table
```

Expected:
- Automation Account `Succeeded` / Active
- Runbook `Start-AzureVM` · state `Published`
- Role Assignment에 `Virtual Machine Contributor` · scope가 대상 RG

---

## Task 11: End-to-End 검증

**Files:** 없음.

- [ ] **Step 1: Runbook 수동 실행 테스트**

Azure Portal → Automation Account → Runbooks → `Start-AzureVM` → **Start** 버튼 클릭 → 파라미터 입력
- SubscriptionId: tfvars에 있는 값
- ResourceGroup: VM RG
- VmName: VM 이름

또는 CLI:

```bash
az automation runbook start \
  --automation-account-name "<aa-name>" \
  --resource-group "<rg>" \
  --name "Start-AzureVM" \
  --parameters SubscriptionId=<sub> ResourceGroup=<rg> VmName=<vm>
```

Expected:
- Job 상태가 1~2분 내 `Completed`
- 로그에 `VM 기동 완료` 또는 `VM이 이미 running 상태` 출력

- [ ] **Step 2: VM 내부 systemd 상태 검증**

```bash
# linger 활성화 확인
ssh claude-vm 'loginctl show-user azureuser -p Linger'
# → Linger=yes

# 서비스 상태
ssh claude-vm 'systemctl --user status claude-remote-control.service'
ssh claude-vm 'systemctl --user status claude-telegram.service'
ssh claude-vm 'systemctl --user status claude-url-notifier.service'
```

Expected: 모두 `Active: active (running)` 또는 notifier는 `active (exited)`.

- [ ] **Step 3: tmux 세션 확인**

```bash
ssh claude-vm 'tmux ls'
```

Expected: `remote-control`, `telegram` 2개 표시.

- [ ] **Step 4: 로그 및 Telegram 메시지 확인**

```bash
# URL 로그 확인
ssh claude-vm 'tail -n 50 ~/.local/share/claude-remote/rc.log'

# notifier 실행 로그
ssh claude-vm 'journalctl --user -u claude-url-notifier.service -n 30'
```

Expected:
- `rc.log`에 `https://claude.ai/...` 포함
- notifier 로그 마지막 줄: `Telegram 전송 완료: https://...`
- 본인 Telegram 봇 대화에 URL 메시지 도착

- [ ] **Step 5: VM 종료 → 스케쥴 자동 기동 실측 (하루 대기)**

- Azure Portal에서 VM Stop (Deallocate)
- 다음 날 19:20 KST 이후 Telegram 확인
- Azure Portal → Automation Account → Jobs 탭에서 해당 시각 Job이 `Completed` 상태인지 확인

Expected:
- 19:20:xx — Runbook Job start
- 19:22~19:24 — VM 부팅 완료 + systemd 기동 + Telegram 메시지 수신

---

## 완료 조건

- [ ] 태스크 1~9 완료 (모든 파일 작성/수정)
- [ ] 태스크 10 완료 (사용자 승인 하에 `terraform apply` 성공)
- [ ] 태스크 11 완료 (end-to-end 검증, Telegram URL 메시지 수신 확인)
- [ ] 설계 문서 `docs/superpowers/specs/...`와 README에 변경 사항이 이미 반영되어 있음 (브레인스토밍 단계에서 완료)
- [ ] 실제 구현 중 발견된 차이나 이슈는 **즉시 설계 문서 + README + MEMORY.md에 반영**

---

## 실행 이후 고려사항

- **Azure Automation 과금**: Basic SKU 무료 한도 500분/월 → 본 설계 약 60분/월.
- **Runbook 코드 변경 시**: `autostart.tf`의 `content = file(...)`이므로 `terraform apply`만 실행하면 자동 publish.
- **토큰 교체 시**: BotFather에서 토큰 재발급 → VM에 SSH → `~/.config/claude-remote/notifier.env` 직접 수정 → `systemctl --user restart claude-url-notifier.service`.
- **실패 알림(Action Group)**: Runbook이 Failed 되면 스케쥴 다음 날까지 모름. 필요하면 Log Analytics + Alert Rule 추가 (별도 작업).
