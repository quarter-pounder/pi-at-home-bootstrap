# Manages DNS records and Cloudflare tunnel

# Get Cloudflare zone ID
data "cloudflare_zone" "domain" {
  name = var.domain
}

# Create Cloudflare tunnel
resource "cloudflare_tunnel" "gitlab" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
}

# Create tunnel configuration
resource "cloudflare_tunnel_config" "gitlab" {
  tunnel_id = cloudflare_tunnel.gitlab.id

  config {
    ingress_rule {
      hostname = "gitlab.${var.domain}"
      service  = "http://localhost:80"
    }
    ingress_rule {
      hostname = "registry.${var.domain}"
      service  = "http://localhost:5050"
    }
    ingress_rule {
      hostname = "grafana.${var.domain}"
      service  = "http://localhost:${var.grafana_port}"
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# DNS records for GitLab services
resource "cloudflare_record" "gitlab" {
  count   = var.pi5_ip != "" ? 1 : 0
  zone_id = data.cloudflare_zone.domain.id
  name    = "gitlab"
  content = var.pi5_ip
  type    = "A"
  ttl     = 300
  comment = "GitLab Pi - managed by Terraform"
}

resource "cloudflare_record" "registry" {
  count   = var.pi5_ip != "" ? 1 : 0
  zone_id = data.cloudflare_zone.domain.id
  name    = "registry"
  content = var.pi5_ip
  type    = "A"
  ttl     = 300
  comment = "GitLab Registry - managed by Terraform"
}

resource "cloudflare_record" "grafana" {
  count   = var.pi5_ip != "" ? 1 : 0
  zone_id = data.cloudflare_zone.domain.id
  name    = "grafana"
  content = var.pi5_ip
  type    = "A"
  ttl     = 300
  comment = "Grafana - managed by Terraform"
}

# Optional: CNAME records for tunnel (if not using A records)
resource "cloudflare_record" "gitlab_tunnel" {
  count   = var.pi5_ip == "" ? 1 : 0
  zone_id = data.cloudflare_zone.domain.id
  name    = "gitlab"
  content = "${cloudflare_tunnel.gitlab.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 300
  comment = "GitLab Pi Tunnel - managed by Terraform"
}

resource "cloudflare_record" "registry_tunnel" {
  count   = var.pi5_ip == "" ? 1 : 0
  zone_id = data.cloudflare_zone.domain.id
  name    = "registry"
  content = "${cloudflare_tunnel.gitlab.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 300
  comment = "GitLab Registry Tunnel - managed by Terraform"
}

resource "cloudflare_record" "grafana_tunnel" {
  count   = var.pi5_ip == "" ? 1 : 0
  zone_id = data.cloudflare_zone.domain.id
  name    = "grafana"
  content = "${cloudflare_tunnel.gitlab.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 300
  comment = "Grafana Tunnel - managed by Terraform"
}
