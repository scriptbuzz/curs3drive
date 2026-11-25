# curs3drive on a Windows 11 Production PC

_DRAFT - For internal use only. Last modified: 2026-11-25 12:38 EST by mbitar._

**curs3drive** ([scriptbuzz/curs3drive](https://github.com/scriptbuzz/curs3drive)) is a proof of concept that makes an Amazon S3 bucket work like a Windows network drive, so people can open, edit and save large Cost and Usage Report (CUR) files. It uses **Amazon S3 File Gateway**, one type of AWS Storage Gateway, which runs on an EC2 instance and shares the bucket over SMB, the Windows file-sharing protocol. The PC connects with the AWS VPN Client and maps the share as drive S:. The gateway uploads every save to S3. It has been tested only from a Mac, and its AWS parts were removed on 23 November 2026.

This page answers two questions: can curs3drive run on a production Windows 11 PC, and what needs a Windows administrator password?

[Back to the README](README.md)

## Answer so far

**Probably yes, if IT installs the AWS VPN Client.** This comes from the code and vendor documentation. Nothing has been run on Windows. The PC's policies and network decide, so run option 1 of the [test script](#test-script), after IT agrees.

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

## For IT: steps that may trigger security tools

**Show this section to IT or the security team before anyone runs the script.** Security tools may treat these steps as suspicious, because attackers use similar ones. Each marked step shows `[MAY ALERT]` on the screen.

| Option and step | What the script does | Why a security tool may react |
|---|---|---|
| All | Runs a long block of text pasted into PowerShell | PowerShell logging may record the block and raise an alert |
| 1, step 2 | Runs `whoami /groups` | It lists the user's groups |
| 1, step 4 | Reads the AppLocker and App Control rules | It looks for security controls |
| 1, step 6 | Reads the SMB signing and NTLM settings | It looks for weak sign-in settings |
| 1, step 7 | Reads the Windows Firewall profiles | It looks for security controls |
| 1, steps 8 and 9 | Opens two connections to ec2.us-east-1.amazonaws.com on TCP port 443, and pings it if the first one fails | PowerShell connects directly to the internet |
| 1, step 10 | Lists Windows services and looks for VPN and security products | It looks for security software |
| 1, step 11 | Reads the network routes | It looks for internal networks |
| 2, steps 1 and 2 | Reads the route and the network adapter, tests TCP port 445 on the gateway, and pings it if that fails | It can look like a network scan |
| 2, step 3 | Runs `net use` with a shared user name and password | It can look like an attacker moving to another computer |
| 2, steps 4 and 5 | Writes, reads and deletes one text file on the share | Data loss prevention may block or report it |
| 3, step 2 | Deletes a `.ovpn` file from Downloads, after a question | It can look like removing evidence |

- **Not part of the script:** Installing the AWS VPN Client and connecting it next to a company VPN may also raise alerts.
- **Skipping:** Answer `N` to the first question of option 1 to skip its marked steps. Option 2 does not start without a yes.
- **What the script never does:** It does not ask for administrator rights, download a program, turn off a security setting, read stored passwords, or send the results anywhere.
- **If an alert appears or a step is blocked:** Stop, tell IT, and do not try another way.

Message to IT:

> I plan to run the curs3drive test script in Windows PowerShell, as a standard user, on PC [name] on [date and time]. It may trigger the alerts listed on the page "curs3drive on a Windows 11 Production PC". May I run option 1 and option 2?

## Test script

One script shows a menu. Each step shows a progress bar and its status, and each option ends with a result.

| Option | What it does | What it changes |
|---|---|---|
| 1 | Checks this PC | Nothing |
| 2 | Tests drive S: | It connects a drive, uses one test file, and disconnects the drive |
| 3 | Cleans up | It asks before it disconnects or deletes anything |

The script has not been run on Windows. Read it first, and follow company rules on pasting commands.

1. Get IT's agreement, as described above.
2. For option 1, disconnect the AWS VPN Client if it is installed. For option 2, [deploy the gateway again](docs/deployment.md), have IT install the client, and [connect the VPN](docs/connect-windows.md).
3. Open **Windows PowerShell** as the normal user, not with **Run as administrator**.
4. Paste the whole block, press Enter, and type the number of an option.
5. After option 1, copy only the table. Remove anything private, and share it only where company rules allow. An error message can show your Windows user name.

```powershell
& {
# ============================================================
# curs3drive TEST SCRIPT for a production Windows 11 PC
# ============================================================
# The script shows a menu: 1 checks this PC, 2 tests drive S:, 3 cleans up, and Q quits.
# It never asks for an administrator password, and it changes no Windows security setting.
# It stores no password and saves no report. Steps marked [MAY ALERT] can trigger security tools.
# The ampersand and the braces around the script make PowerShell run it as one piece.
# Press Ctrl+C to stop at any time. If option 2 was running, then run option 3.
#
# Hide the progress bars of Windows commands. The script shows its own progress.
$ProgressPreference = 'SilentlyContinue'
# ------------------------------------------------------------
# Helper functions. They exist only while the script runs.
# ------------------------------------------------------------
# Ask shows a question and returns the answer without spaces around it.
function Ask($Question) { "$(Read-Host $Question)".Trim() }
# Yes shows a question until the answer is Y or N. It returns true for Y.
function Yes($Question) {
    do { $reply = Ask "$Question (Y/N)" } until ($reply -match '^[YyNn]$')
    $reply -match '^[Yy]$'
}
# Step shows a progress bar, the step number and what the step does.
function Step($Number, $Total, $Text) {
    $bar = ('#' * $Number) + ('-' * ($Total - $Number))
    Write-Host "[$bar] Step $Number of $Total - $Text" -ForegroundColor Cyan
}
# Status shows the result of a step at once: green is good, red stops the test, yellow needs action.
function Status($Result, $Check, $Detail) {
    $color = 'Gray'
    if ($Result -eq 'WORKS' -or $Result -eq 'DONE') { $color = 'Green' }
    if ($Result -eq 'STOP') { $color = 'Red' }
    if ($Result -eq 'WINDOWS ADMIN' -or $Result -eq 'ASK IT' -or $Result -eq 'TO DO' -or $Result -eq 'SKIPPED') { $color = 'Yellow' }
    Write-Host "    $Result - ${Check}: $Detail" -ForegroundColor $color
}
# Row shows the result of a step and keeps it as one line for the table at the end of option 1.
function Row($Check, $Result, $Detail) {
    Status $Result $Check $Detail
    1 | Select-Object @{n='Result';e={$Result}}, @{n='Check';e={$Check}}, @{n='Detail';e={$Detail}}
}
# Skip keeps a line for a step that IT has not agreed to yet.
function Skip($Check) { Row $Check 'SKIPPED' 'IT has not agreed to this step yet.' }
# Reg reads one value from the Windows registry.
# It returns nothing if the value does not exist or cannot be read.
function Reg($Path, $Name) {
    $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($item) { $item.$Name }
}
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
# PrivateIp tells whether the text is an IP address that is used only inside private networks.
function PrivateIp($Ip) {
    if ($Ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return $false }
    foreach ($part in ($Ip -split '\.')) { if ([int]$part -gt 255) { return $false } }
    $Ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'
}
# ============================================================
# OPTION 1: CHECK THIS PC
# ============================================================
# This option only reads settings. It does not install, change or delete anything.
# It makes two short connections to a public AWS address, to test the network.
# If Windows refuses to show a setting, some steps say ASK IT. Steps that read the registry
# cannot tell a hidden setting from a missing one, so they then say that no policy was found.
function CheckPc {
    Write-Host 'This option only reads settings. Steps marked [MAY ALERT] can trigger security tools.'
    $agreed = Yes 'Has IT or the security team agreed to the steps marked [MAY ALERT]? N skips them.'
    $rows = & {
        # ----- Windows and the user -----
        # WINDOWS VERSION
        # Reads the edition, version, build number and processor type from the registry.
        # Windows 11 starts at build 22000.
        # The edition and version matter, because they decide the default rule for SMB signing.
        Step 1 11 'Windows version'
        $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $build = [int](Reg $cv 'CurrentBuildNumber')
        $about = "$(Reg $cv 'EditionID') $(Reg $cv 'DisplayVersion'), build $build, $env:PROCESSOR_ARCHITECTURE"
        if ($build -ge 22000) { Row 'Windows 11' 'WORKS' $about }
        else { Row 'Windows 11' 'WINDOWS ADMIN' "Not Windows 11: $about" }
        # USER
        # Checks whether the user belongs to the local Administrators group.
        # S-1-5-32-544 is the fixed ID of that group in every language of Windows.
        # This does not use the rights. It only reads the group list.
        Step 2 11 'User rights [MAY ALERT]'
        $isAdmin = $false
        if ($agreed) {
            $isAdmin = [bool](whoami /groups | Select-String -SimpleMatch 'S-1-5-32-544')
            if ($isAdmin) { Row 'User' 'INFO' 'Member of the local Administrators group.' }
            else { Row 'User' 'INFO' 'Standard user.' }
        } else { Skip 'User' }
        # ----- AWS VPN Client -----
        # Looks for the client in the list of installed programs, and then in its folder.
        # Version 6.3.1 is the version this page was written for. Versions 4.1.0 and 5.0.0 to 5.2.1
        # have a known flaw that can give a standard user administrator rights during installation.
        # If it is missing, a standard user gets WINDOWS ADMIN, because the installer adds a Windows service.
        Step 3 11 'AWS VPN Client and .NET Framework'
        $vpn = $null
        try {
            $programs = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            $vpn = @(Get-ItemProperty -Path $programs -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'AWS*VPN Client*' })[0]
        } catch { }
        $found = [bool]$vpn -or (Test-Path "$env:ProgramFiles\Amazon\AWS VPN Client")
        $current = $null
        try { $current = ([version]"$($vpn.DisplayVersion)") -ge ([version]'6.3.1') } catch { }
        if ($found -and $current) { Row 'AWS VPN Client' 'WORKS' "Version $($vpn.DisplayVersion) is installed." }
        elseif ($found -and $current -eq $false) { Row 'AWS VPN Client' 'WINDOWS ADMIN' "Version $($vpn.DisplayVersion) is too old. It needs 6.3.1 or newer." }
        elseif ($found) { Row 'AWS VPN Client' 'ASK IT' 'Installed, but the version was not found. It needs 6.3.1 or newer.' }
        elseif ($isAdmin) { Row 'AWS VPN Client' 'WORKS' 'Not installed. This user should be able to install it.' }
        else { Row 'AWS VPN Client' 'WINDOWS ADMIN' 'Not installed.' }
        # NET FRAMEWORK
        # The client needs version 4.7.2 (release number 461808) on x64 processors,
        # and version 4.8.1 (release number 533320) on Arm64 processors.
        $need = 461808
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $need = 533320 }
        $release = [int](Reg 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' 'Release')
        if ($release -ge $need) { Row '.NET Framework' 'WORKS' "Release $release, needs $need." }
        else { Row '.NET Framework' 'WINDOWS ADMIN' "Release $release, needs $need." }
        # ----- Programs and scripts -----
        # APPLICATION CONTROL
        # PowerShell runs in a restricted mode when tools such as AppLocker or App Control for Business are enforced.
        # A restricted mode is a sign that the company may block the AWS VPN Client too.
        # AppLocker and App Control decide which programs may run. A rule group of AppLocker is enforced
        # if it is Enabled, or if it has rules and no mode is set.
        # A rule that cannot be read counts as ASK IT, never as a pass.
        Step 4 11 'Application control [MAY ALERT]'
        if ($agreed) {
            $control = @()
            $unknown = @()
            $mode = "$($ExecutionContext.SessionState.LanguageMode)"
            if ($mode -ne 'FullLanguage') { $control += "PowerShell is restricted ($mode)" }
            try {
                [xml]$al = Get-AppLockerPolicy -Effective -Xml -ErrorAction Stop
                foreach ($c in @($al.AppLockerPolicy.RuleCollection)) {
                    $on = ($c.EnforcementMode -eq 'Enabled') -or (($c.EnforcementMode -eq 'NotConfigured') -and ($c.ChildNodes.Count -gt 0))
                    if ($on -and ($c.Type -eq 'Exe' -or $c.Type -eq 'Dll')) { $control += "AppLocker $($c.Type) rules are enforced" }
                }
            } catch { $unknown += 'AppLocker' }
            try {
                $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
                if ($dg.UsermodeCodeIntegrityPolicyEnforcementStatus -eq 2) { $control += 'App Control is enforced' }
            } catch { $unknown += 'App Control' }
            if ($control.Count) { Row 'Application control' 'ASK IT' "$($control -join '; '). Is the AWS VPN Client allowed?" }
            elseif ($unknown.Count) { Row 'Application control' 'ASK IT' "This could not be read: $($unknown -join ', ')." }
            else { Row 'Application control' 'WORKS' 'No enforced AppLocker program rules or App Control were found.' }
        } else { Skip 'Application control' }
        # POWERSHELL SCRIPT FILES
        # Reads whether script files may run. The share does not need a script file, so this is only INFO.
        # FILE SHARING
        # The Workstation service is the part of Windows that connects to network drives.
        # DRIVE LETTER
        # Any free letter works, so a taken letter is only INFO.
        Step 5 11 'Script files, file sharing and drive letter'
        $policy = "$(Get-ExecutionPolicy)"
        Row 'PowerShell script files' 'INFO' "The policy is $policy. The share does not need script files."
        $service = Get-Service LanmanWorkstation -ErrorAction SilentlyContinue
        if ("$($service.Status)" -eq 'Running') { Row 'File sharing' 'WORKS' 'The Workstation service is running.' }
        else { Row 'File sharing' 'WINDOWS ADMIN' 'The Workstation service is not running.' }
        if (Get-PSDrive -Name S -ErrorAction SilentlyContinue) { Row 'Drive letter S:' 'INFO' 'Taken. Use another letter.' }
        else { Row 'Drive letter S:' 'INFO' 'Free.' }
        # ----- Drive S: -----
        # SMB SIGNING
        # Reads whether Windows requires every file-sharing connection to be signed.
        # Signing does not allow guest access, so a required value has to be proved with option 2.
        # Do not turn signing off. It protects the PC.
        # NTLM SIGN-IN
        # The guest account is expected to sign in with NTLM, an older Windows sign-in method.
        # RestrictSendingNTLMTraffic = 2 means that the PC may not use NTLM to sign in to other computers.
        # BlockNTLM is the same kind of rule for file sharing only.
        # Only IT can decide whether to allow the gateway as an exception.
        Step 6 11 'SMB signing and NTLM sign-in [MAY ALERT]'
        if ($agreed) {
            $smb = $null
            try { $smb = Get-SmbClientConfiguration -ErrorAction Stop } catch { }
            if (-not $smb) { Row 'SMB signing' 'ASK IT' 'Windows did not show this setting.' }
            elseif ($smb.RequireSecuritySignature) { Row 'SMB signing' 'TEST LATER' 'Required. Option 2 shows if the share works with it.' }
            else { Row 'SMB signing' 'INFO' 'Not required. The share does not need a change.' }
            $lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
            if (((Reg "$lsa\MSV1_0" 'RestrictSendingNTLMTraffic') -eq 2) -or ($smb -and $smb.BlockNTLM)) { Row 'NTLM sign-in' 'WINDOWS ADMIN' 'Blocked. IT decides whether to allow the gateway.' }
            else { Row 'NTLM sign-in' 'TEST LATER' 'No block found.' }
        } else {
            Skip 'SMB signing'
            Skip 'NTLM sign-in'
        }
        # ----- Network -----
        # WINDOWS FIREWALL
        # Reads whether the firewall blocks all outgoing traffic by default.
        # It does not read single rules, and it cannot see other firewall products.
        # Option 2 tests the file-sharing port through the VPN.
        Step 7 11 'Windows Firewall [MAY ALERT]'
        if ($agreed) {
            try {
                $blocked = Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop | Where-Object { "$($_.Enabled)" -eq 'True' -and "$($_.DefaultOutboundAction)" -eq 'Block' }
                if ($blocked) { Row 'Windows Firewall' 'WINDOWS ADMIN' "Blocks outgoing traffic by default: $($blocked.Name -join ', ')." }
                else { Row 'Windows Firewall' 'TEST LATER' 'Does not block outgoing traffic by default. Single rules are not checked.' }
            } catch { Row 'Windows Firewall' 'ASK IT' 'Windows did not show this setting.' }
        } else { Skip 'Windows Firewall' }
        # TCP 443 TO AWS
        # The VPN connects to AWS on TCP port 443. This opens one connection to a public AWS address on that port.
        # It sends no files or settings from the PC. A failure can come from the PC, the company network or a proxy.
        $aws = 'ec2.us-east-1.amazonaws.com'
        Step 8 11 'TCP 443 to AWS, up to 30 seconds [MAY ALERT]'
        if ($agreed) {
            if (Test-NetConnection $aws -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue) { Row 'TCP 443 to AWS' 'WORKS' 'Opened.' }
            else { Row 'TCP 443 to AWS' 'ASK IT' 'Blocked by the PC, the network or a proxy.' }
        } else { Skip 'TCP 443 to AWS' }
        # TLS INSPECTION
        # Opens a second connection and looks at who issued the certificate.
        # If it is not Amazon, a company device probably opens and reads encrypted traffic.
        # The VPN probably cannot pass through such a device. Only IT can decide on an exception.
        Step 9 11 'TLS inspection, up to 30 seconds [MAY ALERT]'
        if ($agreed) {
            try {
                $client = New-Object System.Net.Sockets.TcpClient
                $client.Connect($aws, 443)
                $ssl = New-Object System.Net.Security.SslStream -ArgumentList $client.GetStream()
                $ssl.AuthenticateAsClient($aws)
                if ($ssl.RemoteCertificate.Issuer -like '*Amazon*') { Row 'TLS inspection' 'TEST LATER' 'Not seen for this address.' }
                else { Row 'TLS inspection' 'ASK IT' 'Likely. The certificate is not from Amazon.' }
                $client.Close()
            } catch { Row 'TLS inspection' 'ASK IT' 'Could not be checked.' }
        } else { Skip 'TLS inspection' }
        # OTHER VPN OR WEB AGENT
        # Looks for running services of common VPN and web security products.
        # They can capture the traffic or not allow a second VPN.
        Step 10 11 'Other VPNs and web security agents [MAY ALERT]'
        if ($agreed) {
            $agents = Get-Service -ErrorAction SilentlyContinue | Where-Object { "$($_.Status)" -eq 'Running' -and $_.DisplayName -notmatch 'AWS' -and $_.DisplayName -match 'VPN|Zscaler|GlobalProtect|AnyConnect|Cisco Secure|Forti|Netskope|Pulse Secure|Ivanti|Cloudflare|WireGuard' }
            if ($agents) { Row 'Other VPN or web agent' 'ASK IT' "Running: $($agents.DisplayName -join ', ')" }
            else { Row 'Other VPN or web agent' 'INFO' 'No common one found.' }
        } else { Skip 'Other VPN or web agent' }
        # ADDRESS RANGES
        # 10.40.0.0/16 is the gateway's network, and 10.50.0.0/22 is the range for VPN users.
        # If the PC already has a route that covers them, traffic may go to the wrong place.
        # The ranges can also be changed in Terraform, without a Windows administrator.
        Step 11 11 'Address ranges [MAY ALERT]'
        if ($agreed) {
            $clash = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { (Overlaps $_.DestinationPrefix '10.40.0.0/16') -or (Overlaps $_.DestinationPrefix '10.50.0.0/22') }
            if ($clash) { Row 'Address ranges' 'ASK IT' "Routes overlap: $(($clash.DestinationPrefix | Select-Object -Unique) -join ', ')" }
            else { Row 'Address ranges' 'WORKS' 'No overlap.' }
        } else { Skip 'Address ranges' }
    }
    # THE ANSWER FOR DRIVE S:
    # The most serious result above decides it.
    $admin = @($rows | Where-Object { $_.Result -eq 'WINDOWS ADMIN' } | ForEach-Object { $_.Check })
    $askit = @($rows | Where-Object { $_.Result -eq 'ASK IT' } | ForEach-Object { $_.Check })
    $skipped = @($rows | Where-Object { $_.Result -eq 'SKIPPED' })
    Write-Host "Finished: $(@($rows).Count) results, $($admin.Count) WINDOWS ADMIN, $($askit.Count) ASK IT, $($skipped.Count) SKIPPED."
    $answer = if ($admin.Count) { Row '==> Drive S:' 'WINDOWS ADMIN' "An administrator must act on: $($admin -join ', ')." }
    elseif ($askit.Count) { Row '==> Drive S:' 'ASK IT' "IT must answer about: $($askit -join ', ')." }
    elseif ($skipped.Count) { Row '==> Drive S:' 'ASK IT' 'IT must first agree to the skipped steps.' }
    else { Row '==> Drive S:' 'TEST LATER' 'No blocker was found. Option 2 shows if it works.' }
    # Show the table. Lines that need an administrator come first, and the answer (==>) comes last.
    # Nothing is saved to a file.
    $order = @{ 'WINDOWS ADMIN' = 0; 'ASK IT' = 1; 'SKIPPED' = 2; 'TEST LATER' = 3; 'WORKS' = 4; 'INFO' = 5 }
    $table = @($rows) + @($answer) | Sort-Object { if ($_.Check -like '==>*') { 9 } else { $order[$_.Result] } }, { $_.Check } | Format-Table Result, Check, Detail -AutoSize -Wrap | Out-String -Width 120
    Write-Host $table
    Write-Host 'Copy only this table. It can name internal networks and security settings, so treat it as internal.'
}
# ============================================================
# OPTION 2: TEST DRIVE S:
# ============================================================
# Run it only after the gateway is deployed and the AWS VPN Client shows Connected.
# It connects a drive, writes, reads and deletes one small test file, and disconnects the drive.
# Windows asks for the guest password. The script does not read or store the password.
function TestDrive {
    Write-Host 'This option connects the gateway share, uses one small test file, and disconnects the share.'
    Write-Host 'Steps marked [MAY ALERT] can trigger security tools. You can leave at the first question.'
    if (-not (Yes 'Has IT agreed to this test, and does the AWS VPN Client show Connected?')) { Write-Host 'Nothing was changed.'; return }
    # THE VALUES OF THE GATEWAY
    # The person who deployed the gateway knows both values. The script has no old values in it,
    # so that the PC never signs in to a computer that only has the address of a deleted gateway.
    do { $address = Ask 'Private address of the gateway, or Q to go back' } until ($address -eq 'Q' -or (PrivateIp $address))
    if ($address -eq 'Q') { Write-Host 'Nothing was changed.'; return }
    do { $gateway = Ask 'Gateway ID, which starts with sgw-, or Q to go back' } until ($gateway -eq 'Q' -or $gateway -match '^sgw-[0-9A-Fa-f]{8,17}$')
    if ($gateway -eq 'Q') { Write-Host 'Nothing was changed.'; return }
    do {
        $letter = Ask 'Free drive letter, or Enter for S'
        if ($letter -eq '') { $letter = 'S' }
        $free = ($letter -match '^[D-Zd-z]$') -and -not (Get-PSDrive -Name $letter -ErrorAction SilentlyContinue)
        if (-not $free) { Write-Host 'That letter is taken or not valid.' }
    } until ($free)
    $mapped = $false
    $passed = $false
    $file = ''
    try {
        # STEP 1: does the traffic go through the VPN?
        # Windows shows the network adapter that it uses for the address.
        # The default route means that the VPN is not connected, so the test stops before any sign-in.
        Step 1 6 'Route to the gateway [MAY ALERT]'
        $route = @(Find-NetRoute -RemoteIPAddress $address -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix })[0]
        $bits = 0
        if ($route) { $bits = [int](($route.DestinationPrefix -split '/')[1]) }
        if ($bits -lt 8) { Status 'STOP' 'Route' 'The address is not reached through the VPN. Connect the AWS VPN Client.'; return }
        $adapter = "$($route.InterfaceAlias)"
        $card = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
        if ($card) { $adapter = "$adapter, $($card.InterfaceDescription)" }
        if (-not (Yes "Windows will use this network adapter: $adapter. Is it the AWS VPN Client?")) { Status 'STOP' 'Route' 'The traffic would not go through the AWS VPN Client.'; return }
        Status 'WORKS' 'Route' 'You confirmed the AWS VPN Client adapter.'
        # STEP 2: can the PC reach the gateway?
        # TCP port 445 is the Windows file-sharing port.
        Step 2 6 'TCP port 445, up to 30 seconds [MAY ALERT]'
        if (-not (Test-NetConnection $address -Port 445 -InformationLevel Quiet -WarningAction SilentlyContinue)) { Status 'STOP' 'Port 445' 'It did not open.'; return }
        Status 'WORKS' 'Port 445' 'It opened.'
        # STEP 3: connect the drive
        # The user name is the gateway ID, a backslash and smbguest.
        # /requireprivacy makes Windows refuse a connection that is not encrypted.
        # /persistent:no stops Windows from connecting the drive again after a restart.
        # LASTEXITCODE is 0 when net use worked. On an error, Windows shows a number such as 53 or 1326.
        Step 3 6 'Connect the drive [MAY ALERT]'
        Write-Host '    Type the guest password when Windows asks. Nothing shows while you type.'
        net use "${letter}:" "\\$address\cur" "/user:$gateway\smbguest" /requireprivacy /persistent:no
        if ($LASTEXITCODE -ne 0) { Status 'STOP' 'Drive' 'It was not connected. Look up the error number on this page.'; return }
        $mapped = $true
        Status 'WORKS' 'Drive' "${letter}: is connected, and Windows requires encryption."
        # STEPS 4 AND 5: can the user write, read and delete a file?
        # The test file holds only the word test. Its name has the date and time, so it replaces no other file.
        # S3 keeps an old version of the deleted file for 30 days.
        $file = "${letter}:\curs3drive-check-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
        try {
            Step 4 6 'Write and read a test file [MAY ALERT]'
            'test' | Set-Content $file -ErrorAction Stop
            if ((Get-Content $file -ErrorAction Stop) -ne 'test') { Status 'STOP' 'Test file' 'The text that was read is different.'; return }
            Status 'WORKS' 'Test file' 'It was written and read.'
            Step 5 6 'Delete the test file [MAY ALERT]'
            Remove-Item $file -ErrorAction Stop
            Status 'WORKS' 'Test file' 'It was deleted.'
            $passed = $true
        } catch { Status 'STOP' 'Test file' "$($_.Exception.Message)" }
        $null = Read-Host "Open ${letter}: in File Explorer if you want to see it, then close it. Press Enter here to disconnect"
    } finally {
        # STEP 6: disconnect the drive
        # This runs even if an earlier step stopped, but only if this script connected the drive.
        # If the test file is still there, the script first tries to delete it once more.
        Step 6 6 'Disconnect the drive'
        if ($mapped) {
            if ($file -and (Test-Path $file)) { Remove-Item $file -ErrorAction SilentlyContinue }
            if ($file -and (Test-Path $file)) { Status 'TO DO' 'Test file' "Ask the person who deployed the gateway to delete $file." }
            net use "${letter}:" /delete
            if ($LASTEXITCODE -eq 0) { Status 'DONE' 'Drive' "${letter}: is disconnected." }
            else { Status 'TO DO' 'Drive' 'It is still connected. Run option 3.' }
        } else { Status 'DONE' 'Drive' 'It was not connected.' }
        if ($passed) { Write-Host 'RESULT: the drive works from this PC. Now run option 3 to clean up.' -ForegroundColor Green }
        else { Write-Host 'RESULT: the test stopped. Copy the STOP line and any error number, then run option 3.' -ForegroundColor Red }
    }
}
# ============================================================
# OPTION 3: CLEAN UP
# ============================================================
# It asks before every change. It removes only curs3drive test files, drives and profile files.
function CleanUp {
    $todo = 0
    # STEP 1: test files and drives
    # Looks for connected drives whose share is called cur at an IP address, which is how option 2 connects.
    # Check the address in the question, because another share can have the same name.
    Step 1 5 'Test files and drives'
    $maps = @(Get-SmbMapping -ErrorAction SilentlyContinue | Where-Object { $_.RemotePath -match '^\\\\[0-9.]+\\cur$' })
    if (-not $maps.Count) { Status 'DONE' 'Drive' 'No gateway drive is connected.' }
    foreach ($map in $maps) {
        $name = "$($map.LocalPath)"
        if ($name -eq '') { $name = "$($map.RemotePath)" }
        $left = @()
        if ("$($map.Status)" -eq 'OK') { $left = @(Get-ChildItem "$($map.RemotePath)\curs3drive-check-*.txt" -ErrorAction SilentlyContinue) }
        foreach ($item in $left) {
            if (Yes "Delete the test file $($item.Name) on $($map.RemotePath)?") { Remove-Item $item.FullName -ErrorAction SilentlyContinue }
            if (Test-Path $item.FullName) { Status 'TO DO' 'Test file' "$($item.Name) is still there."; $todo += 1 }
            else { Status 'DONE' 'Test file' "$($item.Name) was deleted." }
        }
        $gone = $false
        if (Yes "Disconnect $name, which is $($map.RemotePath)?") {
            net use $name /delete
            $gone = ($LASTEXITCODE -eq 0)
        }
        if ($gone) { Status 'DONE' 'Drive' "$name is disconnected." }
        else { Status 'TO DO' 'Drive' "$name is still connected."; $todo += 1 }
    }
    # STEP 2: the VPN profile file in the Downloads folder
    # The file holds a private key, so anyone who copies it can try to connect to the VPN.
    # The script looks only in Downloads, and only for the name that curs3drive uses.
    Step 2 5 'VPN profile file in Downloads [MAY ALERT]'
    $files = @(Get-ChildItem "$HOME\Downloads\cur-file-gateway*.ovpn" -ErrorAction SilentlyContinue)
    if (-not $files.Count) { Status 'DONE' 'Profile file' 'None was found in Downloads.' }
    foreach ($item in $files) {
        if (Yes "Delete $($item.Name) from Downloads for good?") { Remove-Item $item.FullName -ErrorAction SilentlyContinue }
        if (Test-Path $item.FullName) { Status 'TO DO' 'Profile file' "$($item.Name) is still there."; $todo += 1 }
        else { Status 'DONE' 'Profile file' "$($item.Name) was deleted." }
    }
    # STEPS 3 TO 5: things that only a person can do
    # The script asks, so that nothing is forgotten. It does not change anything here.
    Step 3 5 'VPN client'
    if (Yes 'Is the VPN disconnected, and is the profile removed from the AWS VPN Client?') { Status 'DONE' 'VPN profile' 'You confirmed it.' }
    else { Status 'TO DO' 'VPN profile' 'Disconnect, then delete the profile in the AWS VPN Client.'; $todo += 1 }
    Step 4 5 'Other copies'
    if (Yes 'Did you delete every other copy of the profile and the guest password, for example in mail, Teams and the Recycle Bin?') { Status 'DONE' 'Copies' 'You confirmed it.' }
    else { Status 'TO DO' 'Copies' 'Delete them.'; $todo += 1 }
    Step 5 5 'IT'
    if (Yes 'Does IT know that the test is over, so that it can remove the client and any exceptions?') { Status 'DONE' 'IT' 'You confirmed it.' }
    else { Status 'TO DO' 'IT' 'Tell IT when all tests are finished.'; $todo += 1 }
    if ($todo) { Write-Host "RESULT: $todo cleanup items are left. Run option 3 again when they are done." -ForegroundColor Yellow }
    else { Write-Host 'RESULT: the cleanup of this PC is complete.' -ForegroundColor Green }
}
# ============================================================
# THE MENU
# ============================================================
# It comes back after every option, until the answer is Q.
$run = $true
while ($run) {
    Write-Host '------------------------------------------------------------'
    Write-Host 'curs3drive test script'
    Write-Host '  1 = Check this PC (reads settings only, about one minute)'
    Write-Host '  2 = Test drive S: (needs the gateway and the VPN)'
    Write-Host '  3 = Clean up'
    Write-Host '  Q = Quit'
    switch (Ask 'Type 1, 2, 3 or Q') {
        '1' { CheckPc }
        '2' { TestDrive }
        '3' { CleanUp }
        'Q' { $run = $false }
        default { Write-Host 'Please type 1, 2, 3 or Q.' }
    }
}
Write-Host 'The script has ended.'
}
```

### Results

| Result | Meaning |
|---|---|
| `WORKS` | No problem was found. |
| `WINDOWS ADMIN` | A Windows administrator must install or change it. |
| `ASK IT` | A company rule may block it, or the check could not tell. IT or the network team must answer. |
| `SKIPPED` | IT has not agreed to this step yet. |
| `TEST LATER` | No problem was found. Option 2 shows if it works. |
| `INFO` | Background only. |
| `STOP` | The test ended at this step. |
| `DONE` or `TO DO` | A cleanup step is finished, or a person still has to do it. |

The option 1 table has no password, user name or computer name. It can name security programs, internal network ranges and security settings, so treat it as internal. The check cannot see every policy, so `WORKS` can still fail.

### Errors in option 2

| What you see | Likely cause | Who acts |
|---|---|---|
| Port 445 did not open | VPN, firewall, or another VPN | User checks the VPN, then IT |
| Error 5 | Access denied | Person who deployed the gateway |
| Error 53 | Gateway not found, or blocked | User checks the VPN, then IT |
| Error 85 | The letter is taken | User picks another letter |
| Error 1219 | The PC is already connected to the gateway as another user | User runs option 3, then tries again |
| Error 1272 | Windows blocked the sign-in as a guest logon | Stop and record it. Do not weaken the PC's security. |
| Error 1326 | Wrong user name or password, or NTLM is blocked | User, then IT |
| Any other error | Unknown. The connection may not be encrypted. | Record the number and message |

Use **sample files only**. The proof of concept is not secure enough for real data. Option 2 uses `/persistent:no`, which Windows then remembers as this user's default for `net use`.

## Clean up

Run option 3 after testing. It covers rows 1 and 2, and asks about the other rows.

| Row | What to remove | Who does it |
|---|---|---|
| 1 | Test files and the connected drive | Option 3, after a question. Without the script, run `net use S: /delete`. |
| 2 | The VPN profile file in Downloads, which holds a private key | Option 3, after a question |
| 3 | The profile in the AWS VPN Client, after disconnecting | User |
| 4 | Other copies of the profile and the guest password, for example in mail, Teams, the Recycle Bin, or Credential Manager | User |
| 5 | The AWS VPN Client and any exceptions made for the test | Windows administrator or IT |
| 6 | The gateway and its AWS resources, as in [Remove the deployment](docs/deployment.md#remove-the-deployment) | Person who deployed the gateway |

Deleting a profile file does not cancel its certificate. Row 6 removes the VPN that accepts it. If the gateway stays, the person who deployed it must replace the VPN certificate authority, as the [security page](docs/security.md) describes. Replacing only the client key leaves the old profile valid.

## Ask IT

1. Will you install the AWS VPN Client? AWS offers an [`.msi` installer](https://aws.amazon.com/vpn/client-vpn-download/) for x64 and Arm64, and [lists the programs to allow](https://docs.aws.amazon.com/vpn/latest/clientvpn-user/client-vpn-connect-endpoint-security.html).
2. May it connect to AWS on TCP port 443, without TLS inspection and next to a company VPN?
3. May the PC use TCP port 445 through that VPN, with NTLM sign-in?
4. Does data loss prevention block saving to this share?

## Who fixes what

| Problem | Who fixes it |
|---|---|
| AWS VPN Client or .NET Framework is missing or too old | Windows administrator |
| The Workstation service is not running | Windows administrator |
| NTLM sign-in is blocked | Windows administrator |
| The firewall blocks TCP port 443 or 445 | Windows administrator or network team |
| AppLocker or App Control blocks the AWS VPN Client | IT or security team |
| TLS inspection or another VPN stops the connection | Network team |
| Data loss prevention blocks saving to the share | Security team |
| The address ranges overlap | IT names free ranges, and the person who deployed the gateway sets them in Terraform |

## What the user can change

- **Drive letter taken:** use another free letter.
- **Scripts blocked:** use `net use` instead of the script.
- **VPN profile:** add or remove it in the AWS VPN Client.

## Network addresses

The PC makes only outgoing connections. It needs no inbound firewall rule.

- **VPN:** TCP port 443 to the address in the `remote` line of the VPN profile
- **Drive S:** TCP port 445 to the gateway's private address, through the VPN
- **Option 1 of the test script:** TCP port 443 to ec2.us-east-1.amazonaws.com
- **Setup only:** aws.amazon.com, and the address that its download link uses

## Biggest unknown: guest sign-in

Windows 11 24H2 Enterprise, Pro and Education [require SMB signing](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing), which does not allow guest access. The share should still work, because `smbguest` has a password and the Mac's session was encrypted, which [Microsoft says guest logons do not support](https://learn.microsoft.com/en-us/windows-server/storage/file-server/enable-insecure-guest-logons-smb2-and-smb3). Option 2 of the test script tests this.

If it fails, do not turn off signing or turn on insecure guest logons. Use each person's own account, as in the [production design](docs/production.md).

## If IT says no

| Alternative | Needs | Limit |
|---|---|---|
| Site-to-Site VPN or Direct Connect | The network team and the [production design](docs/production.md), which is not built | None on the PC, if policy allows the share |
| Download, edit and upload with the AWS CLI | An AWS sign-in with access to the bucket | Not a network drive. Users cannot save in place, and can overwrite each other. |

## Real rollout by IT

Do not roll out this proof of concept. The [production design](docs/production.md) describes the real setup, with each person's own account instead of the shared guest password.

## Not confirmed

- Nothing has been run on Windows, including the test script.
- The script cannot see single firewall rules, all security products or data loss prevention.
- AWS does not say whether installing or updating the client needs a Windows administrator.

## Sources

- AWS VPN Client: https://docs.aws.amazon.com/vpn/latest/clientvpn-user/windows-troubleshooting.html and https://docs.aws.amazon.com/vpn/latest/clientvpn-user/client-vpn-connect-endpoint-security.html
- SMB signing: https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing
- Guest sign-in: https://learn.microsoft.com/en-us/windows-server/storage/file-server/enable-insecure-guest-logons-smb2-and-smb3
- AppLocker: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/executable-rules-in-applocker

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](LICENSE) and the [disclaimers](DISCLAIMER.md)._
