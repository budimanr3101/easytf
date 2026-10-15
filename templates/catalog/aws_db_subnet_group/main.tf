variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_db_subnet_group" "this" {
  description = try(var.settings.description, null)
  name        = try(var.settings.name, null)
  name_prefix = try(var.settings.name_prefix, null)
  region      = try(var.settings.region, null)
  subnet_ids  = try(var.settings.subnet_ids, null)
  tags        = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all    = try(var.settings.tags_all, null)
}
output "fields" {
  value = {
    arn         = aws_db_subnet_group.this.arn
    id          = aws_db_subnet_group.this.id
    name        = aws_db_subnet_group.this.name
    name_prefix = aws_db_subnet_group.this.name_prefix
    region      = aws_db_subnet_group.this.region
    vpc_id      = aws_db_subnet_group.this.vpc_id
  }
}
