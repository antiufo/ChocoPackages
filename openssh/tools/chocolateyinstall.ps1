
<#
ATTENTION: This code is used extensively to run under PowerShell 2.0 to update 
images from RTM / SP1 source for Windows 7 and Server 2008 R2.  It is also
used under Powershell Core to add OpenSSH to Nano.  Test all enhancements and 
fixes under these two specialty cases (speciality for Chocolatey packagers who are 
likely up to the latest version on everything PowerShell).
#>


$ErrorActionPreference = 'Stop'; # stop on all errors

$ProductName = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'ProductName').ProductName
$EditionId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID').EditionId

#This has to work for Win7 (no get-ciminstance) and Nano (no get-wmiobject) - each of which specially construct win32_operatingsystem.version to handle before and after Windows 10 version numbers (which are in different registry keys)
If ($psversiontable.psversion.major -lt 3)
{
  $OSVersionString = (Get-WMIObject Win32_OperatingSystem).version
}
Else 
{
  $OSVersionString = (Get-CIMInstance Win32_OperatingSystem).version
}


Write-Output "Running on: $ProductName, ($EditionId)"
Write-Output "Windows Version: $OSVersionString"

$RunningOnNano = $False
If ($EditionId -ilike '*Nano*')
{$RunningOnNano = $True}

If (Test-Path variable:shimgen)
{$RunningUnderChocolatey = $True}
Else
{  Write-Output "Running Without Chocolatey"}

$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$OSBits = ([System.IntPtr]::Size * 8) #Get-ProcessorBits

#On 64-bit, always favor 64-bit Program Files no matter what our execution is now (works back past XP / Server 2003)
If ($env:ProgramFiles.contains('x86'))
{
  $PF = $env:ProgramFiles.replace(' (x86)','')
}
Else
{
  $PF = $env:ProgramFiles
}

If (Test-Path "$env:windir\sysnative")
{ #We are running in a 32-bit process under 64-bit Windows
  $sys32dir = "$env:windir\sysnative"
}
Else
{ #We are on a 32-bit OS, or 64-bit proc on 64-bit OS
  $sys32dir = "$env:windir\system32"
}
$filename = "$toolsdir\OpenSSH-Win$($OSBits).zip"
#$TargetFolder = "$PF\OpenSSH"
#$TargetFolderOld = "$PF\OpenSSH-Win$($OSBits)"
$TargetFolder = "$PF\OpenSSH-Win$($OSBits)"
$ExtractFolder = "$env:temp\OpenSSHTemp"
$TERMDefault = 'xterm' #Overall Default
If ([version]$OSVersionString -ge [version]'10.0.0')
{
  $TERMDefault = 'xterm-256color' #Windows 10 / 2016 default
}

$packageArgs = @{
  packageName   = 'openssh'
  unziplocation = "$ExtractFolder"
  fileType      = 'EXE_MSI_OR_MSU' #only one of these: exe, msi, msu

  checksum      = '2F0B993137B01DEA84E8DE97221FD1E20C1CB017'
  checksumType  = 'SHA1'
  checksum64    = '927A5C254B69831F3E19FD522167BC71C32C64E8'
  checksumType64= 'SHA1'
}

If ($RunningUnderChocolatey)
{
  # Default the values before reading params
  $SSHServerFeature = $false
  $KeyBasedAuthenticationFeature = $false
  $DeleteServerKeysAfterInstalled = $false
  $UseNTRights = $false
  $SSHServerPort = '22'
  $DisableKeyPermissionsReset = $False

  $arguments = @{};
  $packageParameters = $env:chocolateyPackageParameters
}

$OpeningMessage = @"

************************************************************************************
************************************************************************************
This package is a Universal Installer and can ALSO install Win32-OpenSSH on 
Nano, Server Core, Docker Containers and more WITHOUT using Chocolatey.

See the following for more details:
https://github.com/DarwinJS/ChocoPackages/blob/master/openssh/readme.md
************************************************************************************
************************************************************************************

"@

Write-Output $OpeningMessage

# Now parse the packageParameters using good old regular expression
if ($packageParameters) {
    $match_pattern = "\/(?<option>([a-zA-Z]+)):(?<value>([`"'])?([a-zA-Z0-9- _\\:\.]+)([`"'])?)|\/(?<option>([a-zA-Z]+))"
    #"
    $option_name = 'option'
    $value_name = 'value'

    if ($packageParameters -match $match_pattern ){
        $results = $packageParameters | Select-String $match_pattern -AllMatches
        $results.matches | % {
          $arguments.Add(
              $_.Groups[$option_name].Value.Trim(),
              $_.Groups[$value_name].Value.Trim())
      }
    }
    else
    {
      throw "Package Parameters were found but were invalid (REGEX Failure)"
    }

    if ($arguments.ContainsKey("SSHAgentFeature")) {
        Write-Host "/SSHAgentFeature was used, including SSH Agent Service."
        $SSHAgentFeature = $true
    }

    if ($arguments.ContainsKey("SSHServerFeature")) {
        Write-Host "/SSHServerFeature was used, including SSH Server Feature."
        $SSHServerFeature = $true
    }

    if ($arguments.ContainsKey("DisableKeyPermissionsReset")) {
        Write-Host "/DisableKeyPermissionsReset was used, will not reset key permissions."
        $DisableKeyPermissionsReset = $true
    }

    if ($arguments.ContainsKey("OverWriteSSHDConf")) {
        Write-Host "/OverWriteSSHDConf was used, will overwrite any existing sshd_conf with one from install media."
        $OverWriteSSHDConf = $true
    }

    if ($arguments.ContainsKey("SSHServerPort")) {
        $SSHServerPort = $arguments.Get_Item("SSHServerPort")
        Write-Host "/SSHServerPort was used, attempting to use SSHD listening port $SSHServerPort."
        If (!$SSHServerFeature)
        {
          Write-Host "You forgot to specify /SSHServerFeature with /SSHServerPort, autofixing for you, enabling /SSHServerFeature"
          $SSHServerFeature = $true
        }
    }

    if ($arguments.ContainsKey("SSHLogLevel")) {

      $ValidLogSettings = @('QUIET', 'FATAL', 'ERROR', 'INFO', 'VERBOSE', 'DEBUG', 'DEBUG1', 'DEBUG2','DEBUG3')
      $SSHLogLevel = $arguments.Get_Item("SSHLogLevel").toupper()
      If ($ValidLogSettings -inotcontains $SSHLogLevel)
      {Throw "$SSHLogLevel is not one of the valid values: $(($ValidLogSettings -join ' ') | out-string)"}
      Write-Host "/SSHLogLevel was used, setting LogLevel in sshd_conf to $SSHLogLevel"

    }
    Else
    {
      $SSHLogLevel = $null
    }

    if ($arguments.ContainsKey("TERM")) {
      $TERM = $arguments.Get_Item("TERM")
      Write-Host "/TERM was used, setting system TERM environment variable to $TERM"
      $TERMSwitchUsed = $True
    }
    Else
    {
      $TERM = 'xterm'
      Write-Host "Defaulting system TERM environment variable to $TERM"
    }

    if ($arguments.ContainsKey("UseNTRights")) {
        Write-Host "Using ntrights.exe to set service permissions (will not work, but generate warning if WOW64 is not present on 64-bit machines)"
        $UseNTRights = $true
    }

    if ($arguments.ContainsKey("DeleteServerKeysAfterInstalled")) {
        Write-Host "Deleting server private keys after they have been secured."
        $DeleteServerKeysAfterInstalled = $true
    }

    if ($arguments.ContainsKey("KeyBasedAuthenticationFeature")) {
        Write-Host "Including LSA DLL Feature."
        $KeyBasedAuthenticationFeature = $true
        If (!$SSHServerFeature)
        {
          Write-Warning "KeyBasedAuthenticationFeature was specified, but is only value when SSHServerFeature is specified, ignoring..."
        }
    }

} else {
    Write-Debug "No Package Parameters Passed in";
}

Function CheckServicePath ($ServiceEXE,$FolderToCheck)
{
  #The modern way:
  #Return ([bool]((Get-WmiObject win32_service | ?{$_.Name -ilike "*$ServiceEXE*"} | select -expand PathName) -ilike "*$FolderToCheck*"))
  #The NANO TP5 Compatible Way:
  Return ([bool](@(wmic service | ?{$_ -ilike "*$ServiceEXE*"}) -ilike "*$FolderToCheck*"))
}

#Extract Files Early
If ($RunningUnderChocolatey)
{
  If (Test-Path $ExtractFolder)
  {
    Remove-Item $ExtractFolder -Recurse -Force
  }
  Get-ChocolateyUnzip "$filename" $ExtractFolder
}
Else
{
  If (Test-Path "$toolsdir\7z.exe")
  {
    #covers nano
    cd $toolsdir
    start-process .\7z.exe -argumentlist "x `"$filename`" -o`"$ExtractFolder`" -aoa" -nonewwindow -wait
  }
  Else
  {
    Throw "You need a copy of 7z.exe next to this script for this operating system.  You can get a copy at 7-zip.org"
  }
}

If ($SSHServerFeature)
{  #Check if anything is already listening on port $SSHServerPort, which is not a previous version of this software.
  Write-Host "/SSHAgentFeature is also automatically enabled when using /SSHServerFeature."
  $SSHAgentFeature = $true
  $AtLeastOneSSHDPortListenerIsNotUs = $False
  Write-Output "Probing for possible conflicts with SSHD server to be configured on port $SSHServerPort ..."
  . "$toolsdir\Get-NetStat.ps1"
  $procslisteningonRequestedSSHDPort = @(Get-Netstat -GetProcessDetails -FilterOnPort $SSHServerPort)
  If ((checkservicepath 'svchost.exe -k SshBrokerGroup' 'Part of Microsoft SSH Server for Windows') -AND (checkservicepath 'svchost.exe -k SshProxyGroup' 'Part of Microsoft SSH Server for Windows'))
  {
    Write-Warning "  > Detected that Developer Mode SSH is present (Probably due to enabling Windows 10 Developer Mode)"
    $DeveloperModeSSHIsPresent = $True
  }

  If ($procslisteningonRequestedSSHDPort.count -ge 1)
  {
    ForEach ($proconRequestedSSHDPort in $procslisteningonRequestedSSHDPort)
    {
      Write-output "  > Checking $($proconRequestedSSHDPort.Localaddressprocesspath) against path $TargetFolder"
      If ("$($proconRequestedSSHDPort.Localaddressprocesspath)" -ilike "*$TargetFolder*")
      {
        Write-Output "  > Found a previous version of Win32-OpenSSH installed by this package on Port $SSHServerPort."
      }
      Else
      {
        $AtLeastOneSSHDPortListenerIsNotUs = $True
        Write-Warning "  > Found something listening on Port $SSHServerPort that was not installed by this package."
        Write-Warning "      $($proconRequestedSSHDPort.LocalAddressProcessPath) is listening on Port $SSHServerPort"
        $ProcessOccupyingPort = "$($proconRequestedSSHDPort.LocalAddressProcessPath)"
      }
    }
  }

  If ($AtLeastOneSSHDPortListenerIsNotUs)
  {
  $errorMessagePort = @"
"$ProcessOccupyingPort" is listening on port $SSHServerPort and you have not specified a different listening port (list above) using the /SSHServerPort parameter.
Please either deconfigure or deinstall whatever is running on Port $SSHServerPort and try again OR specify a different port for this SSHD Server using the /SSHServerPort package parameter.
If you see the message 'Detected that Developer Mode SSH is present' above, you may be able to simply disable the services 'SSHBroker' and 'SSHProxy'
"@
  Throw $errorMessagePort
  }
}

$SSHServiceInstanceExistsAndIsOurs = CheckServicePath 'sshd.exe' "$TargetFolder"
$SSHAGENTServiceInstanceExistsAndIsOurs = CheckServicePath 'ssh-agent.exe' "$TargetFolder"

If ($SSHServerFeature -AND (!$SSHServiceInstanceExistsAndIsOurs) -AND ([bool](Get-Service sshd -ErrorAction SilentlyContinue)))
{
  $ExistingSSHDInstancePath = get-itemproperty hklm:\system\currentcontrolset\services\* | where {($_.ImagePath -ilike '*sshd.exe*')} | Select -expand ImagePath
  Throw "You have requested that the SSHD service be installed, but this system appears to have an instance of an SSHD service configured for another folder ($ExistingSSHDInstancePath).  You can remove the package switch /SSHServerFeature to install just the client tools, or you will need to remove that instance of SSHD to use the one that comes with this package."
}

If ((!$SSHServerFeature) -AND $SSHServiceInstanceExistsAndIsOurs)
{
  Throw "There is a configured instance of the SSHD service, please specify the /SSHServerFeature to confirm it is OK to shutdown and upgrade the SSHD service at this time."
}

If ([bool](get-process ssh -erroraction silentlycontinue | where {$_.Path -ilike "*$TargetFolder*"}))
{
  Throw "It appears you have instances of ssh.exe (client) running from the folder this package installs to, please terminate them and try again."
}

If ((Test-Path $TargetFolder) -AND (@(dir "$TargetFolder\*.exe").count -gt 0)) 
{
  Write-Output "`r`nCURRENT VERSIONS OF SSH EXES:"
    Write-Output "$(dir "$TargetFolder\*.exe"| select -expand fullname | get-command | select -expand fileversioninfo | ft filename, fileversion -auto | out-string)"
}

If (Test-Path "$env:windir\system32\ssh-lsa.dll") 
{
  Write-Output "`r`nCURRENT VERSION OF SSH-LSA.DLL:"
  Write-Output "$(get-command "$env:windir\system32\ssh-lsa.dll" | select -expand fileversioninfo | ft filename, fileversion -auto | out-string)"
}

If ($SSHServiceInstanceExistsAndIsOurs -AND ([bool](Get-Service SSHD -ErrorAction SilentlyContinue | where {$_.Status -ieq 'Running'})))
{
    #Shutdown and unregister service for upgrade
    stop-service sshd -Force
    Stop-Service SSH-Agent -Force
    Start-Sleep -seconds 3
    If (([bool](Get-Service SSHD | where {$_.Status -ieq 'Running'})))
    {
      Throw "Could not stop the SSHD service, please stop manually and retry this package."
    }
    If ($SSHAGENTServiceInstanceExistsAndIsOurs)
    {
      stop-service ssh-agent -Force
      Start-Sleep -seconds 3
      If (([bool](Get-Service ssh-agent | where {$_.Status -ieq 'Running'})))
      {
        Throw "Could not stop the ssh-agent service, please stop manually and retry this package."
      }
    }
}

If ($SSHServiceInstanceExistsAndIsOurs)
{
  Write-output "Stopping SSHD Service for upgrade..."
  Stop-Service sshd
  sc.exe delete sshd | out-null
}
If ($SSHAGENTServiceInstanceExistsAndIsOurs)
{
  Write-output "Stopping SSH-Agent Service for upgrade..."
  Stop-Service ssh-agent -erroraction silentlycontinue
  sc.exe delete ssh-agent | out-null
}

If ($OSBits -eq 64)
{
  $SourceZipChecksum = $packageargs.checksum64
  $SourceZipChecksumType = $packageargs.checksumType64
}
Else
{
  $SourceZipChecksum = $packageargs.checksum
  $SourceZipChecksumType = $packageargs.checksumType
}

If ([bool](get-command get-filehash -ea silentlycontinue))
{
  If ((Get-FileHash $filename -Algorithm $SourceZipChecksumType).Hash -eq $SourceZipChecksum)
  {
    Write-Output "Hashes for internal source match"
  }
  Else
  {
    throw "Checksums for internal source do not match - something is wrong."
  }
}
Else
{
  Write-Output "Source files are internal to the package, checksums are not required nor checked."
}

$ExcludeParams = @{}
If ((Test-Path "$TargetFolder\sshd_config") -AND !($OverWriteSSHDConf))
{
  Write-Output "sshd_config already exists, not overwriting"
  $ExcludeParams.Add("Exclude","sshd_config")
}

Copy-Item "$ExtractFolder\*" "$PF" @ExcludeParams -Force -Recurse -Passthru -ErrorAction Stop
#Fixed version of module
#Write-Host "Updating OpenSSHUtils PowerShell Module to Latest"
Copy-Item "$toolsdir\OpenSSHUtils.ps*" "$TargetFolder" -Force -PassThru -ErrorAction Stop
#Copy-Item "$toolsdir\Fix*FilePermissions.ps1" "$TargetFolder" -Force -PassThru -ErrorAction Stop

Remove-Item "$ExtractFolder" -Force -Recurse

If ($RunningUnderChocolatey)
{
  Install-ChocolateyPath "$TargetFolder" 'Machine'
}
Else
{
  $PathToAdd = $TargetFolder
  $ExistingPathArray = @(((Get-ItemProperty 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' | select -expand path).split(';')))
  if (($ExistingPathArray -inotcontains $PathToAdd) -AND ($ExistingPathArray -inotcontains "$PathToAdd\"))
  {
    $Newpath = $ExistingPathArray + @("$PathToAdd")
    $AssembledNewPath = ($newpath -join(';')).trimend(';')
    Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name 'PATH' -Value "$AssembledNewPath"
  }
}
If ($env:Path -inotlike "*$TargetFolder*")
{
  $env:path += ";$TargetFolder"
}

$ExistingTermValue = $null
$ExistingTermValue = (get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -EA SilentlyContinue | Select -Expand TERM -EA SilentlyContinue)

If (!$TERM) {$TERM = $TERMDefault}

If ((!$ExistingTermValue) -OR ($ExistingTermValue -ine $TERM))
{ 
  Write-Host "Updating machine environment variable TERM from `"$ExistingTermValue`" to `"$TERM`""
  Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name 'TERM' -Value "$TERM"
}

If ($SSHAgentFeature)
{
  New-Service -Name ssh-agent -BinaryPathName "$TargetFolder\ssh-agent.exe" -Description "SSH Agent" -StartupType Automatic | Out-Null
  cmd.exe /c 'sc.exe sdset ssh-agent D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)(A;;RP;;;AU)'

  Start-Service ssh-agent

  Start-Sleep -seconds 3

  If (!$UseNTRights)
  {
    #The code in this .PS1 has been tested on Nano - the hardest case to date for setting special privileges in script
    . "$toolsdir\AddAccountToLogonAsAService.ps1" -AccountToAdd "NT SERVICE\SSH-Agent"
  }
  Else
  {
    If (($OSBits -eq 64) -and (!(Test-Path "$env:windir\syswow64")))
    {
      Write-Warning "This 64-bit system does not have the WOW64 subsystem installed, please manually grant the right SeLogonAsAService to `"NT SERVICE\SSHD`"."
      Write-Warning "OR try again WITHOUT the /UseNTRights switch."
    }
    Else
    {
      write-output "Using ntrights.exe to grant logon as service."
      Start-Process "$TargetFolder\ntrights.exe" -ArgumentList "-u `"NT SERVICE\SSH-Agent`" +r SeServiceLogonRight"
    }
  }
}

If ($SSHServerFeature)
{
  Write-Warning "You have specified SSHServerFeature - this machine is being configured as an SSH Server including opening port $SSHServerPort."

  If((Test-Path "$TargetFolder\sshd_config"))
  {
    #(Get-Content "$TargetFolder\sshd_config") -replace '#LogLevel INFO', 'LogLevel QUIET' | Set-Content "$TargetFolder\sshd_config"

    $CurrentLogLevelConfig = ((gc "$TargetFolder\sshd_config") -imatch "^#*LogLevel\s\w*\b.*$")
    Write-Output 'Setting up SSH Logging'
    If ($SSHLogLevel)
    { #command line specified a log level - override whatever is there
      If ([bool]($CurrentLogLevelConfig -inotmatch "^LogLevel\s$SSHLogLevel\s*$"))
      {
        Write-Output "Current LogLevel setting in `"$TargetFolder\sshd_config`" is `"$CurrentLogLevelConfig`", setting it to `"LogLevel $SSHLogLevel`""
        (Get-Content "$TargetFolder\sshd_config") -replace "^#*LogLevel\s\w*\b.*$", "LogLevel $SSHLogLevel" | Set-Content "$TargetFolder\sshd_config"
      }
    }
    Else
    { #command line did not specify a log level, set it to QUIET - only if it has never been set (currently commented INFO setting)
      If((Test-Path "$TargetFolder\sshd_config") -AND ([bool]((gc "$TargetFolder\sshd_config") -ilike "#LogLevel INFO*")))
      {
        Write-Warning "Explicitly disabling sshd logging as it currently logs about .5 GB / hour"
        (Get-Content "$TargetFolder\sshd_config") -replace '#LogLevel INFO', 'LogLevel QUIET' | Set-Content "$TargetFolder\sshd_config"
      }
    }

     $CurrentPortConfig = ((gc "$TargetFolder\sshd_config") -match "^#*Port\s\d*\s*$")
     If ([bool]($CurrentPortConfig -notmatch "^Port $SSHServerPort"))
     {
       Write-Output "Current port setting in `"$TargetFolder\sshd_config`" is `"$CurrentPortConfig`", setting it to `"Port $SSHServerPort`""
       (Get-Content "$TargetFolder\sshd_config") -replace "^#*Port\s\d*\s*$", "Port $SSHServerPort" | Set-Content "$TargetFolder\sshd_config"
     }
     Else
     {
       Write-Output "Current port setting in `"$TargetFolder\sshd_config`" already matches `"Port $SSHServerPort`", no action necessary."
     }
  }

  If (!(Test-Path "$TargetFolder\KeysGenerated.flg"))
  { #Only ever generate a key the first time SSHD server is installed
      Write-Output "Generating sshd keys in `"$TargetFolder`""
      start-process "$TargetFolder\ssh-keygen.exe" -ArgumentList '-A' -WorkingDirectory "$TargetFolder" -nonewwindow -wait
      New-Item "$TargetFolder\KeysGenerated.flg" -type File | out-null
  }
  Else
  {
    Write-Warning "Found existing server ssh keys in $TargetFolder, you must delete them manually to generate new ones."
  }

  netsh advfirewall firewall add rule name='SSHD Port OpenSSH (chocolatey package: openssh)' dir=in action=allow protocol=TCP localport=$SSHServerPort

  If ($DeleteServerKeysAfterInstalled)
  {
    pushd $TargetFolder
    Foreach ($keyfile in $keylist)
    {
      If (Test-Path $keyfile)
      {
        Remove-Item $keyfile -force
      }
    }
    popd
  }
  Else
  {
    Write-Warning "The following private keys should be removed from the machine: $keylist"
  }
  New-Service -Name sshd -BinaryPathName "$TargetFolder\sshd.exe" -Description "SSH Daemon" -StartupType Automatic -DependsOn ssh-agent | Out-Null
  sc.exe config sshd obj= "NT SERVICE\SSHD"
  
  If (!$DisableKeyPermissionsReset)
  {
    Write-Host "Ensuring all ssh key and configuration files have correct permissions for all users"
    . "$TargetFolder\FixHostFilePermissions.ps1" -Confirm:$false
  }

  $logsdir = "$TargetFolder\Logs"
  If (!(Test-Path $logsdir))
  {
    New-Item $logsdir -ItemType Directory | out-null
    $rights = [System.Security.AccessControl.FileSystemRights]"Read, Write"
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("NT SERVICE\sshd", $rights, "ContainerInherit,ObjectInherit", "None", "Allow")
    If (!$RunningOnNano)
    {
      $aclAccess = (Get-Item -Path $logsdir).GetAccessControl('Access')
      $aclAccess.SetAccessRule($accessRule)
      Set-Acl -AclObject $aclAccess -Path $logsdir -Confirm:$false
    }
    Else
    {
      $aclAccess = Get-Acl -Path $logsdir
      $aclAccess.SetAccessRule($accessRule)
      Set-Acl -Path $logsdir -AclObject $aclAccess
    }
  }

  If (!$UseNTRights)
  {
    #The code in this .PS1 has been tested on Nano - the hardest case to date for setting special privileges in script
    . "$toolsdir\AddAccountToAssignPrimaryToken.ps1" -AccountToAdd "NT SERVICE\SSHD"
    . "$toolsdir\AddAccountToLogonAsAService.ps1" -AccountToAdd "NT SERVICE\SSHD"
  }
  Else
  {
    If (($OSBits -eq 64) -and (!(Test-Path "$env:windir\syswow64")))
    {
      Write-Warning "This 64-bit system does not have the WOW64 subsystem installed, please manually grant the right SeLogonAsAService to `"NT SERVICE\SSHD`"."
      Write-Warning "OR try again WITHOUT the /UseNTRights switch."
    }
    Else
    {
      write-output "Using ntrights.exe to grant logon as service."
      Start-Process "$TargetFolder\ntrights.exe" -ArgumentList "-u `"NT SERVICE\SSHD`" +r SeAssignPrimaryTokenPrivilege"
      Start-Process "$TargetFolder\ntrights.exe" -ArgumentList "-u `"NT SERVICE\SSH-Agent`" +r SeServiceLogonRight"
    }
  }
}

If (CheckServicePath 'sshd.exe' "$TargetFolder")
{
  write-output "Starting SSHD..."
  Start-Service SSHD
}
If (CheckServicePath 'ssh-agent.exe' "$TargetFolder")
{
  write-output "Starting SSH-Agent..."
  Start-Service SSH-Agent
}

$keylist = "ssh_host_dsa_key", "ssh_host_rsa_key", "ssh_host_ecdsa_key", "ssh_host_ed25519_key"
$fullpathkeylist = "'$TargetFolder\ssh_host_dsa_key'", "'$TargetFolder\ssh_host_rsa_key'", "'$TargetFolder\ssh_host_ecdsa_key'", "'$TargetFolder\ssh_host_ed25519_key'"


If ($SSHServerFeature)
{
  If (!(Test-Path "$TargetFolder\KeysAddedToAgent.flg"))
  {
    Write-Output "Installing Server Keys into SSH-Agent"

    schtasks.exe /create /RU "NT AUTHORITY\SYSTEM" /RL HIGHEST /SC ONSTART /TN "ssh-add" /TR "'$TargetFolder\ssh-add.exe'  $fullpathkeylist" /F

    schtasks.exe /Run /I /TN "ssh-add"

    schtasks.exe /Delete /TN "ssh-add" /F

    New-Item "$TargetFolder\KeysAddedToAgent.flg" -type File | out-null
  }
  
}

If (Test-Path "$TargetFolder\ssh.exe") 
{
  Write-Output "`r`nNEW VERSIONS OF SSH EXES:"
  Write-Output "$(dir "$TargetFolder\*.exe" | select -expand fullname | get-command | select -expand fileversioninfo | ft filename, fileversion -auto | out-string)"
}

write-output ""
Write-Warning "You must start a new prompt, or use the command 'refreshenv' (provided by your chocolatey install) to re-read the environment for the tools to be available in this shell session."
