<#
.SYNOPSIS
    Maps the CUR file share as a drive letter on Windows 11.

.DESCRIPTION
    Connect the AWS VPN Client first. The script then checks that the gateway
    answers on the file-sharing port, asks for the share's guest password, and
    maps the share as a drive that stays mapped after a restart.

    Get the two required values from the person who deployed the gateway, or run
    these commands in the terraform folder:
        terraform output -raw gateway_private_ip
        terraform output -raw gateway_id

.EXAMPLE
    .\connect-windows.ps1 -GatewayAddress 10.40.0.217 -GatewayId sgw-C712B1AF
.NOTES
    DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $GatewayAddress,

    [Parameter(Mandatory = $true)]
    [string] $GatewayId,

    [string] $ShareName = "cur",

    [ValidatePattern("^[D-Zd-z]$")]
    [string] $DriveLetter = "S"
)

$ErrorActionPreference = "Stop"
$sharePath = "\\$GatewayAddress\$ShareName"

Write-Host "Checking that $GatewayAddress accepts connections on port 445..."
$test = Test-NetConnection -ComputerName $GatewayAddress -Port 445 -WarningAction SilentlyContinue
if (-not $test.TcpTestSucceeded) {
    throw "The gateway does not accept connections on port 445. Connect the AWS VPN Client and try again."
}

if (Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue) {
    throw "Drive ${DriveLetter}: is already in use. Run the script again with -DriveLetter and a free letter."
}

$credential = Get-Credential -UserName "$GatewayId\smbguest" -Message "Enter the guest password for the $ShareName file share."

New-PSDrive -Name $DriveLetter -PSProvider FileSystem -Root $sharePath -Credential $credential -Persist -Scope Global | Out-Null

Write-Host "Drive ${DriveLetter}: now shows $sharePath. Open and save Excel files there as usual."
