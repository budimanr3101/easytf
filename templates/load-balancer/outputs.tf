output "arn" { value = aws_lb.this.arn }
output "dns_name" { value = aws_lb.this.dns_name }
output "zone_id" { value = aws_lb.this.zone_id }
output "target_groups" { value = { for key, group in aws_lb_target_group.this : key => group.arn } }
output "listeners" { value = { for key, listener in aws_lb_listener.this : key => listener.arn } }

output "attachments" { value = { for key, target in aws_lb_target_group_attachment.this : key => { target_id = target.target_id, target_group_arn = target.target_group_arn } } }
output "tags" { value = aws_lb.this.tags }
