# 1) Make sure the agent is current + running
$Url = "https://s3.us-east-2.amazonaws.com/amazon-ssm-us-east-2/latest/windows_amd64/AmazonSSMAgentSetup.exe"
$Dst = "$env:TEMP\AmazonSSMAgentSetup.exe"
Invoke-WebRequest -Uri $Url -OutFile $Dst -UseBasicParsing
Start-Process $Dst -ArgumentList "/S" -Wait
Set-Service -Name AmazonSSMAgent -StartupType Automatic
Restart-Service -Name AmazonSSMAgent

# 2) Prove IMDS creds are reachable (should return the role name)
Invoke-WebRequest -UseBasicParsing http://169.254.169.254/latest/meta-data/iam/security-credentials/

# 3) DNS & 443 to the SSM endpoints
nslookup ssm.us-east-2.amazonaws.com
Test-NetConnection ssm.us-east-2.amazonaws.com -Port 443
Test-NetConnection ssmmessages.us-east-2.amazonaws.com -Port 443
Test-NetConnection ec2messages.us-east-2.amazonaws.com -Port 443

# 4) Time sync (clock skew kills SigV4)
w32tm /query /status
w32tm /resync /force

# 5) Tail the agent log for obvious auth/DNS errors
Get-Content "C:\ProgramData\Amazon\SSM\Logs\amazon-ssm-agent.log" -Tail 200