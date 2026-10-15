variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_eks_node_group" "this" {
  ami_type               = try(var.settings.ami_type, null)
  capacity_type          = try(var.settings.capacity_type, null)
  cluster_name           = try(var.settings.cluster_name, null)
  disk_size              = try(var.settings.disk_size, null)
  force_update_version   = try(var.settings.force_update_version, null)
  instance_types         = try(var.settings.instance_types, null)
  labels                 = try(var.settings.labels, null)
  node_group_name        = try(var.settings.node_group_name, null)
  node_group_name_prefix = try(var.settings.node_group_name_prefix, null)
  node_role_arn          = try(var.settings.node_role_arn, null)
  region                 = try(var.settings.region, null)
  release_version        = try(var.settings.release_version, null)
  subnet_ids             = try(var.settings.subnet_ids, null)
  tags                   = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all               = try(var.settings.tags_all, null)
  version                = try(var.settings.version, null)
  dynamic "launch_template" {
    for_each = coalesce(try(var.settings.launch_template, null), [])
    iterator = b0
    content {
      id      = try(b0.value.id, null)
      name    = try(b0.value.name, null)
      version = try(b0.value.version, null)
    }
  }
  dynamic "node_repair_config" {
    for_each = coalesce(try(var.settings.node_repair_config, null), [])
    iterator = b0
    content {
      enabled                                 = try(b0.value.enabled, null)
      max_parallel_nodes_repaired_count       = try(b0.value.max_parallel_nodes_repaired_count, null)
      max_parallel_nodes_repaired_percentage  = try(b0.value.max_parallel_nodes_repaired_percentage, null)
      max_unhealthy_node_threshold_count      = try(b0.value.max_unhealthy_node_threshold_count, null)
      max_unhealthy_node_threshold_percentage = try(b0.value.max_unhealthy_node_threshold_percentage, null)
      dynamic "node_repair_config_overrides" {
        for_each = coalesce(try(b0.value.node_repair_config_overrides, null), [])
        iterator = b1
        content {
          min_repair_wait_time_mins = try(b1.value.min_repair_wait_time_mins, null)
          node_monitoring_condition = try(b1.value.node_monitoring_condition, null)
          node_unhealthy_reason     = try(b1.value.node_unhealthy_reason, null)
          repair_action             = try(b1.value.repair_action, null)
        }
      }
    }
  }
  dynamic "remote_access" {
    for_each = coalesce(try(var.settings.remote_access, null), [])
    iterator = b0
    content {
      ec2_ssh_key               = try(b0.value.ec2_ssh_key, null)
      source_security_group_ids = try(b0.value.source_security_group_ids, null)
    }
  }
  dynamic "scaling_config" {
    for_each = coalesce(try(var.settings.scaling_config, null), [])
    iterator = b0
    content {
      desired_size = try(b0.value.desired_size, null)
      max_size     = try(b0.value.max_size, null)
      min_size     = try(b0.value.min_size, null)
    }
  }
  dynamic "taint" {
    for_each = coalesce(try(var.settings.taint, null), [])
    iterator = b0
    content {
      effect = try(b0.value.effect, null)
      key    = try(b0.value.key, null)
      value  = try(b0.value.value, null)
    }
  }
  dynamic "update_config" {
    for_each = coalesce(try(var.settings.update_config, null), [])
    iterator = b0
    content {
      max_unavailable            = try(b0.value.max_unavailable, null)
      max_unavailable_percentage = try(b0.value.max_unavailable_percentage, null)
      update_strategy            = try(b0.value.update_strategy, null)
    }
  }
  dynamic "warm_pool_config" {
    for_each = coalesce(try(var.settings.warm_pool_config, null), [])
    iterator = b0
    content {
      max_group_prepared_capacity = try(b0.value.max_group_prepared_capacity, null)
      min_size                    = try(b0.value.min_size, null)
      pool_state                  = try(b0.value.pool_state, null)
      reuse_on_scale_in           = try(b0.value.reuse_on_scale_in, null)
    }
  }
}
output "fields" {
  value = {
    ami_type               = aws_eks_node_group.this.ami_type
    arn                    = aws_eks_node_group.this.arn
    capacity_type          = aws_eks_node_group.this.capacity_type
    cluster_name           = aws_eks_node_group.this.cluster_name
    disk_size              = aws_eks_node_group.this.disk_size
    id                     = aws_eks_node_group.this.id
    node_group_name        = aws_eks_node_group.this.node_group_name
    node_group_name_prefix = aws_eks_node_group.this.node_group_name_prefix
    region                 = aws_eks_node_group.this.region
    release_version        = aws_eks_node_group.this.release_version
    status                 = aws_eks_node_group.this.status
    version                = aws_eks_node_group.this.version
  }
}
