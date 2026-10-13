output "id" {
  value = aws_instance.this.id
}
output "private_ip" {
  value = aws_instance.this.private_ip
}
output "public_ip" {
  value = aws_instance.this.public_ip
}
output "subnet_id" {
  value = aws_instance.this.subnet_id
}
output "security_group_ids" {
  value = aws_instance.this.vpc_security_group_ids
}

output "iam_instance_profile" {
  value = aws_instance.this.iam_instance_profile
}
