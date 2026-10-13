module "load_balancers" {
  for_each       = var.load_balancers
  source         = "../../modules/load-balancer"
  settings       = each.value
  vpc_id         = data.aws_subnet.existing[each.value.subnet_ids[0]].vpc_id
  subnet_vpc_ids = [for id in each.value.subnet_ids : data.aws_subnet.existing[id].vpc_id]
  subnet_azs     = [for id in each.value.subnet_ids : data.aws_subnet.existing[id].availability_zone]
  tags           = merge(var.tags, each.value.tags)
  security_group_ids = concat(
    [for id in each.value.existing_security_group_ids : data.aws_security_group.existing[id].id],
    [for key in each.value.security_group_keys : module.security_groups[key].id]
  )
  security_group_vpc_ids = concat(
    [for id in each.value.existing_security_group_ids : data.aws_security_group.existing[id].vpc_id],
    [for key in each.value.security_group_keys : module.security_groups[key].vpc_id]
  )
  instances = { for key in toset(flatten([for group in each.value.target_groups : group.instance_keys])) : key => {
    id         = module.instances[key].id
    private_ip = module.instances[key].private_ip
    vpc_id     = data.aws_subnet.existing[var.instances[key].subnet_id].vpc_id
  } }
}
