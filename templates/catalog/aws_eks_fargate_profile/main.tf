variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_eks_fargate_profile" "this" {
  cluster_name           = try(var.settings.cluster_name, null)
  fargate_profile_name   = try(var.settings.fargate_profile_name, null)
  pod_execution_role_arn = try(var.settings.pod_execution_role_arn, null)
  region                 = try(var.settings.region, null)
  subnet_ids             = try(var.settings.subnet_ids, null)
  tags                   = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all               = try(var.settings.tags_all, null)
  dynamic "selector" {
    for_each = coalesce(try(var.settings.selector, null), [])
    iterator = b0
    content {
      labels    = try(b0.value.labels, null)
      namespace = try(b0.value.namespace, null)
    }
  }
}
output "fields" {
  value = {
    arn          = aws_eks_fargate_profile.this.arn
    cluster_name = aws_eks_fargate_profile.this.cluster_name
    id           = aws_eks_fargate_profile.this.id
    region       = aws_eks_fargate_profile.this.region
    status       = aws_eks_fargate_profile.this.status
  }
}
