variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_db_instance" "this" {
  allocated_storage                     = try(var.settings.allocated_storage, null)
  allow_major_version_upgrade           = try(var.settings.allow_major_version_upgrade, null)
  apply_immediately                     = try(var.settings.apply_immediately, null)
  auto_minor_version_upgrade            = try(var.settings.auto_minor_version_upgrade, null)
  availability_zone                     = try(var.settings.availability_zone, null)
  backup_retention_period               = try(var.settings.backup_retention_period, null)
  backup_target                         = try(var.settings.backup_target, null)
  backup_window                         = try(var.settings.backup_window, null)
  ca_cert_identifier                    = try(var.settings.ca_cert_identifier, null)
  character_set_name                    = try(var.settings.character_set_name, null)
  copy_tags_to_snapshot                 = try(var.settings.copy_tags_to_snapshot, null)
  custom_iam_instance_profile           = try(var.settings.custom_iam_instance_profile, null)
  customer_owned_ip_enabled             = try(var.settings.customer_owned_ip_enabled, null)
  database_insights_mode                = try(var.settings.database_insights_mode, null)
  db_name                               = try(var.settings.db_name, null)
  db_subnet_group_name                  = try(var.settings.db_subnet_group_name, null)
  dedicated_log_volume                  = try(var.settings.dedicated_log_volume, null)
  delete_automated_backups              = try(var.settings.delete_automated_backups, null)
  deletion_protection                   = try(var.settings.deletion_protection, null)
  domain                                = try(var.settings.domain, null)
  domain_auth_secret_arn                = try(var.settings.domain_auth_secret_arn, null)
  domain_dns_ips                        = try(var.settings.domain_dns_ips, null)
  domain_fqdn                           = try(var.settings.domain_fqdn, null)
  domain_iam_role_name                  = try(var.settings.domain_iam_role_name, null)
  domain_ou                             = try(var.settings.domain_ou, null)
  enabled_cloudwatch_logs_exports       = try(var.settings.enabled_cloudwatch_logs_exports, null)
  engine                                = try(var.settings.engine, null)
  engine_lifecycle_support              = try(var.settings.engine_lifecycle_support, null)
  engine_version                        = try(var.settings.engine_version, null)
  final_snapshot_identifier             = try(var.settings.final_snapshot_identifier, null)
  iam_database_authentication_enabled   = try(var.settings.iam_database_authentication_enabled, null)
  identifier                            = try(var.settings.identifier, null)
  identifier_prefix                     = try(var.settings.identifier_prefix, null)
  instance_class                        = try(var.settings.instance_class, null)
  iops                                  = try(var.settings.iops, null)
  kms_key_id                            = try(var.settings.kms_key_id, null)
  license_model                         = try(var.settings.license_model, null)
  maintenance_window                    = try(var.settings.maintenance_window, null)
  manage_master_user_password           = try(var.settings.manage_master_user_password, null)
  master_user_secret_kms_key_id         = try(var.settings.master_user_secret_kms_key_id, null)
  max_allocated_storage                 = try(var.settings.max_allocated_storage, null)
  monitoring_interval                   = try(var.settings.monitoring_interval, null)
  monitoring_role_arn                   = try(var.settings.monitoring_role_arn, null)
  multi_az                              = try(var.settings.multi_az, null)
  nchar_character_set_name              = try(var.settings.nchar_character_set_name, null)
  network_type                          = try(var.settings.network_type, null)
  option_group_name                     = try(var.settings.option_group_name, null)
  parameter_group_name                  = try(var.settings.parameter_group_name, null)
  performance_insights_enabled          = try(var.settings.performance_insights_enabled, null)
  performance_insights_kms_key_id       = try(var.settings.performance_insights_kms_key_id, null)
  performance_insights_retention_period = try(var.settings.performance_insights_retention_period, null)
  port                                  = try(var.settings.port, null)
  publicly_accessible                   = try(var.settings.publicly_accessible, null)
  region                                = try(var.settings.region, null)
  replica_mode                          = try(var.settings.replica_mode, null)
  replicate_source_db                   = try(var.settings.replicate_source_db, null)
  skip_final_snapshot                   = try(var.settings.skip_final_snapshot, null)
  snapshot_identifier                   = try(var.settings.snapshot_identifier, null)
  storage_encrypted                     = try(var.settings.storage_encrypted, null)
  storage_throughput                    = try(var.settings.storage_throughput, null)
  storage_type                          = try(var.settings.storage_type, null)
  tags                                  = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                              = try(var.settings.tags_all, null)
  timezone                              = try(var.settings.timezone, null)
  upgrade_storage_config                = try(var.settings.upgrade_storage_config, null)
  username                              = try(var.settings.username, null)
  vpc_security_group_ids                = try(var.settings.vpc_security_group_ids, null)
  warning_event_categories              = try(var.settings.warning_event_categories, null)
  dynamic "blue_green_update" {
    for_each = coalesce(try(var.settings.blue_green_update, null), [])
    iterator = b0
    content {
      enabled = try(b0.value.enabled, null)
    }
  }
  dynamic "restore_to_point_in_time" {
    for_each = coalesce(try(var.settings.restore_to_point_in_time, null), [])
    iterator = b0
    content {
      restore_time                             = try(b0.value.restore_time, null)
      source_db_instance_automated_backups_arn = try(b0.value.source_db_instance_automated_backups_arn, null)
      source_db_instance_identifier            = try(b0.value.source_db_instance_identifier, null)
      source_dbi_resource_id                   = try(b0.value.source_dbi_resource_id, null)
      use_latest_restorable_time               = try(b0.value.use_latest_restorable_time, null)
    }
  }
  dynamic "s3_import" {
    for_each = coalesce(try(var.settings.s3_import, null), [])
    iterator = b0
    content {
      bucket_name           = try(b0.value.bucket_name, null)
      bucket_prefix         = try(b0.value.bucket_prefix, null)
      ingestion_role        = try(b0.value.ingestion_role, null)
      source_engine         = try(b0.value.source_engine, null)
      source_engine_version = try(b0.value.source_engine_version, null)
    }
  }
}
output "fields" {
  value = {
    address                               = aws_db_instance.this.address
    allocated_storage                     = aws_db_instance.this.allocated_storage
    arn                                   = aws_db_instance.this.arn
    availability_zone                     = aws_db_instance.this.availability_zone
    backup_retention_period               = aws_db_instance.this.backup_retention_period
    backup_target                         = aws_db_instance.this.backup_target
    backup_window                         = aws_db_instance.this.backup_window
    ca_cert_identifier                    = aws_db_instance.this.ca_cert_identifier
    character_set_name                    = aws_db_instance.this.character_set_name
    database_insights_mode                = aws_db_instance.this.database_insights_mode
    db_name                               = aws_db_instance.this.db_name
    db_subnet_group_name                  = aws_db_instance.this.db_subnet_group_name
    domain_fqdn                           = aws_db_instance.this.domain_fqdn
    endpoint                              = aws_db_instance.this.endpoint
    engine                                = aws_db_instance.this.engine
    engine_lifecycle_support              = aws_db_instance.this.engine_lifecycle_support
    engine_version                        = aws_db_instance.this.engine_version
    engine_version_actual                 = aws_db_instance.this.engine_version_actual
    hosted_zone_id                        = aws_db_instance.this.hosted_zone_id
    id                                    = aws_db_instance.this.id
    identifier                            = aws_db_instance.this.identifier
    identifier_prefix                     = aws_db_instance.this.identifier_prefix
    iops                                  = aws_db_instance.this.iops
    kms_key_id                            = aws_db_instance.this.kms_key_id
    latest_restorable_time                = aws_db_instance.this.latest_restorable_time
    license_model                         = aws_db_instance.this.license_model
    maintenance_window                    = aws_db_instance.this.maintenance_window
    master_user_secret_kms_key_id         = aws_db_instance.this.master_user_secret_kms_key_id
    monitoring_role_arn                   = aws_db_instance.this.monitoring_role_arn
    multi_az                              = aws_db_instance.this.multi_az
    nchar_character_set_name              = aws_db_instance.this.nchar_character_set_name
    network_type                          = aws_db_instance.this.network_type
    option_group_name                     = aws_db_instance.this.option_group_name
    parameter_group_name                  = aws_db_instance.this.parameter_group_name
    performance_insights_kms_key_id       = aws_db_instance.this.performance_insights_kms_key_id
    performance_insights_retention_period = aws_db_instance.this.performance_insights_retention_period
    port                                  = aws_db_instance.this.port
    region                                = aws_db_instance.this.region
    replica_mode                          = aws_db_instance.this.replica_mode
    resource_id                           = aws_db_instance.this.resource_id
    snapshot_identifier                   = aws_db_instance.this.snapshot_identifier
    status                                = aws_db_instance.this.status
    storage_throughput                    = aws_db_instance.this.storage_throughput
    storage_type                          = aws_db_instance.this.storage_type
    timezone                              = aws_db_instance.this.timezone
    upgrade_rollout_order                 = aws_db_instance.this.upgrade_rollout_order
    username                              = aws_db_instance.this.username
  }
}
