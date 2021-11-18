resource "digitalocean_droplet" "haproxy" {
  image      = var.node_image
  name       = var.node_name
  region     = var.region
  size       = var.node_size
  vpc_uuid   = var.vpc_id
  monitoring = true
  ipv6       = true
  tags       = var.tags

  user_data = data.template_cloudinit_config.config.rendered
}

data "template_cloudinit_config" "config" {
  gzip          = false
  base64_encode = false

  part {
    filename     = "terraform.tpl"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloudinit/01-init.tpl", {
      ssh_users = var.ssh_users
      hostname  = "${var.node_name}.${var.region}.${var.rootdomain}"
    })
  }
  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/cloudinit/02-configure.sh.tpl", {
      ssh_users = var.ssh_users
      hostname  = "${var.node_name}.${var.region}.${var.rootdomain}"
    })
  }
}

resource "cloudflare_record" "haproxyA" {
  zone_id = var.cf_zone_id
  name    = "${var.node_name}.${var.region}"
  type    = "A"
  value   = digitalocean_droplet.haproxy.ipv4_address
  ttl     = 120
}

resource "cloudflare_record" "haproxyAAAA" {
  zone_id = var.cf_zone_id
  name    = "${var.node_name}.${var.region}"
  type    = "AAAA"
  value   = digitalocean_droplet.haproxy.ipv6_address
  ttl     = 120
}

output "ip" {
  value = digitalocean_droplet.haproxy.ipv4_address
}

output "ip6" {
  value = digitalocean_droplet.haproxy.ipv6_address
}

resource "local_file" "inventory" {
  filename = "../inventory.ini"
  content = templatefile("${path.module}/inventory.tpl", {
    hostnames  = digitalocean_droplet.haproxy.*.name
    region     = var.region
    rootdomain = var.rootdomain
  })
}
