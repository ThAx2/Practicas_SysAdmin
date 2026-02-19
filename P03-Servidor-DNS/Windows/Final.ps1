# --- AUTO-ELEVACIÓN ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Ejecuta como Administrador." -ForegroundColor Red; pause; exit
}

$Global:InterfazActiva = ""

function Menu-DHCP {
    if (-not (Get-WindowsFeature DHCP).Installed) { Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null }
    Import-Module DhcpServer -ErrorAction SilentlyContinue
    
    Clear-Host
    Write-Host "=== CONFIGURACION DHCP ===" -ForegroundColor Yellow
    $Global:InterfazActiva = Read-Host "Interfaz (ej: Ethernet 2)"
    $ip_s = Read-Host "IP Servidor (ej: 10.10.10.3)"
    $mask = Read-Host "Mascara (ej: 255.255.255.0)"
    $gw   = Read-Host "Gateway (Enter para dejar VACIO)"
    $ip_f = Read-Host "IP Final Rango DHCP"
    $dns  = Read-Host "DNS (Enter para usar $ip_s)"
    if (-not $dns) { $dns = $ip_s }

    Write-Host "`n[*] Limpiando red y fijando IP..." -ForegroundColor Cyan
    Stop-Service DHCPServer -Force -ErrorAction SilentlyContinue
    
    # Quitar modo cliente para evitar el 169.254
    Set-NetIPInterface -InterfaceAlias $Global:InterfazActiva -DHCP Disabled -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceAlias $Global:InterfazActiva -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    
    $params = @{ InterfaceAlias = $Global:InterfazActiva; IPAddress = $ip_s; PrefixLength = 24 }
    if ($gw) { $params.DefaultGateway = $gw } # El gateway puede ir vacío como pediste
    New-NetIPAddress @params -ErrorAction SilentlyContinue | Out-Null

    Write-Host "[*] Esperando al servicio RPC (Letras Rojas Fix)..." -ForegroundColor Yellow
    Start-Service DHCPServer
    while ((Get-Service DHCPServer).Status -ne "Running") { Start-Sleep -Seconds 1 }
    Start-Sleep -Seconds 4 

    Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue
    $base = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + ".0"
    $r_i  = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)
    
    Add-DhcpServerv4Scope -Name "Red_Limpia" -StartRange $r_i -EndRange $ip_f -SubnetMask $mask -State Active
    if ($gw) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw }
    Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns -Force
    Set-DhcpServerv4Binding -InterfaceAlias $Global:InterfazActiva -BindingState $true
    
    Restart-Service DHCPServer -Force
    Write-Host "[OK] DHCP listo." -ForegroundColor Green; Pause
}

function Menu-DNS {
    if (-not (Get-WindowsFeature DNS).Installed) { Install-WindowsFeature DNS -IncludeManagementTools | Out-Null }
    Import-Module DnsServer -ErrorAction SilentlyContinue
    do {
        Clear-Host
        Write-Host "=== GESTION DNS ===" -ForegroundColor Yellow
        Write-Host "1) ALTA | 2) BAJA | 3) CONSULTA | 4) Volver"
        $op = Read-Host "Opcion"

        switch ($op) {
            "1" {
                $zona = Read-Host "Nombre Dominio"
                if ($Global:InterfazActiva -eq "") { $Global:InterfazActiva = Read-Host "Interfaz (ej: Ethernet 2)" }
                
                # FIX: Obtener IP real del servidor para el default
                $ip_serv = (Get-NetIPAddress -InterfaceAlias $Global:InterfazActiva -AddressFamily IPv4).IPAddress[0]
                $ip = Read-Host "IP Destino (Enter para $ip_serv)"
                if (-not $ip) { $ip = $ip_serv }

                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns" -ErrorAction SilentlyContinue
                }
                Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                
                # Inversa
                $oct = $ip.Split('.'); $inv = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
                if (-not (Get-DnsServerZone -Name $inv -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $inv -ZoneFile "$inv.dns" -ErrorAction SilentlyContinue
                }
                Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $inv -PtrDomainName "$zona." -ErrorAction SilentlyContinue
                Write-Host "[OK] Alta completada." -ForegroundColor Green; Pause
            }
            "2" {
                $zona = Read-Host "Zona a borrar"
                Remove-DnsServerZone -Name $zona -Force -ErrorAction SilentlyContinue
                Write-Host "[!] Zona $zona borrada. No olvides borrar la inversa si es necesario." -ForegroundColor Yellow; Pause
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
    Write-Host "=== GESTOR SERVIDOR ===" -ForegroundColor Cyan
    Write-Host "1) DHCP | 2) DNS | 3) Salir"
    $m = Read-Host "Selecciona"
    if ($m -eq "1") { Menu-DHCP }
    if ($m -eq "2") { Menu-DNS }
} while ($m -ne "3")
