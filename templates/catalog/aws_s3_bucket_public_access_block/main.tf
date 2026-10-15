variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_s3_bucket_public_access_block" "this" {
  block_public_acls       = try(var.settings.block_public_acls, null)
  block_public_policy     = try(var.settings.block_public_policy, null)
  bucket                  = try(var.settings.bucket, null)
  ignore_public_acls      = try(var.settings.ignore_public_acls, null)
  region                  = try(var.settings.region, null)
  restrict_public_buckets = try(var.settings.restrict_public_buckets, null)
  skip_destroy            = try(var.settings.skip_destroy, null)
}
output "fields" {
  value = {
    bucket = aws_s3_bucket_public_access_block.this.bucket
    id     = aws_s3_bucket_public_access_block.this.id
    region = aws_s3_bucket_public_access_block.this.region
  }
}
