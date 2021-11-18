variable "region" {
  type        = string
  description = "DigitalOcean region"
  default     = "sfo3"
}

variable "vpc_name" {
  type        = string
  description = "VPC name"
  default     = "k8s-sfo3-vpc"
}

variable "vpc_range" {
  type        = string
  description = "VPC IP range"
  default     = "192.168.16.0/20"
}

variable "cluster_name" {
  type        = string
  description = "Cluster name"
  default     = "addysnip-sfo3-1"
}

variable "k8s_version" {
  type        = string
  description = "Kubernetes version"
  default     = "1.21.5-do.0"
}

variable "tags" {
  type        = list(string)
  description = "Tags"
  default     = ["addysnip"]
}

variable "k8s_nodepool_size" {
  type        = string
  description = "Kubernetes node pool size"
  default     = "s-2vcpu-4gb"
}

variable "k8s_nodepool_count" {
  type        = number
  description = "Kubernetes node pool count"
  default     = 1
}
