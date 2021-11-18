variable "region" {
  type        = string
  description = "DigitalOcean region"
  default     = "tor1"
}

variable "vpc_id" {
  type        = string
  description = "VPC id"
  default     = "9b65d3ea-fcdf-4c86-8100-cd97a156c80c"
}

variable "tags" {
  type        = list(string)
  description = "Tags"
  default     = ["addysnip"]
}

variable "node_image" {
  type        = string
  description = "Node image"
  default     = "ubuntu-20-04-x64"
}

variable "node_name" {
  type        = string
  description = "Node name"
  default     = "haproxy"
}

variable "node_size" {
  type        = string
  description = "Node size"
  default     = "s-1vcpu-1gb"
}

variable "ssh_users" {
  type = list(object({
    username        = string
    shell           = string
    sudo            = bool
    github_username = string
  }))
  default = [
    {
      username        = "localuser"
      shell           = "/bin/bash"
      sudo            = false
      github_username = ""
    }
  ]
  description = "List of ssh users to setup"
}

variable "rootdomain" {
  type        = string
  description = "Root domain"
  default     = "addysnip.com"
}

variable "cf_zone_id" {
  type        = string
  description = "Cloudflare zone id"
  default     = "51dcc4f604ff2fae587a3012f234b71a"
}
