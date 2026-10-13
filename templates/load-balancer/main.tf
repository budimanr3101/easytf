locals {
  project_targets = flatten([for group_key, group in var.settings.target_groups : [for instance_key in group.instance_keys : {
    key       = jsonencode([group_key, "project", instance_key])
    group_key = group_key
    target_id = group.target_type == "instance" ? var.instances[instance_key].id : var.instances[instance_key].private_ip
    vpc_id    = var.instances[instance_key].vpc_id
  }]])
  existing_targets = flatten([for group_key, group in var.settings.target_groups : [for id in group.existing_target_ids : {
    key       = jsonencode([group_key, "existing", id])
    group_key = group_key
    target_id = id
    vpc_id    = group.target_type == "instance" ? data.aws_subnet.target[id].vpc_id : var.vpc_id
  }]])
}
data "aws_instance" "target" {
  for_each    = toset(flatten([for group in var.settings.target_groups : group.target_type == "instance" ? group.existing_target_ids : []]))
  instance_id = each.key
}
data "aws_subnet" "target" {
  for_each = data.aws_instance.target
  id       = each.value.subnet_id
}
resource "aws_lb" "this" {
  name                       = var.settings.name
  load_balancer_type         = var.settings.load_balancer_type
  internal                   = var.settings.internal
  subnets                    = var.settings.subnet_ids
  security_groups            = length(var.security_group_ids) == 0 ? null : var.security_group_ids
  enable_deletion_protection = var.settings.deletion_protection
  tags                       = merge(var.tags, { Name = var.settings.name })
  lifecycle {
    precondition {
      condition     = alltrue([for vpc in var.subnet_vpc_ids : vpc == var.vpc_id]) && alltrue([for vpc in var.security_group_vpc_ids : vpc == var.vpc_id])
      error_message = "Load balancer subnets and security groups must be in the same VPC."
    }
    precondition {
      condition     = length(distinct(var.subnet_azs)) == length(var.settings.subnet_ids)
      error_message = "Choose at most one subnet per AZ; ALB needs at least two AZs."
    }
  }
}
resource "aws_lb_target_group" "this" {
  for_each    = var.settings.target_groups
  name_prefix = "etf-"
  port        = each.value.port
  protocol    = each.value.protocol
  target_type = each.value.target_type
  vpc_id      = var.vpc_id
  health_check {
    protocol            = each.value.health_check.protocol
    port                = each.value.health_check.port
    path                = each.value.health_check.path
    matcher             = each.value.health_check.matcher
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
  }
  tags = merge(var.tags, each.value.tags, { Name = "${var.settings.name}-${each.key}" })
  lifecycle { create_before_destroy = true }
}
resource "aws_lb_listener" "this" {
  for_each          = var.settings.listeners
  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = each.value.protocol
  certificate_arn   = each.value.certificate_arn
  ssl_policy        = each.value.ssl_policy
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.value.target_group_key].arn
  }
  tags = var.tags
}
resource "aws_lb_target_group_attachment" "this" {
  for_each         = { for target in concat(local.project_targets, local.existing_targets) : target.key => target }
  target_group_arn = aws_lb_target_group.this[each.value.group_key].arn
  target_id        = each.value.target_id
  port             = var.settings.target_groups[each.value.group_key].port
  lifecycle {
    precondition {
      condition     = each.value.vpc_id == var.vpc_id
      error_message = "Instance targets must belong to the load balancer VPC."
    }
  }
}
