# ── 리소스 그룹 (기존 RG 참조) ────────────────────────────────
# 테넌트 정책으로 사용자가 새 RG를 만들 수 없으므로, 이미 존재하는 RG를 data 소스로 참조한다.
# tfvars의 resource_group_name은 이 RG를 가리킨다.
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# ── 네트워크 ───────────────────────────────────────────────────
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.vm_name}"
  address_space       = ["10.0.0.0/16"]
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_subnet" "main" {
  name                 = "snet-${var.vm_name}"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "main" {
  name                = "pip-${var.vm_name}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "main" {
  name                = "nic-${var.vm_name}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# ── NSG (SSH만 허용) ───────────────────────────────────────────
resource "azurerm_network_security_group" "main" {
  name                = "nsg-${var.vm_name}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# ── SSH 키 생성 ────────────────────────────────────────────────
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# ── VM ─────────────────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "main" {
  name                = var.vm_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.main.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # VM 생성 후 Claude Code 환경 자동 셋업
  custom_data = base64encode(file("${path.module}/cloud-init.yaml"))

  # custom_data 변경은 Azure에서 VM을 "강제 재생성"시킨다.
  # cloud-init은 최초 부팅에서만 실행되므로, 이미 프로비저닝된 VM에는 재실행되지 않는다.
  # 따라서 cloud-init.yaml이 갱신되어도 기존 VM은 유지하고,
  # systemd unit 등의 갱신 사항은 start-remote.sh가 SSH로 직접 배포한다 (deploy_vm_services).
  # 새로 생성되는 VM은 최신 cloud-init.yaml 내용이 그대로 적용된다.
  lifecycle {
    ignore_changes = [custom_data]
  }
}

# ── 자동 종료 (설정된 경우에만) ─────────────────────────────────
resource "azurerm_dev_test_global_vm_shutdown_schedule" "main" {
  count = var.auto_shutdown_time != "" ? 1 : 0

  virtual_machine_id    = azurerm_linux_virtual_machine.main.id
  location              = data.azurerm_resource_group.main.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone

  notification_settings {
    enabled = false
  }
}

# ── SSH 키 로컬 저장 ───────────────────────────────────────────
resource "local_file" "ssh_private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/../.ssh/vm_claude_remote_key.pem"
  file_permission = "0600"
}
