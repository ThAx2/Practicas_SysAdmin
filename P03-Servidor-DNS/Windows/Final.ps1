# --- COMPROBAR ADMIN ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Ejecuta como Administrador" -ForegroundColor Red; pause; exit
}

# --- FUNCIÓN DE INSTALACIÓN ---
function Instalar-Servicio {
    param($NombreFeature, $Modulo)
    if (-not (Get-WindowsFeature $NombreFeature).Installed) {
        Write-Host "[+] Instalando $NombreFeature..." -ForegroundColor Yellow
        Install-WindowsFeature $NombreFeature -IncludeManagementTools | Out-Null
        Start-Sleep -Seconds 3
    }
    Import-Module $Modulo -ErrorAction SilentlyContinue
}

do {
    Clear-Host
    Write-Host "===== GESTOR TOTAL (FUERZA BRUTA) =====" -ForegroundColor Cyan
    Write-Host "1) CONFIGURAR DHCP (IP Fija + Rango + DNS)"
    Write-Host "2) CONFIGURAR DNS (Alta Dominio + Inversa)"
    Write-Host "3) CONSULTA / BAJA"
    Write-Host "4) Salir"
    $op = Read-Host "Opcion"

    if ($op -eq "1") {
        Instalar-Servicio -NombreFeature "DHCP" -Modulo "DhcpServer"
        
        $int  = Read-Host "Interfaz (ej: Ethernet 2)"
        $ip_s = Read-Host "IP FIJA del Servidor"
        $ip_f = Read-Host "IP FINAL del rango DHCP"
        $mask = Read-Host "Mascara (ej: 255.255.255.0)"
        $gw   = Read-Host "Gateway (Puerta de enlace)"
        $dns_cli = Read-Host "DNS para clientes (Enter para usar $ip_s)"
        if (-not $dns_cli) { $dns_cli = $ip_s }

        # 1. FORZAR IP FIJA PRIMERO
        Write-Host "[*] Aplicando IP fija a la tarjeta..." -ForegroundColor Yellow
        New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_s -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null

        # 2. CALCULAR RED
        $base = $ip_s.Substring(0,$ip_s.LastIndexOf('.')) + ".0"
        $r_i  = $ip_s.Substring(0,$ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)

        # 3. CREAR ÁMBITO
        Remove-DhcpServerv4Scope -ScopeId $base -Force -ErrorAction SilentlyContinue
        Add-DhcpServerv4Scope -Name "Red_Pecas" -StartRange $r_i -EndRange $ip_f -SubnetMask $mask -State Active
        
        # 4. CONFIGURAR OPCIONES (SALTANDO VALIDACIÓN)
        # El parámetro -Force es CLAVE aquí para evitar el error de "not a valid DNS server"
        Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw -ErrorAction SilentlyContinue
        Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns_cli -Force -ErrorAction SilentlyContinue
        
        Write-Host "[OK] DHCP configurado (Validacion DNS saltada)." -ForegroundColor Green; pause
    }
    elseif ($op -eq "2") {
        Instalar-Servicio -NombreFeature "DNS" -Modulo "DnsServer"
        
        $fullDomain = Read-Host "Dominio (ej: pecas.com)"
        $ip_dest = Read-Host "IP destino (Enter para usar la del servidor)"
        if (-not $ip_dest) { 
            $ip_dest = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Ethernet*" }).IPAddress[0]
        }

        $domain = $fullDomain -replace "^www\.", ""

        # Zona Directa
        if (-not (Get-DnsServerZone -Name $domain -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -Name $domain -ZoneFile "$domain.dns"
        }
        Add-DnsServerResourceRecordA -Name "@" -ZoneName $domain -IPv4Address $ip_dest -ErrorAction SilentlyContinue
        Add-DnsServerResourceRecordA -Name "www" -ZoneName $domain -IPv4Address $ip_dest -ErrorAction SilentlyContinue

        # Zona Inversa
        $oct = $ip_dest.Split('.')
        $invZone = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
        if (-not (Get-DnsServerZone -Name $invZone -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -Name $invZone -ZoneFile "$invZone.dns"
        }
        Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $invZone -PtrDomainName "$domain." -ErrorAction SilentlyContinue

        Write-Host "[OK] DNS configurado correctamente." -ForegroundColor Green; pause
    }
    elseif ($op -eq "3") {
        Write-Host "1) Consultar | 2) Baja"
        $sub = Read-Host "Opcion"
        if ($sub -eq "1") { Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | ft }
        else { 
            $z = Read-Host "Zona a borrar"
            Remove-DnsServerZone -Name $z -Force -ErrorAction SilentlyContinue 
        }
        pause
    }
} while ($op -ne "4")
