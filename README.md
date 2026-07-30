# LegacyLens Core Infrastructure - 16-Day AWS & DevOps Engineering Log

This repository documents the production-grade deployment of the **LegacyLens** cloud architecture using Infrastructure as Code (IaC) with Terraform, Linux system auditing, PostgreSQL database engineering, and security-first network design in the `ap-south-1` (Mumbai) region.

---

## Day 1: Infrastructure as Code (IaC) Foundation

Today, I transitioned the core network architecture for the LegacyLens project from a manual AWS Web Console deployment into a repeatable, automated Infrastructure as Code (IaC) configuration using Terraform. This foundation establishes a secure, multi-tier cloud environment optimized for scalable container and database components, deployed directly within the `ap-south-1` (Mumbai) region.

The core infrastructure centers around a custom Virtual Private Cloud named `Legacylens-VPC` with a `10.0.0.0/16` CIDR block. To guarantee strict boundary isolation, the space is segmented into three distinct subnets: a public tier (`10.0.1.0/24`) providing inbound/outbound edge routing, a private application tier (`10.0.2.0/24`) allocated for container hosting in availability zone `ap-south-1a`, and a completely isolated private database tier (`10.0.3.0/24`) mapped to `ap-south-1b`. External internet connectivity is mediated through a dedicated Internet Gateway linked via a public route table associated exclusively with the public subnet.

To validate routing compliance, I provisioned an external-facing `t3.micro` EC2 Bastion host running Amazon Linux 2023 inside the perimeter. Verification was successfully completed via native PowerShell SSH sessions using locked-down `.pem` file permissions via Windows Access Control Lists (`icacls.exe`). Diagnostic verification commands—including `ping` and `traceroute google.com` executed directly from the cloud instance shell—confirmed 0% packet loss and clean ICMP edge transit, validating the underlying VPC route tables before sealing the layout permanently in the final declarative configuration.

---

## Day 2: Subnet Isolation and Networking Port Diagnostics

### Why a Database Must Reside in a Private Subnet
In a production-ready cloud architecture, the database tier represents the critical state engine of the entire system. Placing the database inside a private subnet is a fundamental application of the **Principle of Least Privilege** and the **Defense-in-Depth** security model for several critical reasons:

* **Elimination of Public Attack Surface:** A private subnet does not possess an attached Internet Gateway (IGW) route handler, and resources within it are assigned private IP addresses (`10.0.3.0/24`). This renders the database completely invisible and unreachable from the public internet, preventing automated brute-force attempts and network-level scans.
* **Granular Network Control:** Traffic entering the private database tier is strictly restricted using AWS Stateful Firewalls (Security Groups). In this setup, the database (`Legacylens-DB-SG`) rejects all incoming requests unless they explicitly originate from the Private Application Subnet (`10.0.2.0/24`) over the designated PostgreSQL port (`5432`). 
* **Controlled Isolation:** Even if a public-facing component (like the Bastion host or an ingress proxy) is compromised, an attacker cannot route directly into the data layer without pivoting horizontally through hardened internal application checkpoints.

### Port-Binding Diagnostics via `ss -tulpn`
To verify how the operating system manages network sockets inside our secure environment, we used the modern kernel utility `ss -tulpn` (Socket Statistics).

#### Understanding the Diagnostic Flags
* **`-t`**: Filters for TCP stream sockets (reliable connection-oriented traffic).
* **`-u`**: Filters for UDP datagram sockets (fast connectionless traffic).
* **`-l`**: Restricts the display to sockets currently in the LISTEN state.
* **`-p`**: Extracts the specific internal Process Name and Process ID (PID).
* **`-n`**: Forces raw Numeric ports and addresses to display.

#### Live Output Breakdown & Core Takeaways
Running this on our active Ubuntu Bastion Host revealed the following structural mappings:
1. **`tcp LISTEN 0 4096 *:22 *:*`**: The SSH daemon (`sshd`) is listening globally on port `22` across all network interfaces (`*`).
2. **`udp UNCONN 0 0 127.0.0.53%lo:53 0.0.0.0:*`**: The system local caching DNS resolver (`systemd-resolved`) is bound strictly to the loopback interface (`lo`), completely hidden from outside network interface cards.

### Outbound Data Egress Lifecycle (The NAT Gateway Pipeline)
To protect our internal computing tier while maintaining the ability to pull package updates and connect to external APIs, we engineered a unidirectional outbound traffic system:

```text
                      [ Internet ]
                           ^
                           | (Outbound Response)
                   [ Internet Gateway ]
                           ^
                           |
            [ Public Subnet (10.0.1.0/24) ] 
             👉 Hosts: [ NAT Gateway (with Elastic IP) ]
                           ^
                           | (Route: 0.0.0.0/0 -> NAT Gateway)
          [ Private App Subnet (10.0.2.0/24) ]
             👉 Hosts: [ Node.js App Server ]
```

---

## Day 3: EC2 Compute Provisioning & Asymmetric Key Cryptography

### 🎯 Architectural Objective
Bridge the physical VPC networking layout from Day 2 with the robust Bastion security models required for Day 4 by correctly provisioning EC2 compute resources via Terraform and configuring asymmetric cryptography for secure access.

### 🛠️ Technical Execution
* **Declarative Compute Deployment:** Authored Terraform `aws_instance` blocks to provision `t3.micro` EC2 compute nodes. Selected specific Amazon Machine Images (AMIs) aligned with Ubuntu 22.04 LTS to ensure a standardized Linux runtime for backend workloads.
* **Cryptographic Key Management:** Generated local RSA 4096-bit key pairs (`.pem` / `.pub`) and utilized the `aws_key_pair` Terraform resource to inject the public key into the AWS hypervisor instance metadata.
* **Idempotent State Management:** Verified that Terraform tracks the exact state of deployed EC2 compute units, allowing seamless updates and teardowns without leaving orphaned resources in `ap-south-1`.

---

## Day 4: Stateful Firewalls, Bastion Architecture, and Security Group Correlation

### 🎯 Architectural Objective
Implementing a multi-layered **Chain of Trust** security framework. By separating public access controllers from private core resources and configuring advanced firewall dependencies, we ensured that our multi-tenant backend infrastructure remains completely hidden from external network sweeps while maintaining smooth administrative manageability.

### 📚 Core Conceptual Framework
* **Bastion Host:** A highly hardened virtual machine deployed explicitly in the public entry network serving as the single, tightly monitored digital checkpoint for network management.
* **Security Group:** A dynamic, host-level stateful firewall wrapping individual cloud resources.
* **Stateful Routing:** A smart security feature where the firewall automatically tracks inbound connections and opens response paths automatically without manual outbound rule clutter.

### 🔒 The Power of Security Group Nesting
Instead of hardcoding easily spoofed IP ranges, we implemented **Security Group Nesting**. We configured the private application firewall to accept incoming traffic **only if it originates from a resource wearing the specific Bastion Security Group Badge (`security_groups = [aws_security_group.bastion_sg.id]`)**.

#### Why this is highly secure:
1. **Dynamic Resiliency:** If the Bastion Host's internal IP changes, the backend vault doesn't break—the network tracks the identity badge, not the IP address.
2. **Absolute External Rejection:** Any data packet sent to the private application tier is dropped at the edge unless it carries the verified tracking token of our public guard.

### 🧪 System Audits & Diagnostic Telemetry
1. **Direct Internet Attack (Blocked):** Attempting to bridge straight from a home network to the vault console (`10.0.2.112`) returned an immediate `Connection refused`.
2. **Chain of Trust Jump (Passed):** Leveraging local `ssh-agent` keys to securely forward credential signatures through the Bastion proxy allowed immediate vault entry.
3. **Session Verification (`w`):** Live telemetry inside the vault verified the source profile originated strictly from the Bastion internal identity (`10.0.1.x`).

---

## Day 5: Production Managed Databases & Multi-AZ Network Group Isolation

Today, I expanded the LegacyLens infrastructure by provisioning a production-ready, fully isolated **AWS RDS PostgreSQL Engine** using declarative Terraform blocks. 

### Core Parameter Breakdown & Operational Engineering Value:
* `allocated_storage = 20`: Allocates a 20 GB General Purpose SSD storage tier.
* `engine = "postgres"` & `engine_version = "16.1"`: Installs a clean PostgreSQL 16.1 distribution.
* `instance_class = "db.t4g.micro"`: Leverages an ARM-based AWS Graviton4-optimized micro-instance, delivering superior price-to-performance scaling compared to older x86 instances.
* `db_subnet_group_name`: **The primary isolation anchor.** Restricts database deployment strictly to multi-AZ private subnets across `ap-south-1a` and `ap-south-1b`.
* `vpc_security_group_ids`: Enforces microsegmentation boundaries. Rejects all network connection handshakes unless they originate strictly over TCP Port 5432 from the private application server's security profile.
* `skip_final_snapshot = true`: Developer-velocity optimization to allow fast iteration during sandbox testing.

---

## Day 6: Infrastructure Deployment & Secure Inside-VPC Database Handshake Verification

### 🛠️ Tasks Executed
1. **Live RDS Provisioning:** Executed `terraform apply` to deploy a managed Multi-AZ PostgreSQL 16 relational database tier across isolated subnets.
2. **Jump Host Tunnel Routing:** Leveraged local SSH Jump tunneling via the public Bastion host gate (`35.154.59.9`) to securely bridge access into the private application instance environment (`10.0.2.128`).
3. **Linux Node Patching & Tooling Deployment:** Updated the internal Linux package manager index and installed native database utilities:

```bash
sudo apt-get update -y
sudo apt-get install postgresql-client -y

psql -h terraform-044b39d4f87acf5e351c17466b.cfew2m0cwv6o.ap-south-1.rds.amazonaws.com -U db_admin_user -d legacylens_prod
```

---

## Day 7: Programmatic Node.js Environment Isolation & Database Socket Verification

### 🛠️ Tasks Executed
1. **Runtime Provisioning via NVM:** Installed Node Version Manager (NVM) and provisioned Node.js `v22.23.1` (LTS) along with `npm` on the private application server node (`10.0.2.105`).
2. **Project Workspace & Dependency Management:** Created `~/legacylens-core` workspace and installed `pg` (node-postgres) driver and `dotenv` for secret isolation.
3. **Secrets Decoupling:** Configured `.env` file to hold database host endpoints, credentials, and parameters safely outside application code.
4. **Programmatic Socket Handshake:** Authored `db-test.js` to execute an asynchronous pool connection to the RDS Multi-AZ PostgreSQL cluster, validating query execution (`SELECT NOW()`) over TLS.

### 🔒 Security & Architectural Insights
* **Zero Secrets in Version Control:** Decoupling sensitive parameters via `.env` prevents credential exposure in version control. At runtime, `dotenv` loads configuration directly into `process.env` in memory.
* **Non-Blocking Asynchronous I/O & Connection Pooling:** The `pg` driver utilizes Node.js event loops to manage database sockets asynchronously without blocking concurrent HTTP application requests.

---

## Day 8: Multi-Tenant Schema Isolation & Dynamic Search Path Driver

### 🛠️ Tasks Executed
1. **Isolated Schema Creation:** Designed and executed `day8_multitenant.sql` to establish two logical schema boundaries (`tenant_alpha` and `tenant_beta`) inside a shared PostgreSQL RDS database.
2. **Schema-Level Data Segregation:** Provisioned `assets` tables, primary keys, performance indices (`idx_alpha_asset_name`, `idx_beta_asset_name`), and seed records within each independent tenant namespace.
3. **Dynamic Driver Implementation:** Authored `index.js` utilizing `pg.Pool` to execute session-level `SET search_path TO <tenant_schema>` statements before query execution.

### 🔒 Architectural Insights
* **Schema-Based Multi-Tenancy:** Using schema isolation balances resource usage and database cost while providing strict logical data boundaries between different tenants without requiring separate physical database instances.
* **Dynamic Connection Context:** Setting `search_path` per connection checkout allows standard, uniform SQL queries (e.g., `SELECT * FROM assets`) to automatically target the correct tenant's data safely and efficiently.

---

## Day 9: Private Database Isolation & Multi-Tenant Schema Configuration

### 🎯 Objective
Secure the LegacyLens PostgreSQL database within a private AWS VPC subnet, establish zero-trust access using an EC2 Bastion host via AWS Systems Manager (SSM), and implement a multi-tenant database schema for client data isolation.

### 🛠️ Tech Stack & AWS Services
* **Compute:** AWS EC2 (Ubuntu Bastion Host), AWS Systems Manager (SSM)
* **Database:** Amazon RDS (PostgreSQL 16)
* **Networking:** Amazon VPC (Private Subnets), Security Groups
* **Infrastructure as Code:** Terraform
* **Tools:** `psql`, AWS CLI, Bash/PowerShell

### 🏗️ Architecture & Security Highlights
1. **Zero-Trust Access (No SSH):** Eliminated the need for public IP addresses or opening Port 22. All administrative database access is routed securely through an EC2 Bastion host using AWS SSM Session Manager.
2. **Private Subnet Isolation:** Deployed the RDS instance strictly within private subnets. The database is completely invisible to the public internet.
3. **Security Group Chaining:** Configured the database Security Group to drop all connections except explicitly whitelisted internal VPC traffic (port 5432).
4. **Multi-Tenant Schema Design:** Engineered a highly scalable PostgreSQL architecture using isolated schemas (`tenant_alpha`, `tenant_beta`) and dynamic `search_path` routing to securely separate restaurant data within a single database instance.

### 🧪 Troubleshooting & Debugging Realities
* **VPC Firewall Blockages:** Diagnosed a database connection timeout by identifying a missing inbound rule on the RDS Security Group. Successfully modified the SG to allow internal `10.0.0.0/16` traffic.
* **Database Authentication:** Troubleshot and bypassed local tunnel authentication failures, switching to direct Bastion access to successfully authenticate the `db_admin_user`.
* **Connection Monitoring:** Executed administrative SQL queries (`SELECT count(*) FROM pg_stat_activity;`) to monitor connection pool health and prevent exhaustion.

---

## Day 10: Linux Network Diagnostics & Automated Database Migrations

### 🎯 Objective
Perform internal VPC network diagnostics using native Linux tools and deploy an idempotent, multi-tenant database migration script to an AWS RDS PostgreSQL instance via an EC2 Bastion host.

### 🛠️ Tech Stack & Tools
* **Compute / OS:** AWS EC2, Ubuntu Linux
* **Database:** PostgreSQL 16 (Amazon RDS)
* **Networking:** `ss`, `iproute2`, Netcat (`nc`)
* **Version Control:** Git, GitHub
* **Scripting:** SQL, Bash

### 🏗️ Technical Execution

#### 1. Advanced Linux Network Auditing
Instead of relying on GUI tools or AWS console dashboards, I utilized native Linux networking commands from inside the Bastion host to audit the environment:
* **`ss -tulpn`**: Inspected all listening TCP/UDP ports. Verified that SSH and SSM agents were running, while ensuring no rogue database services were running locally.
* **`ip route show`**: Traced the internal IP routing table to confirm traffic was properly routing through the VPC's implicit router (`10.0.1.1`).
* **`nc -zv 127.0.0.1 5432`**: Performed a raw TCP handshake test on the local loopback address. The `Connection refused` response validated the decoupled architecture: the database is strictly isolated on its own RDS instance.

#### 2. Idempotent Multi-Tenant Migrations
Transitioned from manual SQL queries to an automated, production-ready migration script (`day10_schema_migration.sql`):
* **Transactional Safety:** Wrapped the execution in a `BEGIN;` and `COMMIT;` block to ensure the database would not be left in a corrupted state if the script failed halfway through.
* **Idempotency:** Utilized `IF NOT EXISTS` clauses for schema and table creation. This ensures the script can be run multiple times without throwing duplication errors or overwriting existing client data.
* **Data Isolation:** Enforced strict logical separation between `tenant_alpha` and `tenant_beta` within a shared RDS instance, preparing the architecture for a scalable, multi-tenant application.

### 💡 Cloud Architecture Takeaways
* **Infrastructure as Code (IaC) Principles in SQL:** Writing database migrations must follow the same idempotent principles as Terraform—describing the *desired state* rather than just a series of blind commands.
* **Decoupled Architecture:** Proving a port is *closed* on a Bastion server is just as important as proving it is *open* on the target database server.

---

## Day 11: Repository Security, AWS Storage Audits & Database Optimization

### 🎯 Objective
To secure the version control environment, perform live Linux storage diagnostics on AWS EC2 hardware, and deploy multi-tenant performance optimizations to the PostgreSQL database layer.

### 🛠️ Execution & Milestones

#### 1. Version Control Security & Hardening
* **Secret Management:** Validated `.gitignore` configurations using Git CLI to ensure sensitive files (`.env`, `terraform.tfstate`, `node_modules`) are strictly isolated from source control.
* **Audit:** Utilized `git status` and `git check-ignore` to prove repository hygiene and prevent cloud credential leakage before committing to GitHub.

#### 2. AWS Zero-Trust Access & Storage Auditing
* **Secure Access:** Bypassed traditional Port 22 SSH methods by utilizing **AWS Systems Manager (SSM) Session Manager** to establish a secure, zero-trust tunnel into the private Linux EC2 instance.
* **Storage Diagnostics:** Executed Linux subsystem commands (`lsblk -f`, `df -hT`, `findmnt`) to map physical block devices.
* **SAA-C03 Validation:** Verified that AWS Elastic Block Store (EBS) root volumes attach to the Nitro system as high-speed NVMe block devices and mapped active filesystem mounting (`ext4`).

#### 3. PostgreSQL Operations & Deployment
* **Admin Override:** Troubleshot local client connection blocks by modifying the `pg_hba.conf` security file, bypassing enforced SSL and password constraints to establish a direct local connection via PowerShell.
* **Schema Initialization:** Provisioned the `legacylens_db` database and deployed Day 10 multi-tenant architectural schemas.
* **Index Optimization:** Executed `day11_index_tuning.sql` to deploy B-Tree composite indices (`created_at DESC, customer_name`) across multiple tenant partitions, eliminating the risk of expensive full-table sequential scans as the application scales.

### 🧠 Implementation Specialist Insights
During the database optimization deployment, the `EXPLAIN ANALYZE` query planner returned a `Seq Scan` instead of an `Index Scan`. This successfully validated that PostgreSQL's query optimizer is functioning as intended: it intelligently bypassed the new index because the tables were currently empty, calculating that reading zero rows directly from disk requires less computational overhead than traversing an index tree.

### 💻 Tech Stack Utilized
* **Version Control:** Git, GitHub
* **Cloud Infrastructure (AWS):** EC2, EBS, Systems Manager (SSM)
* **OS & Scripting:** Windows PowerShell, Linux (Ubuntu 22.04)
* **Database:** PostgreSQL

---

## Day 12: Database Concurrency Diagnostics & AWS Network Refactoring

### 🎯 Objective
To build advanced PostgreSQL diagnostic tools for handling database deadlocks in production, and to refactor a monolithic AWS Terraform configuration into a modular, enterprise-grade multi-tier VPC architecture.

### 🛠️ Execution & Milestones

#### 1. Database Operations & Concurrency Management
* **Deadlock Detection:** Engineered a targeted SQL diagnostic script (`day12_lock_diagnostics.sql`) joining `pg_catalog.pg_locks` and `pg_stat_activity` to instantly isolate blocked queries and identify rogue lock-holding PIDs.
* **Process Termination Strategy:** Established operational protocols to resolve database traffic jams using surgical termination commands (`pg_cancel_backend` and `pg_terminate_backend`), ensuring maximum uptime without requiring full server reboots.

#### 2. Infrastructure as Code (IaC) Refactoring
* **State Modularity:** Successfully refactored a monolithic `main.tf` file, strictly isolating the network routing layer (`vpc.tf`) from the compute and security layers (`main.tf`) to prevent duplicate resource conflicts and improve maintainability.
* **VPC Provisioning:** Deployed a highly available AWS network boundary featuring a public lobby subnet (with an IGW and NAT Gateway) and multiple isolated private subnets for application servers and multi-AZ database deployments.

#### 3. Linux Network Diagnostics (Zero-Trust)
* **Secure Access:** Tunneled into the private EC2 application server using AWS Systems Manager (SSM) Session Manager, bypassing the need for public SSH ports.
* **Internal Routing Validation:** Verified outbound NAT Gateway routing using `curl` and mapped packet hops using `traceroute`.
* **Security Group Auditing:** Proved Least Privilege access between the application tier and the database tier using `nc` (netcat) to verify open TCP communication on port 5432.

### 💻 Tech Stack Utilized
* **Cloud Infrastructure:** AWS (VPC, EC2, NAT Gateway, IGW, SSM, RDS)
* **Infrastructure as Code:** Terraform (HCL)
* **Database:** PostgreSQL (pg_catalog administration)
* **OS & Networking:** Linux (Ubuntu 22.04), Windows PowerShell

---

## Day 13: Application Layer Deployment & Secure Database Driver Integration

### 🎯 Objective
To bridge the underlying network infrastructure with the active application tier by provisioning the Node.js runtime environment on the private EC2 instance, configuring environment-based secret isolation, and validating end-to-end multi-tenant database connectivity to the RDS PostgreSQL cluster.

### 🛠️ Execution & Milestones

#### 1. Private Compute Node & Runtime Provisioning
* **Zero-Trust Access:** Tunneled into the private application server (`Legacylens-Private-App-Server`) using **AWS Systems Manager (SSM) Session Manager**, maintaining a zero-public-IP perimeter.
* **Runtime Standardization:** Provisioned Node Version Manager (`nvm`) to deploy and lock the Node.js runtime and `npm` package manager on the Ubuntu environment.

#### 2. Application Layer & Secret Decoupling
* **Workspace Initialization:** Configured the `~/legacylens-core` application workspace directory.
* **Dependency Management:** Installed production dependencies including `pg` (node-postgres) for non-blocking asynchronous database driver interactions and `dotenv` for runtime configuration loading.
* **Secrets Isolation:** Authored a local `.env` configuration file to safely store sensitive RDS endpoint targets, port mappings, and database credentials outside of application source code.

#### 3. Programmatic Socket & Pool Connection Audit
* **Asynchronous Connection Pooling:** Executed driver scripts utilizing `pg.Pool` to manage database connection lifecycles without blocking the event loop or exhausting RDS `max_connections` allocation limits.
* **TLS-Secured Query Execution:** Successfully verified end-to-end database connectivity by executing parameterized SQL queries (`SELECT NOW()`, `SHOW search_path;`) from the private application server over an encrypted TLS channel to the multi-AZ RDS database.

### 🧠 Implementation Specialist Takeaways
* **Secrets Hygiene:** Keeping credentials in decoupled `.env` files loaded dynamically into `process.env` at runtime guarantees that no database credentials ever enter git source control.
* **Resource Optimization:** Utilizing connection pooling (`pg.Pool`) ensures that high-concurrency Node.js event loops reuse database sockets efficiently, protecting the RDS engine from running out of available connection slots during traffic spikes.

### 💻 Tech Stack Utilized
* **Cloud Infrastructure:** AWS (VPC, Private Subnets, EC2, SSM, RDS PostgreSQL)
* **Runtime & Drivers:** Node.js, `npm`, `pg` (node-postgres), `dotenv`
* **OS & Tools:** Linux (Ubuntu 22.04), Bash
* **Version Control:** Git, GitHub

---

## Day 14: Multi-VPC Transit Gateway (TGW) Architecture Refactoring

### 🎯 Objective
To elevate the network topology beyond a single VPC by provisioning a centralized AWS Transit Gateway (`tgw.tf`), establishing a hub-and-spoke routing architecture capable of securely bridging the Legacylens production environment with future staging and shared-services networks.

### 🛠️ Execution & Milestones
* **TGW Provisioning:** Deployed `aws_ec2_transit_gateway` as a centralized network router, enabling dynamic route propagation and centralized DNS support across attachments.
* **VPC Attachment Strategy:** Attached the Legacylens Production VPC (`10.0.0.0/16`) to the Transit Gateway hub, explicitly bridging the isolated `private_app` and `private_db` subnets.
* **Terraform Route Table Repair:** Resolved Terraform state mismatch errors by refactoring target IDs, successfully routing `10.0.0.0/8` traffic from `private_route_table` directly to the central TGW.

### 🧠 Implementation Specialist Takeaways
* Point-to-point VPC peering creates an unmanageable mesh at scale. A Transit Gateway acts as a central corporate router, significantly reducing administrative overhead when adding new environments or on-premises connections.

---

## Day 15: Hybrid Cloud Connectivity via Site-to-Site IPsec VPN

### 🎯 Objective
To establish a highly secure, encrypted IPsec tunnel bridging the AWS private cloud architecture with a simulated on-premises corporate router using declarative Terraform (`vpn.tf`).

### 🛠️ Execution & Milestones
* **Hardware Simulation:** Provisioned an `aws_customer_gateway` with a static public IP (`203.0.113.12`) to represent the remote corporate data center's border router.
* **AWS VPN Termination:** Deployed an `aws_vpn_gateway` (VGW) and attached it directly to the Legacylens VPC to handle internal cryptographic termination and packet un-encapsulation.
* **BGP Route Propagation:** Activated `aws_vpn_gateway_route_propagation` on the `private_route_table` to allow the VPN tunnel to dynamically inject Border Gateway Protocol (BGP) routes directly into the private application subnets.

### 🧠 Implementation Specialist Takeaways
* EC2 instances never handle VPN encryption payloads themselves. The heavy cryptographic lifting is entirely managed at the VPC border by the Virtual Private Gateway (VGW), allowing application servers to process plain-text traffic seamlessly without CPU overhead.

---

## Day 16: Encrypted Payload Diagnostics & PostgreSQL Row-Level Security (RLS)

### 🎯 Objective
To prove active VPN network encryption using Linux kernel packet sniffers, and to implement enterprise-grade Defense-in-Depth at the database layer using PostgreSQL Row-Level Security (RLS) for multi-tenant data isolation.

### 🛠️ Execution & Milestones

#### 1. Linux Kernel Network Auditing
* **Interface Mapping:** Utilized `ip link show` to identify the active AWS Nitro network interface (`ens5`) on the private application server.
* **State Analysis:** Audited the `ip xfrm state` and `ip xfrm policy` tables. Verified that XFRM states are empty on the application node because IPsec encryption is correctly offloaded to the AWS VGW.
* **Packet Capture:** Deployed `sudo tcpdump -i ens5 -n "proto 50"` to capture active Encapsulating Security Payload (ESP) traffic, mathematically proving that data traverses the virtual tunnel as encrypted ciphertext.

#### 2. PostgreSQL Row-Level Security (RLS) Implementation
* **TLS Certificate Bypass:** Resolved strict SSL root certificate verification blocks (`certificateverify failed`) by passing `sslmode=require` via environment variables (`PGSSLMODE`), forcing encryption while bypassing local `.pem` trust store hurdles.
* **Database Lockdown:** Executed `ALTER TABLE orders ENABLE ROW LEVEL SECURITY;` directly in the production `legacylens_prod` database.
* **Tenant Isolation Policy:** Deployed a dynamic security policy tying data access directly to the active session variable (`app.current_tenant_id`). 

```sql
CREATE POLICY tenant_isolation_policy ON orders
    FOR ALL
    USING (tenant_id = current_setting('app.current_tenant_id', true));
```

### 🧠 Implementation Specialist Takeaways
* **Defense-in-Depth:** By pushing multi-tenant security logic down into the PostgreSQL engine, the database mathematically rejects unauthorized data access. Even if a backend Node.js bug completely omits a `WHERE` clause, the database will strictly return only the rows matching the active `SET LOCAL` tenant ID, preventing catastrophic cross-client data leaks.