output "id" {
  description = "Bucket name."
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "policy" {
  description = "The bucket policy document (JSON)."
  value       = aws_s3_bucket_policy.this.policy
}
