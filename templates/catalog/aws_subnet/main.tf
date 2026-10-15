variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_subnet" "this" {
  assign_ipv6_address_on_creation                = try(var.settings.assign_ipv6_address_on_creation, null)
  availability_zone                              = try(var.settings.availability_zone, null)
  availability_zone_id                           = try(var.settings.availability_zone_id, null)
  cidr_block                                     = try(var.settings.cidr_block, null)
  customer_owned_ipv4_pool                       = try(var.settings.customer_owned_ipv4_pool, null)
  enable_dns64                                   = try(var.settings.enable_dns64, null)
  enable_lni_at_device_index                     = try(var.settings.enable_lni_at_device_index, null)
  enable_resource_name_dns_a_record_on_launch    = try(var.settings.enable_resource_name_dns_a_record_on_launch, null)
  enable_resource_name_dns_aaaa_record_on_launch = try(var.settings.enable_resource_name_dns_aaaa_record_on_launch, null)
  ipv4_ipam_pool_id                              = try(var.settings.ipv4_ipam_pool_id, null)
  ipv4_netmask_length                            = try(var.settings.ipv4_netmask_length, null)
  ipv6_cidr_block                                = try(var.settings.ipv6_cidr_block, null)
  ipv6_ipam_pool_id                              = try(var.settings.ipv6_ipam_pool_id, null)
  ipv6_native                                    = try(var.settings.ipv6_native, null)
  ipv6_netmask_length                            = try(var.settings.ipv6_netmask_length, null)
  map_customer_owned_ip_on_launch                = try(var.settings.map_customer_owned_ip_on_launch, null)
  map_public_ip_on_launch                        = try(var.settings.map_public_ip_on_launch, null)
  outpost_arn                                    = try(var.settings.outpost_arn, null)
  private_dns_hostname_type_on_launch            = try(var.settings.private_dns_hostname_type_on_launch, null)
  region                                         = try(var.settings.region, null)
  tags                                           = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                                       = try(var.settings.tags_all, null)
  vpc_id                                         = try(var.settings.vpc_id, null)
}
output "fields" {
  value = {
    arn                                 = aws_subnet.this.arn
    availability_zone                   = aws_subnet.this.availability_zone
    availability_zone_id                = aws_subnet.this.availability_zone_id
    cidr_block                          = aws_subnet.this.cidr_block
    id                                  = aws_subnet.this.id
    ipv6_cidr_block                     = aws_subnet.this.ipv6_cidr_block
    ipv6_cidr_block_association_id      = aws_subnet.this.ipv6_cidr_block_association_id
    owner_id                            = aws_subnet.this.owner_id
    private_dns_hostname_type_on_launch = aws_subnet.this.private_dns_hostname_type_on_launch
    region                              = aws_subnet.this.region
  }
}
