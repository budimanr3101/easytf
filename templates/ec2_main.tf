data "aws_network_interface" "existing" {
  for_each = toset(concat(
    [for eni in coalesce(var.configuration.primary_network_interface, []) : eni.network_interface_id],
    [for eni in coalesce(var.configuration.network_interface, []) : eni.network_interface_id]
  ))
  id = each.key
}
data "aws_iam_role" "existing" {
  count = var.configuration.instance_role == null ? 0 : 1
  name  = var.configuration.instance_role
}
resource "aws_iam_instance_profile" "role" {
  count       = var.configuration.instance_role == null ? 0 : 1
  name_prefix = "${var.resource_key}-"
  role        = data.aws_iam_role.existing[0].name
  tags        = var.tags
}

locals {
  eni_mode = length(coalesce(var.configuration.primary_network_interface, [])) > 0 || length(coalesce(var.configuration.network_interface, [])) > 0
  root_devices = length(coalesce(var.configuration.root_block_device, [])) > 0 ? var.configuration.root_block_device : length(coalesce(var.configuration.launch_template, [])) > 0 ? [] : [{
    delete_on_termination = true
    encrypted             = true
    iops                  = null
    kms_key_id            = null
    tags                  = null
    throughput            = null
    volume_size           = var.root_volume_gib
    volume_type           = "gp3"
  }]
}

resource "aws_instance" "this" {
  ami                         = var.ami_id == "" ? null : var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = local.eni_mode ? null : var.subnet_id
  vpc_security_group_ids      = local.eni_mode || length(var.security_group_ids) == 0 ? null : var.security_group_ids
  associate_public_ip_address = local.eni_mode ? null : var.associate_public_ip

  availability_zone                    = var.configuration.availability_zone
  disable_api_stop                     = var.configuration.disable_api_stop
  disable_api_termination              = var.configuration.disable_api_termination
  ebs_optimized                        = var.configuration.ebs_optimized
  enable_primary_ipv6                  = var.configuration.enable_primary_ipv6
  force_destroy                        = var.configuration.force_destroy
  get_password_data                    = var.configuration.get_password_data
  hibernation                          = var.configuration.hibernation
  host_id                              = var.configuration.host_id
  host_resource_group_arn              = var.configuration.host_resource_group_arn
  iam_instance_profile                 = var.configuration.instance_role == null ? var.configuration.iam_instance_profile : aws_iam_instance_profile.role[0].name
  instance_initiated_shutdown_behavior = var.configuration.instance_initiated_shutdown_behavior
  ipv6_address_count                   = var.configuration.ipv6_address_count
  ipv6_addresses                       = var.configuration.ipv6_addresses
  key_name                             = var.configuration.key_name
  monitoring                           = var.configuration.monitoring
  placement_group                      = var.configuration.placement_group
  placement_group_id                   = var.configuration.placement_group_id
  placement_partition_number           = var.configuration.placement_partition_number
  private_ip                           = var.configuration.private_ip
  secondary_private_ips                = var.configuration.secondary_private_ips
  source_dest_check                    = var.configuration.source_dest_check
  tenancy                              = var.configuration.tenancy
  user_data                            = var.configuration.user_data
  user_data_base64                     = var.configuration.user_data_base64
  user_data_replace_on_change          = var.configuration.user_data_replace_on_change
  volume_tags                          = var.configuration.volume_tags
  dynamic "capacity_reservation_specification" {
    for_each = var.configuration.capacity_reservation_specification == null ? [] : var.configuration.capacity_reservation_specification
    iterator = capacity_reservation_specification_item
    content {
      capacity_reservation_preference = capacity_reservation_specification_item.value.capacity_reservation_preference
      dynamic "capacity_reservation_target" {
        for_each = capacity_reservation_specification_item.value.capacity_reservation_target == null ? [] : capacity_reservation_specification_item.value.capacity_reservation_target
        iterator = capacity_reservation_target_item
        content {
          capacity_reservation_id                 = capacity_reservation_target_item.value.capacity_reservation_id
          capacity_reservation_resource_group_arn = capacity_reservation_target_item.value.capacity_reservation_resource_group_arn
        }
      }
    }
  }
  dynamic "cpu_options" {
    for_each = var.configuration.cpu_options == null ? [] : var.configuration.cpu_options
    iterator = cpu_options_item
    content {
      amd_sev_snp           = cpu_options_item.value.amd_sev_snp
      core_count            = cpu_options_item.value.core_count
      nested_virtualization = cpu_options_item.value.nested_virtualization
      threads_per_core      = cpu_options_item.value.threads_per_core
    }
  }
  dynamic "credit_specification" {
    for_each = var.configuration.credit_specification == null ? [] : var.configuration.credit_specification
    iterator = credit_specification_item
    content {
      cpu_credits = credit_specification_item.value.cpu_credits
    }
  }
  dynamic "ebs_block_device" {
    for_each = var.configuration.ebs_block_device == null ? [] : var.configuration.ebs_block_device
    iterator = ebs_block_device_item
    content {
      delete_on_termination = ebs_block_device_item.value.delete_on_termination
      device_name           = ebs_block_device_item.value.device_name
      encrypted             = ebs_block_device_item.value.encrypted
      iops                  = ebs_block_device_item.value.iops
      kms_key_id            = ebs_block_device_item.value.kms_key_id
      snapshot_id           = ebs_block_device_item.value.snapshot_id
      tags                  = ebs_block_device_item.value.tags
      throughput            = ebs_block_device_item.value.throughput
      volume_size           = ebs_block_device_item.value.volume_size
      volume_type           = ebs_block_device_item.value.volume_type
    }
  }
  dynamic "enclave_options" {
    for_each = var.configuration.enclave_options == null ? [] : var.configuration.enclave_options
    iterator = enclave_options_item
    content {
      enabled = enclave_options_item.value.enabled
    }
  }
  dynamic "ephemeral_block_device" {
    for_each = var.configuration.ephemeral_block_device == null ? [] : var.configuration.ephemeral_block_device
    iterator = ephemeral_block_device_item
    content {
      device_name  = ephemeral_block_device_item.value.device_name
      no_device    = ephemeral_block_device_item.value.no_device
      virtual_name = ephemeral_block_device_item.value.virtual_name
    }
  }
  dynamic "instance_market_options" {
    for_each = var.configuration.instance_market_options == null ? [] : var.configuration.instance_market_options
    iterator = instance_market_options_item
    content {
      market_type = instance_market_options_item.value.market_type
      dynamic "spot_options" {
        for_each = instance_market_options_item.value.spot_options == null ? [] : instance_market_options_item.value.spot_options
        iterator = spot_options_item
        content {
          instance_interruption_behavior = spot_options_item.value.instance_interruption_behavior
          max_price                      = spot_options_item.value.max_price
          spot_instance_type             = spot_options_item.value.spot_instance_type
          valid_until                    = spot_options_item.value.valid_until
        }
      }
    }
  }
  dynamic "launch_template" {
    for_each = var.configuration.launch_template == null ? [] : var.configuration.launch_template
    iterator = launch_template_item
    content {
      name    = launch_template_item.value.name
      version = launch_template_item.value.version
    }
  }
  dynamic "maintenance_options" {
    for_each = var.configuration.maintenance_options == null ? [] : var.configuration.maintenance_options
    iterator = maintenance_options_item
    content {
      auto_recovery = maintenance_options_item.value.auto_recovery
    }
  }
  dynamic "metadata_options" {
    for_each = var.configuration.metadata_options == null ? [] : var.configuration.metadata_options
    iterator = metadata_options_item
    content {
      http_endpoint               = metadata_options_item.value.http_endpoint
      http_protocol_ipv6          = metadata_options_item.value.http_protocol_ipv6
      http_put_response_hop_limit = metadata_options_item.value.http_put_response_hop_limit
      http_tokens                 = metadata_options_item.value.http_tokens
      instance_metadata_tags      = metadata_options_item.value.instance_metadata_tags
    }
  }
  dynamic "network_interface" {
    for_each = var.configuration.network_interface == null ? [] : var.configuration.network_interface
    iterator = network_interface_item
    content {
      delete_on_termination = network_interface_item.value.delete_on_termination
      device_index          = network_interface_item.value.device_index
      network_card_index    = network_interface_item.value.network_card_index
      network_interface_id  = network_interface_item.value.network_interface_id
    }
  }
  dynamic "primary_network_interface" {
    for_each = var.configuration.primary_network_interface == null ? [] : var.configuration.primary_network_interface
    iterator = primary_network_interface_item
    content {
      network_interface_id = primary_network_interface_item.value.network_interface_id
    }
  }
  dynamic "private_dns_name_options" {
    for_each = var.configuration.private_dns_name_options == null ? [] : var.configuration.private_dns_name_options
    iterator = private_dns_name_options_item
    content {
      enable_resource_name_dns_a_record    = private_dns_name_options_item.value.enable_resource_name_dns_a_record
      enable_resource_name_dns_aaaa_record = private_dns_name_options_item.value.enable_resource_name_dns_aaaa_record
      hostname_type                        = private_dns_name_options_item.value.hostname_type
    }
  }
  dynamic "root_block_device" {
    for_each = local.root_devices
    iterator = root_block_device_item
    content {
      delete_on_termination = root_block_device_item.value.delete_on_termination
      encrypted             = root_block_device_item.value.encrypted
      iops                  = root_block_device_item.value.iops
      kms_key_id            = root_block_device_item.value.kms_key_id
      tags                  = root_block_device_item.value.tags
      throughput            = root_block_device_item.value.throughput
      volume_size           = root_block_device_item.value.volume_size
      volume_type           = root_block_device_item.value.volume_type
    }
  }
  dynamic "secondary_network_interface" {
    for_each = var.configuration.secondary_network_interface == null ? [] : var.configuration.secondary_network_interface
    iterator = secondary_network_interface_item
    content {
      delete_on_termination    = secondary_network_interface_item.value.delete_on_termination
      device_index             = secondary_network_interface_item.value.device_index
      interface_type           = secondary_network_interface_item.value.interface_type
      network_card_index       = secondary_network_interface_item.value.network_card_index
      private_ip_address_count = secondary_network_interface_item.value.private_ip_address_count
      secondary_subnet_id      = secondary_network_interface_item.value.secondary_subnet_id
    }
  }
  dynamic "timeouts" {
    for_each = var.configuration.timeouts == null ? [] : [var.configuration.timeouts]
    iterator = timeouts_item
    content {
      create = timeouts_item.value.create
      delete = timeouts_item.value.delete
      read   = timeouts_item.value.read
      update = timeouts_item.value.update
    }
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = alltrue([for eni in data.aws_network_interface.existing : eni.subnet_id == var.subnet_id && eni.vpc_id == var.vpc_id])
      error_message = "Existing network interfaces must belong to the selected subnet and VPC."
    }
    precondition {
      condition = local.eni_mode || length(coalesce(var.configuration.launch_template, [])) > 0 || (length(var.security_group_ids) > 0 && alltrue([
        for vpc_id in var.security_group_vpc_ids : vpc_id == var.vpc_id
      ]))
      error_message = "Select security groups in the subnet's primary VPC. Additional SG VPC associations are outside this MVP."
    }
  }
}
