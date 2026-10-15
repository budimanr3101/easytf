variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_vpc" "this" {
  assign_generated_ipv6_cidr_block     = try(var.settings.assign_generated_ipv6_cidr_block, null)
  cidr_block                           = try(var.settings.cidr_block, null)
  enable_dns_hostnames                 = try(var.settings.enable_dns_hostnames, null)
  enable_dns_support                   = try(var.settings.enable_dns_support, null)
  enable_network_address_usage_metrics = try(var.settings.enable_network_address_usage_metrics, null)
  instance_tenancy                     = try(var.settings.instance_tenancy, null)
  ipv4_ipam_pool_id                    = try(var.settings.ipv4_ipam_pool_id, null)
  ipv4_netmask_length                  = try(var.settings.ipv4_netmask_length, null)
  ipv6_cidr_block                      = try(var.settings.ipv6_cidr_block, null)
  ipv6_cidr_block_network_border_group = try(var.settings.ipv6_cidr_block_network_border_group, null)
  ipv6_ipam_pool_id                    = try(var.settings.ipv6_ipam_pool_id, null)
  ipv6_netmask_length                  = try(var.settings.ipv6_netmask_length, null)
  region                               = try(var.settings.region, null)
  tags                                 = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                             = try(var.settings.tags_all, null)
}
output "fields" {
  value = {
    arn                                  = aws_vpc.this.arn
    cidr_block                           = aws_vpc.this.cidr_block
    default_network_acl_id               = aws_vpc.this.default_network_acl_id
    default_route_table_id               = aws_vpc.this.default_route_table_id
    default_security_group_id            = aws_vpc.this.default_security_group_id
    dhcp_options_id                      = aws_vpc.this.dhcp_options_id
    enable_dns_hostnames                 = aws_vpc.this.enable_dns_hostnames
    enable_network_address_usage_metrics = aws_vpc.this.enable_network_address_usage_metrics
    id                                   = aws_vpc.this.id
    ipv6_association_id                  = aws_vpc.this.ipv6_association_id
    ipv6_cidr_block                      = aws_vpc.this.ipv6_cidr_block
    ipv6_cidr_block_network_border_group = aws_vpc.this.ipv6_cidr_block_network_border_group
    main_route_table_id                  = aws_vpc.this.main_route_table_id
    owner_id                             = aws_vpc.this.owner_id
    region                               = aws_vpc.this.region
  }
}
