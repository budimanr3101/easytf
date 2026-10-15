variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_iam_role" "this" {
  assume_role_policy    = try(var.settings.assume_role_policy, null)
  description           = try(var.settings.description, null)
  force_detach_policies = try(var.settings.force_detach_policies, null)
  max_session_duration  = try(var.settings.max_session_duration, null)
  name                  = try(var.settings.name, null)
  name_prefix           = try(var.settings.name_prefix, null)
  path                  = try(var.settings.path, null)
  permissions_boundary  = try(var.settings.permissions_boundary, null)
  tags                  = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all              = try(var.settings.tags_all, null)
  dynamic "inline_policy" {
    for_each = coalesce(try(var.settings.inline_policy, null), [])
    iterator = b0
    content {
      name   = try(b0.value.name, null)
      policy = try(b0.value.policy, null)
    }
  }
}
output "fields" {
  value = {
    arn         = aws_iam_role.this.arn
    create_date = aws_iam_role.this.create_date
    id          = aws_iam_role.this.id
    name        = aws_iam_role.this.name
    name_prefix = aws_iam_role.this.name_prefix
    unique_id   = aws_iam_role.this.unique_id
  }
}
