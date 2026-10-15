variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_iam_policy" "this" {
  delay_after_policy_creation_in_ms = try(var.settings.delay_after_policy_creation_in_ms, null)
  description                       = try(var.settings.description, null)
  name                              = try(var.settings.name, null)
  name_prefix                       = try(var.settings.name_prefix, null)
  path                              = try(var.settings.path, null)
  policy                            = try(var.settings.policy, null)
  tags                              = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                          = try(var.settings.tags_all, null)
}
output "fields" {
  value = {
    arn              = aws_iam_policy.this.arn
    attachment_count = aws_iam_policy.this.attachment_count
    id               = aws_iam_policy.this.id
    name             = aws_iam_policy.this.name
    name_prefix      = aws_iam_policy.this.name_prefix
    policy_id        = aws_iam_policy.this.policy_id
  }
}
