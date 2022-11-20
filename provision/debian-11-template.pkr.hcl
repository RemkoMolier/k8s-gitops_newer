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


source "proxmox-iso" "debian-11-netinstall" {
  proxmox_url              = "${var.proxmox_api_url}"
  insecure_skip_tls_verify = var.proxmox_tls_insecure
  username                 = "${var.proxmox_user}"
  password                 = "${var.proxmox_password}"


  template_description = "Debian 11 cloud-init template. Built on ${formatdate("YYYY-MM-DD hh:mm:ss ZZZ", timestamp())}"
  node                 = "${var.proxmox_node}"
  network_adapters {
    bridge   = "vmbr0"
    firewall = false
    model    = "virtio"
    vlan_tag = "10"
  }
  disks {
    disk_size         = "32G"
    format            = "raw"
    io_thread         = true
    storage_pool      = "local-zfs"
    storage_pool_type = "zfs"
    type              = "scsi"
  }
  scsi_controller = "virtio-scsi-single"

  iso_file = "local:iso/debian-11.5.0-amd64-netinst.iso"
  http_directory = "./files"
  boot_wait      = "10s"
  boot_command   = ["<esc><wait>auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<enter>"]
  unmount_iso    = true

  cloud_init              = true
  cloud_init_storage_pool = "local-zfs"

  vm_id = 9000
  vm_name  = "debian-11.5.0-amd64-template"
  cpu_type = "host"
  os       = "l26"
  memory   = 2048
  cores    = 2
  sockets  = "1"

  ssh_username = "debian"
  ssh_password = "debian"
  ssh_timeout = "15m"
}

build {
  name = "debian-11.5.0-amd64-template"
  sources = ["source.proxmox-iso.debian-11-netinstall"]

  provisioner "file" {
    destination = "/tmp/cloud.cfg"
    source      = "files/cloud.cfg"
  }

  provisioner "shell" {
    inline = ["sudo cp /tmp/cloud.cfg /etc/cloud/cloud.cfg"]
  }

}