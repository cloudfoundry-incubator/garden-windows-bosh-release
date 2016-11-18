$ErrorActionPreference = "Stop";
trap { $host.SetShouldExit(1) }

Write-Host "Starting pre-start"
function Get-CurrentLineNumber {
  $MyInvocation.ScriptLineNumber
}
if($PSVersionTable.PSVersion.Major -lt 4) {
  Write-Error "You must be running Powershell version 4 or greater"
}

function DnsServers($interface) {
  return (Get-DnsClientServerAddress -InterfaceAlias $interface -AddressFamily ipv4 -ErrorAction Stop).ServerAddresses
}

[array]$routeable_interfaces = Get-WmiObject Win32_NetworkAdapterConfiguration | Where { $_.IpAddress -AND ($_.IpAddress | Where { $addr = [Net.IPAddress] $_; $addr.AddressFamily -eq "InterNetwork" -AND ($addr.address -BAND ([Net.IPAddress] "255.255.0.0").address) -ne ([Net.IPAddress] "169.254.0.0").address }) }
$ifindex = $routeable_interfaces[0].Index
$interface = (Get-WmiObject Win32_NetworkAdapter | Where { $_.DeviceID -eq $ifindex }).netconnectionid
$servers = DnsServers($interface)
if($servers[0] -eq "127.0.0.1")
{
  Write-Host "DNS Servers are set correctly."
}
else
{
  Write-Host "Setting DNS Servers"
  $newDNS = @("127.0.0.1") + $servers
  Write-Host $newDNS
  Set-DnsClientServerAddress -InterfaceAlias $interface -ServerAddresses ($newDNS -join ",")
  $servers = DnsServers($interface)
  if($servers[0] -ne "127.0.0.1") {
    Write-Error "Failed to set the DNS Servers"
  }
}

if (@(Get-DnsClientCache).Count -ne 0) {
  Clear-DnsClientCache
  if (@(Get-DnsClientCache).Count -ne 0) {
    Write-Error "Failed to clear DNS Client Cache"
  }
}
$RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
$ExpectedValue = 0
$Value = Get-ItemProperty -Path $RegistryPath

if ($Value.MaxNegativeCacheTtl -ne $ExpectedValue) {
  Set-ItemProperty -Path $RegistryPath -Name MaxNegativeCacheTtl -Value $ExpectedValue -Type DWord
  $Value = Get-ItemProperty -Path $RegistryPath
  if ($Value.MaxNegativeCacheTtl -ne $ExpectedValue) {
    Write-Error "Error: Expected MaxNegativeCacheTtl to be '${ExpectedValue}', got '${Value.MaxNegativeCacheTtl}'"
  }
}

$query = "select * from Win32_QuotaSetting where VolumePath='C:\\'"
if (@(Get-WmiObject -query $query).State -ne 2) {
  fsutil quota enforce C:
  if (@(Get-WmiObject -query $query).State -ne 2) {
    Write-Error "Error: Enabling Disk Quota"
  }
}

$RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems"
$ExpectedValue = "$env:SystemRoot\system32\csrss.exe ObjectDirectory=\Windows SharedSection=1024,20480,20480 Windows=On SubSystemType=Windows ServerDll=basesrv,1 ServerDll=winsrv:UserServerDllInitialization,3 ServerDll=sxssrv,4 ProfileControl=Off MaxRequestThreads=16"
$Value = Get-ItemProperty -Path $RegistryPath

if ($Value.Windows -ne $ExpectedValue) {
  Set-ItemProperty -Path $RegistryPath -Name Windows -Value $ExpectedValue -Type String
  $Value = Get-ItemProperty -Path $RegistryPath
  if ($Value.Windows -ne $ExpectedValue) {
    Write-Error "Error: Expected Windows to be '${ExpectedValue}', got '${Value.Windows}'"
  }
}

$anyFirewallsDisabled = !!(Get-NetFirewallProfile -All | Where-Object { $_.Enabled -eq "False" })
$adminRuleMissing = !(Get-NetFirewallRule -Name CFAllowAdmins -ErrorAction Ignore)
if ($anyFirewallsDisabled -or $adminRuleMissing) {
  $admins = New-Object System.Security.Principal.NTAccount("Administrators")
  $adminsSid = $admins.Translate([System.Security.Principal.SecurityIdentifier])

  $LocalUser = "D:(A;;CC;;;$adminsSid)"
  $otherAdmins = Get-WmiObject win32_groupuser |
  Where-Object { $_.GroupComponent -match 'administrators' } |
  ForEach-Object { [wmi]$_.PartComponent }

  foreach($admin in $otherAdmins)
  {
    $ntAccount = New-Object System.Security.Principal.NTAccount($admin.Name)
    $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
    $LocalUser = $LocalUser + "(A;;CC;;;$sid)"
  }
  New-NetFirewallRule -Name CFAllowAdmins -DisplayName "Allow admins" `
    -Description "Allow admin users" -RemotePort Any `
    -LocalPort Any -LocalAddress Any -RemoteAddress Any `
    -Enabled True -Profile Any -Action Allow -Direction Outbound `
    -LocalUser $LocalUser

  Set-NetFirewallProfile -All -DefaultInboundAction Allow -DefaultOutboundAction Block -Enabled True
  $anyFirewallsDisabled = !!(Get-NetFirewallProfile -All | Where-Object { $_.Enabled -eq "False" })
  $adminRuleMissing = !(Get-NetFirewallRule -Name CFAllowAdmins -ErrorAction Ignore)
  if ($anyFirewallsDisabled -or $adminRuleMissing) {
    Write-Host "anyFirewallsDisabled: $anyFirewallsDisabled"
    Write-Host "adminRuleMissing: $adminRuleMissing"
    Write-Error "Failed to Set Firewall rule"
  }
}

Exit 0
