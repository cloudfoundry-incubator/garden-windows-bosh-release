$ErrorActionPreference = "Stop";
trap { $host.SetShouldExit(1) }

Write-Host "Starting pre-start"
function Get-CurrentLineNumber {
  $MyInvocation.ScriptLineNumber
}
if($PSVersionTable.PSVersion.Major -lt 4) {
  Write-Error "You must be running Powershell version 4 or greater"
}

$RepPort = 1800
if (-Not (Get-NetFirewallRule | Where-Object { $_.DisplayName -eq "RepPort" })) {
  New-NetFirewallRule -DisplayName "RepPort" -Action Allow -Direction Inbound -Enabled True -LocalPort $RepPort -Protocol TCP
  if (-Not (Get-NetFirewallRule | Where-Object { $_.DisplayName -eq "RepPort" })) {
    Write-Error "Unable to add RepPort firewall rule"
  }
}

$RequiredFeatures = (
    "Web-Webserver",
    "Web-WebSockets",
    "AS-Web-Support",
    "AS-NET-Framework",
    "Web-WHC",
    "Web-ASP"
)
[string] $MissingFeatures = ""
foreach ($name in $RequiredFeatures) {
    if (-Not (Get-WindowsFeature -Name $name).Installed) {
        if ($MissingFeatures.Length -gt 0) {
            $MissingFeatures += ", "
        }
        $MissingFeatures += $name
    }
}
if ($MissingFeatures.Length -gt 0) {
    Write-Error "Missing required Windows Features: $MissingFeatures.  Please use the most recent stemcell."
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

# Check firewall rules
function get-firewall {
	param([string] $profile)
	$firewall = (Get-NetFirewallProfile -Name $profile)
	$result = "{0},{1},{2}" -f $profile,$firewall.DefaultInboundAction,$firewall.DefaultOutboundAction
	return $result
}

function check-firewall {
	param([string] $profile)
	$firewall = (get-firewall $profile)
	Write-Host $firewall
	if ($firewall -ne "$profile,Block,Block") {
		Write-Host $firewall
		Write-Error "Unable to set $profile Profile"
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

  Set-NetFirewallProfile -All -DefaultInboundAction Block -DefaultOutboundAction Block -Enabled True
  check-firewall "public"
  check-firewall "private"
  check-firewall "domain"
  $anyFirewallsDisabled = !!(Get-NetFirewallProfile -All | Where-Object { $_.Enabled -eq "False" })
  $adminRuleMissing = !(Get-NetFirewallRule -Name CFAllowAdmins -ErrorAction Ignore)
  if ($anyFirewallsDisabled -or $adminRuleMissing) {
    Write-Host "anyFirewallsDisabled: $anyFirewallsDisabled"
    Write-Host "adminRuleMissing: $adminRuleMissing"
    Write-Error "Failed to Set Firewall rule"
  }
}

Exit 0
