variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_s3_bucket" "this" {
  bucket              = try(var.settings.bucket, null)
  bucket_namespace    = try(var.settings.bucket_namespace, null)
  bucket_prefix       = try(var.settings.bucket_prefix, null)
  force_destroy       = try(var.settings.force_destroy, null)
  object_lock_enabled = try(var.settings.object_lock_enabled, null)
  region              = try(var.settings.region, null)
  tags                = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all            = try(var.settings.tags_all, null)
  dynamic "cors_rule" {
    for_each = coalesce(try(var.settings.cors_rule, null), [])
    iterator = b0
    content {
      allowed_headers = try(b0.value.allowed_headers, null)
      allowed_methods = try(b0.value.allowed_methods, null)
      allowed_origins = try(b0.value.allowed_origins, null)
      expose_headers  = try(b0.value.expose_headers, null)
      max_age_seconds = try(b0.value.max_age_seconds, null)
    }
  }
  dynamic "grant" {
    for_each = coalesce(try(var.settings.grant, null), [])
    iterator = b0
    content {
      id          = try(b0.value.id, null)
      permissions = try(b0.value.permissions, null)
      type        = try(b0.value.type, null)
      uri         = try(b0.value.uri, null)
    }
  }
  dynamic "lifecycle_rule" {
    for_each = coalesce(try(var.settings.lifecycle_rule, null), [])
    iterator = b0
    content {
      abort_incomplete_multipart_upload_days = try(b0.value.abort_incomplete_multipart_upload_days, null)
      enabled                                = try(b0.value.enabled, null)
      id                                     = try(b0.value.id, null)
      prefix                                 = try(b0.value.prefix, null)
      tags                                   = try(b0.value.tags, null)
      dynamic "expiration" {
        for_each = coalesce(try(b0.value.expiration, null), [])
        iterator = b1
        content {
          date                         = try(b1.value.date, null)
          days                         = try(b1.value.days, null)
          expired_object_delete_marker = try(b1.value.expired_object_delete_marker, null)
        }
      }
      dynamic "noncurrent_version_expiration" {
        for_each = coalesce(try(b0.value.noncurrent_version_expiration, null), [])
        iterator = b1
        content {
          days = try(b1.value.days, null)
        }
      }
      dynamic "noncurrent_version_transition" {
        for_each = coalesce(try(b0.value.noncurrent_version_transition, null), [])
        iterator = b1
        content {
          days          = try(b1.value.days, null)
          storage_class = try(b1.value.storage_class, null)
        }
      }
      dynamic "transition" {
        for_each = coalesce(try(b0.value.transition, null), [])
        iterator = b1
        content {
          date          = try(b1.value.date, null)
          days          = try(b1.value.days, null)
          storage_class = try(b1.value.storage_class, null)
        }
      }
    }
  }
  dynamic "logging" {
    for_each = coalesce(try(var.settings.logging, null), [])
    iterator = b0
    content {
      target_bucket = try(b0.value.target_bucket, null)
      target_prefix = try(b0.value.target_prefix, null)
    }
  }
  dynamic "object_lock_configuration" {
    for_each = coalesce(try(var.settings.object_lock_configuration, null), [])
    iterator = b0
    content {
      dynamic "rule" {
        for_each = coalesce(try(b0.value.rule, null), [])
        iterator = b1
        content {
          dynamic "default_retention" {
            for_each = coalesce(try(b1.value.default_retention, null), [])
            iterator = b2
            content {
              days  = try(b2.value.days, null)
              mode  = try(b2.value.mode, null)
              years = try(b2.value.years, null)
            }
          }
        }
      }
    }
  }
  dynamic "replication_configuration" {
    for_each = coalesce(try(var.settings.replication_configuration, null), [])
    iterator = b0
    content {
      role = try(b0.value.role, null)
      dynamic "rules" {
        for_each = coalesce(try(b0.value.rules, null), [])
        iterator = b1
        content {
          delete_marker_replication_status = try(b1.value.delete_marker_replication_status, null)
          id                               = try(b1.value.id, null)
          prefix                           = try(b1.value.prefix, null)
          priority                         = try(b1.value.priority, null)
          status                           = try(b1.value.status, null)
          dynamic "destination" {
            for_each = coalesce(try(b1.value.destination, null), [])
            iterator = b2
            content {
              account_id         = try(b2.value.account_id, null)
              bucket             = try(b2.value.bucket, null)
              replica_kms_key_id = try(b2.value.replica_kms_key_id, null)
              storage_class      = try(b2.value.storage_class, null)
              dynamic "access_control_translation" {
                for_each = coalesce(try(b2.value.access_control_translation, null), [])
                iterator = b3
                content {
                  owner = try(b3.value.owner, null)
                }
              }
              dynamic "metrics" {
                for_each = coalesce(try(b2.value.metrics, null), [])
                iterator = b3
                content {
                  minutes = try(b3.value.minutes, null)
                  status  = try(b3.value.status, null)
                }
              }
              dynamic "replication_time" {
                for_each = coalesce(try(b2.value.replication_time, null), [])
                iterator = b3
                content {
                  minutes = try(b3.value.minutes, null)
                  status  = try(b3.value.status, null)
                }
              }
            }
          }
          dynamic "filter" {
            for_each = coalesce(try(b1.value.filter, null), [])
            iterator = b2
            content {
              prefix = try(b2.value.prefix, null)
              tags   = try(b2.value.tags, null)
            }
          }
          dynamic "source_selection_criteria" {
            for_each = coalesce(try(b1.value.source_selection_criteria, null), [])
            iterator = b2
            content {
              dynamic "sse_kms_encrypted_objects" {
                for_each = coalesce(try(b2.value.sse_kms_encrypted_objects, null), [])
                iterator = b3
                content {
                  enabled = try(b3.value.enabled, null)
                }
              }
            }
          }
        }
      }
    }
  }
  dynamic "server_side_encryption_configuration" {
    for_each = coalesce(try(var.settings.server_side_encryption_configuration, null), [])
    iterator = b0
    content {
      dynamic "rule" {
        for_each = coalesce(try(b0.value.rule, null), [])
        iterator = b1
        content {
          bucket_key_enabled = try(b1.value.bucket_key_enabled, null)
          dynamic "apply_server_side_encryption_by_default" {
            for_each = coalesce(try(b1.value.apply_server_side_encryption_by_default, null), [])
            iterator = b2
            content {
              kms_master_key_id = try(b2.value.kms_master_key_id, null)
              sse_algorithm     = try(b2.value.sse_algorithm, null)
            }
          }
        }
      }
    }
  }
  dynamic "versioning" {
    for_each = coalesce(try(var.settings.versioning, null), [])
    iterator = b0
    content {
      enabled    = try(b0.value.enabled, null)
      mfa_delete = try(b0.value.mfa_delete, null)
    }
  }
  dynamic "website" {
    for_each = coalesce(try(var.settings.website, null), [])
    iterator = b0
    content {
      error_document           = try(b0.value.error_document, null)
      index_document           = try(b0.value.index_document, null)
      redirect_all_requests_to = try(b0.value.redirect_all_requests_to, null)
      routing_rules            = try(b0.value.routing_rules, null)
    }
  }
}
output "fields" {
  value = {
    arn                         = aws_s3_bucket.this.arn
    bucket                      = aws_s3_bucket.this.bucket
    bucket_domain_name          = aws_s3_bucket.this.bucket_domain_name
    bucket_namespace            = aws_s3_bucket.this.bucket_namespace
    bucket_prefix               = aws_s3_bucket.this.bucket_prefix
    bucket_region               = aws_s3_bucket.this.bucket_region
    bucket_regional_domain_name = aws_s3_bucket.this.bucket_regional_domain_name
    hosted_zone_id              = aws_s3_bucket.this.hosted_zone_id
    id                          = aws_s3_bucket.this.id
    object_lock_enabled         = aws_s3_bucket.this.object_lock_enabled
    region                      = aws_s3_bucket.this.region
  }
}
