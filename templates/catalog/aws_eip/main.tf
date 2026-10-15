variable "settings" { type = any }
variable "environment_tags" { type = map(string) }
variable "resource_tags" { type = map(string) }
resource "aws_eip" "this" {
  address                   = try(var.settings.address, null)
  associate_with_private_ip = try(var.settings.associate_with_private_ip, null)
  customer_owned_ipv4_pool  = try(var.settings.customer_owned_ipv4_pool, null)
  domain                    = try(var.settings.domain, null)
  instance                  = try(var.settings.instance, null)
  ipam_pool_id              = try(var.settings.ipam_pool_id, null)
  network_border_group      = try(var.settings.network_border_group, null)
  network_interface         = try(var.settings.network_interface, null)
  public_ipv4_pool          = try(var.settings.public_ipv4_pool, null)
  region                    = try(var.settings.region, null)
  tags                      = merge(var.environment_tags, coalesce(try(var.settings.tags, null), {}), var.resource_tags)
  tags_all                  = try(var.settings.tags_all, null)
}
output "fields" {
  value = {
    allocation_id        = aws_eip.this.allocation_id
    arn                  = aws_eip.this.arn
    association_id       = aws_eip.this.association_id
    carrier_ip           = aws_eip.this.carrier_ip
    customer_owned_ip    = aws_eip.this.customer_owned_ip
    domain               = aws_eip.this.domain
    id                   = aws_eip.this.id
    instance             = aws_eip.this.instance
    ipam_pool_id         = aws_eip.this.ipam_pool_id
    network_border_group = aws_eip.this.network_border_group
    network_interface    = aws_eip.this.network_interface
    private_dns          = aws_eip.this.private_dns
    private_ip           = aws_eip.this.private_ip
    ptr_record           = aws_eip.this.ptr_record
    public_dns           = aws_eip.this.public_dns
    public_ip            = aws_eip.this.public_ip
    public_ipv4_pool     = aws_eip.this.public_ipv4_pool
    region               = aws_eip.this.region
  }
}
