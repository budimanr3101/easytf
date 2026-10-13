variable "name" {
  type = string
}
variable "ami_id" {
  type = string
}
variable "instance_type" {
  type = string
}
variable "subnet_id" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "security_group_ids" {
  type = list(string)
}
variable "security_group_vpc_ids" {
  type = list(string)
}
variable "root_volume_gib" {
  type = number
  validation {
    condition     = var.root_volume_gib > 0 && floor(var.root_volume_gib) == var.root_volume_gib
    error_message = "Root volume size must be a positive integer."
  }
}
variable "associate_public_ip" {
  type = bool
}
variable "tags" {
  type    = map(string)
  default = {}
}

variable "resource_key" {
  type    = string
  default = "instance"
}

variable "configuration" {
  description = "Optional EC2 settings from AWS provider 6.68.0; null leaves provider defaults."
  type = object({
    availability_zone                    = optional(string)
    disable_api_stop                     = optional(bool)
    disable_api_termination              = optional(bool)
    ebs_optimized                        = optional(bool)
    enable_primary_ipv6                  = optional(bool)
    force_destroy                        = optional(bool)
    get_password_data                    = optional(bool)
    hibernation                          = optional(bool)
    host_id                              = optional(string)
    host_resource_group_arn              = optional(string)
    iam_instance_profile                 = optional(string)
    instance_initiated_shutdown_behavior = optional(string)
    ipv6_address_count                   = optional(number)
    ipv6_addresses                       = optional(list(string))
    key_name                             = optional(string)
    monitoring                           = optional(bool)
    placement_group                      = optional(string)
    placement_group_id                   = optional(string)
    placement_partition_number           = optional(number)
    private_ip                           = optional(string)
    secondary_private_ips                = optional(list(string))
    source_dest_check                    = optional(bool)
    tenancy                              = optional(string)
    user_data                            = optional(string)
    user_data_base64                     = optional(string)
    user_data_replace_on_change          = optional(bool)
    volume_tags                          = optional(map(string))
    capacity_reservation_specification = optional(list(object({
      capacity_reservation_preference = optional(string)
      capacity_reservation_target = optional(list(object({
        capacity_reservation_id                 = optional(string)
        capacity_reservation_resource_group_arn = optional(string)
      })))
    })))
    cpu_options = optional(list(object({
      amd_sev_snp           = optional(string)
      core_count            = optional(number)
      nested_virtualization = optional(string)
      threads_per_core      = optional(number)
    })))
    credit_specification = optional(list(object({
      cpu_credits = optional(string)
    })))
    ebs_block_device = optional(list(object({
      delete_on_termination = optional(bool)
      device_name           = string
      encrypted             = optional(bool)
      iops                  = optional(number)
      kms_key_id            = optional(string)
      snapshot_id           = optional(string)
      tags                  = optional(map(string))
      throughput            = optional(number)
      volume_size           = optional(number)
      volume_type           = optional(string)
    })))
    enclave_options = optional(list(object({
      enabled = optional(bool)
    })))
    ephemeral_block_device = optional(list(object({
      device_name  = string
      no_device    = optional(bool)
      virtual_name = optional(string)
    })))
    instance_market_options = optional(list(object({
      market_type = optional(string)
      spot_options = optional(list(object({
        instance_interruption_behavior = optional(string)
        max_price                      = optional(string)
        spot_instance_type             = optional(string)
        valid_until                    = optional(string)
      })))
    })))
    launch_template = optional(list(object({
      name    = optional(string)
      version = optional(string)
    })))
    maintenance_options = optional(list(object({
      auto_recovery = optional(string)
    })))
    metadata_options = optional(list(object({
      http_endpoint               = optional(string)
      http_protocol_ipv6          = optional(string)
      http_put_response_hop_limit = optional(number)
      http_tokens                 = optional(string)
      instance_metadata_tags      = optional(string)
    })))
    network_interface = optional(list(object({
      delete_on_termination = optional(bool)
      device_index          = number
      network_card_index    = optional(number)
      network_interface_id  = string
    })))
    primary_network_interface = optional(list(object({
      network_interface_id = string
    })))
    private_dns_name_options = optional(list(object({
      enable_resource_name_dns_a_record    = optional(bool)
      enable_resource_name_dns_aaaa_record = optional(bool)
      hostname_type                        = optional(string)
    })))
    root_block_device = optional(list(object({
      delete_on_termination = optional(bool)
      encrypted             = optional(bool)
      iops                  = optional(number)
      kms_key_id            = optional(string)
      tags                  = optional(map(string))
      throughput            = optional(number)
      volume_size           = optional(number)
      volume_type           = optional(string)
    })))
    secondary_network_interface = optional(list(object({
      delete_on_termination    = optional(bool)
      device_index             = optional(number)
      interface_type           = optional(string)
      network_card_index       = number
      private_ip_address_count = optional(number)
      secondary_subnet_id      = string
    })))
    timeouts = optional(object({
      create = optional(string)
      delete = optional(string)
      read   = optional(string)
      update = optional(string)
    }))
    instance_role = optional(string)
  })
  default = {}
}
