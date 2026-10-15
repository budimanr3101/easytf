variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_eks_addon" "this" {
  addon_name                  = try(var.settings.addon_name, null)
  addon_version               = try(var.settings.addon_version, null)
  cluster_name                = try(var.settings.cluster_name, null)
  configuration_values        = try(var.settings.configuration_values, null)
  preserve                    = try(var.settings.preserve, null)
  region                      = try(var.settings.region, null)
  resolve_conflicts_on_create = try(var.settings.resolve_conflicts_on_create, null)
  resolve_conflicts_on_update = try(var.settings.resolve_conflicts_on_update, null)
  service_account_role_arn    = try(var.settings.service_account_role_arn, null)
  tags                        = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                    = try(var.settings.tags_all, null)
  dynamic "namespace_config" {
    for_each = coalesce(try(var.settings.namespace_config, null), [])
    iterator = b0
    content {
      namespace = try(b0.value.namespace, null)
    }
  }
  dynamic "pod_identity_association" {
    for_each = coalesce(try(var.settings.pod_identity_association, null), [])
    iterator = b0
    content {
      role_arn        = try(b0.value.role_arn, null)
      service_account = try(b0.value.service_account, null)
    }
  }
}
output "fields" {
  value = {
    addon_version        = aws_eks_addon.this.addon_version
    arn                  = aws_eks_addon.this.arn
    cluster_name         = aws_eks_addon.this.cluster_name
    configuration_values = aws_eks_addon.this.configuration_values
    created_at           = aws_eks_addon.this.created_at
    id                   = aws_eks_addon.this.id
    modified_at          = aws_eks_addon.this.modified_at
    region               = aws_eks_addon.this.region
  }
}
