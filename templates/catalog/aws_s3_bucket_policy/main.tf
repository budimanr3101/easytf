variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_s3_bucket_policy" "this" {
  bucket = try(var.settings.bucket, null)
  policy = try(var.settings.policy, null)
  region = try(var.settings.region, null)
}
output "fields" {
  value = {
    bucket = aws_s3_bucket_policy.this.bucket
    id     = aws_s3_bucket_policy.this.id
    region = aws_s3_bucket_policy.this.region
  }
}
