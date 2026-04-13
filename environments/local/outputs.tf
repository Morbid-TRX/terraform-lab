output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.my_vpc.id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = aws_subnet.my_subnet.id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.my_sg.id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.my_bucket.id
}