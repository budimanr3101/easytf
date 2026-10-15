variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_route53_zone" "this" {
  comment                     = try(var.settings.comment, null)
  delegation_set_id           = try(var.settings.delegation_set_id, null)
  enable_accelerated_recovery = try(var.settings.enable_accelerated_recovery, null)
  force_destroy               = try(var.settings.force_destroy, null)
  name                        = try(var.settings.name, null)
  tags                        = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                    = try(var.settings.tags_all, null)
  dynamic "vpc" {
    for_each = coalesce(try(var.settings.vpc, null), [])
    iterator = b0
    content {
      vpc_id     = try(b0.value.vpc_id, null)
      vpc_region = try(b0.value.vpc_region, null)
    }
  }
}
output "fields" {
  value = {
    arn                         = aws_route53_zone.this.arn
    enable_accelerated_recovery = aws_route53_zone.this.enable_accelerated_recovery
    id                          = aws_route53_zone.this.id
    name                        = aws_route53_zone.this.name
    primary_name_server         = aws_route53_zone.this.primary_name_server
    zone_id                     = aws_route53_zone.this.zone_id
  }
}
