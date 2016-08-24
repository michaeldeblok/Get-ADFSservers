#Requires –Version 4
#Requires -RunAsAdministrator 

$cred = Get-Credential
$adfs = Read-Host -Prompt 'Please type in your adfs endpoint hostname (i.e. adfs.contoso.com)' 

$formatenumerationlimit = -1
$dc = $env:Logonserver -replace "\\", ""
$s = New-PSSession -ComputerName $dc -Credential $cred
Invoke-Command -Session $s {Import-Module ActiveDirectory}
Import-PSSession -Session $s -Module ActiveDirectory -Prefix dc
$services = "adfssrv","MSSQL$MICROSOFT%"
$servers = Get-dcADComputer -LDAPFilter "(&(objectcategory=computer)(OperatingSystem=*server*))"
$value = 1
if ($servers.count -lt "100") {$adfsservers = ForEach-Object {Get-WmiObject Win32_Service -ComputerName $servers.dnshostname -Filter "Name Like 'adfssrv'" -Credential $cred | select-object PSComputerName -ExpandProperty PSComputerName}}`
else {$adfsservers = @()
do {
$input = (Read-Host "Please enter ADFS server #$value (enter if last one)")
if ($input -ne '') {$adfsservers += $input}
$value++
}
until ($input -eq '')}
$ips = $adfsservers | foreach {Resolve-DNSName $_ | Select-Object IPAddress -ExpandProperty IPAddress}
$adfssrvs = $adfsservers | ForEach {Get-dcADComputer "$_" | Select-Object DnsHostName -ExpandProperty DnsHostName}
$adfssessions = New-PSSession -ComputerName $adfssrvs -Credential $cred
Start-TranScript c:\temp\ADFS-TESTS.TXT -force
write-host ====================================
Write-host Number of ADFS Servers: ($adfsservers).count
$adfssrvs
write-host ====================================
Write-Host -foregroundcolor "Green" Showing status of services on ADFS Servers:
$services | ForEach-Object {Get-WmiObject Win32_Service -ComputerName $servers.dnshostname -Filter "Name Like '$_'" -Credential $cred | Format-Table Name, DisplayName, State, StartMode, StartName, SystemName -auto}

$f = "c:\temp\ADFSDiagnostics.psm1"
$c = Get-Content $f
icm -Session $adfssessions -ScriptBlock {mkdir c:\temp -force -erroraction silentlycontinue}
icm -Session $adfssessions -ScriptBlock {param($filename,$contents) `
Set-Content -Path $filename -Value $contents} -ArgumentList $f,$c

icm -Session $adfssessions -ScriptBlock {
C:
cd \temp
Import-Module .\ADFSDiagnostics.psm1
Write-Host -foregroundcolor "Green" Running cmdlet Get-AdfsSystemInformation on $env:computername
Get-AdfsSystemInformation
Write-Host -foregroundcolor "Green" Running cmdlet Get-AdfsServerConfiguration on $env:computername
Get-AdfsServerConfiguration
Write-Host -foregroundcolor "Green" Running cmdlet Test-AdfsServerHealth on $env:computername
Test-AdfsServerHealth | ft Name,Result -AutoSize
Write-Host -foregroundcolor "Green" Running cmdlet Test-AdfsServerHealth showing failures on $env:computername
Test-AdfsServerHealth | where {$_.Result -eq "Fail"} | fl
}

C:
cd \temp
Import-Module .\ADFSDiagnostics.psm1
Import-Module .\Hostnames.psm1
foreach ($ip in $ips)
{
Add-Hostnames $ip $adfs
Test-AdfsServerToken -federationServer $adfs -appliesTo urn:federation:MicrosoftOnline
Test-AdfsServerToken -federationServer $adfs -appliesTo urn:federation:MicrosoftOnline -credential $cred
$token = [Xml](Test-AdfsServerToken -federationServer $adfs -appliesTo urn:federation:MicrosoftOnline)
$token.Envelope.Body.RequestSecurityTokenResponse.RequestedSecurityToken.Assertion.AttributeStatement.Attribute | ft
Remove-Hostnames $adfs
}

Write-Host -foregroundcolor "Green" Starting services marked as AUTO that are now marked as STOPPED
icm -Session $adfssessions -ScriptBlock {get-wmiobject win32_service | where-object {$_.Startmode -eq "auto" -and $_.State -ne "running"}| Start-Service -Verbose}


Get-PSSession | Remove-PSSession
Stop-TranScript
