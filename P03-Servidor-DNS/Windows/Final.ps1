# --- FUNCIONES DE APOYO ---
function Test-IP {
    param([string]$IP)
    return $IP -match '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
}

function Instalar-Rol {
    param($Nombre)
    Write-Host "[*] Preparando $Nombre..." -ForegroundColor Cyan
    try {
        Install-WindowsFeature $Nombre -IncludeManagementTools -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "[!] Error critico instalando $Nombre. Revisa DISM." -ForegroundColor Red
    }
}

# --- LÓGICA DHCP ---
function Ejecutar-DHCP {
    Instalar-Rol -Nombre "DHCP"
    $int = "Ethernet" # Cambia si tu interfaz tiene otro nombre
    
    $ip_srv = Read-Host "IP del Servidor (ej. 192.168.100.20)"
    $mask   = Read-Host "Mascara (ej. 255.255.255.0)"
    $ip_fin = Read-Host "IP Final del Rango"
    $gw     = Read-Host "Puerta de Enlace (Enter para omitir)"

    $base = "$($ip_srv.Split('.')[0..2] -join '.').0"

    # Configurar red local
    New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_srv -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    
    # Configurar Ambito
    Remove-DhcpServerv4Scope -ScopeId $base -Force -ErrorAction SilentlyContinue
    Add-DhcpServerv4Scope -Name "Red_Pecas" -StartRange $ip_srv -EndRange $ip_fin -SubnetMask $mask -State Active
    
    # OPCIONES VITALES (DNS y GW)
    Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $ip_srv
    if ($gw) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw }
    
    Write-Host "[OK] DHCP listo. Clientes verán a $ip_srv como su DNS." -ForegroundColor Green
    Pause
}

# --- LÓGICA DNS ---
function Ejecutar-DNS {
    Instalar-Rol -Nombre "DNS"
    $ip_actual = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.PrefixOrigin -eq 'Manual'}).IPAddress | Select-Object -First 1
    
    Write-Host "`n1) Alta Dominio`n2) Baja Dominio`n3) Ver Dominios`n4) Volver"
    $sub = Read-Host "Opcion"
    
    if ($sub -eq "1") {
        $dom = Read-Host "Dominio (ej. pecas.com)"
        $dest = Read-Host "IP de Destino (Enter para $ip_actual)"
        $ip_f = if ([string]::IsNullOrWhiteSpace($dest)) { $ip_actual } else { $dest }
        
        Add-DnsServerPrimaryZone -Name $dom -ZoneFile "$dom.dns" -ErrorAction SilentlyContinue
        Add-DnsServerResourceRecordA -Name "@" -ZoneName $dom -IPv4Address $ip_f -Force
        Add-DnsServerResourceRecordCName -Name "www" -ZoneName $dom -HostNameAlias "$dom." -Force
        Write-Host "[OK] $dom -> $ip_f" -ForegroundColor Green
    } 
    elseif ($sub -eq "2") {
        $m = Read-Host "Dominio a borrar"
        Remove-DnsServerZone -Name $m -Force
    }
    elseif ($sub -eq "3") {
        Get-DnsServerZone | Where-Object IsReverseLookupZone -eq $false | Select ZoneName
    }
    Pause
}

# --- MENU PRINCIPAL ---
while ($true) {
    Clear-Host
    Write-Host "===============================" -ForegroundColor Yellow
    Write-Host "   ORQUESTADOR DE SERVICIOS    " -ForegroundColor Yellow
    Write-Host "===============================" -ForegroundColor Yellow
    Write-Host "1) DHCP`n2) DNS (ABC)`n3) Estatus`n4) Salir"
    $main = Read-Host "Seleccion"
    
    if ($main -eq "1") { Ejecutar-DHCP }
    elseif ($main -eq "2") { Ejecutar-DNS }
    elseif ($main -eq "3") { Get-Service DHCPServer, DNS | Select Name, Status; Pause }
    elseif ($main -eq "4") { break }
}
