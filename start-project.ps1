$Region = "ap-southeast-1"
$DbInstanceId = "crm-db"
$BastionInstanceId = "i-0f09f376daefd4395"
$BastionSecurityGroupId = "sg-0f454c3209abfec90"

Write-Host "=== Starting RDS ===" -ForegroundColor Cyan
aws rds start-db-instance --db-instance-identifier $DbInstanceId --region $Region | Out-Null
Write-Host "RDS start requested. Waiting for it to become available (this can take a few minutes)..."

do {
    Start-Sleep -Seconds 15
    $status = aws rds describe-db-instances --db-instance-identifier $DbInstanceId --region $Region --query "DBInstances[0].DBInstanceStatus" --output text
    Write-Host "  RDS status: $status"
} while ($status -ne "available")
Write-Host "RDS is available." -ForegroundColor Green

Write-Host "`n=== Starting bastion ===" -ForegroundColor Cyan
aws ec2 start-instances --instance-ids $BastionInstanceId --region $Region | Out-Null
Write-Host "Waiting for bastion to reach 'running' state..."

do {
    Start-Sleep -Seconds 5
    $state = aws ec2 describe-instances --instance-ids $BastionInstanceId --region $Region --query "Reservations[0].Instances[0].State.Name" --output text
} while ($state -ne "running")
Write-Host "Bastion is running." -ForegroundColor Green

Write-Host "`n=== Opening SSH access ===" -ForegroundColor Cyan
$myIp = (Invoke-WebRequest -Uri "http://ifconfig.me/ip" -UseBasicParsing).Content.Trim()
Write-Host "Your current public IP: $myIp"

$result = aws ec2 authorize-security-group-ingress --group-id $BastionSecurityGroupId --protocol tcp --port 22 --cidr "$myIp/32" --region $Region 2>&1
if ($result -match "InvalidPermission.Duplicate") {
    Write-Host "SSH rule for this IP already exists - no action needed." -ForegroundColor Yellow
} else {
    Write-Host "SSH access opened for $myIp." -ForegroundColor Green
}

$bastionIp = aws ec2 describe-instances --instance-ids $BastionInstanceId --region $Region --query "Reservations[0].Instances[0].PublicIpAddress" --output text
Write-Host "`n=== Ready ===" -ForegroundColor Cyan
Write-Host "Bastion public IP: $bastionIp"
Write-Host "Connect with:"
Write-Host "  ssh -o GSSAPIAuthentication=no -i crm-bastion-key ec2-user@$bastionIp" -ForegroundColor White

Write-Host "`nDon't forget to also start your frontend dev server if needed:"
Write-Host "  cd C:\crm-terraform\crm-frontend; npm run dev" -ForegroundColor White