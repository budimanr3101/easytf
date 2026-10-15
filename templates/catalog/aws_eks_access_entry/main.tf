variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_eks_access_entry" "this" {
  cluster_name      = try(var.settings.cluster_name, null)
  kubernetes_groups = try(var.settings.kubernetes_groups, null)
  principal_arn     = try(var.settings.principal_arn, null)
  region            = try(var.settings.region, null)
  tags              = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all          = try(var.settings.tags_all, null)
  type              = try(var.settings.type, null)
  user_name         = try(var.settings.user_name, null)
}
output "fields" {
  value = {
    access_entry_arn = aws_eks_access_entry.this.access_entry_arn
    cluster_name     = aws_eks_access_entry.this.cluster_name
    created_at       = aws_eks_access_entry.this.created_at
    id               = aws_eks_access_entry.this.id
    modified_at      = aws_eks_access_entry.this.modified_at
    region           = aws_eks_access_entry.this.region
    user_name        = aws_eks_access_entry.this.user_name
  }
}
