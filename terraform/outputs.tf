# ====================================================================
# PRODUCER VPC (LEGACYLENS) OUTPUTS
# ====================================================================

output "producer_vpc_id" {
  description = "The ID of the Producer VPC (LegacyLens)"
  value       = aws_vpc.legacylens.id
}

output "producer_vpc_cidr" {
  description = "The CIDR block of the Producer VPC"
  value       = aws_vpc.legacylens.cidr_block
}

output "public_subnet_id" {
  description = "The ID of the public subnet (used for Bastion & NAT)"
  value       = aws_subnet.public_subnet.id
}

output "private_app_subnet_id" {
  description = "The ID of the private application subnet"
  value       = aws_subnet.private_app.id
}

output "private_db_subnet_ids" {
  description = "The IDs of the multi-AZ private database subnets"
  value       = [
    aws_subnet.private_db_subnet.id,
    aws_subnet.private_db_subnet_2.id
  ]
}

# ====================================================================
# CONSUMER VPC (ALPHA) OUTPUTS
# ====================================================================

output "consumer_vpc_id" {
  description = "The ID of the Consumer VPC (Alpha)"
  value       = aws_vpc.alpha.id
}

output "consumer_vpc_cidr" {
  description = "The CIDR block of the Consumer VPC"
  value       = aws_vpc.alpha.cidr_block
}

output "consumer_private_subnets" {
  description = "The IDs of the Consumer VPC private subnets"
  value       = [
    aws_subnet.alpha_private_a.id,
    aws_subnet.alpha_private_b.id
  ]
}

# ====================================================================
# COMPUTE & DATABASE OUTPUTS
# ====================================================================

output "bastion_host_id" {
  description = "The Instance ID of the Bastion Host"
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "The Public IP address of the Bastion Host"
  value       = aws_instance.bastion.public_ip
}

output "private_app_server_id" {
  description = "The Instance ID of the Private Application Server"
  value       = aws_instance.private_app_server.id
}

output "private_app_server_ip" {
  description = "The Private IP address of the Application Server"
  value       = aws_instance.private_app_server.private_ip
}

output "database_endpoint" {
  description = "The connection endpoint string for the RDS PostgreSQL database"
  value       = aws_db_instance.postgres_db.endpoint
}

output "database_port" {
  description = "The port the RDS database is listening on"
  value       = aws_db_instance.postgres_db.port
}

# ====================================================================
# SECURITY GROUP OUTPUTS
# ====================================================================

output "bastion_sg_id" {
  description = "The Security Group ID for the Bastion Host"
  value       = aws_security_group.bastion_sg.id
}

output "app_server_sg_id" {
  description = "The Security Group ID for the Application Server"
  value       = aws_security_group.private_app_sg.id
}

output "database_sg_id" {
  description = "The Security Group ID for the Database"
  value       = aws_security_group.db_sg.id
}