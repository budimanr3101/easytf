variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_eks_cluster" "this" {
  bootstrap_self_managed_addons = try(var.settings.bootstrap_self_managed_addons, null)
  deletion_protection           = try(var.settings.deletion_protection, null)
  enabled_cluster_log_types     = try(var.settings.enabled_cluster_log_types, null)
  force_update_version          = try(var.settings.force_update_version, null)
  name                          = try(var.settings.name, null)
  region                        = try(var.settings.region, null)
  role_arn                      = try(var.settings.role_arn, null)
  tags                          = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                      = try(var.settings.tags_all, null)
  version                       = try(var.settings.version, null)
  dynamic "access_config" {
    for_each = coalesce(try(var.settings.access_config, null), [])
    iterator = b0
    content {
      authentication_mode                         = try(b0.value.authentication_mode, null)
      bootstrap_cluster_creator_admin_permissions = try(b0.value.bootstrap_cluster_creator_admin_permissions, null)
    }
  }
  dynamic "compute_config" {
    for_each = coalesce(try(var.settings.compute_config, null), [])
    iterator = b0
    content {
      enabled       = try(b0.value.enabled, null)
      node_pools    = try(b0.value.node_pools, null)
      node_role_arn = try(b0.value.node_role_arn, null)
    }
  }
  dynamic "control_plane_scaling_config" {
    for_each = coalesce(try(var.settings.control_plane_scaling_config, null), [])
    iterator = b0
    content {
      tier = try(b0.value.tier, null)
    }
  }
  dynamic "encryption_config" {
    for_each = coalesce(try(var.settings.encryption_config, null), [])
    iterator = b0
    content {
      resources = try(b0.value.resources, null)
      dynamic "provider" {
        for_each = coalesce(try(b0.value.provider, null), [])
        iterator = b1
        content {
          key_arn = try(b1.value.key_arn, null)
        }
      }
    }
  }
  dynamic "kube_api_server_config" {
    for_each = coalesce(try(var.settings.kube_api_server_config, null), [])
    iterator = b0
    content {
      event_ttl = try(b0.value.event_ttl, null)
      dynamic "service_node_port_range" {
        for_each = coalesce(try(b0.value.service_node_port_range, null), [])
        iterator = b1
        content {
          max_port = try(b1.value.max_port, null)
          min_port = try(b1.value.min_port, null)
        }
      }
    }
  }
  dynamic "kube_controller_manager_config" {
    for_each = coalesce(try(var.settings.kube_controller_manager_config, null), [])
    iterator = b0
    content {
      dynamic "horizontal_pod_autoscaler_controller_config" {
        for_each = coalesce(try(b0.value.horizontal_pod_autoscaler_controller_config, null), [])
        iterator = b1
        content {
          horizontal_pod_autoscaler_sync_period = try(b1.value.horizontal_pod_autoscaler_sync_period, null)
        }
      }
      dynamic "pod_gc_controller_config" {
        for_each = coalesce(try(b0.value.pod_gc_controller_config, null), [])
        iterator = b1
        content {
          terminated_pod_gc_threshold = try(b1.value.terminated_pod_gc_threshold, null)
        }
      }
    }
  }
  dynamic "kube_scheduler_config" {
    for_each = coalesce(try(var.settings.kube_scheduler_config, null), [])
    iterator = b0
    content {
      dynamic "node_resources_fit" {
        for_each = coalesce(try(b0.value.node_resources_fit, null), [])
        iterator = b1
        content {
          dynamic "scoring_strategy" {
            for_each = coalesce(try(b1.value.scoring_strategy, null), [])
            iterator = b2
            content {
              type = try(b2.value.type, null)
              dynamic "resource" {
                for_each = coalesce(try(b2.value.resource, null), [])
                iterator = b3
                content {
                  name   = try(b3.value.name, null)
                  weight = try(b3.value.weight, null)
                }
              }
            }
          }
        }
      }
    }
  }
  dynamic "kubernetes_network_config" {
    for_each = coalesce(try(var.settings.kubernetes_network_config, null), [])
    iterator = b0
    content {
      ip_family         = try(b0.value.ip_family, null)
      service_ipv4_cidr = try(b0.value.service_ipv4_cidr, null)
      dynamic "elastic_load_balancing" {
        for_each = coalesce(try(b0.value.elastic_load_balancing, null), [])
        iterator = b1
        content {
          enabled = try(b1.value.enabled, null)
        }
      }
    }
  }
  dynamic "outpost_config" {
    for_each = coalesce(try(var.settings.outpost_config, null), [])
    iterator = b0
    content {
      control_plane_instance_type = try(b0.value.control_plane_instance_type, null)
      etcd_instance_type          = try(b0.value.etcd_instance_type, null)
      outpost_arns                = try(b0.value.outpost_arns, null)
      dynamic "control_plane_placement" {
        for_each = coalesce(try(b0.value.control_plane_placement, null), [])
        iterator = b1
        content {
          group_name   = try(b1.value.group_name, null)
          spread_level = try(b1.value.spread_level, null)
        }
      }
      dynamic "etcd_placement" {
        for_each = coalesce(try(b0.value.etcd_placement, null), [])
        iterator = b1
        content {
          spread_level = try(b1.value.spread_level, null)
        }
      }
    }
  }
  dynamic "remote_network_config" {
    for_each = coalesce(try(var.settings.remote_network_config, null), [])
    iterator = b0
    content {
      dynamic "remote_node_networks" {
        for_each = coalesce(try(b0.value.remote_node_networks, null), [])
        iterator = b1
        content {
          cidrs = try(b1.value.cidrs, null)
        }
      }
      dynamic "remote_pod_networks" {
        for_each = coalesce(try(b0.value.remote_pod_networks, null), [])
        iterator = b1
        content {
          cidrs = try(b1.value.cidrs, null)
        }
      }
    }
  }
  dynamic "storage_config" {
    for_each = coalesce(try(var.settings.storage_config, null), [])
    iterator = b0
    content {
      dynamic "block_storage" {
        for_each = coalesce(try(b0.value.block_storage, null), [])
        iterator = b1
        content {
          enabled = try(b1.value.enabled, null)
        }
      }
    }
  }
  dynamic "upgrade_policy" {
    for_each = coalesce(try(var.settings.upgrade_policy, null), [])
    iterator = b0
    content {
      support_type = try(b0.value.support_type, null)
    }
  }
  dynamic "vpc_config" {
    for_each = coalesce(try(var.settings.vpc_config, null), [])
    iterator = b0
    content {
      control_plane_egress_mode = try(b0.value.control_plane_egress_mode, null)
      endpoint_private_access   = try(b0.value.endpoint_private_access, null)
      endpoint_public_access    = try(b0.value.endpoint_public_access, null)
      public_access_cidrs       = try(b0.value.public_access_cidrs, null)
      security_group_ids        = try(b0.value.security_group_ids, null)
      subnet_ids                = try(b0.value.subnet_ids, null)
    }
  }
  dynamic "zonal_shift_config" {
    for_each = coalesce(try(var.settings.zonal_shift_config, null), [])
    iterator = b0
    content {
      enabled = try(b0.value.enabled, null)
    }
  }
}
output "fields" {
  value = {
    arn                 = aws_eks_cluster.this.arn
    cluster_id          = aws_eks_cluster.this.cluster_id
    created_at          = aws_eks_cluster.this.created_at
    deletion_protection = aws_eks_cluster.this.deletion_protection
    endpoint            = aws_eks_cluster.this.endpoint
    id                  = aws_eks_cluster.this.id
    name                = aws_eks_cluster.this.name
    platform_version    = aws_eks_cluster.this.platform_version
    region              = aws_eks_cluster.this.region
    status              = aws_eks_cluster.this.status
    version             = aws_eks_cluster.this.version
  }
}
