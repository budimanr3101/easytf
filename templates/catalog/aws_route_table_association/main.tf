variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_route_table_association" "this" {
  gateway_id     = try(var.settings.gateway_id, null)
  region         = try(var.settings.region, null)
  route_table_id = try(var.settings.route_table_id, null)
  subnet_id      = try(var.settings.subnet_id, null)
}
output "fields" {
  value = {
    id     = aws_route_table_association.this.id
    region = aws_route_table_association.this.region
  }
}
