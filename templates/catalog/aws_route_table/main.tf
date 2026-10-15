variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_route_table" "this" {
  propagating_vgws = try(var.settings.propagating_vgws, null)
  region           = try(var.settings.region, null)
  route            = try(var.settings.route, null)
  tags             = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all         = try(var.settings.tags_all, null)
  vpc_id           = try(var.settings.vpc_id, null)
}
output "fields" {
  value = {
    arn      = aws_route_table.this.arn
    id       = aws_route_table.this.id
    owner_id = aws_route_table.this.owner_id
    region   = aws_route_table.this.region
  }
}
