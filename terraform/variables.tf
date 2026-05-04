variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "리소스 그룹 이름"
  type        = string
  default     = "rg-claude-remote"
}

variable "location" {
  description = "Azure 리전"
  type        = string
  default     = "koreacentral"
}

variable "vm_name" {
  description = "VM 이름"
  type        = string
  default     = "vm-claude-remote"
}

variable "vm_size" {
  description = "VM 사이즈"
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "VM 관리자 계정"
  type        = string
  default     = "azureuser"
}

variable "auto_shutdown_time" {
  description = "자동 종료 시간 (HHMM, 24h, UTC 기준). 빈 문자열이면 비활성화"
  type        = string
  default     = ""
}

variable "auto_shutdown_timezone" {
  description = "자동 종료 타임존"
  type        = string
  default     = "Korea Standard Time"
}

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
      start_time_kst = "19:10"
    }
  }
}
