terraform {
    required_providers {
        digitalocean = {
            source = "digitalocean/digitalocean"
            version = "~> 2.0"
        }

        helm = {
            source = "hashicorp/helm"
        }

        kubernetes = {
            source = "hashicorp/kubernetes"
        }

        kubectl = {
            source = "gavinbunney/kubectl"
        }
    }
}

variable "do_token" {}

provider "digitalocean" {
    token = var.do_token
}

provider "helm" {
    kubernetes {
        host = digitalocean_kubernetes_cluster.k8s_cluster.endpoint
        token = digitalocean_kubernetes_cluster.k8s_cluster.kube_config[0].token

        cluster_ca_certificate = base64decode(
            digitalocean_kubernetes_cluster.k8s_cluster.kube_config[0].cluster_ca_certificate
        )
    }
}

provider "kubernetes" {
    host = digitalocean_kubernetes_cluster.k8s_cluster.endpoint
    token = digitalocean_kubernetes_cluster.k8s_cluster.kube_config[0].token
    cluster_ca_certificate = base64decode(
        digitalocean_kubernetes_cluster.k8s_cluster.kube_config[0].cluster_ca_certificate
    )
}

provider "kubectl" {
    load_config_file = false
    host = digitalocean_kubernetes_cluster.k8s_cluster.endpoint
    token = digitalocean_kubernetes_cluster.k8s_cluster.kube_config[0].token
    cluster_ca_certificate = base64decode(
        digitalocean_kubernetes_cluster.k8s_cluster.kube_config[0].cluster_ca_certificate
    )
    apply_retry_count = 5
}