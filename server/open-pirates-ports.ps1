# Opens the Windows firewall for the Pirates Online client agent (TCP 7100) so another PC on your network
# can reach the WSL server (mirrored networking exposes it on this PC's LAN address).
# Run once as Administrator.
$rule = 'Pirates Online LAN (TCP 7100)'
if (-not (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $rule -Direction Inbound -Protocol TCP -LocalPort 7100 -Action Allow -Profile Private | Out-Null
    "added: $rule"
} else {
    "already present: $rule"
}
