variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_ecr_lifecycle_policy" "this" {
  policy     = try(var.settings.policy, null)
  region     = try(var.settings.region, null)
  repository = try(var.settings.repository, null)
}
output "fields" {
  value = {
    id          = aws_ecr_lifecycle_policy.this.id
    region      = aws_ecr_lifecycle_policy.this.region
    registry_id = aws_ecr_lifecycle_policy.this.registry_id
  }
}
