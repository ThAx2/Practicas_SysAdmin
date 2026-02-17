# -------------------------------
# COMPROBAR ADMIN
# -------------------------------
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Ejecuta como Administrador" -ForegroundColor Red
    pause; exit
}

Import-Module DnsServer -ErrorAction SilentlyContinue
Import-Module DhcpServer -ErrorAction SilentlyContinue

do {
    Clear-Host
    Write-Host "===== GESTOR COMPLETO (DIRECTA + INVERSA) =====" -ForegroundColor Cyan
    Write-Host "1) Configurar DHCP"
    Write-Host "2) Alta DNS (Dominio + WWW + Inversa)"
    Write-Host "3) Salir"
    $op = Read-Host "Opcion"

    if ($op -eq "1") {
        $int = Read-Host "Interfaz (ej: Ethernet 2)"
        $ip_s = Read-Host "IP del servidor"
        $ip_f = Read-Host "IP final del rango"
        
        New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_s -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null

        $base = $ip_s.Substring(0,$ip_s.LastIndexOf('.')) + ".0"
        $r_i = $ip_s.Substring(0,$ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)

        Remove-DhcpServerv4Scope -ScopeId $base -Force -ErrorAction SilentlyContinue
        Add-DhcpServerv4Scope -Name "Red_Local" -StartRange $r_i -EndRange $ip_f -SubnetMask 255.255.255.0 -State Active
        Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $ip_s -ErrorAction SilentlyContinue
        
        Write-Host "`n[OK] DHCP configurado." -ForegroundColor Green
        pause
    }
    elseif ($op -eq "2") {
        $fullDomain = Read-Host "Nombre del dominio (ej: pecas.com)"
        $ip_puntos = Read-Host "IP a la que apunta (ej: 192.168.100.20)"

        # 1. Procesar Dominio
        $domain = $fullDomain -replace "^www\.", ""

        # 2. Crear Zona Directa
        if (-not (Get-DnsServerZone -Name $domain -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -Name $domain -ZoneFile "$domain.dns"
        }
        Add-DnsServerResourceRecordA -Name "@" -ZoneName $domain -IPv4Address $ip_puntos -Force -ErrorAction SilentlyContinue
        Add-DnsServerResourceRecordA -Name "www" -ZoneName $domain -IPv4Address $ip_puntos -Force -ErrorAction SilentlyContinue

        # 3. ZONA INVERSA (Cálculo manual para evitar errores de red)
        $oct = $ip_puntos.Split('.')
        $invZone = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"

        if (-not (Get-DnsServerZone -Name $invZone -ErrorAction SilentlyContinue)) {
            # Se crea por nombre de zona para evitar el fallo de "Parameter set"
            Add-DnsServerPrimaryZone -Name $invZone -ZoneFile "$invZone.dns"
        }

        # 4. Crear el registro PTR (Inverso)
        Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $invZone -PtrDomainName "$domain." -Force -ErrorAction SilentlyContinue

        Write-Host "`n[OK] Configurado: $domain, www.$domain y su zona inversa." -ForegroundColor Green
        pause
    }
} while ($op -ne "3")
