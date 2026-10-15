variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_ecr_repository" "this" {
  force_delete         = try(var.settings.force_delete, null)
  image_tag_mutability = try(var.settings.image_tag_mutability, null)
  name                 = try(var.settings.name, null)
  region               = try(var.settings.region, null)
  tags                 = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all             = try(var.settings.tags_all, null)
  dynamic "encryption_configuration" {
    for_each = coalesce(try(var.settings.encryption_configuration, null), [])
    iterator = b0
    content {
      encryption_type = try(b0.value.encryption_type, null)
      kms_key         = try(b0.value.kms_key, null)
    }
  }
  dynamic "image_scanning_configuration" {
    for_each = coalesce(try(var.settings.image_scanning_configuration, null), [])
    iterator = b0
    content {
      scan_on_push = try(b0.value.scan_on_push, null)
    }
  }
  dynamic "image_tag_mutability_exclusion_filter" {
    for_each = coalesce(try(var.settings.image_tag_mutability_exclusion_filter, null), [])
    iterator = b0
    content {
      filter      = try(b0.value.filter, null)
      filter_type = try(b0.value.filter_type, null)
    }
  }
}
output "fields" {
  value = {
    arn            = aws_ecr_repository.this.arn
    id             = aws_ecr_repository.this.id
    name           = aws_ecr_repository.this.name
    region         = aws_ecr_repository.this.region
    registry_id    = aws_ecr_repository.this.registry_id
    repository_url = aws_ecr_repository.this.repository_url
  }
}
