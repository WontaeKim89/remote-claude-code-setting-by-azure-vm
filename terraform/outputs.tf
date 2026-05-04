output "vm_public_ip" {
  description = "VM Public IP 주소 (SSH 접속용)"
  value       = azurerm_public_ip.main.ip_address
}

output "vm_name" {
  description = "VM 이름"
  value       = azurerm_linux_virtual_machine.main.name
}

output "ssh_command" {
  description = "SSH 접속 명령어"
  value       = "ssh -i ${local_file.ssh_private_key.filename} ${var.admin_username}@${azurerm_public_ip.main.ip_address}"
}

output "ssh_private_key_path" {
  description = "생성된 SSH 키 경로"
  value       = local_file.ssh_private_key.filename
}

output "ssh_config_entry" {
  description = "~/.ssh/config에 추가할 내용"
  value       = <<-EOT
    Host claude-vm
        HostName ${azurerm_public_ip.main.ip_address}
        User ${var.admin_username}
        IdentityFile ${abspath(local_file.ssh_private_key.filename)}
        ServerAliveInterval 60
  EOT
}

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
