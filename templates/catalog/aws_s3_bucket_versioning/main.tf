variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_s3_bucket_versioning" "this" {
  bucket = try(var.settings.bucket, null)
  mfa    = try(var.settings.mfa, null)
  region = try(var.settings.region, null)
  dynamic "versioning_configuration" {
    for_each = coalesce(try(var.settings.versioning_configuration, null), [])
    iterator = b0
    content {
      mfa_delete = try(b0.value.mfa_delete, null)
      status     = try(b0.value.status, null)
    }
  }
}
output "fields" {
  value = {
    bucket = aws_s3_bucket_versioning.this.bucket
    id     = aws_s3_bucket_versioning.this.id
    region = aws_s3_bucket_versioning.this.region
  }
}
