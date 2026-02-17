function Configurar-DHCP {
    param($interface)
    Check-Service -RoleName "DHCP" -ServiceName "DHCPServer"
    do { $mask = Read-Host " Mascara" } until (Test-IsValidIP -IP $mask -Tipo "mask")
    do { $ip_srv = Read-Host " IP Servidor" } until (Test-IsValidIP -IP $ip_srv -Tipo "host")
    do { $ip_f = Read-Host " IP Final" } until (Test-IsValidIP -IP $ip_f -Tipo "host")
    
    $dns = Read-Host " Servidor DNS (Enter para $ip_srv)"
    $dns_final = if ([string]::IsNullOrWhiteSpace($dns)) { $ip_srv } else { $dns }
    $gw = Read-Host " Puerta de Enlace (Enter para omitir)"

    $base_red = "$($ip_srv.Split('.')[0..2] -join '.').0"
    New-NetIPAddress -InterfaceAlias $interface -IPAddress $ip_srv -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    
    Remove-DhcpServerv4Scope -ScopeId $base_red -Force -ErrorAction SilentlyContinue
    Add-DhcpServerv4Scope -Name "AmbitoPrincipal" -StartRange $ip_srv -EndRange $ip_f -SubnetMask $mask -State Active
    
    # OPCIONES DHCP
    Set-DhcpServerv4OptionValue -ScopeId $base_red -OptionId 6 -Value $dns_final
    if ($gw) { Set-DhcpServerv4OptionValue -ScopeId $base_red -OptionId 3 -Value $gw }
    Write-Host "[OK] DHCP con DNS: $dns_final" -ForegroundColor Green
}
