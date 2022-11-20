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

variable "proxmox_tls_insecure" {
  type = bool
  default = false
}

variable "proxmox_node" {
  type = string
}

variable "k3s_version" {
  type = string
  default = "v1.25.3+k3s1"
}


variable "k3s_servers" {
  type = number
  default = 1 
}

variable "k3s_agents" {
  type = number
  default = 2
}

variable "flux_target_path" {
  type = string
  default = "clusters/production"
}

variable "flux_url" {
  type = string
  default = "clusters/production"
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
  pm_api_url = "${var.proxmox_api_url}"
  pm_user = "${var.proxmox_user}"
  pm_password = "${var.proxmox_password}"
  pm_tls_insecure = var.proxmox_tls_insecure
}

resource "random_password" "k3s_token" {
  length           = 32
  special          = false
  override_special = "_%@"
}

resource "proxmox_vm_qemu" "k3s_server" {
  count = var.k3s_servers
  name = "k3s-server-${count.index+1}"
  target_node = "${var.proxmox_node}"

  vmid = 500+count.index
  
  clone = "debian-11.5.0-amd64-template"
  os_type = "cloud-init"
  memory      = 4096
  cores       = 2

  agent = 1

  network {
    bridge   = "vmbr0"
    firewall = false
    model    = "virtio"
    tag      = 5
  }

  network {
    bridge   = "vmbr0"
    firewall = false
    model    = "virtio"
    tag      = 10
  }

  network {
    bridge   = "vmbr0"
    firewall = false
    model    = "virtio"
    tag      = 20
  }

  ipconfig0 = "ip=10.0.0.${51+count.index}/24,gw=10.0.0.1"
  ipconfig1 = "ip=10.1.0.${51+count.index}/16"
  ipconfig2 = "ip=10.254.0.${51+count.index}/24"

  lifecycle {
    ignore_changes = [
      ciuser,
      sshkeys,
      disk,
      network
    ]
  }

  connection {
    user = "debian"
    host = self.default_ipv4_address
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "remote-exec" {
    inline = [
      "/usr/bin/cloud-init status --wait",
      
    ]
  }
}

resource "proxmox_vm_qemu" "k3s_agent" {
  count = var.k3s_agents
  name = "k3s-agent-${count.index+1}"
  target_node = "${var.proxmox_node}"

  vmid = 600+count.index
  
  clone = "debian-11.5.0-amd64-template"
  os_type = "cloud-init"
  memory = 8192
  cores = 4

  agent = 1

  network {
    bridge   = "vmbr0"
    firewall = false
    model    = "virtio"
    tag      = 5
  }

  ipconfig0 = "ip=10.0.0.${60+count.index}/24,gw=10.0.0.1"
  
  lifecycle {
    ignore_changes = [
      ciuser,
      sshkeys,
      disk,
      network
    ]
  }

  connection {
    user = "debian"
    host = self.default_ipv4_address
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "remote-exec" {
    inline = [
      "/usr/bin/cloud-init status --wait",
      
    ]
  }
}

data "flux_install" "main" {
  target_path      = "${var.flux_target_path}"
}

data "flux_sync" "main" {
  target_path = "${var.flux_target_path}"
  url         = "${var.flux_url}"
}



resource "null_resource" "k3s_server_cluster_init" {
  count = length(proxmox_vm_qemu.k3s_server) > 0 ? 1:0
  
  connection {
    user = "debian"
    host = proxmox_vm_qemu.k3s_server[0].default_ipv4_address
    private_key = file("~/.ssh/id_rsa")
    timeout = "20m"
  }

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=\"${var.k3s_version}\" K3S_TOKEN=\"${random_password.k3s_token.result}\" sh -s - server --cluster-init --disable servicelb --disable traefik --tls-san=10.0.0.50 --flannel-iface=eth0 --node-ip=${proxmox_vm_qemu.k3s_server[0].default_ipv4_address}",
      "sudo kubectl wait --for=condition=Ready node/${proxmox_vm_qemu.k3s_server[0].name}",
      "sudo kubectl apply -f https://kube-vip.io/manifests/rbac.yaml",
      "sudo ctr image pull ghcr.io/kube-vip/kube-vip:v0.5.6 -q",
      "alias kube-vip=\"sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:v0.5.6 vip /kube-vip\"",
      "kube-vip manifest daemonset --interface eth0 --address 10.0.0.50 --inCluster --taint --controlplane --services --arp --leaderElection | sudo kubectl apply -f -"
    ]
  }
  
}

resource "null_resource" "k3s_server_cluster_add" {
  count = length(proxmox_vm_qemu.k3s_server)-1 > 0 ? length(proxmox_vm_qemu.k3s_server)-1 : 0
  
  connection {
    user = "debian"
    host = proxmox_vm_qemu.k3s_server[count.index+1].default_ipv4_address
    private_key = file("~/.ssh/id_rsa")
    timeout = "20m"
  }

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=\"${var.k3s_version}\" K3S_TOKEN=\"${random_password.k3s_token.result}\" sh -s - server --server https://10.0.0.50:6443 --disable servicelb --disable traefik --tls-san=10.0.0.50 --flannel-iface=eth0 --node-ip=${proxmox_vm_qemu.k3s_server[count.index+1].default_ipv4_address}",
    ]
  }

  depends_on = [
    null_resource.k3s_server_cluster_init
  ]
  
}

resource "null_resource" "k3s_agent_cluster_add" {
  count = length(proxmox_vm_qemu.k3s_agent)

  connection {
    user = "debian"
    host = proxmox_vm_qemu.k3s_agent[count.index].default_ipv4_address
    private_key = file("~/.ssh/id_rsa")
    timeout = "20m"
  }

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=\"${var.k3s_version}\" K3S_TOKEN=\"${random_password.k3s_token.result}\" sh -s - agent --server https://10.0.0.50:6443",
    ]
  }

  depends_on = [
    null_resource.k3s_server_cluster_init
  ]
  
}

data "external" "kubeconfig" {
  depends_on = [
    null_resource.k3s_server_cluster_init
  ]

  program = [
    "/usr/bin/ssh",
    "-o UserKnownHostsFile=/dev/null",
    "-o StrictHostKeyChecking=no",
    "debian@${proxmox_vm_qemu.k3s_server[0].default_ipv4_address}",
    "echo '{\"kubeconfig\":\"'$(sudo cat /etc/rancher/k3s/k3s.yaml | sed -e 's/${proxmox_vm_qemu.k3s_server[0].default_ipv4_address}/10.0.0.50/g' | base64)'\"}'"
  ]
}

output "kubeconfig" {
  value = data.external.kubeconfig
  sensitive = true
}
