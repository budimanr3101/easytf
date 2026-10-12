resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = var.associate_public_ip

  root_block_device {
    volume_size = var.root_volume_gib
    volume_type = "gp3"
    encrypted   = true
  }
  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition = length(var.security_group_ids) > 0 && alltrue([
        for vpc_id in var.security_group_vpc_ids : vpc_id == var.vpc_id
      ])
      error_message = "Select security groups in the subnet's primary VPC. Additional SG VPC associations are outside this MVP."
    }
  }
}
