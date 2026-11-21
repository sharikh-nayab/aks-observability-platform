variable "name_prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = null
}

variable "sku_tier" {
  type    = string
  default = "Free"
}

variable "availability_zones" {
  type    = list(string)
  default = ["1", "2", "3"]
}

variable "system_node_size" {
  type = string
}

variable "system_node_count" {
  type = number
}

variable "user_node_size" {
  type = string
}

variable "user_node_min" {
  type = number
}

variable "user_node_max" {
  type = number
}

variable "pod_cidr" {
  type = string
}

variable "service_cidr" {
  type = string
}

variable "dns_service_ip" {
  type = string
}

variable "admin_group_object_ids" {
  type    = list(string)
  default = []
}

variable "authorized_ip_ranges" {
  type    = list(string)
  default = []
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
