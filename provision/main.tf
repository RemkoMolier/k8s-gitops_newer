
# Variable Definitions
variable "proxmox_api_url" {
  type = string
}

variable "proxmox_user" {
  type = string
}

variable "proxmox_password" {
  type = string
  sensitive = true
}

variable "proxmox_api_token_id" {
  type = string
}

variable "proxmox_api_token_secret" {
  type = string
  sensitive = true
}

variable "proxmox_otp" {
  type = string
  sensitive = true
}

variable "proxmox_tls_insecure" {
  type = bool
  default = false
}

variable "proxmox_node" {
  type = string
}

variable "k3s_servers" {
  type = number 
}

variable "k3s_agents" {
  type = number
}


terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "2.9.11"
    }
  }
}

provider "proxmox" {
  # Configuration options
  pm_api_url = "${vars.proxmox_api_url}"
  pm_user = "${vars.proxmox_user}"
  pm_password = "${vars.proxmox_password}"
  pm_api_token_id = "${vars.proxmox_api_token_id}"
  pm_api_token_secret = "${vars.proxmox_api_token_secret}"
  pm_otp = "${vars.proxmox_otp}"
  pm_tls_insecure = vars.proxmox_tls_insecure
}

resource "proxmox_vm_qemu" "k3s_servers" {
  count = vars.k8s_masters
  name = "k3s-server-${count.index}"
  target_node = "${vars.proxmox_node}"

  agent = 1
}

resource "proxmox_vm_qemu" "k3s_agents" {
  count = vars.k8s_workers
  name = "k3s-agent-${count.index}"
  target_node = "${vars.proxmox_node}"

  agent = 1

}


module "k3s" {
  source  = "xunleii/k3s/module"
  version = "3.2.0"
  
  servers = {
    for i in range(length(proxmox_vm_qemu.k3s_servers)) :
    proxmox_vm_qemu.k3s_servers[i].name => {
      ip = proxmox_vm_qemu.k3s_servers[i].ip
      connection = {
        host = proxmox_vm_qemu.k3s_servers[i].ipv4_address
      }
      flags       = ["--disable-cloud-controller"]
      annotations = { "server_id" : i } 
    }
  }

  agents = {
    for i in range(length(proxmox_vm_qemu.k3s_agents)) :
    "${proxmox_vm_qemu.k3s_agents[i].name}_node" => {
      name = proxmox_vm_qemu.k3s_agents[i].name
      ip   = proxmox_vm_qemu.k3s_agents[i].ip
      connection = {
        host = proxmox_vm_qemu.k3s_agents.ipv4_address
      }
    }
  }

}