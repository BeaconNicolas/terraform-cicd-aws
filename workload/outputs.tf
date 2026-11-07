output "bucket_name" {
  description = "Name of the example S3 bucket."
  value       = aws_s3_bucket.app.bucket
}

output "parameter_name" {
  description = "Name of the example SSM parameter."
  value       = aws_ssm_parameter.app_message.name
}
