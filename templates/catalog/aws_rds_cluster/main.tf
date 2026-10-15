variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_rds_cluster" "this" {
  allocated_storage                     = try(var.settings.allocated_storage, null)
  allow_major_version_upgrade           = try(var.settings.allow_major_version_upgrade, null)
  apply_immediately                     = try(var.settings.apply_immediately, null)
  auto_minor_version_upgrade            = try(var.settings.auto_minor_version_upgrade, null)
  availability_zones                    = try(var.settings.availability_zones, null)
  backtrack_window                      = try(var.settings.backtrack_window, null)
  backup_retention_period               = try(var.settings.backup_retention_period, null)
  ca_certificate_identifier             = try(var.settings.ca_certificate_identifier, null)
  cluster_identifier                    = try(var.settings.cluster_identifier, null)
  cluster_identifier_prefix             = try(var.settings.cluster_identifier_prefix, null)
  cluster_members                       = try(var.settings.cluster_members, null)
  cluster_scalability_type              = try(var.settings.cluster_scalability_type, null)
  copy_tags_to_snapshot                 = try(var.settings.copy_tags_to_snapshot, null)
  database_insights_mode                = try(var.settings.database_insights_mode, null)
  database_name                         = try(var.settings.database_name, null)
  db_cluster_instance_class             = try(var.settings.db_cluster_instance_class, null)
  db_cluster_parameter_group_name       = try(var.settings.db_cluster_parameter_group_name, null)
  db_instance_parameter_group_name      = try(var.settings.db_instance_parameter_group_name, null)
  db_subnet_group_name                  = try(var.settings.db_subnet_group_name, null)
  db_system_id                          = try(var.settings.db_system_id, null)
  delete_automated_backups              = try(var.settings.delete_automated_backups, null)
  deletion_protection                   = try(var.settings.deletion_protection, null)
  domain                                = try(var.settings.domain, null)
  domain_iam_role_name                  = try(var.settings.domain_iam_role_name, null)
  enable_global_write_forwarding        = try(var.settings.enable_global_write_forwarding, null)
  enable_http_endpoint                  = try(var.settings.enable_http_endpoint, null)
  enable_local_write_forwarding         = try(var.settings.enable_local_write_forwarding, null)
  enabled_cloudwatch_logs_exports       = try(var.settings.enabled_cloudwatch_logs_exports, null)
  engine                                = try(var.settings.engine, null)
  engine_lifecycle_support              = try(var.settings.engine_lifecycle_support, null)
  engine_mode                           = try(var.settings.engine_mode, null)
  engine_version                        = try(var.settings.engine_version, null)
  final_snapshot_identifier             = try(var.settings.final_snapshot_identifier, null)
  global_cluster_identifier             = try(var.settings.global_cluster_identifier, null)
  iam_database_authentication_enabled   = try(var.settings.iam_database_authentication_enabled, null)
  iam_roles                             = try(var.settings.iam_roles, null)
  iops                                  = try(var.settings.iops, null)
  kms_key_id                            = try(var.settings.kms_key_id, null)
  manage_master_user_password           = try(var.settings.manage_master_user_password, null)
  master_user_secret_kms_key_id         = try(var.settings.master_user_secret_kms_key_id, null)
  master_username                       = try(var.settings.master_username, null)
  monitoring_interval                   = try(var.settings.monitoring_interval, null)
  monitoring_role_arn                   = try(var.settings.monitoring_role_arn, null)
  network_type                          = try(var.settings.network_type, null)
  performance_insights_enabled          = try(var.settings.performance_insights_enabled, null)
  performance_insights_kms_key_id       = try(var.settings.performance_insights_kms_key_id, null)
  performance_insights_retention_period = try(var.settings.performance_insights_retention_period, null)
  port                                  = try(var.settings.port, null)
  preferred_backup_window               = try(var.settings.preferred_backup_window, null)
  preferred_maintenance_window          = try(var.settings.preferred_maintenance_window, null)
  region                                = try(var.settings.region, null)
  replication_source_identifier         = try(var.settings.replication_source_identifier, null)
  skip_final_snapshot                   = try(var.settings.skip_final_snapshot, null)
  snapshot_identifier                   = try(var.settings.snapshot_identifier, null)
  source_region                         = try(var.settings.source_region, null)
  storage_encrypted                     = try(var.settings.storage_encrypted, null)
  storage_type                          = try(var.settings.storage_type, null)
  tags                                  = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                              = try(var.settings.tags_all, null)
  vpc_security_group_ids                = try(var.settings.vpc_security_group_ids, null)
  warning_event_categories              = try(var.settings.warning_event_categories, null)
  dynamic "restore_to_point_in_time" {
    for_each = coalesce(try(var.settings.restore_to_point_in_time, null), [])
    iterator = b0
    content {
      restore_to_time            = try(b0.value.restore_to_time, null)
      restore_type               = try(b0.value.restore_type, null)
      source_cluster_identifier  = try(b0.value.source_cluster_identifier, null)
      source_cluster_resource_id = try(b0.value.source_cluster_resource_id, null)
      use_latest_restorable_time = try(b0.value.use_latest_restorable_time, null)
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
  dynamic "scaling_configuration" {
    for_each = coalesce(try(var.settings.scaling_configuration, null), [])
    iterator = b0
    content {
      auto_pause               = try(b0.value.auto_pause, null)
      max_capacity             = try(b0.value.max_capacity, null)
      min_capacity             = try(b0.value.min_capacity, null)
      seconds_before_timeout   = try(b0.value.seconds_before_timeout, null)
      seconds_until_auto_pause = try(b0.value.seconds_until_auto_pause, null)
      timeout_action           = try(b0.value.timeout_action, null)
    }
  }
  dynamic "serverlessv2_scaling_configuration" {
    for_each = coalesce(try(var.settings.serverlessv2_scaling_configuration, null), [])
    iterator = b0
    content {
      max_capacity             = try(b0.value.max_capacity, null)
      min_capacity             = try(b0.value.min_capacity, null)
      seconds_until_auto_pause = try(b0.value.seconds_until_auto_pause, null)
    }
  }
}
output "fields" {
  value = {
    allocated_storage                     = aws_rds_cluster.this.allocated_storage
    apply_immediately                     = aws_rds_cluster.this.apply_immediately
    arn                                   = aws_rds_cluster.this.arn
    auto_minor_version_upgrade            = aws_rds_cluster.this.auto_minor_version_upgrade
    backup_retention_period               = aws_rds_cluster.this.backup_retention_period
    ca_certificate_identifier             = aws_rds_cluster.this.ca_certificate_identifier
    ca_certificate_valid_till             = aws_rds_cluster.this.ca_certificate_valid_till
    cluster_identifier                    = aws_rds_cluster.this.cluster_identifier
    cluster_identifier_prefix             = aws_rds_cluster.this.cluster_identifier_prefix
    cluster_resource_id                   = aws_rds_cluster.this.cluster_resource_id
    cluster_scalability_type              = aws_rds_cluster.this.cluster_scalability_type
    database_insights_mode                = aws_rds_cluster.this.database_insights_mode
    database_name                         = aws_rds_cluster.this.database_name
    db_cluster_parameter_group_name       = aws_rds_cluster.this.db_cluster_parameter_group_name
    db_subnet_group_name                  = aws_rds_cluster.this.db_subnet_group_name
    db_system_id                          = aws_rds_cluster.this.db_system_id
    endpoint                              = aws_rds_cluster.this.endpoint
    engine                                = aws_rds_cluster.this.engine
    engine_lifecycle_support              = aws_rds_cluster.this.engine_lifecycle_support
    engine_version                        = aws_rds_cluster.this.engine_version
    engine_version_actual                 = aws_rds_cluster.this.engine_version_actual
    hosted_zone_id                        = aws_rds_cluster.this.hosted_zone_id
    id                                    = aws_rds_cluster.this.id
    kms_key_id                            = aws_rds_cluster.this.kms_key_id
    master_user_secret_kms_key_id         = aws_rds_cluster.this.master_user_secret_kms_key_id
    master_username                       = aws_rds_cluster.this.master_username
    monitoring_interval                   = aws_rds_cluster.this.monitoring_interval
    monitoring_role_arn                   = aws_rds_cluster.this.monitoring_role_arn
    network_type                          = aws_rds_cluster.this.network_type
    performance_insights_kms_key_id       = aws_rds_cluster.this.performance_insights_kms_key_id
    performance_insights_retention_period = aws_rds_cluster.this.performance_insights_retention_period
    port                                  = aws_rds_cluster.this.port
    preferred_backup_window               = aws_rds_cluster.this.preferred_backup_window
    preferred_maintenance_window          = aws_rds_cluster.this.preferred_maintenance_window
    reader_endpoint                       = aws_rds_cluster.this.reader_endpoint
    region                                = aws_rds_cluster.this.region
    storage_encrypted                     = aws_rds_cluster.this.storage_encrypted
    storage_type                          = aws_rds_cluster.this.storage_type
    upgrade_rollout_order                 = aws_rds_cluster.this.upgrade_rollout_order
  }
}
