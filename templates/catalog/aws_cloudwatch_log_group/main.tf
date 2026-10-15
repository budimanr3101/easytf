variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_cloudwatch_log_group" "this" {
  deletion_protection_enabled = try(var.settings.deletion_protection_enabled, null)
  kms_key_id                  = try(var.settings.kms_key_id, null)
  log_group_class             = try(var.settings.log_group_class, null)
  name                        = try(var.settings.name, null)
  name_prefix                 = try(var.settings.name_prefix, null)
  region                      = try(var.settings.region, null)
  retention_in_days           = try(var.settings.retention_in_days, null)
  skip_destroy                = try(var.settings.skip_destroy, null)
  tags                        = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                    = try(var.settings.tags_all, null)
}
output "fields" {
  value = {
    arn                         = aws_cloudwatch_log_group.this.arn
    deletion_protection_enabled = aws_cloudwatch_log_group.this.deletion_protection_enabled
    id                          = aws_cloudwatch_log_group.this.id
    log_group_class             = aws_cloudwatch_log_group.this.log_group_class
    name                        = aws_cloudwatch_log_group.this.name
    name_prefix                 = aws_cloudwatch_log_group.this.name_prefix
    region                      = aws_cloudwatch_log_group.this.region
  }
}
