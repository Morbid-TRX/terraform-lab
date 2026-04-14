output "vpc_id" {
  description = "ID of the VPC"
  value       = module.infrastructure.vpc_id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = module.infrastructure.subnet_id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = module.infrastructure.s3_bucket_name
}
