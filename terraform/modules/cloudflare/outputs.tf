# Cloudflare module outputs

output "tunnel_id" {
  description = "Cloudflare tunnel ID"
  value       = cloudflare_tunnel.gitlab.id
}

output "tunnel_token" {
  description = "Cloudflare tunnel token for Pi setup"
  value       = cloudflare_tunnel.gitlab.tunnel_token
  sensitive   = true
}

output "zone_id" {
  description = "Cloudflare zone ID"
  value       = data.cloudflare_zone.domain.id
}

output "dns_records" {
  description = "DNS records created"
  value = {
    gitlab = var.pi5_ip != "" ? cloudflare_record.gitlab[0].hostname : cloudflare_record.gitlab_tunnel[0].hostname
    registry = var.pi5_ip != "" ? cloudflare_record.registry[0].hostname : cloudflare_record.registry_tunnel[0].hostname
    grafana = var.pi5_ip != "" ? cloudflare_record.grafana[0].hostname : cloudflare_record.grafana_tunnel[0].hostname
  }
}

output "tunnel_urls" {
  description = "Tunnel URLs for services"
  value = {
    gitlab   = "https://gitlab.${var.domain}"
    registry = "https://registry.${var.domain}"
    grafana  = "https://grafana.${var.domain}"
  }
}
