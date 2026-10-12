variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
}

variable "aws_profile" {
  description = "Optional AWS profile; null uses the normal AWS credential chain."
  type        = string
  default     = null
}

variable "tags" {
  description = "Default resource tags."
  type        = map(string)
  default     = {}
}

variable "instances" {
  description = "EC2 instances keyed by stable resource identity."
  type = map(object({
    name                        = string
    ami_id                      = string
    instance_type               = string
    subnet_id                   = string
    existing_security_group_ids = optional(list(string), [])
    security_group_keys         = optional(list(string), [])
    root_volume_gib             = optional(number, 20)
    associate_public_ip         = optional(bool, false)
    tags                        = optional(map(string), {})
  }))
  default = {}
}

variable "security_groups" {
  description = "Managed security groups; the existing subnet determines their primary VPC."
  type = map(object({
    name        = string
    description = string
    subnet_id   = string
    ingress = optional(map(object({
      protocol    = string
      from_port   = optional(number)
      to_port     = optional(number)
      cidr_ipv4   = string
      description = string
    })), {})
    egress = optional(map(object({
      protocol    = string
      from_port   = optional(number)
      to_port     = optional(number)
      cidr_ipv4   = string
      description = string
      })), {
      all_ipv4 = {
        protocol    = "-1"
        from_port   = null
        to_port     = null
        cidr_ipv4   = "0.0.0.0/0"
        description = "Allow outbound IPv4 traffic"
      }
    })
    tags = optional(map(string), {})
  }))
  default = {}
}
