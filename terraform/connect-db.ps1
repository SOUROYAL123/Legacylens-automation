# connect-db.ps1
Write-Host "Fetching live infrastructure outputs from Terraform..." -ForegroundColor Cyan

# Dynamically grab the latest Bastion ID and Database Endpoint
$BASTION = terraform output -raw bastion_instance_id
$DB_ENDPOINT = terraform output -raw postgres_endpoint

Write-Host "Starting Secure SSM Tunnel to $DB_ENDPOINT via $BASTION..." -ForegroundColor Green
Write-Host "Press CTRL+C to close the tunnel when finished." -ForegroundColor Yellow

# Start the SSM Session Manager tunnel
aws ssm start-session `
    --target $BASTION `
    --document-name AWS-StartPortForwardingSessionToRemoteHost `
    --parameters host="$DB_ENDPOINT",portNumber="5432",localPortNumber="5432"