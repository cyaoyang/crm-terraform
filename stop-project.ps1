$Region = "ap-southeast-1"
$DbInstanceId = "crm-db"
$BastionInstanceId = "i-0f09f376daefd4395"
$BastionSecurityGroupId = "sg-0f454c3209abfec90"

Write-Host "=== Closing SSH access ===" -ForegroundColor Cyan
$myIp = (Invoke-WebRequest -Uri "http://ifconfig.me/ip" -UseBasicParsing).Content.Trim()

$existingRules = aws ec2 describe-security-groups --group-ids $BastionSecurityGroupId --region $Region --query "SecurityGroups[0].IpPermissions[].IpRanges[].CidrIp" --output text

if ($existingRules) {
    foreach ($cidr in $existingRules -split "\s+") {
        if ($cidr) {
            Write-Host "Revoking SSH rule for $cidr..."
            aws ec2 revoke-security-group-ingress --group-id $BastionSecurityGroupId --protocol tcp --port 22 --cidr $cidr --region $Region | Out-Null
        }
    }
    Write-Host "SSH access closed." -ForegroundColor Green
} else {
    Write-Host "No SSH rules found - already closed." -ForegroundColor Yellow
}

Write-Host "`n=== Stopping bastion ===" -ForegroundColor Cyan
aws ec2 stop-instances --instance-ids $BastionInstanceId --region $Region | Out-Null
Write-Host "Bastion stop requested." -ForegroundColor Green

Write-Host "`n=== Stopping RDS ===" -ForegroundColor Cyan
aws rds stop-db-instance --db-instance-identifier $DbInstanceId --region $Region 2>&1 | Out-Null
Write-Host "RDS stop requested." -ForegroundColor Green
Write-Host "(Note: AWS auto-restarts a stopped RDS instance after 7 days - not urgent, just a heads up.)" -ForegroundColor Yellow

Write-Host "`n=== Cleaning up temp files ===" -ForegroundColor Cyan
$tempFiles = @("pwfile.txt", "payload.json", "payload2.json", "response.json", "response2.json", "response3.json")
foreach ($f in $tempFiles) {
    if (Test-Path $f) {
        Remove-Item $f
        Write-Host "Removed $f"
    }
}

Write-Host "`n=== Done. Safe to close for this session. ===" -ForegroundColor Cyan