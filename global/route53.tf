resource "aws_route53_zone" "hosted_zones" {
  # Need to mark as nonsensitive since Terraform treats SSM parameter values as sensitive by default
  for_each = toset(split(",", nonsensitive(data.aws_ssm_parameter.hosted_zone_names.value)))
  name     = each.value
}

resource "aws_route53_record" "observations" {
  for_each = aws_route53_zone.hosted_zones
  zone_id  = each.value.id
  type     = "A"
  ttl      = 1800
  name     = "observations"
  records  = [data.aws_ssm_parameter.observations_ip.value]

}

resource "aws_route53_record" "radar" {
  for_each = aws_route53_zone.hosted_zones
  zone_id  = each.value.id
  type     = "A"
  ttl      = 1800
  name     = "radar"

  records = [data.aws_ssm_parameter.radar_ip.value]
}

resource "aws_route53_record" "root" {
  for_each = aws_route53_zone.hosted_zones
  zone_id  = each.value.id
  type     = "A"
  ttl      = 1800
  name     = "" # Empty name for root domain

  records = [data.aws_ssm_parameter.root_ip.value]
}
