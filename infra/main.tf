# Tell Terraform to include the hcloud provider
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.56.0"
    }
    ovh = {
      source  = "ovh/ovh"
      version = "0.39.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}

# Declare the hcloud_token variable from .tfvars
variable "hetzner_api_key" {
  description = "The Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "The public SSH key content to be used for server access."
  type        = string
  sensitive   = true
}

variable "github_username" {
  description = "The GitHub username of the user to be used for SSH access. This is used to fetch SSH keys from GitHub."
  type        = string
  default     = null

  validation {
    condition     = var.github_username != ""
    error_message = "The GitHub username cannot be empty."
  }
}

variable "username" {
  description = "The username for SSH access to the servers."
  type        = string
  default     = "kamal"
}

variable "app_uid" {
  description = "UID of the user running the Rails container (used to own mounted volumes)."
  type        = number
  default     = 1000
}

variable "app_gid" {
  description = "GID of the user running the Rails container (used to own mounted volumes)."
  type        = number
  default     = 1000
}

variable "region" {
  description = "The Hetzner Cloud region where resources will be provisioned. See https://docs.hetzner.com/cloud/general/locations for available locations."
  type        = string
  default     = "nbg1"

  validation {
    condition     = contains(["fsn1", "nbg1", "hel1", "ash", "hil", "sin"], var.region)
    error_message = "The region must be one of fsn1, nbg1, hel1, ash, hil, or sin."
  }
}

variable "server_type" {
  description = "The type of server to deploy. See https://www.hetzner.com/cloud/#pricing for available server types."
  type        = string
  default     = "cx23"

  validation {
    condition = contains(
      [
        "cx23", "cx33", "cx43", "cx53",
        "cpx22", "cpx32", "cpx42", "cpx52", "cpx62",
        "ccx13", "ccx23", "ccx33", "ccx43", "ccx53", "ccx63"
    ], var.server_type)
    error_message = "The server_type must be valid. See https://www.hetzner.com/cloud/#pricing for available server types."
  }
}

variable "operating_system" {
  description = "The operating system image to use for the servers."
  type        = string
  default     = "ubuntu-24.04"
}

variable "enable_ipv4" {
  description = "Enable IPv4 for the public network interface."
  type        = bool
  default     = true
}

variable "enable_ipv6" {
  description = "Enable IPv6 for the public network interface."
  type        = bool
  default     = true
}

variable "wait_for_ssh" {
  description = "Whether Terraform should wait for SSH to be reachable before finishing apply."
  type        = bool
  default     = true
}

variable "ssh_poll_interval_seconds" {
  description = "Seconds between SSH readiness checks."
  type        = number
  default     = 10

  validation {
    condition     = var.ssh_poll_interval_seconds >= 1
    error_message = "ssh_poll_interval_seconds must be >= 1."
  }
}

variable "ssh_poll_timeout_seconds" {
  description = "Total timeout in seconds for waiting on SSH readiness."
  type        = number
  default     = 600

  validation {
    condition     = var.ssh_poll_timeout_seconds >= 30
    error_message = "ssh_poll_timeout_seconds must be >= 30."
  }
}

locals {
  # Single web server IP in private network
  web_server_ip = cidrhost("10.0.0.0/24", 2)
  # Deterministic automount path for the Hetzner volume
  fizzy_mount_path = "/mnt/HC_Volume_${split("HC_Volume_", hcloud_volume.fizzy_storage.linux_device)[1]}"

  # Prefer IPv4 for SSH polling (simpler on most local setups), fallback to IPv6.
  ssh_poll_host = var.enable_ipv4 ? hcloud_server.web_server.ipv4_address : hcloud_server.web_server.ipv6_address
}

variable "allowed_ssh_ips" {
  description = "A list of CIDR-formatted IP address ranges from which SSH access is allowed."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "allowed_http_ips" {
  description = "A list of CIDR-formatted IP address ranges from which HTTP access is allowed."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "allowed_https_ips" {
  description = "A list of CIDR-formatted IP address ranges from which HTTPS access is allowed."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "ovh_endpoint" { type = string }
variable "ovh_application_key" {
  type      = string
  sensitive = true
}
variable "ovh_application_secret" {
  type      = string
  sensitive = true
}
variable "ovh_consumer_key" {
  type      = string
  sensitive = true
}

# Configure the Hetzner Cloud Provider with your token
provider "hcloud" {
  token = var.hetzner_api_key
}

provider "ovh" {
  endpoint           = var.ovh_endpoint
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}

resource "hcloud_ssh_key" "ssh_key_for_hetzner" {
  name       = "ssh-key-for-hetzner"
  public_key = var.ssh_public_key
}

resource "hcloud_network" "network" {
  name     = "private-network"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "network_subnet" {
  type         = "cloud"
  network_id   = hcloud_network.network.id
  network_zone = "eu-central"
  ip_range     = "10.0.0.0/24"
}

resource "hcloud_server" "web_server" {
  name        = "fizzy"
  image       = var.operating_system
  server_type = var.server_type
  location    = var.region
  labels = {
    "ssh"  = "yes",
    "http" = "yes"
  }

  user_data = data.cloudinit_config.web_server_config.rendered

  network {
    network_id = hcloud_network.network.id
    ip         = local.web_server_ip
  }

  ssh_keys = [
    hcloud_ssh_key.ssh_key_for_hetzner.id
  ]

  public_net {
    ipv4_enabled = var.enable_ipv4
    ipv6_enabled = var.enable_ipv6
  }
}

resource "hcloud_firewall" "web_server_and_ssh" {
  name = "Web Server and SSH"

  rule {
    description = "Allow HTTP traffic"
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    description = "Allow HTTPS traffic"
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    description = "Allow SSH traffic"
    direction   = "in"
    protocol    = "tcp"
    port        = "2222"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}

# Attach the firewall to the server so rules apply
resource "hcloud_firewall_attachment" "web_fw_attach" {
  firewall_id = hcloud_firewall.web_server_and_ssh.id
  server_ids  = [hcloud_server.web_server.id]
}

# After a brand new server is created, it can take a couple minutes until cloud-init finishes
# and SSH logins are accepted. This keeps `terraform apply` from returning early.
resource "null_resource" "wait_for_ssh" {
  count = var.wait_for_ssh ? 1 : 0

  triggers = {
    server_id = hcloud_server.web_server.id
    host      = local.ssh_poll_host
    user      = var.username
    port      = "2222"
    interval  = tostring(var.ssh_poll_interval_seconds)
    timeout   = tostring(var.ssh_poll_timeout_seconds)
  }

  depends_on = [
    hcloud_server.web_server,
    hcloud_firewall_attachment.web_fw_attach,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOT
      set -euo pipefail

      host="${local.ssh_poll_host}"
      user="${var.username}"
      port="2222"
      interval="${var.ssh_poll_interval_seconds}"
      timeout="${var.ssh_poll_timeout_seconds}"

      if [[ -z "$host" ]]; then
        echo "SSH wait skipped: no public IP available (check enable_ipv4/enable_ipv6)." >&2
        exit 0
      fi

      echo "Waiting for SSH to be ready at $user@$host:$port (poll ${var.ssh_poll_interval_seconds}s, timeout ${var.ssh_poll_timeout_seconds}s)..."
      echo "Note: this checks real SSH login using your local SSH agent/keys."

      deadline=$((SECONDS + timeout))
      while true; do
        if ssh \
          -p "$port" \
          -o BatchMode=yes \
          -o PasswordAuthentication=no \
          -o KbdInteractiveAuthentication=no \
          -o ConnectTimeout=5 \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          "$user@$host" "echo ok" >/dev/null 2>&1; then
          echo "SSH is ready."
          exit 0
        fi

        if (( SECONDS >= deadline )); then
          echo "Timed out after ${var.ssh_poll_timeout_seconds}s waiting for SSH readiness." >&2
          exit 1
        fi

        sleep "$interval"
      done
    EOT
  }
}

# Configure a stable bind mount for the Hetzner volume and ensure the Rails UID/GID can write.
# This is intentionally done *after* SSH is reachable.
resource "null_resource" "configure_volume_mount" {
  triggers = {
    server_id = hcloud_server.web_server.id
    host      = local.ssh_poll_host
    user      = var.username
    port      = "2222"
    source    = local.fizzy_mount_path
    target    = "/mnt/fizzy_storage"
    app_uid   = tostring(var.app_uid)
    app_gid   = tostring(var.app_gid)
  }

  depends_on = [
    hcloud_server.web_server,
    hcloud_firewall_attachment.web_fw_attach,
    hcloud_volume_attachment.fizzy_storage_attachment,
    null_resource.wait_for_ssh,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOT
      set -euo pipefail

      host="${local.ssh_poll_host}"
      user="${var.username}"
      port="2222"

      if [[ -z "$host" ]]; then
        echo "Volume mount skipped: no public IP available (check enable_ipv4/enable_ipv6)." >&2
        exit 0
      fi

      # Execute the mount setup on the server.
      ssh \
        -p "$port" \
        -o BatchMode=yes \
        -o PasswordAuthentication=no \
        -o KbdInteractiveAuthentication=no \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$user@$host" "sudo -n bash -s" <<'REMOTE'
      set -euo pipefail

      SOURCE="${local.fizzy_mount_path}"
      TARGET="/mnt/fizzy_storage"
      APP_UID="${var.app_uid}"
      APP_GID="${var.app_gid}"

      # The volume is automounted by Hetzner, but the directory can appear slightly later.
      for _ in $(seq 1 30); do
        [[ -d "$SOURCE" ]] && break
        sleep 2
      done

      if [[ ! -d "$SOURCE" ]]; then
        echo "Source volume mount $SOURCE not found; expected automount to be present." >&2
        exit 1
      fi

      mkdir -p "$TARGET"

      # Persist the bind mount so reboots keep the path stable.
      if ! grep -qsE "^[^#]*[[:space:]]+$TARGET[[:space:]]+none[[:space:]]+bind" /etc/fstab; then
        echo "$SOURCE $TARGET none bind 0 0" >> /etc/fstab
      fi

      # Ensure the bind mount is active now.
      if ! mountpoint -q "$TARGET"; then
        mount --bind "$SOURCE" "$TARGET"
      fi

      # Ownership and mode so the rails user (uid/gid 1000 by default) can write.
      chown "$APP_UID:$APP_GID" "$SOURCE" "$TARGET"
      chmod 2775 "$SOURCE" "$TARGET"
REMOTE
    EOT
  }
}

data "cloudinit_config" "web_server_config" {
  gzip          = true
  base64_encode = true

  # Base system configuration
  part {
    content_type = "text/cloud-config"
    content = templatefile("./cloudinit/base.yml", {
      hostname        = "web"
      username        = var.username
      github_username = var.github_username
    })
  }
}

# Persistent block storage volume for app data (Active Storage, sqlite, etc.)
resource "hcloud_volume" "fizzy_storage" {
  name     = "fizzy_storage"
  size     = 20 # GB
  location = var.region
  format   = "ext4"
}

# Attach volume to server
resource "hcloud_volume_attachment" "fizzy_storage_attachment" {
  volume_id = hcloud_volume.fizzy_storage.id
  server_id = hcloud_server.web_server.id
  automount = true
}

resource "ovh_domain_zone_record" "fizzy_a" {
  zone      = "gual.me"
  subdomain = "fizzy"
  fieldtype = "A"
  ttl       = 60
  target    = hcloud_server.web_server.ipv4_address
}

resource "ovh_domain_zone_record" "fizzy_aaaa" {
  zone      = "gual.me"
  subdomain = "fizzy"
  fieldtype = "AAAA"
  ttl       = 60
  target    = hcloud_server.web_server.ipv6_address
}


output "ipv4_web_address" {
  value = {
    (hcloud_server.web_server.name) = hcloud_server.web_server.ipv4_address
  }
}

output "volume_original_mountpoint" {
  value = "/mnt/HC_Volume_${split("HC_Volume_", hcloud_volume.fizzy_storage.linux_device)[1]}"
}
