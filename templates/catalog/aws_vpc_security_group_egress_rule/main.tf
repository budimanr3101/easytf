variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_vpc_security_group_egress_rule" "this" {
  cidr_ipv4                    = try(var.settings.cidr_ipv4, null)
  cidr_ipv6                    = try(var.settings.cidr_ipv6, null)
  description                  = try(var.settings.description, null)
  from_port                    = try(var.settings.from_port, null)
  ip_protocol                  = try(var.settings.ip_protocol, null)
  prefix_list_id               = try(var.settings.prefix_list_id, null)
  referenced_security_group_id = try(var.settings.referenced_security_group_id, null)
  region                       = try(var.settings.region, null)
  security_group_id            = try(var.settings.security_group_id, null)
  tags                         = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  to_port                      = try(var.settings.to_port, null)
}
output "fields" {
  value = {
    arn                    = aws_vpc_security_group_egress_rule.this.arn
    id                     = aws_vpc_security_group_egress_rule.this.id
    region                 = aws_vpc_security_group_egress_rule.this.region
    security_group_rule_id = aws_vpc_security_group_egress_rule.this.security_group_rule_id
  }
}
