variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_eks_access_policy_association" "this" {
  cluster_name  = try(var.settings.cluster_name, null)
  policy_arn    = try(var.settings.policy_arn, null)
  principal_arn = try(var.settings.principal_arn, null)
  region        = try(var.settings.region, null)
  dynamic "access_scope" {
    for_each = coalesce(try(var.settings.access_scope, null), [])
    iterator = b0
    content {
      namespaces = try(b0.value.namespaces, null)
      type       = try(b0.value.type, null)
    }
  }
}
output "fields" {
  value = {
    associated_at = aws_eks_access_policy_association.this.associated_at
    cluster_name  = aws_eks_access_policy_association.this.cluster_name
    id            = aws_eks_access_policy_association.this.id
    modified_at   = aws_eks_access_policy_association.this.modified_at
    region        = aws_eks_access_policy_association.this.region
  }
}
