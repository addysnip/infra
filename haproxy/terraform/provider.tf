terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 3.4.0"
    }
  }
}

variable "do_token" {}
variable "cf_apikey" {}
variable "cf_email" {}

provider "digitalocean" {
  token = var.do_token
}

provider "cloudflare" {
  email   = var.cf_email
  api_key = var.cf_apikey
}
