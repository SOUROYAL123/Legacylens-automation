# LegacyLens Core Infrastructure — 22-Day AWS & DevOps Engineering Log

This repository documents the production deployment of the LegacyLens cloud architecture: Infrastructure as Code (IaC) with Terraform, Linux system auditing, PostgreSQL database engineering, and network security design in the `ap-south-1` (Mumbai) region.

---

## Day 1: Infrastructure as Code (IaC) Foundation

Migrated the core network architecture for LegacyLens from a manual AWS Console deployment to a repeatable Terraform configuration. This established a secure, multi-tier environment for container and database components in `ap-south-1`.

The infrastructure is built around a Virtual Private Cloud (`Legacylens-VPC`) with a `10.0.0.0/16` CIDR block, segmented into three subnets:

- **Public tier** (`10.0.1.0/24`) — inbound/outbound edge routing
- **Private application tier** (`10.0.2.0/24`) — container hosting, `ap-south-1a`
- **Private database tier** (`10.0.3.0/24`) — fully isolated, `ap-south-1b`

External connectivity is handled by a dedicated Internet Gateway, linked via a public route table associated only with the public subnet.

To validate routing, a `t3.micro` EC2 bastion host (Amazon Linux 2023) was provisioned at the perimeter. Access was verified over SSH from PowerShell using `.pem` file permissions restricted with `icacls.exe`. `ping` and `traceroute google.com`, run from the instance shell, returned 0% packet loss, confirming the route tables before the layout was finalized in Terraform.

---

## Day 2: Subnet Isolation and Networking Port Diagnostics

### Why the Database Resides in a Private Subnet

Placing the database tier in a private subnet applies the principles of least privilege and defense-in-depth:

- **No public attack surface** — the private subnet has no Internet Gateway route, and its resources use private IPs (`10.0.3.0/24`), making the database unreachable from the internet.
- **Granular network control** — the database security group (`Legacylens-DB-SG`) rejects all inbound traffic except from the private application subnet (`10.0.2.0/24`) on PostgreSQL's port `5432`.
- **Contained blast radius** — if a public-facing component (bastion host, ingress proxy) is compromised, an attacker still cannot reach the data layer directly; they would need to pivot through the internal application tier.

### Port-Binding Diagnostics via `ss -tulpn`

`ss -tulpn` (socket statistics) was used to inspect how the OS manages network sockets.

**Flags used:**
- `-t` — TCP stream sockets
- `-u` — UDP datagram sockets
- `-l` — sockets in the LISTEN state only
- `-p` — process name and PID
- `-n` — numeric ports and addresses

**Output on the Ubuntu bastion host:**
1. `tcp LISTEN 0 4096 *:22 *:*` — `sshd` listening on port `22` across all interfaces.
2. `udp UNCONN 0 0 127.0.0.53%lo:53 0.0.0.0:*` — `systemd-resolved` bound to the loopback interface only, not reachable externally.

### Outbound Data Egress (NAT Gateway Pipeline)

To allow the private application tier to reach package repositories and external APIs without accepting inbound connections, outbound traffic is routed through a NAT Gateway in the public subnet:

```text
                      [ Internet ]
                           ^
                           | (Outbound Response)
                   [ Internet Gateway ]
                           ^
                           |
            [ Public Subnet (10.0.1.0/24) ]
              Hosts: [ NAT Gateway (Elastic IP) ]
                           ^
                           | (Route: 0.0.0.0/0 -> NAT Gateway)
          [ Private App Subnet (10.0.2.0/24) ]
              Hosts: [ Node.js App Server ]
```

---

## Day 3: EC2 Compute Provisioning & Asymmetric Key Cryptography

### Objective

Provision EC2 compute via Terraform and configure asymmetric-key access, connecting the Day 2 network layout to the bastion access model built on Day 4.

### Implementation

- **Compute deployment** — `aws_instance` blocks provision `t3.micro` nodes on Ubuntu 22.04 LTS AMIs for a standardized backend runtime.
- **Key management** — generated local RSA 4096-bit key pairs (`.pem` / `.pub`) and injected the public key into instance metadata via the `aws_key_pair` Terraform resource.
- **State management** — confirmed Terraform tracks the deployed EC2 resources accurately, supporting clean updates and teardowns with no orphaned resources in `ap-south-1`.

---

## Day 4: Stateful Firewalls, Bastion Architecture, and Security Group Correlation

### Objective

Separate public access points from private core resources and configure security group dependencies so the backend infrastructure stays unreachable from external scans while remaining manageable by administrators.

### Core Concepts

- **Bastion host** — a hardened instance in the public subnet, used as the single controlled entry point for administrative access.
- **Security group** — a stateful, host-level firewall attached to individual resources.
- **Stateful routing** — inbound connections are tracked automatically, so response traffic is permitted without explicit outbound rules.

### Security Group Referencing

Rather than allow-listing IP ranges (which can change or be spoofed), the private application security group is configured to accept traffic only from resources attached to the bastion security group (`security_groups = [aws_security_group.bastion_sg.id]`).

This has two practical effects:
- If the bastion host's internal IP changes, access still works — the rule is tied to the security group ID, not the IP.
- Any traffic reaching the private application tier without that security group attached is dropped at the edge.

### Verification

- A direct connection attempt from an external network to the private application instance (`10.0.2.112`) returned `Connection refused`, confirming isolation.
- Forwarding local `ssh-agent` credentials through the bastion succeeded, confirming the intended access path works.
- The `w` command, run inside the private instance, confirmed the active session originated from the bastion's internal IP (`10.0.1.x`).

---

## Day 5: Production Managed Databases & Multi-AZ Network Group Isolation

Provisioned a production-ready, isolated AWS RDS PostgreSQL instance via Terraform.

**Key configuration parameters:**
- `allocated_storage = 20` — 20 GB General Purpose SSD storage
- `engine = "postgres"`, `engine_version = "16.1"` — PostgreSQL 16.1
- `instance_class = "db.t4g.micro"` — ARM Graviton-based instance for better price-to-performance than comparable x86 instances
- `db_subnet_group_name` — restricts deployment to the private multi-AZ subnets (`ap-south-1a`, `ap-south-1b`)
- `vpc_security_group_ids` — allows connections only on TCP port `5432` from the application server's security group
- `skip_final_snapshot = true` — speeds up iteration during sandbox testing

---

## Day 6: Infrastructure Deployment & Inside-VPC Database Handshake Verification

**Work completed:**
- Ran `terraform apply` to deploy the managed Multi-AZ PostgreSQL 16 database across the isolated subnets.
- Used SSH jump-host tunneling through the public bastion (`35.154.59.9`) to reach the private application instance (`10.0.2.128`).
- Updated the package index and installed database client tooling:

```bash
sudo apt-get update -y
sudo apt-get install postgresql-client -y

psql -h terraform-044b39d4f87acf5e351c17466b.cfew2m0cwv6o.ap-south-1.rds.amazonaws.com -U db_admin_user -d legacylens_prod
```

---

## Day 7: Node.js Environment Isolation & Database Socket Verification

**Work completed:**
- Installed Node Version Manager (NVM) and provisioned Node.js v22.23.1 (LTS) with npm on the private application server (`10.0.2.105`).
- Created the `~/legacylens-core` workspace and installed the `pg` (node-postgres) driver and `dotenv` for secrets isolation.
- Configured a `.env` file to hold database host, credentials, and connection parameters outside application code.
- Wrote `db-test.js` to run an asynchronous pooled connection to the RDS cluster and validate query execution (`SELECT NOW()`) over TLS.

**Notes:**
- Keeping secrets in `.env`, loaded into `process.env` at runtime via `dotenv`, keeps credentials out of version control.
- The `pg` driver uses Node's event loop to manage database sockets asynchronously, without blocking concurrent HTTP requests.

---

## Day 8: Multi-Tenant Schema Isolation & Dynamic Search Path

**Work completed:**
- Wrote `day8_multitenant.sql` to create two schemas (`tenant_alpha`, `tenant_beta`) inside the shared RDS database.
- Provisioned `assets` tables, primary keys, indexes (`idx_alpha_asset_name`, `idx_beta_asset_name`), and seed data within each tenant namespace.
- Wrote `index.js` using `pg.Pool`, issuing a session-level `SET search_path TO <tenant_schema>` before each query.

**Notes:**
- Schema-based multi-tenancy balances resource cost against logical data isolation, without requiring separate database instances per tenant.
- Setting `search_path` per connection checkout means standard queries (`SELECT * FROM assets`) automatically target the correct tenant's data.

---

## Day 9: Private Database Isolation & Multi-Tenant Schema Configuration

### Objective

Secure the PostgreSQL database within a private VPC subnet, establish zero-trust access via an EC2 bastion using AWS Systems Manager (SSM), and implement a multi-tenant schema for client data isolation.

### Tech Stack

Compute: EC2 (Ubuntu bastion), SSM · Database: RDS (PostgreSQL 16) · Networking: VPC private subnets, security groups · IaC: Terraform · Tools: `psql`, AWS CLI, Bash/PowerShell

### Architecture & Security

- **Zero-trust access** — no public IPs or open port 22; all administrative database access goes through SSM Session Manager.
- **Private subnet isolation** — the RDS instance is deployed only in private subnets and is not reachable from the internet.
- **Security group chaining** — the database security group drops all connections except whitelisted internal VPC traffic on port `5432`.
- **Multi-tenant schema design** — isolated schemas (`tenant_alpha`, `tenant_beta`) with dynamic `search_path` routing separate tenant data within a single database instance.

### Troubleshooting

- Diagnosed a connection timeout caused by a missing inbound rule on the RDS security group; added a rule allowing internal `10.0.0.0/16` traffic.
- Worked around a local tunnel authentication failure by switching to direct bastion access to authenticate `db_admin_user`.
- Ran `SELECT count(*) FROM pg_stat_activity;` to monitor connection pool health and check for exhaustion.

---

## Day 10: Linux Network Diagnostics & Automated Database Migrations

### Objective

Run internal VPC network diagnostics with native Linux tools, and deploy an idempotent, multi-tenant database migration script to RDS via the EC2 bastion.

### Tech Stack

Compute/OS: EC2, Ubuntu · Database: PostgreSQL 16 (RDS) · Networking: `ss`, `iproute2`, netcat · VCS: Git, GitHub · Scripting: SQL, Bash

### Technical Execution

**1. Linux network auditing**
- `ss -tulpn` — confirmed SSH and SSM agents were running and no unexpected database services were listening locally.
- `ip route show` — confirmed traffic routes through the VPC's implicit router (`10.0.1.1`).
- `nc -zv 127.0.0.1 5432` — a `Connection refused` result confirmed the database is not running locally and is fully decoupled onto its own RDS instance.

**2. Idempotent multi-tenant migrations**

Moved from manual SQL to an automated migration script (`day10_schema_migration.sql`):
- Wrapped execution in `BEGIN;` / `COMMIT;` to avoid a partially applied migration on failure.
- Used `IF NOT EXISTS` clauses for schema and table creation so the script can be re-run safely.
- Kept `tenant_alpha` and `tenant_beta` strictly separated within the shared RDS instance.

### Takeaways

- Database migrations should follow the same idempotent, declarative-state principle as Terraform.
- Confirming a port is closed on the bastion is as important as confirming it's open on the target database.

---

## Day 11: Repository Security, AWS Storage Audits & Database Optimization

### Objective

Secure the version control workflow, run Linux storage diagnostics on EC2, and deploy performance optimizations to the PostgreSQL layer.

### Execution

**1. Version control security**
- Validated `.gitignore` coverage to keep `.env`, `terraform.tfstate`, and `node_modules` out of source control.
- Used `git status` and `git check-ignore` to confirm repository hygiene before committing.

**2. AWS zero-trust access & storage auditing**
- Used SSM Session Manager instead of SSH (port 22) to access the private EC2 instance.
- Ran `lsblk -f`, `df -hT`, and `findmnt` to map block devices.
- Confirmed EBS root volumes attach as NVMe block devices under the Nitro system, mounted as `ext4`.

**3. PostgreSQL operations**
- Modified `pg_hba.conf` to resolve a local client connection block, temporarily relaxing SSL/password constraints for a direct local connection via PowerShell.
- Provisioned the `legacylens_db` database and deployed the Day 10 multi-tenant schemas.
- Ran `day11_index_tuning.sql` to add composite B-tree indexes (`created_at DESC, customer_name`) across tenant partitions, avoiding full sequential scans as data grows.

### Insights

`EXPLAIN ANALYZE` returned a sequential scan instead of an index scan after the new indexes were added — expected behavior, since the tables were empty and reading zero rows directly is cheaper than traversing an index tree.

### Tech Stack

VCS: Git, GitHub · Cloud: EC2, EBS, SSM · OS/Scripting: PowerShell, Ubuntu 22.04 · Database: PostgreSQL

---

## Day 12: Database Concurrency Diagnostics & AWS Network Refactoring

### Objective

Build diagnostic tooling for PostgreSQL deadlocks in production, and refactor a monolithic Terraform configuration into a modular multi-tier VPC setup.

### Execution

**1. Concurrency management**
- Wrote `day12_lock_diagnostics.sql`, joining `pg_catalog.pg_locks` and `pg_stat_activity` to identify blocked queries and lock-holding PIDs.
- Established a process for resolving contention using `pg_cancel_backend` and `pg_terminate_backend` without requiring a server restart.

**2. IaC refactoring**
- Split a monolithic `main.tf` into a dedicated networking file (`vpc.tf`) and a compute/security file (`main.tf`) to avoid resource conflicts and improve maintainability.
- Deployed a highly available network layout with a public subnet (IGW + NAT Gateway) and multiple isolated private subnets for application and database tiers.

**3. Linux network diagnostics**
- Accessed the private EC2 application server via SSM Session Manager (no public SSH port).
- Verified outbound NAT Gateway routing with `curl` and mapped hops with `traceroute`.
- Used `nc` to confirm least-privilege access between the application and database tiers over port `5432`.

### Tech Stack

Cloud: VPC, EC2, NAT Gateway, IGW, SSM, RDS · IaC: Terraform (HCL) · Database: PostgreSQL · OS/Networking: Ubuntu 22.04, PowerShell

---

## Day 13: Application Layer Deployment & Secure Database Driver Integration

### Objective

Provision the Node.js runtime on the private EC2 instance, configure environment-based secrets, and validate end-to-end multi-tenant connectivity to RDS.

### Execution

**1. Private compute & runtime provisioning**
- Connected to the private application server (`Legacylens-Private-App-Server`) via SSM Session Manager.
- Used `nvm` to install and pin the Node.js runtime and npm.

**2. Application layer & secrets**
- Set up the `~/legacylens-core` workspace.
- Installed `pg` for the asynchronous database driver and `dotenv` for runtime configuration.
- Stored RDS endpoint, port, and credentials in a local `.env` file, outside application source code.

**3. Connection audit**
- Used `pg.Pool` to manage connection lifecycles without blocking the event loop or exceeding RDS's `max_connections` limit.
- Verified connectivity with parameterized queries (`SELECT NOW()`, `SHOW search_path;`) over TLS to the multi-AZ RDS instance.

### Takeaways

- Loading credentials from `.env` at runtime keeps them out of git entirely.
- Connection pooling (`pg.Pool`) lets high-concurrency Node event loops reuse database sockets efficiently, protecting RDS from connection exhaustion during traffic spikes.

### Tech Stack

Cloud: VPC, private subnets, EC2, SSM, RDS PostgreSQL · Runtime: Node.js, npm, `pg`, `dotenv` · OS: Ubuntu 22.04, Bash · VCS: Git, GitHub

---

## Day 14: Multi-VPC Transit Gateway (TGW) Architecture Refactoring

### Objective

Move beyond a single-VPC topology by provisioning a centralized Transit Gateway (`tgw.tf`), establishing a hub-and-spoke design that can later connect staging and shared-services networks to production.

### Execution

- Deployed `aws_ec2_transit_gateway` as a central router, enabling route propagation and centralized DNS support across attachments.
- Attached the LegacyLens production VPC (`10.0.0.0/16`) to the TGW hub, bridging the `private_app` and `private_db` subnets.
- Resolved a Terraform state mismatch by refactoring target IDs, routing `10.0.0.0/8` traffic from `private_route_table` to the TGW.

### Takeaways

Point-to-point VPC peering becomes an unmanageable mesh as the number of VPCs grows. A Transit Gateway centralizes routing, reducing the administrative overhead of adding new environments or on-premises connections.

---

## Day 15: Hybrid Cloud Connectivity via Site-to-Site IPsec VPN

### Objective

Establish an encrypted IPsec tunnel between the AWS VPC and a simulated on-premises router, using Terraform (`vpn.tf`).

### Execution

- Provisioned `aws_customer_gateway` with a static public IP (`203.0.113.12`) to represent the remote router.
- Deployed `aws_vpn_gateway` (VGW), attached to the LegacyLens VPC to terminate the tunnel and handle decapsulation.
- Enabled `aws_vpn_gateway_route_propagation` on `private_route_table` so BGP routes from the VPN tunnel propagate into the private application subnets.

### Takeaways

EC2 instances never handle VPN encryption directly — that work happens at the VPC border on the Virtual Private Gateway, so application servers process plaintext traffic without additional CPU overhead.

---

## Day 16: Encrypted Payload Diagnostics & PostgreSQL Row-Level Security (RLS)

### Objective

Confirm active VPN encryption using Linux packet capture tools, and implement PostgreSQL Row-Level Security (RLS) for multi-tenant data isolation.

### Execution

**1. Linux kernel network auditing**
- `ip link show` — identified the active Nitro network interface (`ens5`) on the private application server.
- `ip xfrm state` / `ip xfrm policy` — confirmed XFRM state is empty on the application node, since IPsec encryption is offloaded to the AWS VGW.
- `sudo tcpdump -i ens5 -n "proto 50"` — captured ESP traffic, confirming data crosses the tunnel as ciphertext.

**2. PostgreSQL Row-Level Security**
- Resolved a `certificate verify failed` error by setting `sslmode=require` via `PGSSLMODE`, forcing encryption without relying on the local `.pem` trust store.
- Ran `ALTER TABLE orders ENABLE ROW LEVEL SECURITY;` on the production `legacylens_prod` database.
- Deployed a policy tying data access to the active session variable `app.current_tenant_id`:

```sql
CREATE POLICY tenant_isolation_policy ON orders
    FOR ALL
    USING (tenant_id = current_setting('app.current_tenant_id', true));
```

### Takeaways

Pushing multi-tenant access control down into PostgreSQL means the database enforces isolation independently of the application layer. Even if a Node.js query is missing a `WHERE` clause, RLS restricts results to rows matching the active `tenant_id`, preventing cross-tenant data exposure.

---

## Day 17: Application Containerization & Artifact Registry

### Objective

Package the LegacyLens Node.js application into a Docker container and host it in an AWS Elastic Container Registry (ECR) repository.

### Execution

- Wrote a multi-stage `Dockerfile` on a `node:22-alpine` base image, separating `npm install` from the runtime stage to reduce image size and attack surface.
- Provisioned `aws_ecr_repository` via Terraform as the private image registry.
- Authenticated the local Docker daemon with short-lived tokens (`aws ecr get-login-password`) and pushed the `v1.0.0` image.

### Takeaways

Containerization guarantees the runtime, OS dependencies, and application code tested locally match what runs in production.

---

## Day 18: Connection Pooling (PgBouncer) & OS-Level Process Hardening

### Objective

Optimize database connection handling for concurrent workloads using PgBouncer, and constrain local process resource usage with systemd.

### Execution

- Deployed PgBouncer in transaction pooling mode, multiplexing many Node.js client connections across a small, fixed pool of RDS connections.
- Replaced the process manager (PM2) with a native systemd service unit (`legacylens.service`).
- Set `cgroups v2` resource limits (`MemoryMax=512M`, `CPUQuota=50%`) and `ProtectSystem=full` in the unit file, capping resource usage during a memory leak or traffic spike.

---

## Day 19: Serverless Container Orchestration (AWS ECS Fargate)

### Objective

Move the compute layer from manually managed EC2 instances to a managed ECS cluster on AWS Fargate.

### Execution

- Provisioned an ECS cluster and `aws_ecs_task_definition` targeting Fargate, referencing the ECR image URI and loading environment variables from Systems Manager Parameter Store.
- Attached an ECS task execution role scoped to pulling the ECR image and writing logs to CloudWatch.
- Deployed the ECS service into the private application subnets (`10.0.2.0/24`), offloading OS patching and server maintenance to AWS.

---

## Day 20: Application Load Balancing (ALB) & Webhook Ingress

### Objective

Expose the private ECS containers to the internet to receive WhatsApp webhook traffic, without exposing the containers directly.

### Execution

- Deployed an Application Load Balancer (`aws_lb`) in the public subnets, attached to a security group allowing inbound HTTP/HTTPS.
- Configured `aws_lb_target_group` to route to the ECS Fargate task IPs, with a health check on `/health` so the ALB only routes to healthy containers.
- Attached an ACM TLS certificate to the ALB to encrypt webhook payloads in transit and offload TLS termination from the application.

---

## Day 21: Continuous Integration & Continuous Deployment (CI/CD)

### Objective

Automate the deployment lifecycle so new code is tested, built, and deployed to the ECS cluster on every commit.

### Execution

- Replaced long-lived IAM access keys with GitHub OIDC, allowing GitHub Actions to request short-lived deployment credentials from AWS STS.
- Wrote a GitHub Actions workflow triggered on pushes to `main`.
- The workflow checks out the code, builds the Docker image, authenticates with AWS, pushes to ECR, and runs `aws ecs update-service --force-new-deployment` for a zero-downtime rolling update.

---

## Day 22: Cloud Observability, Logging & Alerting

### Objective

Establish centralized observability across the architecture for faster detection and resolution of production issues.

### Execution

- Configured the `awslogs` log driver in the ECS task definition to stream stdout/stderr into a CloudWatch Log Group.
- Enabled VPC Flow Logs to capture network interface traffic, stored in S3 for security auditing.
- Provisioned `aws_cloudwatch_metric_alarm` resources, including an alarm that triggers an SNS email notification if the ALB's HTTP 5XX error rate rises over a 5-minute window.

### Takeaways

Automated alerting shifts incident detection from reactive (a client reporting an outage) to proactive (CloudWatch and SNS notifying the engineering team directly).
