output "rds_endpoint" {
  value       = aws_db_instance.crm_db.endpoint
  description = "The hostname:port to connect to the database"
}

output "rds_password" {
  value       = random_password.rds_master_password.result
  sensitive   = true
  description = "Master password for the RDS instance - handle carefully"
}