variable "name" {
  type = string
}
variable "ami_id" {
  type = string
}
variable "instance_type" {
  type = string
}
variable "subnet_id" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "security_group_ids" {
  type = list(string)
}
variable "security_group_vpc_ids" {
  type = list(string)
}
variable "root_volume_gib" {
  type = number
  validation {
    condition     = var.root_volume_gib > 0 && floor(var.root_volume_gib) == var.root_volume_gib
    error_message = "Root volume size must be a positive integer."
  }
}
variable "associate_public_ip" {
  type = bool
}
variable "tags" {
  type    = map(string)
  default = {}
}
