variable "name" {
  type = string
}
variable "description" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "ingress" {
  type = map(object({
    protocol    = string
    from_port   = optional(number)
    to_port     = optional(number)
    cidr_ipv4   = string
    description = string
  }))
}
variable "egress" {
  type = map(object({
    protocol    = string
    from_port   = optional(number)
    to_port     = optional(number)
    cidr_ipv4   = string
    description = string
  }))
}
variable "tags" {
  type    = map(string)
  default = {}
}
