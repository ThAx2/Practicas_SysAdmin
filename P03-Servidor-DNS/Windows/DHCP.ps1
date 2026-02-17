function Configurar-DHCP {
    param($interface)
    Check-Service -RoleName "DHCP" -ServiceName "DHCPServer"
    
    # 1. Captura de datos básicos
    do { $mask = Read-Host " Mascara de Subred (ej. 255.255.255.0)" } until (Test-IsValidIP -IP $mask -Tipo "mask")
    do { $ip_srv = Read-Host " IP para este Servidor" } until (Test-IsValidIP -IP $ip_srv -Tipo "host")
    do { $ip_f = Read-Host " IP Final del Rango" } until (Test-IsValidIP -IP $ip_f -IPReferencia $ip_srv -Tipo "rango")
    
    # 2. Captura de Opciones DHCP (DNS y GW)
    $gw = Read-Host " Puerta de Enlace (Enter para omitir)"
    $dns = Read-Host " Servidor DNS (Enter para usar esta IP: $ip_srv)"
    $dns_final = if ([string]::IsNullOrWhiteSpace($dns)) { $ip_srv } else { $dns }
    
    $scopeName = Read-Host " Nombre del Ambito"
    $base_red = "$($ip_srv.Split('.')[0..2] -join '.').0"

    # 3. Aplicar Configuración de Red al Servidor
    Write-Host " [*] Aplicando IP estática $ip_srv..." -ForegroundColor Cyan
    Remove-NetIPAddress -InterfaceAlias $interface -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $interface -IPAddress $ip_srv -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    
    # 4. Crear Ámbito y Configurar Opciones (DNS = Opción 6, GW = Opción 3)
    Write-Host " [*] Creando Ambito $base_red..." -ForegroundColor Cyan
    Remove-DhcpServerv4Scope -ScopeId $base_red -Force -ErrorAction SilentlyContinue
    
    # El rango inicia en la IP siguiente al servidor para evitar conflictos
    $rango_inicio = "$($ip_srv.Split('.')[0..2] -join '.').$([int]$ip_srv.Split('.')[3] + 1)"
    
    Add-DhcpServerv4Scope -Name $scopeName -StartRange $rango_inicio -EndRange $ip_f -SubnetMask $mask -State Active
    
    # ASIGNACIÓN DE DNS (Lo que faltaba)
    Set-DhcpServerv4OptionValue -ScopeId $base_red -OptionId 6 -Value $dns_final
    
    if ($gw) { 
        Set-DhcpServerv4OptionValue -ScopeId $base_red -OptionId 3 -Value $gw 
    }

    Write-Host "`n [OK] DHCP Activo. Clientes usarán DNS: $dns_final" -ForegroundColor Green
    Pause
}
