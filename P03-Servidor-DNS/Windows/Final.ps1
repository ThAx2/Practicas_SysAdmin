if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Ejecuta como Administrador." -ForegroundColor Red; pause; exit
}

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
    $int  = Read-Host "Nombre Interfaz (ej: Ethernet 2)"
    $ip_s = Read-Host "IP Servidor (ej: 192.168.100.20)"
    $mask = Read-Host "Mascara (ej: 255.255.255.0)"
    $gw   = Read-Host "Gateway (Enter para dejar vacio)"
    $ip_f = Read-Host "IP Final Rango"
    $dns  = Read-Host "DNS (Enter para usar $ip_s)"
    if (-not $dns) { $dns = $ip_s }

    Write-Host "`n[!] LIMPIANDO INTERFAZ Y DESACTIVANDO MODO CLIENTE..." -ForegroundColor Red
    Stop-Service DHCPServer -Force -ErrorAction SilentlyContinue
    
    # Esto quita el 169.254 y permite que la IP fija funcione
    Set-NetIPInterface -InterfaceAlias $int -DHCP Disabled -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceAlias $int -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue

    Write-Host "[*] Aplicando IP Fija..." -ForegroundColor Cyan
    $params = @{ InterfaceAlias = $int; IPAddress = $ip_s; PrefixLength = 24 }
    if ($gw) { $params.DefaultGateway = $gw }
    New-NetIPAddress @params -ErrorAction SilentlyContinue | Out-Null

    $base = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + ".0"
    $r_i  = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)
    
    Add-DhcpServerv4Scope -Name "Red_Limpia" -StartRange $r_i -EndRange $ip_f -SubnetMask $mask -State Active
    if ($gw) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw }
    Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns -Force
    
    Set-DhcpServerv4Binding -InterfaceAlias $int -BindingState $true
    Start-Service DHCPServer
    Write-Host "[OK] DHCP Configurado. El servidor ya no deberia tener IP 169.254." -ForegroundColor Green
    Pause
}

function Menu-DNS {
    Gestionar-Instalacion -FeatureName "DNS" -ServiceName "DnsServer"
    do {
        Clear-Host
        Write-Host "--- GESTION DNS ---" -ForegroundColor Yellow
        Write-Host "1) ALTA | 2) BAJA | 3) CONSULTA TOTAL | 4) Volver"
        $opDNS = Read-Host "Opcion"

        switch ($opDNS) {
            "1" {
                $zona = Read-Host "Nombre Zona"; $ip = Read-Host "IP (Enter para servidor)"
                if (-not $ip) { $ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias $int).IPAddress[0] }
                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns" -ErrorAction SilentlyContinue
                }
                Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                $oct = $ip.Split('.'); $invZone = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
                if (-not (Get-DnsServerZone -Name $invZone -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $invZone -ZoneFile "$invZone.dns" -ErrorAction SilentlyContinue
                }
                Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $invZone -PtrDomainName "$zona." -ErrorAction SilentlyContinue
                Pause
            }
            "2" {
                $z = Read-Host "Zona a borrar"; Remove-DnsServerZone -Name $z -Force -ErrorAction SilentlyContinue; Pause
            }
            "3" {
                Get-DnsServerZone | ForEach-Object {
                    Write-Host "`n>> ZONA: $($_.ZoneName)" -ForegroundColor Magenta
                    Get-DnsServerResourceRecord -ZoneName $_.ZoneName | ft HostName, RecordType, RecordData -AutoSize
                }
                Pause
            }
        }
    } while ($opDNS -ne "4")
}

do {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    GESTOR DE SERVIDOR" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host " 1) DHCP (Fijar IP y Scope)"
    Write-Host " 2) DNS (Altas/Bajas/Consultas)"
    Write-Host " 3) Salir"
    $m = Read-Host " Selecciona"
    if ($m -eq "1") { Menu-DHCP }
    if ($m -eq "2") { Menu-DNS }
} while ($m -ne "3")
