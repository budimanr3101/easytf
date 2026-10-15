variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_rds_cluster_parameter_group" "this" {
  description = try(var.settings.description, null)
  family      = try(var.settings.family, null)
  name        = try(var.settings.name, null)
  name_prefix = try(var.settings.name_prefix, null)
  region      = try(var.settings.region, null)
  tags        = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all    = try(var.settings.tags_all, null)
  dynamic "parameter" {
    for_each = coalesce(try(var.settings.parameter, null), [])
    iterator = b0
    content {
      apply_method = try(b0.value.apply_method, null)
      name         = try(b0.value.name, null)
      value        = try(b0.value.value, null)
    }
  }
}
output "fields" {
  value = {
    arn         = aws_rds_cluster_parameter_group.this.arn
    id          = aws_rds_cluster_parameter_group.this.id
    name        = aws_rds_cluster_parameter_group.this.name
    name_prefix = aws_rds_cluster_parameter_group.this.name_prefix
    region      = aws_rds_cluster_parameter_group.this.region
  }
}
