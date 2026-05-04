# Azure VM for Claude Remote Development
# - 이미 VM이 존재하면 유지, 없으면 새로 생성
# - B2s (2 vCPU / 4GB) 상시 운용 기준

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
