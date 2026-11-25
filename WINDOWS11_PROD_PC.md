# curs3drive on a Windows 11 Production PC

_DRAFT - For internal use only. Last modified: 2026-11-25 11:48 EST by mbitar._

**curs3drive** is a proof of concept that makes an Amazon S3 bucket work like a Windows network drive, so people can open, edit and save large Cost and Usage Report (CUR) files. It uses **Amazon S3 File Gateway**, one type of AWS Storage Gateway, which runs on an EC2 instance and shares the bucket over SMB, the Windows file-sharing protocol. The PC connects with the AWS VPN Client and maps the share as drive S:. The gateway uploads every save to S3. It has been tested only from a Mac, and its AWS parts were removed on 23 November 2026.

This page answers two questions: can curs3drive run on a production Windows 11 PC, and what needs a Windows administrator password?

[Back to the README](README.md)

## Answer so far

**Probably yes, if IT installs the AWS VPN Client.** This comes from the code and vendor documentation. Nothing has been tested on Windows.

- "Administrator" means a Windows administrator of the PC, not an AWS administrator.
- Reported by the user, not checked: the user has no administrator password, and Python and the AWS CLI are installed.
- Microsoft Office is out of scope.

## What needs a Windows administrator

| Part | Administrator needed? | What company policy can block |
|---|---|---|
| AWS VPN Client | **Yes, to install and probably to update** | Unapproved programs |
| .NET Framework, used by the client | Only if missing or too old | |
| VPN profile | No | Adding profiles |
| VPN connection | No | The connection, through a firewall, TLS inspection or another VPN |
| Drive S: | No | NTLM or guest sign-in, TCP port 445, or saving to an unapproved share |
| PowerShell script | No, it is optional | Scripts. Use `net use` instead. |
| Python and the AWS CLI | No, the share does not use them | |

AWS does not state that installing the client needs an administrator. We expect it, because the client uses a [Windows service for privileged operations](https://docs.aws.amazon.com/vpn/latest/clientvpn-user/windows-troubleshooting.html).

## Check 1: Run now

This check reads settings and makes two short connections to a public AWS address. It changes nothing, and needs no password or gateway. It has not been run on Windows, so read it first and follow company rules on pasting commands.

1. Disconnect the AWS VPN Client, if it is installed.
2. Open **Windows PowerShell** as the normal user, not with **Run as administrator**.
3. Paste the whole block and press Enter. It takes up to about a minute.

```powershell
& {
# ============================================================
# CHECK 1: which parts work now, and which need a Windows administrator
# ============================================================
# This block only reads settings. It does not install, change or delete anything.
# It asks for no password and is written for a user without administrator rights.
# It makes two short connections to a public AWS address, to test the network.
# The ampersand and the braces around the block make PowerShell run it as one piece.
# If Windows refuses to show a setting, some checks say ASK IT. Checks that read the registry
# cannot tell a hidden setting from a missing one, so they then say that no policy was found.
#
# Hide progress bars, so that the output is easy to copy. This applies only inside this block.
$ProgressPreference = 'SilentlyContinue'
# ------------------------------------------------------------
# Helper functions. They exist only while this block runs.
# ------------------------------------------------------------
# Row makes one line of the result table.
#   Check  = what was checked
#   Result = WORKS, ADMIN, ASK IT, TEST LATER or INFO
#   Detail = a short explanation
function Row($Check, $Result, $Detail) {
    1 | Select-Object @{n='Result';e={$Result}}, @{n='Check';e={$Check}}, @{n='Detail';e={$Detail}}
}
# Reg reads one value from the Windows registry.
# It returns nothing if the value does not exist or cannot be read.
function Reg($Path, $Name) {
    $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($item) { $item.$Name }
}
# Step shows which check is running, so that the window does not look stuck.
# The line appears on the screen only. It is not part of the result table.
function Step($Number, $Text) { Write-Host "[$Number/9] $Text" }
# IpNumber turns an IP address, such as 10.40.0.0, into one large number, so that it can be compared.
function IpNumber($Ip) {
    $p = $Ip -split '\.'
    ([long]$p[0] * 16777216) + ([long]$p[1] * 65536) + ([long]$p[2] * 256) + [long]$p[3]
}
# Overlaps tells whether two network ranges, such as 10.0.0.0/8 and 10.40.0.0/16, share addresses.
# It compares only the part that both ranges have in common.
# It ignores the default route, 0.0.0.0/0, because that route covers every address.
function Overlaps($A, $B) {
    $x = $A -split '/'
    $y = $B -split '/'
    $bits = [int]$x[1]
    if ([int]$y[1] -lt $bits) { $bits = [int]$y[1] }
    if ($bits -eq 0) { return $false }
    $size = [long]1 -shl (32 - $bits)
    $m = IpNumber $x[0]
    $n = IpNumber $y[0]
    ($m - ($m % $size)) -eq ($n - ($n % $size))
}
# ------------------------------------------------------------
# The checks. Each one adds one line to the table.
# ------------------------------------------------------------
$rows = & {
    # ----- Windows and the user -----
    # WINDOWS VERSION
    # Reads the edition, version, build number and processor type from the registry.
    # Windows 11 starts at build 22000.
    # The edition and version matter, because they decide the default rule for SMB signing.
    Step 1 'Windows version and user'
    $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int](Reg $cv 'CurrentBuildNumber')
    $about = "$(Reg $cv 'EditionID') $(Reg $cv 'DisplayVersion'), build $build, $env:PROCESSOR_ARCHITECTURE"
    if ($build -ge 22000) { Row 'Windows 11' 'WORKS' $about }
    else { Row 'Windows 11' 'ADMIN' "Not Windows 11: $about" }
    # USER
    # Checks whether the user belongs to the local Administrators group.
    # S-1-5-32-544 is the fixed ID of that group in every language of Windows.
    # This does not use the rights. It only reads the group list.
    $isAdmin = [bool](whoami /groups | Select-String -SimpleMatch 'S-1-5-32-544')
    if ($isAdmin) { Row 'User' 'INFO' 'Member of the local Administrators group.' }
    else { Row 'User' 'INFO' 'Standard user.' }
    # ----- AWS VPN Client -----
    # Looks for the folder where the client is installed.
    # If it is missing, a standard user gets ADMIN, because the installer adds a Windows service.
    Step 2 'AWS VPN Client and .NET Framework'
    if (Test-Path "$env:ProgramFiles\Amazon\AWS VPN Client") { Row 'AWS VPN Client' 'WORKS' 'Already installed.' }
    elseif ($isAdmin) { Row 'AWS VPN Client' 'WORKS' 'Not installed. This user should be able to install it.' }
    else { Row 'AWS VPN Client' 'ADMIN' 'Not installed.' }
    # NET FRAMEWORK
    # The client needs version 4.7.2 (release number 461808) on x64 processors,
    # and version 4.8.1 (release number 533320) on Arm64 processors.
    $need = 461808
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $need = 533320 }
    $release = [int](Reg 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' 'Release')
    if ($release -ge $need) { Row '.NET Framework' 'WORKS' "Release $release, needs $need." }
    else { Row '.NET Framework' 'ADMIN' "Release $release, needs $need." }
    # ----- Programs and scripts -----
    # APPLICATION CONTROL
    # PowerShell runs in a restricted mode when tools such as AppLocker or App Control for Business are enforced.
    # A restricted mode is a sign that the company may block the AWS VPN Client too.
    Step 3 'Programs and scripts'
    $mode = "$($ExecutionContext.SessionState.LanguageMode)"
    if ($mode -eq 'FullLanguage') { Row 'Application control' 'INFO' 'PowerShell is not restricted. Other programs may be.' }
    else { Row 'Application control' 'ASK IT' "PowerShell is restricted ($mode), so other programs may be blocked too." }
    # POWERSHELL SCRIPT
    # Reads whether script files may run. The share does not need the script, so this is only INFO.
    # This rule is about files, so it does not apply to a pasted block.
    $policy = "$(Get-ExecutionPolicy)"
    if ($policy -eq 'Restricted' -or $policy -eq 'AllSigned') { Row 'PowerShell script' 'INFO' "Blocked ($policy). Use net use instead." }
    else { Row 'PowerShell script' 'INFO' "Script policy is $policy." }
    # ----- Drive S: -----
    # FILE SHARING
    # The Workstation service is the part of Windows that connects to network drives.
    Step 4 'File sharing, signing and sign-in rules'
    $service = Get-Service LanmanWorkstation -ErrorAction SilentlyContinue
    if ("$($service.Status)" -eq 'Running') { Row 'File sharing' 'WORKS' 'The Workstation service is running.' }
    else { Row 'File sharing' 'ADMIN' 'The Workstation service is not running.' }
    # SMB SIGNING
    # Reads whether Windows requires every file-sharing connection to be signed.
    # Signing does not allow guest access, so a required value has to be proved with Check 2.
    # Do not turn signing off. It protects the PC.
    $smb = $null
    try { $smb = Get-SmbClientConfiguration -ErrorAction Stop } catch { }
    if (-not $smb) { Row 'SMB signing' 'ASK IT' 'Windows did not show this setting.' }
    elseif ($smb.RequireSecuritySignature) { Row 'SMB signing' 'TEST LATER' 'Required. Check 2 shows if the share works with it.' }
    else { Row 'SMB signing' 'WORKS' 'Not required.' }
    # NTLM SIGN-IN
    # The guest account is expected to sign in with NTLM, an older Windows sign-in method.
    # RestrictSendingNTLMTraffic = 2 means that the PC may not use NTLM to sign in to other computers.
    # BlockNTLM is the same kind of rule for file sharing only.
    # An administrator can add an exception for the gateway.
    $lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    if (((Reg "$lsa\MSV1_0" 'RestrictSendingNTLMTraffic') -eq 2) -or ($smb -and $smb.BlockNTLM)) { Row 'NTLM sign-in' 'ADMIN' 'Blocked. IT has to allow the gateway.' }
    else { Row 'NTLM sign-in' 'TEST LATER' 'No block found.' }
    # DRIVE LETTER
    # Any free letter works, so a taken letter is only INFO.
    if (Get-PSDrive -Name S -ErrorAction SilentlyContinue) { Row 'Drive letter S:' 'INFO' 'Taken. Use another letter.' }
    else { Row 'Drive letter S:' 'INFO' 'Free.' }
    # ----- Network -----
    # WINDOWS FIREWALL
    # Reads whether the firewall blocks all outgoing traffic by default.
    # It does not read single rules, and it cannot see other firewall products.
    # Check 2 tests the file-sharing port through the VPN.
    Step 5 'Windows Firewall'
    try {
        $blocked = Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop | Where-Object { "$($_.Enabled)" -eq 'True' -and "$($_.DefaultOutboundAction)" -eq 'Block' }
        if ($blocked) { Row 'Windows Firewall' 'ADMIN' "Blocks outgoing traffic by default: $($blocked.Name -join ', ')." }
        else { Row 'Windows Firewall' 'TEST LATER' 'Does not block outgoing traffic by default. Single rules are not checked.' }
    } catch { Row 'Windows Firewall' 'ASK IT' 'Windows did not show this setting.' }
    # TCP 443 TO AWS
    # The VPN connects to AWS on TCP port 443. This opens one connection to a public AWS address on that port.
    # It sends no files or settings from the PC. A failure can come from the PC, the company network or a proxy.
    Step 6 'TCP 443 to AWS (this can take 30 seconds if it is blocked)'
    $aws = 'ec2.us-east-1.amazonaws.com'
    if (Test-NetConnection $aws -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue) { Row 'TCP 443 to AWS' 'WORKS' 'Opened.' }
    else { Row 'TCP 443 to AWS' 'ASK IT' 'Blocked by the PC, the network or a proxy.' }
    Step 7 'TLS inspection (this can take 30 seconds if it is blocked)'
    try {
        # TLS INSPECTION
        # Opens a second connection and looks at who issued the certificate.
        # If it is not Amazon, a company device probably opens and reads encrypted traffic.
        # The VPN probably cannot pass through such a device, so IT may have to add an exception.
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($aws, 443)
        $ssl = New-Object System.Net.Security.SslStream -ArgumentList $client.GetStream()
        $ssl.AuthenticateAsClient($aws)
        if ($ssl.RemoteCertificate.Issuer -like '*Amazon*') { Row 'TLS inspection' 'TEST LATER' 'Not seen for this address.' }
        else { Row 'TLS inspection' 'ASK IT' 'Likely. The certificate is not from Amazon.' }
        $client.Close()
    } catch { Row 'TLS inspection' 'ASK IT' 'Could not be checked.' }
    # OTHER VPN OR WEB AGENT
    # Looks for running services of common VPN and web security products.
    # They can capture the traffic or not allow a second VPN.
    Step 8 'Other VPNs and web security agents'
    $agents = Get-Service -ErrorAction SilentlyContinue | Where-Object { "$($_.Status)" -eq 'Running' -and $_.DisplayName -notmatch 'AWS' -and $_.DisplayName -match 'VPN|Zscaler|GlobalProtect|AnyConnect|Cisco Secure|Forti|Netskope|Pulse Secure|Ivanti|Cloudflare|WireGuard' }
    if ($agents) { Row 'Other VPN or web agent' 'ASK IT' "Running: $($agents.DisplayName -join ', ')" }
    else { Row 'Other VPN or web agent' 'INFO' 'No common one found.' }
    # ADDRESS RANGES
    # 10.40.0.0/16 is the gateway's network, and 10.50.0.0/22 is the range for VPN users.
    # If the PC already has a route that covers them, traffic may go to the wrong place.
    # The ranges can also be changed in Terraform, without a Windows administrator.
    Step 9 'Address ranges'
    $clash = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { (Overlaps $_.DestinationPrefix '10.40.0.0/16') -or (Overlaps $_.DestinationPrefix '10.50.0.0/22') }
    if ($clash) { Row 'Address ranges' 'ASK IT' "Routes overlap: $(($clash.DestinationPrefix | Select-Object -Unique) -join ', ')" }
    else { Row 'Address ranges' 'WORKS' 'No overlap.' }
}
# ------------------------------------------------------------
# Show the table. Lines that need an administrator come first, and background information comes last.
# Nothing is saved to a file.
# ------------------------------------------------------------
Write-Host 'Done. The results are below.'
$rows | Sort-Object { @{ 'ADMIN' = 0; 'ASK IT' = 1; 'TEST LATER' = 2; 'WORKS' = 3; 'INFO' = 4 }[$_.Result] } | Format-Table Result, Check, Detail -AutoSize -Wrap | Out-String -Width 120
}
```

| Result | Meaning |
|---|---|
| `WORKS` | No problem was found. |
| `ADMIN` | A Windows administrator must install or change it. |
| `ASK IT` | IT or the network team must answer. |
| `TEST LATER` | No problem was found. Check 2 proves it. |
| `INFO` | Background only. |

The output has no password, user name or computer name, but it can name VPN and security programs, so treat it as internal. The check cannot see every policy, so `WORKS` can still fail.

## Check 2: Run after the gateway is deployed

First, [deploy the gateway again](docs/deployment.md), have IT install the AWS VPN Client, and [connect the VPN](docs/connect-windows.md).

This check maps drive S:, then writes, reads and deletes a test file. In a normal **Windows PowerShell** window, set the first two values, paste the block, and type the guest password when asked. Nothing shows while you type.

```powershell
# ============================================================
# CHECK 2: does the share work from this PC
# ============================================================
# Run it only after the gateway is deployed and the AWS VPN Client shows Connected.
# It connects drive S:, then writes, reads and deletes one small test file on the share.
# Windows asks for the guest password. The password is not stored in this block.
# Run it in a normal window, or File Explorer does not show drive S:.
#
# CHANGE THESE TWO LINES to the values of the new gateway:
# the private address of the gateway, and its gateway ID.
$GatewayAddress = '10.40.0.217'
$GatewayId = 'sgw-C712B1AF'
& {
    # STEP 1: can the PC reach the gateway?
    # TCP port 445 is the Windows file-sharing port. The connection goes through the VPN.
    # If it does not open, the block stops here and nothing is changed.
    Write-Host '[1/3] Connecting to the gateway. This can take 30 seconds if it is blocked.'
    if (-not (Test-NetConnection $GatewayAddress -Port 445 -InformationLevel Quiet -WarningAction SilentlyContinue)) { 'STOP: port 445 did not open.'; return }
    'WORKS: port 445 opened.'
    # STEP 2: connect drive S:
    # The user name is the gateway ID, a backslash and smbguest.
    # /persistent:yes makes Windows connect the drive again after a restart.
    # This is the only change to the PC. To undo it, run: net use S: /delete
    Write-Host '[2/3] Connecting drive S:. Type the guest password when asked.'
    net use S: "\\$GatewayAddress\cur" /user:"$GatewayId\smbguest" /persistent:yes
    # LASTEXITCODE is 0 when net use worked. On an error, Windows shows a number such as 53 or 1326.
    if ($LASTEXITCODE -ne 0) { 'STOP: drive S: was not mapped. Look up the error number below.'; return }
    'WORKS: drive S: is mapped.'
    # STEP 3: can the user write, read and delete a file?
    # The test file holds only the word test. It is deleted at the end.
    # S3 keeps an old version of the deleted file for 30 days.
    Write-Host '[3/3] Writing, reading and deleting a test file.'
    $file = 'S:\windows-check.txt'
    try {
        'test' | Set-Content $file -ErrorAction Stop
        if ((Get-Content $file -ErrorAction Stop) -eq 'test') { 'WORKS: a file was written and read.' }
        Remove-Item $file -ErrorAction Stop
        'WORKS: the file was deleted.'
    } catch { "STOP: $($_.Exception.Message)" }
}
```

| What you see | Likely cause | Who acts |
|---|---|---|
| Port 445 did not open | VPN, firewall, or another VPN | User checks the VPN, then IT |
| Error 5 | Access denied | Person who deployed the gateway |
| Error 53 | Gateway not found, or blocked | User checks the VPN, then IT |
| Error 85 | Letter S: is taken | User picks another letter |
| Error 1272 | Windows blocked the sign-in as a guest logon | Stop and record it. Do not weaken the PC's security. |
| Error 1326 | Wrong user name or password, or NTLM is blocked | User, then IT |
| Any other error | Unknown | Record the number and message |

Use **sample files only**. The proof of concept is not secure enough for real data. To undo this check, run `net use S: /delete`.

## Ask IT

1. Will you install the AWS VPN Client? AWS offers an [`.msi` installer](https://aws.amazon.com/vpn/client-vpn-download/) for x64 and Arm64, and [lists the programs to allow](https://docs.aws.amazon.com/vpn/latest/clientvpn-user/client-vpn-connect-endpoint-security.html).
2. May it connect to AWS on TCP port 443, without TLS inspection and next to a company VPN?
3. May the PC use TCP port 445 through that VPN, with NTLM sign-in?
4. Does data loss prevention block saving to this share?

## Biggest unknown: guest sign-in

Windows 11 24H2 Enterprise, Pro and Education [require SMB signing](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing), which does not allow guest access. The share should still work, because `smbguest` has a password and the Mac's session was encrypted, which [Microsoft says guest logons do not support](https://learn.microsoft.com/en-us/windows-server/storage/file-server/enable-insecure-guest-logons-smb2-and-smb3). Check 2 tests this.

If it fails, do not turn off signing or turn on insecure guest logons. Use each person's own account, as in the [production design](docs/production.md).

## If IT does not install the client

| Alternative | Needs | Limit |
|---|---|---|
| Site-to-Site VPN or Direct Connect | The network team and the [production design](docs/production.md), which is not built | None on the PC, if policy allows the share |
| Download, edit and upload with the AWS CLI | An AWS sign-in with access to the bucket | Not a network drive. Users cannot save in place, and can overwrite each other. |

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](LICENSE) and the [disclaimers](DISCLAIMER.md)._
