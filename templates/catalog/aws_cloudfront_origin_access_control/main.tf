variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_cloudfront_origin_access_control" "this" {
  description                       = try(var.settings.description, null)
  name                              = try(var.settings.name, null)
  origin_access_control_origin_type = try(var.settings.origin_access_control_origin_type, null)
  signing_behavior                  = try(var.settings.signing_behavior, null)
  signing_protocol                  = try(var.settings.signing_protocol, null)
}
output "fields" {
  value = {
    arn  = aws_cloudfront_origin_access_control.this.arn
    etag = aws_cloudfront_origin_access_control.this.etag
    id   = aws_cloudfront_origin_access_control.this.id
    name = aws_cloudfront_origin_access_control.this.name
  }
}
