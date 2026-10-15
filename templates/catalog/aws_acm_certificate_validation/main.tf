variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = try(var.settings.certificate_arn, null)
  region                  = try(var.settings.region, null)
  validation_record_fqdns = try(var.settings.validation_record_fqdns, null)
}
output "fields" {
  value = {
    id     = aws_acm_certificate_validation.this.id
    region = aws_acm_certificate_validation.this.region
  }
}
