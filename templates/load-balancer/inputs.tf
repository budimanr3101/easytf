variable "instances" { type = map(object({ id = string, private_ip = string, vpc_id = string })) }
variable "vpc_id" { type = string }
variable "subnet_vpc_ids" { type = list(string) }
variable "subnet_azs" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "security_group_vpc_ids" { type = list(string) }
variable "tags" { type = map(string) }
