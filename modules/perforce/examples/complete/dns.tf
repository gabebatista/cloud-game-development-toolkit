##########################################
# Perforce Helix DNS
##########################################

# fetch hosted zone for root domain name
data "aws_route53_zone" "root" {
  name         = var.fully_qualified_domain_name
  private_zone = false
}

# create hosted zone for helix subdomain
resource "aws_route53_zone" "helix" {
  name = "helix.${data.aws_route53_zone.root.name}"
  #checkov:skip=CKV2_AWS_38: Hosted zone is private (vpc association)
  #checkov:skip=CKV2_AWS_39: Query logging disabled by design
}

# Add NS record to root domain hosted zone for helix subdomain
resource "aws_route53_record" "helix_ns" {
  zone_id = data.aws_route53_zone.root.id
  name    = aws_route53_zone.helix.name
  type    = "NS"
  records = aws_route53_zone.helix.name_servers
}

resource "aws_route53_record" "helix_swarm" {
  zone_id = aws_route53_zone.helix.id
  name    = "swarm.${aws_route53_zone.helix.name}"
  type    = "A"
  alias {
    name                   = module.perforce_helix_swarm.alb_dns_name
    zone_id                = module.perforce_helix_swarm.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "helix_authentication_service" {
  zone_id = aws_route53_zone.helix.id
  name    = "auth.${aws_route53_zone.helix.name}"
  type    = "A"
  alias {
    name                   = module.perforce_helix_authentication_service.alb_dns_name
    zone_id                = module.perforce_helix_authentication_service.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "perforce_helix_core" {
  zone_id = aws_route53_zone.helix.zone_id
  name    = "core.${aws_route53_zone.helix.name}"
  type    = "A"
  ttl     = 300
  #checkov:skip=CKV2_AWS_23:The attached resource is managed by CGD Toolkit
  records = [module.perforce_helix_core.helix_core_eip_private_ip]
}

##########################################
# Perforce Helix Certificate Management
##########################################

resource "aws_acm_certificate" "helix" {
  domain_name       = "*.${aws_route53_zone.helix.name}"
  validation_method = "DNS"

  tags = {
    Environment = "dev"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "helix_cert" {
  for_each = {
    for dvo in aws_acm_certificate.helix.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.helix.id
}

resource "aws_acm_certificate_validation" "helix" {
  timeouts {
    create = "15m"
  }
  certificate_arn         = aws_acm_certificate.helix.arn
  validation_record_fqdns = [for record in aws_route53_record.helix_cert : record.fqdn]
}
