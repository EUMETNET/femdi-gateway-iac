# These records are related to meteogate.eu but not directly related to gateway solutions
# Records are kept here (= currently no better place available) 
# when moving to different AWS account these records are not dropped by mistake

resource "aws_route53_record" "observations" {
  zone_id = var.new_route53_zone_id_filter
  type    = "A"
  ttl     = 1800
  name    = "observations"

  records = [var.observations_ip]

}

resource "aws_route53_record" "radar" {
  zone_id = var.new_route53_zone_id_filter
  type    = "A"
  ttl     = 1800
  name    = "radar"

  records = [var.radar_ip]

}
