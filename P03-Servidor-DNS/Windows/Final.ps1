# --- FUNCIONES DE APOYO ---
function Test-IP {
    param([string]$IP, [switch]$PermitirVacio)
    if ([string]::IsNullOrWhiteSpace($IP)) { return $PermitirVacio }
    # Filtro real: No permite números > 255 ni formatos basura
    return $IP -match '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
}

function Instalar-Rol {
    param($Nombre)
    Write-Host "[*] Verificando $Nombre..." -ForegroundColor Cyan
    if (-not (Get-WindowsFeature $Nombre).Installed) {
        Write-Host "[!] Instalando... ten paciencia" -ForegroundColor Yellow
        # Esto soluciona el error 0x800f081f al intentar descargar de nuevo
        Install-WindowsFeature $Nombre -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    }
}

# --- LÓGICA DHCP ---
function Ejecutar-DHCP {
    Instalar-Rol -Nombre "DHCP"
    $int = "Ethernet" 

    # VALIDACIÓN REAL: Si metes .303, te lo vuelve a pedir
    do { $ip_srv = Read-Host "IP Servidor" } until (Test-IP $ip_srv)
    do { $mask   = Read-Host "Mascara (ej. 255.255.255.0)" } until (Test-IP $mask)
    do { $ip_fin = Read-Host "IP Final Rango" } until (Test-IP $ip_fin)
    
    # ACEPTAN VACÍOS: Si das Enter, no explota
    do { $gw = Read-Host "Puerta de Enlace (Enter para saltar)" } until (Test-IP $gw -PermitirVacio)
    do { $dns = Read-Host "Servidor DNS (Enter para saltar)" } until (Test-IP $dns -PermitirVacio)

    $base = "$($ip_srv.Split('.')[0..2] -join '.').0"

    New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_srv -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    Remove-DhcpServerv4Scope -ScopeId $base -Force -ErrorAction SilentlyContinue
    
    Add-DhcpServerv4Scope -Name "Red_Pecas" -StartRange $ip_srv -EndRange $ip_fin -SubnetMask $mask -State Active
    
    # Solo aplica opciones si NO están vacías
    if (-not [string]::IsNullOrWhiteSpace($dns)) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns }
    if (-not [string]::IsNullOrWhiteSpace($gw)) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw }
    
    Write-Host "[OK] DHCP configurado correctamente." -ForegroundColor Green
    Pause
}

# --- LÓGICA DNS ---
function Ejecutar-DNS {
    Instalar-Rol -Nombre "DNS"
    $ip_actual = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.PrefixOrigin -eq 'Manual'}).IPAddress | Select-Object -First 1
    if ($null -eq $ip_actual) { $ip_actual = "192.168.100.20" }

    Write-Host "`n1) Alta`n2) Baja`n3) Ver`n4) Volver"
    $sub = Read-Host "Opcion"
    
    if ($sub -eq "1") {
        $dom = Read-Host "Dominio"
        $dest = Read-Host "IP Destino (Enter para $ip_actual)"
        $ip_f = if ([string]::IsNullOrWhiteSpace($dest)) { $ip_actual } else { $dest }
        
        Add-DnsServerPrimaryZone -Name $dom -ZoneFile "$dom.dns" -ErrorAction SilentlyContinue
        Add-DnsServerResourceRecordA -Name "@" -ZoneName $dom -IPv4Address $ip_f -Force
        Write-Host "[OK] $dom -> $ip_f" -ForegroundColor Green
    } 
    elseif ($sub -eq "2") {
        $m = Read-Host "Dominio a borrar"; Remove-DnsServerZone -Name $m -Force
    }
    elseif ($sub -eq "3") {
        Get-DnsServerZone | Where-Object IsReverseLookupZone -eq $false | Select ZoneName
    }
    Pause
}

# --- MENU PRINCIPAL ---
while ($true) {
    Clear-Host
    Write-Host "=== ORQUESTADOR WINDOWSITO ===" -ForegroundColor Yellow
    Write-Host "1) DHCP`n2) DNS (ABC)`n3) Estatus`n4) Salir"
    $main = Read-Host "Seleccion"
    
    if ($main -eq "1") { Ejecutar-DHCP }
    elseif ($main -eq "2") { Ejecutar-DNS }
    elseif ($main -eq "3") { 
        Get-Service DHCPServer, DNS -ErrorAction SilentlyContinue | Select Name, Status
        Pause 
    }
    elseif ($main -eq "4") { break }
}
