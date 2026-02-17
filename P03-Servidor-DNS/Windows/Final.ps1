# --- 1. VALIDACIÓN ESTRICTA (Bloquea .303 y otros errores) ---
function Test-IP {
    param([string]$IP, [switch]$PermitirVacio)
    if ([string]::IsNullOrWhiteSpace($IP)) { return $PermitirVacio }
    # Valida que cada octeto esté entre 0-255 y sigan el formato X.X.X.X
    return $IP -match '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
}

# --- 2. INSTALACIÓN FORZADA (Arregla error 0x800f081f) ---
function Instalar-Rol {
    param($Nombre)
    Write-Host "[*] Verificando $Nombre..." -ForegroundColor Cyan
    if (-not (Get-WindowsFeature $Nombre).Installed) {
        Write-Host "[!] Instalando... Por favor espera." -ForegroundColor Yellow
        # Se intenta instalar; si falla, te avisará para usar DISM
        Install-WindowsFeature $Nombre -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    }
}

# --- 3. LÓGICA DHCP (Con DNS y Gateway opcionales) ---
function Ejecutar-DHCP {
    Instalar-Rol -Nombre "DHCP"
    if (-not (Get-Command Add-DhcpServerv4Scope -ErrorAction SilentlyContinue)) {
        Write-Host "[!] ERROR: El rol DHCP no se instaló. Ejecuta 'dism /online /cleanup-image /restorehealth' y reintenta." -ForegroundColor Red
        Pause; return
    }

    $int = "Ethernet" 
    do { $ip_srv = Read-Host "IP Servidor" } until (Test-IP $ip_srv)
    do { $mask   = Read-Host "Mascara (ej. 255.255.255.0)" } until (Test-IP $mask)
    do { $ip_fin = Read-Host "IP Final Rango" } until (Test-IP $ip_fin)
    do { $gw     = Read-Host "Puerta de Enlace (Enter para saltar)" } until (Test-IP $gw -PermitirVacio)
    do { $dns    = Read-Host "Servidor DNS (Enter para saltar)" } until (Test-IP $dns -PermitirVacio)

    $base = "$($ip_srv.Split('.')[0..2] -join '.').0"

    New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_srv -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    Remove-DhcpServerv4Scope -ScopeId $base -Force -ErrorAction SilentlyContinue
    Add-DhcpServerv4Scope -Name "Red_Pecas" -StartRange $ip_srv -EndRange $ip_fin -SubnetMask $mask -State Active
    
    if (-not [string]::IsNullOrWhiteSpace($dns)) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns }
    if (-not [string]::IsNullOrWhiteSpace($gw)) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw }
    
    Write-Host "[OK] DHCP configurado." -ForegroundColor Green
    Pause
}

# --- 4. LÓGICA DNS ---
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
    } elseif ($sub -eq "2") {
        $m = Read-Host "Dominio a borrar"; Remove-DnsServerZone -Name $m -Force
    } elseif ($sub -eq "3") {
        Get-DnsServerZone | Where-Object IsReverseLookupZone -eq $false | Select ZoneName
    }
    Pause
}

# --- 5. MENÚ PRINCIPAL ---
while ($true) {
    Clear-Host
    Write-Host "=== ORQUESTADOR WINDOWSITO ===" -ForegroundColor Yellow
    Write-Host "1) DHCP`n2) DNS (ABC)`n3) Estatus`n4) Salir"
    $main = Read-Host "Seleccion"
    if ($main -eq "1") { Ejecutar-DHCP }
    elseif ($main -eq "2") { Ejecutar-DNS }
    elseif ($main -eq "3") { Get-Service DHCPServer, DNS -ErrorAction SilentlyContinue | Select Name, Status; Pause }
    elseif ($main -eq "4") { break }
}
