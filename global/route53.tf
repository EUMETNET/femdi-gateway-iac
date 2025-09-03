resource "aws_route53_zone" "hosted_zones" {
  for_each = toset(var.hosted_zone_names)
  name     = each.value
}

# Uncomment following zones once the "main" zone is moved to new AWS account

#resource "aws_route53_zone" "meteogate_org" {
#  name = "meteogate.org"
#}
#
#resource "aws_route53_zone" "meteogate_net" {
#  name = "meteogate.net"
#}

resource "aws_route53_record" "observations" {
  for_each = aws_route53_zone.hosted_zones
  zone_id  = each.value.id
  type     = "A"
  ttl      = 1800
  name     = "observations"
  records  = [var.observations_ip]

}

resource "aws_route53_record" "radar" {
  for_each = aws_route53_zone.hosted_zones
  zone_id  = each.value.id
  type     = "A"
  ttl      = 1800
  name     = "radar"

  records = [var.radar_ip]
}

resource "aws_route53_record" "root" {
  for_each = aws_route53_zone.hosted_zones
  zone_id  = each.value.id
  type     = "A"
  ttl      = 1800
  name     = "" # Empty name for root domain

  records = [var.root_ip]
}
