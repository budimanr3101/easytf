variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_cloudwatch_metric_alarm" "this" {
  actions_enabled                       = try(var.settings.actions_enabled, null)
  alarm_actions                         = try(var.settings.alarm_actions, null)
  alarm_description                     = try(var.settings.alarm_description, null)
  alarm_name                            = try(var.settings.alarm_name, null)
  comparison_operator                   = try(var.settings.comparison_operator, null)
  datapoints_to_alarm                   = try(var.settings.datapoints_to_alarm, null)
  dimensions                            = try(var.settings.dimensions, null)
  evaluate_low_sample_count_percentiles = try(var.settings.evaluate_low_sample_count_percentiles, null)
  evaluation_interval                   = try(var.settings.evaluation_interval, null)
  evaluation_periods                    = try(var.settings.evaluation_periods, null)
  extended_statistic                    = try(var.settings.extended_statistic, null)
  insufficient_data_actions             = try(var.settings.insufficient_data_actions, null)
  metric_name                           = try(var.settings.metric_name, null)
  namespace                             = try(var.settings.namespace, null)
  ok_actions                            = try(var.settings.ok_actions, null)
  period                                = try(var.settings.period, null)
  region                                = try(var.settings.region, null)
  statistic                             = try(var.settings.statistic, null)
  tags                                  = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                              = try(var.settings.tags_all, null)
  threshold                             = try(var.settings.threshold, null)
  threshold_metric_id                   = try(var.settings.threshold_metric_id, null)
  treat_missing_data                    = try(var.settings.treat_missing_data, null)
  unit                                  = try(var.settings.unit, null)
  dynamic "evaluation_criteria" {
    for_each = coalesce(try(var.settings.evaluation_criteria, null), [])
    iterator = b0
    content {
      dynamic "promql_criteria" {
        for_each = coalesce(try(b0.value.promql_criteria, null), [])
        iterator = b1
        content {
          pending_period  = try(b1.value.pending_period, null)
          query           = try(b1.value.query, null)
          recovery_period = try(b1.value.recovery_period, null)
        }
      }
    }
  }
  dynamic "metric_query" {
    for_each = coalesce(try(var.settings.metric_query, null), [])
    iterator = b0
    content {
      account_id  = try(b0.value.account_id, null)
      expression  = try(b0.value.expression, null)
      id          = try(b0.value.id, null)
      label       = try(b0.value.label, null)
      period      = try(b0.value.period, null)
      return_data = try(b0.value.return_data, null)
      dynamic "metric" {
        for_each = coalesce(try(b0.value.metric, null), [])
        iterator = b1
        content {
          dimensions  = try(b1.value.dimensions, null)
          metric_name = try(b1.value.metric_name, null)
          namespace   = try(b1.value.namespace, null)
          period      = try(b1.value.period, null)
          stat        = try(b1.value.stat, null)
          unit        = try(b1.value.unit, null)
        }
      }
    }
  }
  dynamic "warm_up_configuration" {
    for_each = coalesce(try(var.settings.warm_up_configuration, null), [])
    iterator = b0
    content {
      only_start_evaluating_after_warm_up_period_ends = try(b0.value.only_start_evaluating_after_warm_up_period_ends, null)
      warm_up_period_duration_in_minutes              = try(b0.value.warm_up_period_duration_in_minutes, null)
    }
  }
}
output "fields" {
  value = {
    arn                                   = aws_cloudwatch_metric_alarm.this.arn
    evaluate_low_sample_count_percentiles = aws_cloudwatch_metric_alarm.this.evaluate_low_sample_count_percentiles
    id                                    = aws_cloudwatch_metric_alarm.this.id
    region                                = aws_cloudwatch_metric_alarm.this.region
  }
}
