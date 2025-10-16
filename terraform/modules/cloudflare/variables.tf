# Cloudflare module variables

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
  default     = ""
}

variable "domain" {
  description = "Domain name for GitLab services"
  type        = string
}

variable "tunnel_name" {
  description = "Name for the Cloudflare tunnel"
  type        = string
  default     = "gitlab-pi"
}

variable "pi5_ip" {
  description = "IP address of the Raspberry Pi 5 (leave empty to use tunnel CNAMEs)"
  type        = string
  default     = ""
}

variable "grafana_port" {
  description = "Port for Grafana service"
  type        = number
  default     = 3000
}
