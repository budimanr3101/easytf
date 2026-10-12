data "aws_subnet" "existing" {
  for_each = toset(concat(
    [for instance in var.instances : instance.subnet_id],
    [for group in var.security_groups : group.subnet_id]
  ))
  id = each.key
}

data "aws_security_group" "existing" {
  for_each = toset(flatten([
    for instance in var.instances : instance.existing_security_group_ids
  ]))
  id = each.key
}

module "security_groups" {
  for_each = var.security_groups
  source   = "../../modules/security-group"

  name        = each.value.name
  description = each.value.description
  vpc_id      = data.aws_subnet.existing[each.value.subnet_id].vpc_id
  ingress     = each.value.ingress
  egress      = each.value.egress
  tags        = each.value.tags
}

module "instances" {
  for_each = var.instances
  source   = "../../modules/ec2"

  name                = each.value.name
  ami_id              = each.value.ami_id
  instance_type       = each.value.instance_type
  subnet_id           = data.aws_subnet.existing[each.value.subnet_id].id
  vpc_id              = data.aws_subnet.existing[each.value.subnet_id].vpc_id
  root_volume_gib     = each.value.root_volume_gib
  associate_public_ip = each.value.associate_public_ip
  tags                = each.value.tags
  security_group_ids = concat(
    [for id in each.value.existing_security_group_ids : data.aws_security_group.existing[id].id],
    [for key in each.value.security_group_keys : module.security_groups[key].id]
  )
  security_group_vpc_ids = concat(
    [for id in each.value.existing_security_group_ids : data.aws_security_group.existing[id].vpc_id],
    [for key in each.value.security_group_keys : module.security_groups[key].vpc_id]
  )
}
