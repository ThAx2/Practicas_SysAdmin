# --- COMPROBAR ADMIN ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Ejecuta como Administrador" -ForegroundColor Red; pause; exit
}

Import-Module DnsServer, DhcpServer -ErrorAction SilentlyContinue

do {
    Clear-Host
    Write-Host "===== GESTOR TOTAL: DHCP + DNS (ALTAS/BAJAS/CONSULTAS) =====" -ForegroundColor Cyan
    Write-Host "1) Configurar DHCP (Rango, Mask, Gateway, DNS)"
    Write-Host "2) DNS: Alta de Dominio (Directa + WWW + Inversa)"
    Write-Host "3) DNS: Baja de Dominio"
    Write-Host "4) DNS: Consulta de Zonas"
    Write-Host "5) Salir"
    $op = Read-Host "Opcion"

    if ($op -eq "1") {
        $int = Read-Host "Interfaz (ej: Ethernet 2)"
        $ip_s = Read-Host "IP fija del Servidor"
        $ip_f = Read-Host "IP final del rango DHCP"
        $mask = Read-Host "Mascara de subred (ej: 255.255.255.0)"
        $gw   = Read-Host "Puerta de Enlace (Gateway)"
        $dns_cli = Read-Host "DNS para clientes (Enter para usar la IP fija $ip_s)"
        if (-not $dns_cli) { $dns_cli = $ip_s }

        New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_s -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null

        $base = $ip_s.Substring(0,$ip_s.LastIndexOf('.')) + ".0"
        $r_i = $ip_s.Substring(0,$ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)

        Remove-DhcpServerv4Scope -ScopeId $base -Force -ErrorAction SilentlyContinue
        Add-DhcpServerv4Scope -Name "Red_Interna" -StartRange $r_i -EndRange $ip_f -SubnetMask $mask -State Active
        
        # Configuracion de opciones (Gateway y DNS)
        Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw
        Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns_cli -ErrorAction SilentlyContinue
        
        Write-Host "[OK] DHCP configurado con exito." -ForegroundColor Green; pause
    }
    elseif ($op -eq "2") {
        $fullDomain = Read-Host "Dominio (ej: pecas.com)"
        $ip_dest = Read-Host "IP de destino (Enter para usar la fija del servidor)"
        if (-not $ip_dest) { $ip_dest = (Get-NetIPAddress -InterfaceAlias "Ethernet 2" -AddressFamily IPv4).IPAddress }

        $domain = $fullDomain -replace "^www\.", ""

        # Zona Directa y registros
        if (-not (Get-DnsServerZone -Name $domain -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -Name $domain -ZoneFile "$domain.dns"
        }
        Add-DnsServerResourceRecordA -Name "@" -ZoneName $domain -IPv4Address $ip_dest -ErrorAction SilentlyContinue
        Add-DnsServerResourceRecordA -Name "www" -ZoneName $domain -IPv4Address $ip_dest -ErrorAction SilentlyContinue

        # Zona Inversa y PTR
        $oct = $ip_dest.Split('.')
        $invZone = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
        if (-not (Get-DnsServerZone -Name $invZone -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -Name $invZone -ZoneFile "$invZone.dns"
        }
        Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $invZone -PtrDomainName "$domain." -ErrorAction SilentlyContinue

        Write-Host "[OK] Alta completada para $domain." -ForegroundColor Green; pause
    }
    elseif ($op -eq "3") {
        $delZone = Read-Host "Nombre del dominio a eliminar"
        Remove-DnsServerZone -Name $delZone -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Zona eliminada." -ForegroundColor Yellow; pause
    }
    elseif ($op -eq "4") {
        Write-Host "`n--- ZONAS CONFIGURADAS ---" -ForegroundColor Cyan
        Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | ft ZoneName, ZoneType
        pause
    }
} while ($op -ne "5")
