variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_nat_gateway" "this" {
  allocation_id                      = try(var.settings.allocation_id, null)
  availability_mode                  = try(var.settings.availability_mode, null)
  connectivity_type                  = try(var.settings.connectivity_type, null)
  private_ip                         = try(var.settings.private_ip, null)
  region                             = try(var.settings.region, null)
  secondary_allocation_ids           = try(var.settings.secondary_allocation_ids, null)
  secondary_private_ip_address_count = try(var.settings.secondary_private_ip_address_count, null)
  secondary_private_ip_addresses     = try(var.settings.secondary_private_ip_addresses, null)
  subnet_id                          = try(var.settings.subnet_id, null)
  tags                               = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                           = try(var.settings.tags_all, null)
  vpc_id                             = try(var.settings.vpc_id, null)
  dynamic "availability_zone_address" {
    for_each = coalesce(try(var.settings.availability_zone_address, null), [])
    iterator = b0
    content {
      allocation_ids       = try(b0.value.allocation_ids, null)
      availability_zone    = try(b0.value.availability_zone, null)
      availability_zone_id = try(b0.value.availability_zone_id, null)
    }
  }
}
output "fields" {
  value = {
    association_id                     = aws_nat_gateway.this.association_id
    auto_provision_zones               = aws_nat_gateway.this.auto_provision_zones
    auto_scaling_ips                   = aws_nat_gateway.this.auto_scaling_ips
    availability_mode                  = aws_nat_gateway.this.availability_mode
    id                                 = aws_nat_gateway.this.id
    network_interface_id               = aws_nat_gateway.this.network_interface_id
    private_ip                         = aws_nat_gateway.this.private_ip
    public_ip                          = aws_nat_gateway.this.public_ip
    region                             = aws_nat_gateway.this.region
    regional_nat_gateway_auto_mode     = aws_nat_gateway.this.regional_nat_gateway_auto_mode
    route_table_id                     = aws_nat_gateway.this.route_table_id
    secondary_private_ip_address_count = aws_nat_gateway.this.secondary_private_ip_address_count
    vpc_id                             = aws_nat_gateway.this.vpc_id
  }
}
