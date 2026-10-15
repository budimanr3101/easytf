variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_route53_record" "this" {
  allow_overwrite                  = try(var.settings.allow_overwrite, null)
  health_check_id                  = try(var.settings.health_check_id, null)
  multivalue_answer_routing_policy = try(var.settings.multivalue_answer_routing_policy, null)
  name                             = try(var.settings.name, null)
  records                          = try(var.settings.records, null)
  set_identifier                   = try(var.settings.set_identifier, null)
  ttl                              = try(var.settings.ttl, null)
  type                             = try(var.settings.type, null)
  zone_id                          = try(var.settings.zone_id, null)
  dynamic "alias" {
    for_each = coalesce(try(var.settings.alias, null), [])
    iterator = b0
    content {
      evaluate_target_health = try(b0.value.evaluate_target_health, null)
      name                   = try(b0.value.name, null)
      zone_id                = try(b0.value.zone_id, null)
    }
  }
  dynamic "cidr_routing_policy" {
    for_each = coalesce(try(var.settings.cidr_routing_policy, null), [])
    iterator = b0
    content {
      collection_id = try(b0.value.collection_id, null)
      location_name = try(b0.value.location_name, null)
    }
  }
  dynamic "failover_routing_policy" {
    for_each = coalesce(try(var.settings.failover_routing_policy, null), [])
    iterator = b0
    content {
      type = try(b0.value.type, null)
    }
  }
  dynamic "geolocation_routing_policy" {
    for_each = coalesce(try(var.settings.geolocation_routing_policy, null), [])
    iterator = b0
    content {
      continent   = try(b0.value.continent, null)
      country     = try(b0.value.country, null)
      subdivision = try(b0.value.subdivision, null)
    }
  }
  dynamic "geoproximity_routing_policy" {
    for_each = coalesce(try(var.settings.geoproximity_routing_policy, null), [])
    iterator = b0
    content {
      aws_region       = try(b0.value.aws_region, null)
      bias             = try(b0.value.bias, null)
      local_zone_group = try(b0.value.local_zone_group, null)
      dynamic "coordinates" {
        for_each = coalesce(try(b0.value.coordinates, null), [])
        iterator = b1
        content {
          latitude  = try(b1.value.latitude, null)
          longitude = try(b1.value.longitude, null)
        }
      }
    }
  }
  dynamic "latency_routing_policy" {
    for_each = coalesce(try(var.settings.latency_routing_policy, null), [])
    iterator = b0
    content {
      region = try(b0.value.region, null)
    }
  }
  dynamic "weighted_routing_policy" {
    for_each = coalesce(try(var.settings.weighted_routing_policy, null), [])
    iterator = b0
    content {
      weight = try(b0.value.weight, null)
    }
  }
}
output "fields" {
  value = {
    allow_overwrite = aws_route53_record.this.allow_overwrite
    fqdn            = aws_route53_record.this.fqdn
    id              = aws_route53_record.this.id
    name            = aws_route53_record.this.name
  }
}
