variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_security_group" "this" {
  description            = try(var.settings.description, null)
  egress                 = try(var.settings.egress, null)
  ingress                = try(var.settings.ingress, null)
  name                   = try(var.settings.name, null)
  name_prefix            = try(var.settings.name_prefix, null)
  region                 = try(var.settings.region, null)
  revoke_rules_on_delete = try(var.settings.revoke_rules_on_delete, null)
  tags                   = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all               = try(var.settings.tags_all, null)
  vpc_id                 = try(var.settings.vpc_id, null)
}
output "fields" {
  value = {
    arn         = aws_security_group.this.arn
    id          = aws_security_group.this.id
    name        = aws_security_group.this.name
    name_prefix = aws_security_group.this.name_prefix
    owner_id    = aws_security_group.this.owner_id
    region      = aws_security_group.this.region
    vpc_id      = aws_security_group.this.vpc_id
  }
}
