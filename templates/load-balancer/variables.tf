variable "instances" { type = map(object({ id = string, private_ip = string, vpc_id = string })) }
variable "vpc_id" { type = string }
variable "subnet_vpc_ids" { type = list(string) }
variable "subnet_azs" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "security_group_vpc_ids" { type = list(string) }
variable "tags" { type = map(string) }

variable "settings" {
  type = object({
    name                        = string
    load_balancer_type          = string
    internal                    = optional(bool, false)
    subnet_ids                  = list(string)
    existing_security_group_ids = optional(list(string), [])
    security_group_keys         = optional(list(string), [])
    deletion_protection         = optional(bool, false)
    tags                        = optional(map(string), {})
    target_groups = map(object({
      port                = number
      protocol            = string
      target_type         = string
      instance_keys       = optional(list(string), [])
      existing_target_ids = optional(list(string), [])
      tags                = optional(map(string), {})
      health_check = object({
        protocol            = string
        port                = string
        path                = optional(string)
        matcher             = optional(string)
        interval            = number
        timeout             = number
        healthy_threshold   = number
        unhealthy_threshold = number
      })
    }))
    listeners = map(object({
      port             = number
      protocol         = string
      target_group_key = string
      certificate_arn  = optional(string)
      ssl_policy       = optional(string)
    }))
  })

}
