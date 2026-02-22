function Validar-IP {
    param($IP)
    if ($IP -match "^\d{1,3}(\.\d{1,3}){3}$") { return $true } else { return $false }
}

function Validar-Dominio {
    param($Dominio)
    if ($Dominio -like "*.*") { return $true } else { return $false }
}

function Configurar-Red {
    param($Interfaz, $IP, $Mascara, $Gateway)
    
    Write-Host "[*] Aplicando IP estática en $Interfaz..." -ForegroundColor Cyan
    Set-NetIPInterface -InterfaceAlias $Interfaz -DHCP Disabled -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceAlias $Interfaz -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    $p = @{ InterfaceAlias = $Interfaz; IPAddress = $IP; PrefixLength = 24 }
    
    # El gateway puede ir vacío como pediste [2026-02-19]
    if ($Gateway) { $p.DefaultGateway = $Gateway }
    
    New-NetIPAddress @p -ErrorAction SilentlyContinue | Out-Null
    Write-Host "[OK] Red configurada." -ForegroundColor Green
}
