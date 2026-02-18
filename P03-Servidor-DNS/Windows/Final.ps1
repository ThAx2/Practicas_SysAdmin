# --- 0. VALIDACIÓN DE ADMINISTRADOR ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Ejecuta como Administrador." -ForegroundColor Red; pause; exit
}
function Gestionar-Instalacion {
    param($FeatureName, $ServiceName)
    
    Write-Host "`n[*] Verificando $FeatureName..." -ForegroundColor Cyan
    $instalado = (Get-WindowsFeature $FeatureName).Installed
    
    if ($instalado) {
        Write-Host "    -> Estado: INSTALADO." -ForegroundColor Green
        $re = Read-Host "    -> ¿Deseas FORZAR una REINSTALACION/REPARACION? (S/N)"
        if ($re -eq "S") {
            Write-Host "    [...] Reinstalando $FeatureName..." -ForegroundColor Yellow
            Install-WindowsFeature $FeatureName -IncludeManagementTools -Force | Out-Null
        }
    } else {
        Write-Host "    -> Estado: NO INSTALADO. Instalando..." -ForegroundColor Yellow
        Install-WindowsFeature $FeatureName -IncludeManagementTools | Out-Null
    }
    
    # Importar módulo y esperar a que el servicio arranque
    Import-Module $ServiceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# --- 2. FUNCIÓN DHCP (LIMPIEZA TOTAL + FORCE DNS) ---
function Menu-DHCP {
    Gestionar-Instalacion -FeatureName "DHCP" -ServiceName "DhcpServer"

    Clear-Host
    Write-Host "--- CONFIGURACION DHCP ---" -ForegroundColor Yellow
    $int  = Read-Host "Nombre Interfaz (ej: Ethernet 2)"
    $ip_s = Read-Host "IP Servidor (ej: 192.168.100.20)"
    $mask = Read-Host "Mascara (ej: 255.255.255.0)"
    $gw   = Read-Host "Gateway"
    $ip_f = Read-Host "IP Final Rango"
    $dns  = Read-Host "DNS (Enter para usar $ip_s)"
    if (-not $dns) { $dns = $ip_s }

    Write-Host "`n[!] LIMPIANDO INTERFAZ DE RED Y SCOPES ANTIGUOS..." -ForegroundColor Red
    # 1. Borrar IPs basura de la tarjeta
    Get-NetIPAddress -InterfaceAlias $int -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    # 2. Borrar Scopes viejos
    Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue

    Write-Host "[*] Asignando IP Fija y creando Scope..." -ForegroundColor Cyan
    New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_s -PrefixLength 24 -DefaultGateway $gw -ErrorAction SilentlyContinue | Out-Null

    # Calculo de inicio de rango
    $base = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + ".0"
    $r_i  = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)

    Add-DhcpServerv4Scope -Name "Red_Limpia" -StartRange $r_i -EndRange $ip_f -SubnetMask $mask -State Active
    Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw

    # AQUI ESTA LA ORDEN: OBLIGAR AL DNS A ENTRAR AUNQUE NO RESPONDA
    Write-Host "[*] Configurando DNS Option 006 con -Force..." -ForegroundColor Yellow
    Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns -Force
    
    Write-Host "[OK] DHCP Configurado." -ForegroundColor Green
    Pause
}

# --- 3. FUNCIÓN DNS (ALTAS, BAJAS, CONSULTA TOTAL) ---
function Menu-DNS {
    Gestionar-Instalacion -FeatureName "DNS" -ServiceName "DnsServer"

    do {
        Clear-Host
        Write-Host "--- GESTION DNS ---" -ForegroundColor Yellow
        Write-Host "1) ALTA "
        Write-Host "2) BAJA "
        Write-Host "3) CONSULTA TOTAL"
        Write-Host "4) Volver"
        $opDNS = Read-Host "Opcion"

        switch ($opDNS) {
            "1" { # ALTA
                $zona = Read-Host "Nombre Zona (ej: pecas.com)"
                $ip   = Read-Host "IP (Enter para usar la del servidor)"
                if (-not $ip) { $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -like "*Ethernet*"}).IPAddress[0] }

                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns" -ErrorAction SilentlyContinue
                }
                Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue

                $oct = $ip.Split('.')
                $invZone = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
                if (-not (Get-DnsServerZone -Name $invZone -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $invZone -ZoneFile "$invZone.dns" -ErrorAction SilentlyContinue
                }
                Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $invZone -PtrDomainName "$zona." -ErrorAction SilentlyContinue
                
                Write-Host "[OK] Zona creada. Ping y NSLookup funcionaran en ambos sentidos." -ForegroundColor Green
                Pause
            }
            "2" { # BAJA
                $z = Read-Host "Zona a borrar"
                Remove-DnsServerZone -Name $z -Force -ErrorAction SilentlyContinue
                Write-Host "[OK] Zona eliminada." -ForegroundColor Yellow; Pause
            }
            "3" { # CONSULTA TOTAL
                $z = Read-Host "Zona a consultar"
                Write-Host "`n--- TODOS LOS REGISTROS DE $z ---" -ForegroundColor Cyan
                Get-DnsServerResourceRecord -ZoneName $z | Format-Table -AutoSize
                Pause
            }
        }
    } while ($opDNS -ne "4")
}
do {
    Clear-Host
    $sDHCP = Get-Service "dhcpserver" -ErrorAction SilentlyContinue
    $sDNS  = Get-Service "dns" -ErrorAction SilentlyContinue
    $stDHCP = if ($sDHCP) { $sDHCP.Status } else { "No Instalado" }
    $stDNS  = if ($sDNS) { $sDNS.Status } else { "No Instalado" }

    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   GESTOR DE SERVIDOR" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host " [MONITOR] DHCP: $stDHCP | DNS: $stDNS" -ForegroundColor Magenta
    Write-Host "------------------------------------------"
    Write-Host " 1) DHCP"
    Write-Host " 2) DNS (Altas/Bajas/Consultas Totales)"
    Write-Host " 3) Salir"
    
    $m = Read-Host " Selecciona"
    if ($m -eq "1") { Menu-DHCP }
    if ($m -eq "2") { Menu-DNS }

} while ($m -ne "3")
