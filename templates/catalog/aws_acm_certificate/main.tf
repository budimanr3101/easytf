variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_acm_certificate" "this" {
  certificate_authority_arn = try(var.settings.certificate_authority_arn, null)
  certificate_body          = try(var.settings.certificate_body, null)
  certificate_chain         = try(var.settings.certificate_chain, null)
  domain_name               = try(var.settings.domain_name, null)
  early_renewal_duration    = try(var.settings.early_renewal_duration, null)
  key_algorithm             = try(var.settings.key_algorithm, null)
  region                    = try(var.settings.region, null)
  subject_alternative_names = try(var.settings.subject_alternative_names, null)
  tags                      = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                  = try(var.settings.tags_all, null)
  validation_method         = try(var.settings.validation_method, null)
  dynamic "options" {
    for_each = coalesce(try(var.settings.options, null), [])
    iterator = b0
    content {
      certificate_transparency_logging_preference = try(b0.value.certificate_transparency_logging_preference, null)
      export                                      = try(b0.value.export, null)
    }
  }
  dynamic "validation_option" {
    for_each = coalesce(try(var.settings.validation_option, null), [])
    iterator = b0
    content {
      domain_name       = try(b0.value.domain_name, null)
      validation_domain = try(b0.value.validation_domain, null)
    }
  }
}
output "fields" {
  value = {
    arn                 = aws_acm_certificate.this.arn
    domain_name         = aws_acm_certificate.this.domain_name
    id                  = aws_acm_certificate.this.id
    key_algorithm       = aws_acm_certificate.this.key_algorithm
    not_after           = aws_acm_certificate.this.not_after
    not_before          = aws_acm_certificate.this.not_before
    pending_renewal     = aws_acm_certificate.this.pending_renewal
    region              = aws_acm_certificate.this.region
    renewal_eligibility = aws_acm_certificate.this.renewal_eligibility
    status              = aws_acm_certificate.this.status
    type                = aws_acm_certificate.this.type
    validation_method   = aws_acm_certificate.this.validation_method
  }
}
