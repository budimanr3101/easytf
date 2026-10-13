mock_provider "aws" {
  mock_resource "aws_lb" { defaults = { arn = "arn:aws:elasticloadbalancing:ap-southeast-3:123456789012:loadbalancer/app/mock/123456789abcdef0" } }
  mock_resource "aws_lb_target_group" { defaults = { arn = "arn:aws:elasticloadbalancing:ap-southeast-3:123456789012:targetgroup/mock/123456789abcdef0" } }
  mock_resource "aws_instance" { defaults = { id = "i-0123456789abcdef0", private_ip = "10.0.0.10" } }
  mock_data "aws_subnet" { defaults = { vpc_id = "vpc-0123456789abcdef0", availability_zone = "ap-southeast-3a" } }
  mock_data "aws_security_group" { defaults = { vpc_id = "vpc-0123456789abcdef0" } }
}
override_data {
  target = data.aws_subnet.existing["subnet-11111111111111111"]
  values = { vpc_id = "vpc-0123456789abcdef0", availability_zone = "ap-southeast-3b" }
}
run "plan_with_unknown_ec2_ids" {
  command = plan
  assert {
    condition     = length(module.load_balancers["frontend_alb"].target_groups) == 1 && length(module.load_balancers["frontend_nlb"].target_groups) == 1
    error_message = "ALB and NLB must each expose the linked target group."
  }
}
run "mock_apply_resolves_targets_and_tags" {
  command = apply
  assert {
    condition     = module.load_balancers["frontend_alb"].attachments[jsonencode(["web", "project", "web_primary"])].target_id == module.instances["web_primary"].id && module.load_balancers["frontend_nlb"].attachments[jsonencode(["web", "project", "web_primary"])].target_id == module.instances["web_primary"].id
    error_message = "Both LBs must register the actual EC2 output ID."
  }
  assert {
    condition     = module.load_balancers["frontend_alb"].tags["env"] == "dev" && module.load_balancers["frontend_nlb"].tags["project"] == "payment-service"
    error_message = "Environment tags must reach both load balancers."
  }
}
