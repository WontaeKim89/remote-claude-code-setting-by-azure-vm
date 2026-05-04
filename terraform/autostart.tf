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
      resource_group = v.resource_group != "" ? v.resource_group : data.azurerm_resource_group.main.name
      start_time_kst = v.start_time_kst
    }
  }
}

# Runbook 실행 시 Az.* 모듈 인증에 사용할 Subscription ID 조회.
data "azurerm_client_config" "current" {}

# ── Automation Account (System-Assigned Managed Identity) ─────
resource "azurerm_automation_account" "autostart" {
  name                = "aa-${var.vm_name}-autostart"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  # Basic SKU: 500분/월 무료. 본 설계 사용량(~60분/월) 기준 무료 한도 내.
  sku_name = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = {
    purpose = "vm-autostart"
  }
}

# ── Runbook (PowerShell) ──────────────────────────────────────
resource "azurerm_automation_runbook" "start_vm" {
  name                    = "Start-AzureVM"
  location                = data.azurerm_resource_group.main.location
  resource_group_name     = data.azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.autostart.name
  runbook_type            = "PowerShell"
  log_progress            = true
  log_verbose             = true
  description             = "Managed Identity 기반 Azure VM 자동 기동. 멱등."

  # 스크립트 본문을 파일에서 인라인으로 주입 → 코드 리뷰/버전 관리 용이
  content = file("${path.module}/scripts/Start-AzureVM.ps1")
}

# ── 스케쥴 (VM별, 매일 KST 지정 시각) ────────────────────────
resource "azurerm_automation_schedule" "per_vm" {
  for_each = local.autostart_resolved

  name                    = "daily-${each.key}-${replace(each.value.start_time_kst, ":", "")}"
  resource_group_name     = data.azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.autostart.name
  frequency               = "Day"
  interval                = 1
  timezone                = "Asia/Seoul" # azurerm provider는 IANA TZ 이름을 요구

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

  resource_group_name     = data.azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.autostart.name
  runbook_name            = azurerm_automation_runbook.start_vm.name
  schedule_name           = azurerm_automation_schedule.per_vm[each.key].name

  # Runbook param 이름은 PowerShell 대소문자 구분이 없으나 azurerm는 lowercase 키를 요구.
  parameters = {
    subscriptionid = data.azurerm_client_config.current.subscription_id
    resourcegroup  = each.value.resource_group
    vmname         = each.value.vm_name
  }
}

# ── Managed Identity RBAC (대상 RG 범위, 최소권한) ───────────
# autostart_targets에 정의된 RG들을 distinct set으로 만든 뒤
# 각각에 Virtual Machine Contributor를 부여한다.
resource "azurerm_role_assignment" "aa_vm_contrib" {
  for_each = toset([for v in local.autostart_resolved : v.resource_group])

  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${each.value}"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_automation_account.autostart.identity[0].principal_id

  description = "Automation Account의 Managed Identity가 대상 RG 내 VM을 Start할 수 있도록 부여"
}
