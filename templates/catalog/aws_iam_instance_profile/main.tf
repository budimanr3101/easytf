variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_iam_instance_profile" "this" {
  name        = try(var.settings.name, null)
  name_prefix = try(var.settings.name_prefix, null)
  path        = try(var.settings.path, null)
  role        = try(var.settings.role, null)
  tags        = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all    = try(var.settings.tags_all, null)
}
output "fields" {
  value = {
    arn         = aws_iam_instance_profile.this.arn
    create_date = aws_iam_instance_profile.this.create_date
    id          = aws_iam_instance_profile.this.id
    name        = aws_iam_instance_profile.this.name
    name_prefix = aws_iam_instance_profile.this.name_prefix
    unique_id   = aws_iam_instance_profile.this.unique_id
  }
}
