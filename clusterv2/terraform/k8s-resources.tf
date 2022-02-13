resource "digitalocean_kubernetes_cluster" "k8s_cluster" {
  name          = var.cluster_name
  region        = var.region
  version       = var.k8s_version
  vpc_uuid      = "9b65d3ea-fcdf-4c86-8100-cd97a156c80c"
  auto_upgrade  = false
  surge_upgrade = true
  tags          = var.tags
  node_pool {
    name       = "${var.cluster_name}-pool"
    size       = var.k8s_nodepool_size
    node_count = var.k8s_nodepool_count
    tags       = var.tags
  }
}

resource "kubernetes_namespace" "cert-manager" {
  metadata {
    name = "cert-manager"
  }

  depends_on = [digitalocean_kubernetes_cluster.k8s_cluster]
}

resource "helm_release" "cert-manager" {
  name = "cert-manager"

  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [kubernetes_namespace.cert-manager]
}

output "k8s_cluster" {
  value = digitalocean_kubernetes_cluster.k8s_cluster.id
}

output "k8s_cluster_name" {
  value = digitalocean_kubernetes_cluster.k8s_cluster.name
}

output "k8s_region" {
  value = var.region
}
