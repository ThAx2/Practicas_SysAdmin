# --- AUTO-ELEVACIÓN A ADMINISTRADOR ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] ERROR: Ejecuta como Administrador." -ForegroundColor Red; pause; exit
}

# Variable Global para persistencia entre menús
$Global:InterfazActiva = ""

function Comprobar-Instalacion {
    param($Feature)
    $estado = Get-WindowsFeature $Feature
    if ($estado.Installed) {
        Write-Host "[v] El servicio $($Feature) ya está instalado." -ForegroundColor Green
        $resp = Read-Host "¿Desea reinstalarlo? (s/n)"
        if ($resp -eq "s") {
            Write-Host "[*] Reinstalando..." -ForegroundColor Yellow
            Uninstall-WindowsFeature $Feature -IncludeManagementTools | Out-Null
            Install-WindowsFeature $Feature -IncludeManagementTools | Out-Null
        }
    } else {
        Write-Host "[x] El servicio $($Feature) NO está instalado." -ForegroundColor Red
        $resp = Read-Host "¿Desea instalarlo ahora? (s/n)"
        if ($resp -eq "s") {
            Install-WindowsFeature $Feature -IncludeManagementTools | Out-Null
        }
    }
}

function Monitor-Servicios {
    $dhcp = Get-Service DHCPServer -ErrorAction SilentlyContinue
    $dns = Get-Service DNS -ErrorAction SilentlyContinue
    
    $statusDHCP = if ($dhcp.Status -eq "Running") { "RUNNING" } else { "STOPPED" }
    $statusDNS = if ($dns.Status -eq "Running") { "RUNNING" } else { "STOPPED" }
    
    Write-Host "----------------------------------------------" -ForegroundColor Gray
    Write-Host " MONITOR -> DHCP: " -NoNewline
    Write-Host $statusDHCP -ForegroundColor (if ($statusDHCP -eq "RUNNING") { "Green" } else { "Red" }) -NoNewline
    Write-Host " | DNS: " -NoNewline
    Write-Host $statusDNS -ForegroundColor (if ($statusDNS -eq "RUNNING") { "Green" } else { "Red" })
    Write-Host "----------------------------------------------" -ForegroundColor Gray
}

function Menu-DHCP {
    Comprobar-Instalacion -Feature "DHCP"
    Clear-Host
    Write-Host "=== CONFIGURACION DHCP (GATEWAY OPCIONAL) ===" -ForegroundColor Yellow
    $Global:InterfazActiva = Read-Host "Interfaz (ej: Ethernet 2)"
    $ip_s = Read-Host "IP Servidor (ej: 10.10.10.3)"
    $mask = Read-Host "Mascara (ej: 255.255.255.0)"
    $gw   = Read-Host "Gateway (Enter para dejar VACIO)"
    $ip_f = Read-Host "IP Final Rango"
    $dns  = Read-Host "DNS (Enter para usar $ip_s)"
    if (-not $dns) { $dns = $ip_s }

    Write-Host "`n[*] Limpiando y fijando IP estática..." -ForegroundColor Cyan
    Stop-Service DHCPServer -Force -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias $Global:InterfazActiva -DHCP Disabled -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceAlias $Global:InterfazActiva -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    $p = @{ InterfaceAlias = $Global:InterfazActiva; IPAddress = $ip_s; PrefixLength = 24 }
    if ($gw) { $p.DefaultGateway = $gw }
    New-NetIPAddress @p -ErrorAction SilentlyContinue | Out-Null

    Write-Host "[*] Iniciando DHCP (Esperando sincronización RPC)..." -ForegroundColor Yellow
    Start-Service DHCPServer
    while ((Get-Service DHCPServer).Status -ne "Running") { Start-Sleep -Seconds 1 }
    Start-Sleep -Seconds 4 # Evita errores rojos WIN32 1753

    Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue
    $base = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + ".0"
    $r_i  = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)
    
    Add-DhcpServerv4Scope -Name "Red_Scope" -StartRange $r_i -EndRange $ip_f -SubnetMask $mask -State Active
    if ($gw) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw }
    Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns -Force
    Set-DhcpServerv4Binding -InterfaceAlias $Global:InterfazActiva -BindingState $true
    
    Restart-Service DHCPServer -Force
    Write-Host "[OK] DHCP Configurado." -ForegroundColor Green; Pause
}

function Menu-DNS {
    Comprobar-Instalacion -Feature "DNS"
    do {
        Clear-Host
        Monitor-Servicios
        Write-Host "=== GESTION DNS ===" -ForegroundColor Yellow
        Write-Host "1) ALTA (Directa + Inversa)"
        Write-Host "2) BAJA (Directa + Inversa)"
        Write-Host "3) CONSULTA TOTAL"
        Write-Host "4) Volver"
        $op = Read-Host "Opcion"

        switch ($op) {
            "1" {
                $zona = Read-Host "Nombre Dominio"
                if (-not $Global:InterfazActiva) { $Global:InterfazActiva = Read-Host "Nombre Interfaz" }
                $ip_def = (Get-NetIPAddress -InterfaceAlias $Global:InterfazActiva -AddressFamily IPv4).IPAddress[0]
                $ip = Read-Host "IP Destino (Enter para $ip_def)"
                if (-not $ip) { $ip = $ip_def }

                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns" -ErrorAction SilentlyContinue
                }
                Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue -Force
                Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue -Force
                
                $oct = $ip.Split('.'); $inv = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
                if (-not (Get-DnsServerZone -Name $inv -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $inv -ZoneFile "$inv.dns" -ErrorAction SilentlyContinue
                }
                Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $inv -PtrDomainName "$zona." -ErrorAction SilentlyContinue -Force
                Write-Host "[OK] Alta completada." -ForegroundColor Green; Pause
            }
            "2" {
                $zona = Read-Host "Dominio a borrar"
                $ip_z = (Get-DnsServerResourceRecord -ZoneName $zona -Name "@" -RRType A).RecordData.IPv4Address.IPAddressToString
                Remove-DnsServerZone -Name $zona -Force -ErrorAction SilentlyContinue
                if ($ip_z) {
                    $oct = $ip_z.Split('.'); $inv = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
                    Remove-DnsServerZone -Name $inv -Force -ErrorAction SilentlyContinue
                    Write-Host "[!] Borrada zona directa e inversa ($inv)." -ForegroundColor Yellow
                }
                Pause
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
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "      GESTOR DE RED WINDOWS SERVER" -ForegroundColor Cyan
    Monitor-Servicios
    Write-Host " 1) DHCP (Configurar Red)"
    Write-Host " 2) DNS (Zonas y Registros)"
    Write-Host " 3) Salir"
    $m = Read-Host " Selecciona"
    if ($m -eq "1") { Menu-DHCP }
    if ($m -eq "2") { Menu-DNS }
} while ($m -ne "3")
