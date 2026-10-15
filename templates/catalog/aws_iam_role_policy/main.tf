variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_iam_role_policy" "this" {
  name        = try(var.settings.name, null)
  name_prefix = try(var.settings.name_prefix, null)
  policy      = try(var.settings.policy, null)
  role        = try(var.settings.role, null)
}
output "fields" {
  value = {
    id          = aws_iam_role_policy.this.id
    name        = aws_iam_role_policy.this.name
    name_prefix = aws_iam_role_policy.this.name_prefix
  }
}
