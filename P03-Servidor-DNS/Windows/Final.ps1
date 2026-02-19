# --- COMPROBACIÓN DE ADMINISTRADOR ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Ejecuta como Administrador." -ForegroundColor Red; pause; exit
}

# Variable Global para que DNS sepa qué tarjeta usar y no dé error "Null"
$Global:InterfazActiva = ""

function Gestionar-Instalacion {
    param($FeatureName, $ServiceName)
    if (-not (Get-WindowsFeature $FeatureName).Installed) {
        Install-WindowsFeature $FeatureName -IncludeManagementTools | Out-Null
    }
    Import-Module $ServiceName -ErrorAction SilentlyContinue
}

function Menu-DHCP {
    Gestionar-Instalacion -FeatureName "DHCP" -ServiceName "DhcpServer"
    Clear-Host
    Write-Host "--- CONFIGURACION DHCP ---" -ForegroundColor Yellow
    $Global:InterfazActiva = Read-Host "Nombre Interfaz (ej: Ethernet 2)"
    $ip_s = Read-Host "IP Servidor (ej: 10.10.10.3)"
    $mask = Read-Host "Mascara (ej: 255.255.255.0)"
    $gw   = Read-Host "Gateway (Enter para dejar VACIO)"
    $ip_f = Read-Host "IP Final Rango"
    $dns  = Read-Host "DNS (Enter para usar $ip_s)"
    if (-not $dns) { $dns = $ip_s }

    Write-Host "`n[*] Limpiando red y forzando IP estatica..." -ForegroundColor Cyan
    Stop-Service DHCPServer -Force -ErrorAction SilentlyContinue
    
    # Esto elimina el 169.254 y las IPs duplicadas de tus fotos
    Set-NetIPInterface -InterfaceAlias $Global:InterfazActiva -DHCP Disabled -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceAlias $Global:InterfazActiva -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    
    $ipParams = @{ InterfaceAlias = $Global:InterfazActiva; IPAddress = $ip_s; PrefixLength = 24 }
    if ($gw) { $ipParams.DefaultGateway = $gw }
    New-NetIPAddress @ipParams -ErrorAction SilentlyContinue | Out-Null

    # --- SOLUCION A LAS LETRAS ROJAS (RPC / WIN32 1753) ---
    Write-Host "[*] Iniciando servicio y esperando sincronizacion..." -ForegroundColor Yellow
    Start-Service DHCPServer
    while ((Get-Service DHCPServer).Status -ne "Running") { Start-Sleep -Seconds 1 }
    Start-Sleep -Seconds 4 # Tiempo extra vital para que el motor DHCP responda

    # Limpieza de Scopes antiguos para evitar conflictos
    Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue

    $base = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + ".0"
    $r_i  = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)
    
    Add-DhcpServerv4Scope -Name "Red_Limpia" -StartRange $r_i -EndRange $ip_f -SubnetMask $mask -State Active
    if ($gw) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw }
    Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns -Force
    Set-DhcpServerv4Binding -InterfaceAlias $Global:InterfazActiva -BindingState $true
    
    Restart-Service DHCPServer -Force
    Write-Host "[OK] DHCP Configurado sin errores rojos." -ForegroundColor Green
    Pause
}

function Menu-DNS {
    Gestionar-Instalacion -FeatureName "DNS" -ServiceName "DnsServer"
    do {
        Clear-Host
        Write-Host "--- GESTION DNS ---" -ForegroundColor Yellow
        Write-Host "1) ALTA | 2) CONSULTA TOTAL | 3) Volver"
        $opDNS = Read-Host "Opcion"

        switch ($opDNS) {
            "1" {
                $zona = Read-Host "Nombre Zona (ej: reprobados.com)"
                if (-not $Global:InterfazActiva) { $Global:InterfazActiva = Read-Host "Introduce el nombre de la Interfaz" }
                
                # Obtiene la IP actual de la tarjeta seleccionada (evita error de null)
                $ip_actual = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias $Global:InterfazActiva).IPAddress[0]
                $ip = Read-Host "IP (Enter para usar la del servidor: $ip_actual)"
                if (-not $ip) { $ip = $ip_actual }

                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns" -ErrorAction SilentlyContinue
                }
                
                # Usamos SilentlyContinue para ignorar el error si el registro ya existe (ResourceExists)
                Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue

                $oct = $ip.Split('.'); $inv = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
                if (-not (Get-DnsServerZone -Name $inv -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $inv -ZoneFile "$inv.dns" -ErrorAction SilentlyContinue
                }
                Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $inv -PtrDomainName "$zona." -ErrorAction SilentlyContinue
                
                Write-Host "[OK] DNS Configurado." -ForegroundColor Green; Pause
            }
            "2" {
                Get-DnsServerZone | ForEach-Object {
                    Write-Host "`n>> ZONA: $($_.ZoneName)" -ForegroundColor Magenta
                    Get-DnsServerResourceRecord -ZoneName $_.ZoneName | ft HostName, RecordType, RecordData -AutoSize
                }
                Pause
            }
        }
    } while ($opDNS -ne "3")
}

do {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    GESTOR DE SERVIDOR DEFINITIVO" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host " 1) DHCP (Limpia IPs y crea Scope)"
    Write-Host " 2) DNS (Altas y Consultas)"
    Write-Host " 3) Salir"
    $m = Read-Host " Selecciona"
    if ($m -eq "1") { Menu-DHCP }
    if ($m -eq "2") { Menu-DNS }
} while ($m -ne "3")
