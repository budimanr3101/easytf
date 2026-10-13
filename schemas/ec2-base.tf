resource "aws_instance" "this" {
  ami                         = var.ami_id == "" ? null : var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = local.eni_mode ? null : var.subnet_id
  vpc_security_group_ids      = local.eni_mode || length(var.security_group_ids) == 0 ? null : var.security_group_ids
  associate_public_ip_address = local.eni_mode ? null : var.associate_public_ip

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition = alltrue([for eni in data.aws_network_interface.existing : eni.subnet_id == var.subnet_id && eni.vpc_id == var.vpc_id])
      error_message = "Existing network interfaces must belong to the selected subnet and VPC."
    }
    precondition {
      condition = local.eni_mode || length(coalesce(var.configuration.launch_template, [])) > 0 || (length(var.security_group_ids) > 0 && alltrue([
        for vpc_id in var.security_group_vpc_ids : vpc_id == var.vpc_id
      ]))
      error_message = "Select security groups in the subnet's primary VPC. Additional SG VPC associations are outside this MVP."
    }
  }
}
