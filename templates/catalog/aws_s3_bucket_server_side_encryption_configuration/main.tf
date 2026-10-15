variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = try(var.settings.bucket, null)
  region = try(var.settings.region, null)
  dynamic "rule" {
    for_each = coalesce(try(var.settings.rule, null), [])
    iterator = b0
    content {
      blocked_encryption_types = try(b0.value.blocked_encryption_types, null)
      bucket_key_enabled       = try(b0.value.bucket_key_enabled, null)
      dynamic "apply_server_side_encryption_by_default" {
        for_each = coalesce(try(b0.value.apply_server_side_encryption_by_default, null), [])
        iterator = b1
        content {
          kms_master_key_id = try(b1.value.kms_master_key_id, null)
          sse_algorithm     = try(b1.value.sse_algorithm, null)
        }
      }
    }
  }
}
output "fields" {
  value = {
    bucket = aws_s3_bucket_server_side_encryption_configuration.this.bucket
    id     = aws_s3_bucket_server_side_encryption_configuration.this.id
    region = aws_s3_bucket_server_side_encryption_configuration.this.region
  }
}
