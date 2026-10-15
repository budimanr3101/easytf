variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_route" "this" {
  carrier_gateway_id          = try(var.settings.carrier_gateway_id, null)
  core_network_arn            = try(var.settings.core_network_arn, null)
  destination_cidr_block      = try(var.settings.destination_cidr_block, null)
  destination_ipv6_cidr_block = try(var.settings.destination_ipv6_cidr_block, null)
  destination_prefix_list_id  = try(var.settings.destination_prefix_list_id, null)
  egress_only_gateway_id      = try(var.settings.egress_only_gateway_id, null)
  gateway_id                  = try(var.settings.gateway_id, null)
  local_gateway_id            = try(var.settings.local_gateway_id, null)
  nat_gateway_id              = try(var.settings.nat_gateway_id, null)
  network_interface_id        = try(var.settings.network_interface_id, null)
  odb_network_arn             = try(var.settings.odb_network_arn, null)
  region                      = try(var.settings.region, null)
  route_table_id              = try(var.settings.route_table_id, null)
  transit_gateway_id          = try(var.settings.transit_gateway_id, null)
  vpc_endpoint_id             = try(var.settings.vpc_endpoint_id, null)
  vpc_peering_connection_id   = try(var.settings.vpc_peering_connection_id, null)
}
output "fields" {
  value = {
    id                   = aws_route.this.id
    instance_id          = aws_route.this.instance_id
    instance_owner_id    = aws_route.this.instance_owner_id
    network_interface_id = aws_route.this.network_interface_id
    origin               = aws_route.this.origin
    region               = aws_route.this.region
    state                = aws_route.this.state
  }
}
