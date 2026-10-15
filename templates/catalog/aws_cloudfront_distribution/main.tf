variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_cloudfront_distribution" "this" {
  aliases                         = try(var.settings.aliases, null)
  anycast_ip_list_id              = try(var.settings.anycast_ip_list_id, null)
  comment                         = try(var.settings.comment, null)
  continuous_deployment_policy_id = try(var.settings.continuous_deployment_policy_id, null)
  default_root_object             = try(var.settings.default_root_object, null)
  enabled                         = try(var.settings.enabled, null)
  http_version                    = try(var.settings.http_version, null)
  is_ipv6_enabled                 = try(var.settings.is_ipv6_enabled, null)
  price_class                     = try(var.settings.price_class, null)
  retain_on_delete                = try(var.settings.retain_on_delete, null)
  staging                         = try(var.settings.staging, null)
  tags                            = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                        = try(var.settings.tags_all, null)
  wait_for_deployment             = try(var.settings.wait_for_deployment, null)
  web_acl_id                      = try(var.settings.web_acl_id, null)
  dynamic "cache_tag_config" {
    for_each = coalesce(try(var.settings.cache_tag_config, null), [])
    iterator = b0
    content {
      header_name = try(b0.value.header_name, null)
    }
  }
  dynamic "connection_function_association" {
    for_each = coalesce(try(var.settings.connection_function_association, null), [])
    iterator = b0
    content {
      id = try(b0.value.id, null)
    }
  }
  dynamic "custom_error_response" {
    for_each = coalesce(try(var.settings.custom_error_response, null), [])
    iterator = b0
    content {
      error_caching_min_ttl = try(b0.value.error_caching_min_ttl, null)
      error_code            = try(b0.value.error_code, null)
      response_code         = try(b0.value.response_code, null)
      response_page_path    = try(b0.value.response_page_path, null)
    }
  }
  dynamic "default_cache_behavior" {
    for_each = coalesce(try(var.settings.default_cache_behavior, null), [])
    iterator = b0
    content {
      allowed_methods            = try(b0.value.allowed_methods, null)
      cache_policy_id            = try(b0.value.cache_policy_id, null)
      cached_methods             = try(b0.value.cached_methods, null)
      compress                   = try(b0.value.compress, null)
      default_ttl                = try(b0.value.default_ttl, null)
      field_level_encryption_id  = try(b0.value.field_level_encryption_id, null)
      max_ttl                    = try(b0.value.max_ttl, null)
      min_ttl                    = try(b0.value.min_ttl, null)
      origin_request_policy_id   = try(b0.value.origin_request_policy_id, null)
      realtime_log_config_arn    = try(b0.value.realtime_log_config_arn, null)
      response_headers_policy_id = try(b0.value.response_headers_policy_id, null)
      smooth_streaming           = try(b0.value.smooth_streaming, null)
      target_origin_id           = try(b0.value.target_origin_id, null)
      trusted_key_groups         = try(b0.value.trusted_key_groups, null)
      trusted_signers            = try(b0.value.trusted_signers, null)
      viewer_protocol_policy     = try(b0.value.viewer_protocol_policy, null)
      dynamic "forwarded_values" {
        for_each = coalesce(try(b0.value.forwarded_values, null), [])
        iterator = b1
        content {
          headers                 = try(b1.value.headers, null)
          query_string            = try(b1.value.query_string, null)
          query_string_cache_keys = try(b1.value.query_string_cache_keys, null)
          dynamic "cookies" {
            for_each = coalesce(try(b1.value.cookies, null), [])
            iterator = b2
            content {
              forward           = try(b2.value.forward, null)
              whitelisted_names = try(b2.value.whitelisted_names, null)
            }
          }
        }
      }
      dynamic "function_association" {
        for_each = coalesce(try(b0.value.function_association, null), [])
        iterator = b1
        content {
          event_type   = try(b1.value.event_type, null)
          function_arn = try(b1.value.function_arn, null)
        }
      }
      dynamic "grpc_config" {
        for_each = coalesce(try(b0.value.grpc_config, null), [])
        iterator = b1
        content {
          enabled = try(b1.value.enabled, null)
        }
      }
      dynamic "lambda_function_association" {
        for_each = coalesce(try(b0.value.lambda_function_association, null), [])
        iterator = b1
        content {
          event_type   = try(b1.value.event_type, null)
          include_body = try(b1.value.include_body, null)
          lambda_arn   = try(b1.value.lambda_arn, null)
        }
      }
    }
  }
  dynamic "logging_config" {
    for_each = coalesce(try(var.settings.logging_config, null), [])
    iterator = b0
    content {
      bucket          = try(b0.value.bucket, null)
      include_cookies = try(b0.value.include_cookies, null)
      prefix          = try(b0.value.prefix, null)
    }
  }
  dynamic "ordered_cache_behavior" {
    for_each = coalesce(try(var.settings.ordered_cache_behavior, null), [])
    iterator = b0
    content {
      allowed_methods            = try(b0.value.allowed_methods, null)
      cache_policy_id            = try(b0.value.cache_policy_id, null)
      cached_methods             = try(b0.value.cached_methods, null)
      compress                   = try(b0.value.compress, null)
      default_ttl                = try(b0.value.default_ttl, null)
      field_level_encryption_id  = try(b0.value.field_level_encryption_id, null)
      max_ttl                    = try(b0.value.max_ttl, null)
      min_ttl                    = try(b0.value.min_ttl, null)
      origin_request_policy_id   = try(b0.value.origin_request_policy_id, null)
      path_pattern               = try(b0.value.path_pattern, null)
      realtime_log_config_arn    = try(b0.value.realtime_log_config_arn, null)
      response_headers_policy_id = try(b0.value.response_headers_policy_id, null)
      smooth_streaming           = try(b0.value.smooth_streaming, null)
      target_origin_id           = try(b0.value.target_origin_id, null)
      trusted_key_groups         = try(b0.value.trusted_key_groups, null)
      trusted_signers            = try(b0.value.trusted_signers, null)
      viewer_protocol_policy     = try(b0.value.viewer_protocol_policy, null)
      dynamic "forwarded_values" {
        for_each = coalesce(try(b0.value.forwarded_values, null), [])
        iterator = b1
        content {
          headers                 = try(b1.value.headers, null)
          query_string            = try(b1.value.query_string, null)
          query_string_cache_keys = try(b1.value.query_string_cache_keys, null)
          dynamic "cookies" {
            for_each = coalesce(try(b1.value.cookies, null), [])
            iterator = b2
            content {
              forward           = try(b2.value.forward, null)
              whitelisted_names = try(b2.value.whitelisted_names, null)
            }
          }
        }
      }
      dynamic "function_association" {
        for_each = coalesce(try(b0.value.function_association, null), [])
        iterator = b1
        content {
          event_type   = try(b1.value.event_type, null)
          function_arn = try(b1.value.function_arn, null)
        }
      }
      dynamic "grpc_config" {
        for_each = coalesce(try(b0.value.grpc_config, null), [])
        iterator = b1
        content {
          enabled = try(b1.value.enabled, null)
        }
      }
      dynamic "lambda_function_association" {
        for_each = coalesce(try(b0.value.lambda_function_association, null), [])
        iterator = b1
        content {
          event_type   = try(b1.value.event_type, null)
          include_body = try(b1.value.include_body, null)
          lambda_arn   = try(b1.value.lambda_arn, null)
        }
      }
    }
  }
  dynamic "origin" {
    for_each = coalesce(try(var.settings.origin, null), [])
    iterator = b0
    content {
      connection_attempts         = try(b0.value.connection_attempts, null)
      connection_timeout          = try(b0.value.connection_timeout, null)
      domain_name                 = try(b0.value.domain_name, null)
      origin_access_control_id    = try(b0.value.origin_access_control_id, null)
      origin_id                   = try(b0.value.origin_id, null)
      origin_path                 = try(b0.value.origin_path, null)
      response_completion_timeout = try(b0.value.response_completion_timeout, null)
      dynamic "custom_header" {
        for_each = coalesce(try(b0.value.custom_header, null), [])
        iterator = b1
        content {
          name  = try(b1.value.name, null)
          value = try(b1.value.value, null)
        }
      }
      dynamic "custom_origin_config" {
        for_each = coalesce(try(b0.value.custom_origin_config, null), [])
        iterator = b1
        content {
          http_port                = try(b1.value.http_port, null)
          https_port               = try(b1.value.https_port, null)
          ip_address_type          = try(b1.value.ip_address_type, null)
          origin_keepalive_timeout = try(b1.value.origin_keepalive_timeout, null)
          origin_protocol_policy   = try(b1.value.origin_protocol_policy, null)
          origin_read_timeout      = try(b1.value.origin_read_timeout, null)
          origin_ssl_protocols     = try(b1.value.origin_ssl_protocols, null)
          dynamic "origin_mtls_config" {
            for_each = coalesce(try(b1.value.origin_mtls_config, null), [])
            iterator = b2
            content {
              client_certificate_arn = try(b2.value.client_certificate_arn, null)
            }
          }
        }
      }
      dynamic "origin_shield" {
        for_each = coalesce(try(b0.value.origin_shield, null), [])
        iterator = b1
        content {
          enabled              = try(b1.value.enabled, null)
          origin_shield_region = try(b1.value.origin_shield_region, null)
        }
      }
      dynamic "s3_origin_config" {
        for_each = coalesce(try(b0.value.s3_origin_config, null), [])
        iterator = b1
        content {
          origin_access_identity = try(b1.value.origin_access_identity, null)
        }
      }
      dynamic "vpc_origin_config" {
        for_each = coalesce(try(b0.value.vpc_origin_config, null), [])
        iterator = b1
        content {
          origin_keepalive_timeout = try(b1.value.origin_keepalive_timeout, null)
          origin_read_timeout      = try(b1.value.origin_read_timeout, null)
          owner_account_id         = try(b1.value.owner_account_id, null)
          vpc_origin_id            = try(b1.value.vpc_origin_id, null)
        }
      }
    }
  }
  dynamic "origin_group" {
    for_each = coalesce(try(var.settings.origin_group, null), [])
    iterator = b0
    content {
      origin_id = try(b0.value.origin_id, null)
      dynamic "failover_criteria" {
        for_each = coalesce(try(b0.value.failover_criteria, null), [])
        iterator = b1
        content {
          status_codes = try(b1.value.status_codes, null)
        }
      }
      dynamic "member" {
        for_each = coalesce(try(b0.value.member, null), [])
        iterator = b1
        content {
          origin_id = try(b1.value.origin_id, null)
        }
      }
    }
  }
  dynamic "restrictions" {
    for_each = coalesce(try(var.settings.restrictions, null), [])
    iterator = b0
    content {
      dynamic "geo_restriction" {
        for_each = coalesce(try(b0.value.geo_restriction, null), [])
        iterator = b1
        content {
          locations        = try(b1.value.locations, null)
          restriction_type = try(b1.value.restriction_type, null)
        }
      }
    }
  }
  dynamic "viewer_certificate" {
    for_each = coalesce(try(var.settings.viewer_certificate, null), [])
    iterator = b0
    content {
      acm_certificate_arn            = try(b0.value.acm_certificate_arn, null)
      cloudfront_default_certificate = try(b0.value.cloudfront_default_certificate, null)
      iam_certificate_id             = try(b0.value.iam_certificate_id, null)
      minimum_protocol_version       = try(b0.value.minimum_protocol_version, null)
      ssl_support_method             = try(b0.value.ssl_support_method, null)
    }
  }
  dynamic "viewer_mtls_config" {
    for_each = coalesce(try(var.settings.viewer_mtls_config, null), [])
    iterator = b0
    content {
      mode = try(b0.value.mode, null)
      dynamic "trust_store_config" {
        for_each = coalesce(try(b0.value.trust_store_config, null), [])
        iterator = b1
        content {
          advertise_trust_store_ca_names = try(b1.value.advertise_trust_store_ca_names, null)
          ignore_certificate_expiry      = try(b1.value.ignore_certificate_expiry, null)
          trust_store_id                 = try(b1.value.trust_store_id, null)
        }
      }
    }
  }
}
output "fields" {
  value = {
    arn                             = aws_cloudfront_distribution.this.arn
    caller_reference                = aws_cloudfront_distribution.this.caller_reference
    continuous_deployment_policy_id = aws_cloudfront_distribution.this.continuous_deployment_policy_id
    domain_name                     = aws_cloudfront_distribution.this.domain_name
    etag                            = aws_cloudfront_distribution.this.etag
    hosted_zone_id                  = aws_cloudfront_distribution.this.hosted_zone_id
    id                              = aws_cloudfront_distribution.this.id
    in_progress_validation_batches  = aws_cloudfront_distribution.this.in_progress_validation_batches
    last_modified_time              = aws_cloudfront_distribution.this.last_modified_time
    logging_v1_enabled              = aws_cloudfront_distribution.this.logging_v1_enabled
    status                          = aws_cloudfront_distribution.this.status
  }
}
