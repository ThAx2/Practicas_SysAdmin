# --- AUTO-ELEVACIÓN A ADMINISTRADOR ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] ERROR: Ejecuta como Administrador." -ForegroundColor Red; pause; exit
}

$Global:InterfazActiva = ""

# Función para monitorizar sin errores de sintaxis
function Monitor-Servicios {
    $dhcp = Get-Service DHCPServer -ErrorAction SilentlyContinue
    $dns = Get-Service DNS -ErrorAction SilentlyContinue
    
    $colorDHCP = "Red"; $statusDHCP = "STOPPED"
    if ($dhcp.Status -eq "Running") { $statusDHCP = "RUNNING"; $colorDHCP = "Green" }
    
    $colorDNS = "Red"; $statusDNS = "STOPPED"
    if ($dns.Status -eq "Running") { $statusDNS = "RUNNING"; $colorDNS = "Green" }
    
    Write-Host "`n----------------------------------------------" -ForegroundColor Gray
    Write-Host " MONITOR -> DHCP: " -NoNewline
    Write-Host $statusDHCP -ForegroundColor $colorDHCP -NoNewline
    Write-Host " | DNS: " -NoNewline
    Write-Host $statusDNS -ForegroundColor $colorDNS
    Write-Host "----------------------------------------------" -ForegroundColor Gray
}

function Gestionar-Instalacion {
    param($Feature)
    $f = Get-WindowsFeature $Feature
    if ($f.Installed) {
        Write-Host "[v] El servicio $Feature ya está instalado." -ForegroundColor Green
        $r = Read-Host "¿Desea REINSTALAR (borrado total)? (s/n)"
        if ($r -eq "s") {
            Write-Host "[*] Eliminando..." -ForegroundColor Yellow
            Uninstall-WindowsFeature $Feature -IncludeManagementTools | Out-Null
            Install-WindowsFeature $Feature -IncludeManagementTools | Out-Null
        }
    } else {
        Write-Host "[x] $Feature no detectado." -ForegroundColor Red
        $r = Read-Host "¿Instalar ahora? (s/n)"
        if ($r -eq "s") { Install-WindowsFeature $Feature -IncludeManagementTools | Out-Null }
    }
}

function Menu-DHCP {
    Gestionar-Instalacion -Feature "DHCP"
    Clear-Host
    Write-Host "--- CONFIGURACION DHCP ---" -ForegroundColor Yellow
    $Global:InterfazActiva = Read-Host "Nombre Interfaz (ej: Ethernet 2)"
    $ip_s = Read-Host "IP Servidor (ej: 10.10.10.3)"
    $mask = Read-Host "Mascara (ej: 255.255.255.0)"
    $gw   = Read-Host "Gateway (Enter para vacio)"
    $ip_f = Read-Host "IP Final Rango"
    $dns  = Read-Host "DNS (Enter para $ip_s)"
    if (-not $dns) { $dns = $ip_s }

    Write-Host "`n[*] Limpiando red y RPC..." -ForegroundColor Cyan
    Stop-Service DHCPServer -Force -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias $Global:InterfazActiva -DHCP Disabled -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceAlias $Global:InterfazActiva -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    $p = @{ InterfaceAlias = $Global:InterfazActiva; IPAddress = $ip_s; PrefixLength = 24 }
    if ($gw) { $p.DefaultGateway = $gw }
    New-NetIPAddress @p -ErrorAction SilentlyContinue | Out-Null

    Start-Service DHCPServer
    while ((Get-Service DHCPServer).Status -ne "Running") { Start-Sleep -Seconds 1 }
    Start-Sleep -Seconds 4 # FIX WIN32 1753

    Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue
    $base = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + ".0"
    $r_i  = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)
    
    Add-DhcpServerv4Scope -Name "Red_Scope" -StartRange $r_i -EndRange $ip_f -SubnetMask $mask -State Active
    if ($gw) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw }
    Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns -Force
    Set-DhcpServerv4Binding -InterfaceAlias $Global:InterfazActiva -BindingState $true
    
    Restart-Service DHCPServer -Force
    Write-Host "[OK] DHCP listo." -ForegroundColor Green; Pause
}

function Menu-DNS {
    Gestionar-Instalacion -Feature "DNS"
    do {
        Clear-Host
        Monitor-Servicios
        Write-Host "--- GESTION DNS ---" -ForegroundColor Yellow
        Write-Host "1) ALTA | 2) BAJA (Completa) | 3) CONSULTA | 4) Volver"
        $op = Read-Host "Opcion"

        switch ($op) {
            "1" {
                $zona = Read-Host "Nombre Dominio"
                if (-not $Global:InterfazActiva) { $Global:InterfazActiva = Read-Host "Interfaz" }
                
                # FIX: Obtención segura de IP del servidor
                $ip_serv = (Get-NetIPAddress -InterfaceAlias $Global:InterfazActiva -AddressFamily IPv4).IPAddress[0]
                $ip = Read-Host "IP (Enter para $ip_serv)"
                if (-not $ip) { $ip = $ip_serv }

                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns" -ErrorAction SilentlyContinue
                }
                Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ip -Force -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ip -Force -ErrorAction SilentlyContinue
                
                $oct = $ip.Split('.'); $inv = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
                if (-not (Get-DnsServerZone -Name $inv -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $inv -ZoneFile "$inv.dns" -ErrorAction SilentlyContinue
                }
                Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $inv -PtrDomainName "$zona." -Force -ErrorAction SilentlyContinue
                Write-Host "[OK] DNS Creado." -ForegroundColor Green; Pause
            }
            "2" {
                $zona = Read-Host "Dominio a borrar"
                # Intentamos sacar la IP para borrar la inversa antes de destruir la zona
                $rec = Get-DnsServerResourceRecord -ZoneName $zona -Name "@" -RRType A -ErrorAction SilentlyContinue
                if ($rec) {
                    $ip_z = $rec.RecordData.IPv4Address.IPAddressToString
                    $oct = $ip_z.Split('.'); $inv = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
                    Remove-DnsServerZone -Name $inv -Force -ErrorAction SilentlyContinue
                    Write-Host "[!] Zona Inversa $inv eliminada." -ForegroundColor Yellow
                }
                Remove-DnsServerZone -Name $zona -Force -ErrorAction SilentlyContinue
                Write-Host "[!] Zona Directa $zona eliminada." -ForegroundColor Yellow; Pause
            }
            "3" {
                Get-DnsServerZone | ForEach-Object { 
                    Write-Host "`n>> $($_.ZoneName)" -ForegroundColor Magenta
                    Get-DnsServerResourceRecord -ZoneName $_.ZoneName | ft HostName,RecordType,RecordData -AutoSize
                }
                Pause
            }
        }
    } while ($op -ne "4")
}

do {
    Clear-Host
    Write-Host "=== GESTOR DE RED WINDOWS SERVER ===" -ForegroundColor Cyan
    Monitor-Servicios
    Write-Host "1) DHCP | 2) DNS | 3) Salir"
    $m = Read-Host "Selecciona"
    if ($m -eq "1") { Menu-DHCP }
    if ($m -eq "2") { Menu-DNS }
} while ($m -ne "3")
