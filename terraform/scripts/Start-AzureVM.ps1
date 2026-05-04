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
