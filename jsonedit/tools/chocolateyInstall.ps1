﻿$packageName = 'jsonedit'
$url = 'http://tomeko.net/software/JSONedit/bin/JSONedit_0_9_24.zip'
$validExitCodes = @(0)
$exeName = "jsonedit.exe"
$checksum      = 'F4B3013B10D755E022D1E6CE0CCF93F8BA1D1026'
$checksumType  = 'sha1'

Install-ChocolateyZipPackage "$packageName" "$url" "$(Split-Path -parent $MyInvocation.MyCommand.Definition)" -checksum $checksum -checksumType $checksumType

$AppPathKey = "Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exeName"
If (!(Test-Path $AppPathKey)) {New-Item "$AppPathKey" | Out-Null}
Set-ItemProperty -Path $AppPathKey -Name "(Default)" -Value "$env:chocolateyinstall\lib\$packagename\tools\$exeName"
Set-ItemProperty -Path $AppPathKey -Name "Path" -Value "$env:chocolateyinstall\lib\$packagename\tools\"

Write-Output "************************************************************************************************"
Write-Output "*  INSTRUCTIONS: In the search prompt of your start menu type `"$exeName`"                     *"
Write-Output "*   More Info:                                                                                 *"
Write-Output "*   http://tomeko.net/software/JSONedit/                                                       *"
Write-Output "************************************************************************************************"
