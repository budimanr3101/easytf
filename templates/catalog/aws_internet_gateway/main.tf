variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_internet_gateway" "this" {
  region   = try(var.settings.region, null)
  tags     = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all = try(var.settings.tags_all, null)
  vpc_id   = try(var.settings.vpc_id, null)
}
output "fields" {
  value = {
    arn      = aws_internet_gateway.this.arn
    id       = aws_internet_gateway.this.id
    owner_id = aws_internet_gateway.this.owner_id
    region   = aws_internet_gateway.this.region
    vpc_id   = aws_internet_gateway.this.vpc_id
  }
}
