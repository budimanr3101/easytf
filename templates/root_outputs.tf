output "instances" {
  description = "Managed EC2 instance IDs, addresses, and network context."
  value = {
    for key, instance in module.instances : key => {
      id                 = instance.id
      private_ip         = instance.private_ip
      public_ip          = instance.public_ip
      subnet_id          = instance.subnet_id
      security_group_ids = instance.security_group_ids
    }
  }
}

output "security_groups" {
  description = "Managed security group IDs and primary VPCs."
  value = { for key, group in module.security_groups : key => {
    id     = group.id
    vpc_id = group.vpc_id
  } }
}

output "existing_subnets" {
  description = "Referenced subnet information; these subnets are not adopted."
  value = { for id, subnet in data.aws_subnet.existing : id => {
    vpc_id            = subnet.vpc_id
    availability_zone = subnet.availability_zone
  } }
}
