variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_iam_role_policy_attachment" "this" {
  policy_arn = try(var.settings.policy_arn, null)
  role       = try(var.settings.role, null)
}
output "fields" {
  value = {
    id = aws_iam_role_policy_attachment.this.id
  }
}
