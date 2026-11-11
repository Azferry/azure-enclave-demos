<#
.SYNOPSIS
    Runs INSIDE the enclave VM (via Invoke-AzVMRunCommand or interactively) to
    prove the path enclave VM -> community firewall -> transit hub -> corp VNet -> DC.

.PARAMETER DcIp
    Private IP of the domain controller in the peered corporate VNet.

.PARAMETER DomainName
    Optional AD DNS domain name (e.g. corp.contoso.local). When supplied, the
    script also checks DNS SRV records for domain controllers.
#>
param(
    [Parameter(Mandatory)]
    [string]$DcIp,

    [string]$DomainName
)

$ErrorActionPreference = 'Continue'

function Test-TcpPort {
    param([string]$ComputerName, [int]$Port, [int]$TimeoutMs = 3000)
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne($TimeoutMs) -and $client.Connected) {
            $client.EndConnect($async)
            return $true
        }
        return $false
    }
    catch { return $false }
    finally { $client.Dispose() }
}

$hostIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -First 1).IPAddress

Write-Output "=== Azure Virtual Enclaves -> Corporate AD connectivity test ==="
Write-Output ("Source : {0} ({1})" -f $env:COMPUTERNAME, $hostIp)
Write-Output ("Target : {0}" -f $DcIp)
Write-Output ("DNS    : {0}" -f ((Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object ServerAddresses | Select-Object -First 1).ServerAddresses -join ', '))
Write-Output ''

$ping = [System.Net.NetworkInformation.Ping]::new()
try {
    $reply = $ping.Send($DcIp, 2000)
    $pingResult = if ($reply.Status -eq 'Success') { "OK ($($reply.RoundtripTime) ms)" } else { "No reply ($($reply.Status)) - DC Windows Firewall blocks ICMP by default" }
}
catch { $pingResult = "Error: $($_.Exception.Message)" }
finally { $ping.Dispose() }
Write-Output ("ICMP echo                  : {0}" -f $pingResult)

$ports = [ordered]@{
    'RDP (3389)'                 = 3389
    'DNS (53/tcp)'               = 53
    'Kerberos (88)'              = 88
    'RPC endpoint mapper (135)'  = 135
    'LDAP (389)'                 = 389
    'SMB (445)'                  = 445
    'Kerberos pwd (464)'         = 464
    'LDAPS (636)'                = 636
    'Global Catalog (3268)'      = 3268
    'AD Web Services (9389)'     = 9389
}

$results = foreach ($entry in $ports.GetEnumerator()) {
    $open = Test-TcpPort -ComputerName $DcIp -Port $entry.Value
    [pscustomobject]@{
        Service = $entry.Key
        Result  = if ($open) { 'OPEN' } else { 'closed / filtered' }
    }
}
$results | ForEach-Object { Write-Output ("{0,-27}: {1}" -f $_.Service, $_.Result) }

if ($DomainName) {
    Write-Output ''
    foreach ($query in @(
            @{ Name = $DomainName; Type = 'A' },
            @{ Name = "_ldap._tcp.dc._msdcs.$DomainName"; Type = 'SRV' })) {
        try {
            $answer = Resolve-DnsName -Name $query.Name -Type $query.Type -Server $DcIp -DnsOnly -ErrorAction Stop
            $text = ($answer | ForEach-Object { if ($_.IPAddress) { $_.IPAddress } elseif ($_.NameTarget) { "$($_.NameTarget):$($_.Port)" } }) -join ', '
            Write-Output ("DNS {0,-4} {1,-40}: {2}" -f $query.Type, $query.Name, $text)
        }
        catch {
            Write-Output ("DNS {0,-4} {1,-40}: FAILED ({2})" -f $query.Type, $query.Name, $_.Exception.Message)
        }
    }
}

Write-Output ''
$adPortsOpen = ($results | Where-Object { $_.Service -match 'LDAP \(389\)|Kerberos \(88\)|DNS' -and $_.Result -eq 'OPEN' }).Count
$anyOpen = @($results | Where-Object Result -eq 'OPEN').Count -gt 0
if ($adPortsOpen -ge 3) {
    Write-Output 'RESULT: Enclave VM can reach Active Directory services in the peered corporate VNet.'
}
elseif ($anyOpen -or $pingResult -like 'OK*') {
    Write-Output 'RESULT: Network path through the community firewall + transit hub is UP.'
    Write-Output '        AD ports are not answering yet - promote the DC (see README) and re-run.'
}
else {
    Write-Output 'RESULT: No path to the DC. Check the enclave connection, community endpoint, transit hub state and corp NSG.'
}
