# Requires PowerShell 7 on Windows. Writes sensitive inventory only to ignored local-discovery/.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourceIPv4)
$ErrorActionPreference = 'Stop'
$source = [Net.IPAddress]::Parse($SourceIPv4)
if ($source.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'Use an IPv4 address.' }
$b = $source.GetAddressBytes()
if (-not ($b[0] -eq 10 -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168))) { throw 'Only private IPv4 LANs are supported.' }
$adapter = Get-NetIPAddress -AddressFamily IPv4 | Where-Object IPAddress -eq $SourceIPv4
if (-not $adapter -or $adapter.PrefixLength -ne 24) { throw 'Source must be an existing local /24 interface. Other sizes require a separate reviewed scope.' }
$out = Join-Path $PSScriptRoot '../local-discovery'
New-Item -ItemType Directory -Force -Path $out | Out-Null
if (-not ('LocalLabArp' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Runtime.InteropServices;
using System.Collections.Concurrent;
using System.Threading.Tasks;
public static class LocalLabArp {
  [DllImport("iphlpapi.dll", ExactSpelling=true)]
  static extern int SendARP(uint dest, uint source, byte[] mac, ref uint length);
  public static string[] Scan(string source) {
    var replies = new ConcurrentBag<string>();
    var src = BitConverter.ToUInt32(IPAddress.Parse(source).GetAddressBytes(), 0);
    var prefix = source.Substring(0, source.LastIndexOf('.') + 1);
    Parallel.For(1, 255, new ParallelOptions { MaxDegreeOfParallelism = 24 }, i => {
      var ip = prefix + i;
      if (ip == source) return;
      var mac = new byte[6]; uint length = 6;
      int result = SendARP(BitConverter.ToUInt32(IPAddress.Parse(ip).GetAddressBytes(), 0), src, mac, ref length);
      if (result == 0 && length == 6) replies.Add(ip + "," + BitConverter.ToString(mac));
    });
    return replies.ToArray();
  }
}
'@
}
$start = [DateTimeOffset]::UtcNow.ToString('o')
$lan = @([LocalLabArp]::Scan($SourceIPv4) | ForEach-Object {
    $parts = $_.Split(',')
    [pscustomobject]@{ ipv4 = $parts[0]; mac = $parts[1]; evidence = 'SendARP response on selected local interface' }
} | Sort-Object { [version]$_.ipv4 })
$vm = @(); $vmAdapters = @(); $gaps = @(); $tail = @()
try {
    $vm = @(Get-VM | Select-Object Name,@{Name='State';Expression={$_.State.ToString()}},Generation)
    $vmAdapters = @(Get-VMNetworkAdapter -All | Select-Object VMName,SwitchName,MacAddress,IPAddresses)
} catch { $gaps += 'Hyper-V inventory unavailable: ' + $_.Exception.Message }
$ts = Join-Path $env:ProgramFiles 'Tailscale/tailscale.exe'
if (Test-Path $ts) {
    try {
        $status = (& $ts status --json | ConvertFrom-Json)
        if ($LASTEXITCODE -ne 0) { throw 'Tailscale status failed' }
        $tail = @(@($status.Self) + @($status.Peer.PSObject.Properties.Value) | ForEach-Object {
            [pscustomobject]@{ hostname=$_.HostName; dnsName=$_.DNSName; os=$_.OS; online=$_.Online; ips=$_.TailscaleIPs; advertisedRoutes=$_.PrimaryRoutes }
        })
    } catch { $gaps += 'Tailscale inventory unavailable: ' + $_.Exception.Message }
} else { $gaps += 'Tailscale not installed' }
$snapshot = [ordered]@{
    startedAtUtc=$start; completedAtUtc=[DateTimeOffset]::UtcNow.ToString('o'); sourceIPv4=$SourceIPv4
    scope='Local IPv4 /24 ARP only; local Hyper-V inventory; Tailscale reported status'
    lan=$lan; hyperV=$vm; hyperVAdapters=$vmAdapters; tailscale=$tail; gaps=$gaps
    limitations=@('ARP covers only the selected broadcast network. Nonresponders are not proven offline.', 'Tailscale online is reported status, not an independent reachability test.', 'No host-to-VM placement is inferred from MAC addresses or open ports.', 'IPv6, other VLANs, router leases, remote hypervisors, WSL and container inventories are not collected.')
}
$path = Join-Path $out ('discovery-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '.json')
$snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
Write-Output ('Saved local inventory: ' + $path)
$lan | Format-Table
$vm | Format-Table
$vmAdapters | Format-List
$tail | Select-Object hostname,os,online | Format-Table
if ($gaps.Count) { Write-Warning ($gaps -join '; ') }
