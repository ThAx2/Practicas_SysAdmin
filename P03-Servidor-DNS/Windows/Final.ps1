# -------------------------------
# COMPROBAR ADMIN
# -------------------------------
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $currentPrincipal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {

    Write-Host "[!] Ejecuta como Administrador" -ForegroundColor Red
    pause
    exit
}

# -------------------------------
# INSTALACION FORZADA
# -------------------------------
function Forzar-Instalacion {
    param($NombrePS, $NombreDISM)

    Write-Host "`n[+] Verificando $NombrePS..." -ForegroundColor Cyan

    if (-not (Get-WindowsFeature $NombrePS).Installed) {
        Write-Host "[*] Instalando por DISM..." -ForegroundColor Yellow
        dism /online /enable-feature /featurename:$NombreDISM /all /norestart | Out-Null
    }
}

# -------------------------------
# MENU DNS CON DIRECTA + INVERSA
# -------------------------------
function Menu-DNS {

    Forzar-Instalacion -NombrePS "DNS" -NombreDISM "DNS-Server-Full-Role"

    do {
        Clear-Host
        Write-Host "=== GESTION DNS COMPLETA ===" -ForegroundColor Cyan
        Write-Host "1) Alta (A + www + raiz + PTR)"
        Write-Host "2) Baja (A + PTR)"
        Write-Host "3) Consulta completa"
        Write-Host "4) Volver"

        $op = Read-Host "Opcion"

        switch ($op) {

            # -------------------------------
            # ALTA
            # -------------------------------
            "1" {

                $zona = Read-Host "Zona directa (ej: pecas.local)"
                $host = Read-Host "Host principal (ej: servidor o @)"
                $ip   = Read-Host "IP"

                # ----- ZONA DIRECTA -----
                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns"
                }

                # A del host
                if ($host -ne "@") {
                    Add-DnsServerResourceRecordA `
                        -Name $host `
                        -ZoneName $zona `
                        -IPv4Address $ip `
                        -ErrorAction SilentlyContinue
                }

                # A para la raiz
                Add-DnsServerResourceRecordA `
                    -Name "@" `
                    -ZoneName $zona `
                    -IPv4Address $ip `
                    -ErrorAction SilentlyContinue

                # A para www
                Add-DnsServerResourceRecordA `
                    -Name "www" `
                    -ZoneName $zona `
                    -IPv4Address $ip `
                    -ErrorAction SilentlyContinue


                # ----- ZONA INVERSA -----
                $oct = $ip.Split('.')
                $network = "$($oct[0]).$($oct[1]).$($oct[2]).0/24"
                $reverseZone = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"

                if (-not (Get-DnsServerZone -Name $reverseZone -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -NetworkId $network
                }

                # PTR
                Add-DnsServerResourceRecordPtr `
                    -Name $oct[3] `
                    -ZoneName $reverseZone `
                    -PtrDomainName "$zona." `
                    -ErrorAction SilentlyContinue

                Write-Host "`n[OK] A, www, raiz y PTR creados." -ForegroundColor Green
                pause
            }

            # -------------------------------
            # BAJA
            # -------------------------------
            "2" {

                $zona = Read-Host "Zona directa"
                $host = Read-Host "Host a borrar"
                $ip   = Read-Host "IP del host"

                if ($host -ne "@") {
                    Remove-DnsServerResourceRecord `
                        -ZoneName $zona `
                        -Name $host `
                        -RRType A `
                        -Force `
                        -ErrorAction SilentlyContinue
                }

                Remove-DnsServerResourceRecord `
                    -ZoneName $zona `
                    -Name "www" `
                    -RRType A `
                    -Force `
                    -ErrorAction SilentlyContinue

                Remove-DnsServerResourceRecord `
                    -ZoneName $zona `
                    -Name "@" `
                    -RRType A `
                    -Force `
                    -ErrorAction SilentlyContinue

                $oct = $ip.Split('.')
                $reverseZone = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"

                Remove-DnsServerResourceRecord `
                    -ZoneName $reverseZone `
                    -Name $oct[3] `
                    -RRType PTR `
                    -Force `
                    -ErrorAction SilentlyContinue

                Write-Host "[OK] Registros eliminados." -ForegroundColor Yellow
                pause
            }

            # -------------------------------
            # CONSULTA COMPLETA
            # -------------------------------
            "3" {

                Clear-Host

                Write-Host "`n--- ZONAS DIRECTAS ---" -ForegroundColor Cyan

                Get-DnsServerZone |
                Where-Object { $_.IsReverseLookupZone -eq $false } |
                ForEach-Object {

                    Write-Host "`nZona: $($_.ZoneName)" -ForegroundColor Yellow
                    Get-DnsServerResourceRecord -ZoneName $_.ZoneName |
                    Format-Table HostName,RecordType,RecordData -AutoSize
                }

                Write-Host "`n--- ZONAS INVERSAS ---" -ForegroundColor Cyan

                Get-DnsServerZone |
                Where-Object { $_.IsReverseLookupZone -eq $true } |
                ForEach-Object {

                    Write-Host "`nZona: $($_.ZoneName)" -ForegroundColor Yellow
                    Get-DnsServerResourceRecord -ZoneName $_.ZoneName |
                    Format-Table HostName,RecordType,RecordData -AutoSize
                }

                pause
            }
        }

    } while ($op -ne "4")
}

# -------------------------------
# DHCP (tu version)
# -------------------------------
function Ejecutar-DHCP {

    Forzar-Instalacion -NombrePS "DHCP" -NombreDISM "DHCPServer"

    $int  = Read-Host "Interfaz (ej. Ethernet 2)"
    $ip_s = Read-Host "IP del servidor"
    $ip_f = Read-Host "IP final del rango"
    $dns  = Read-Host "DNS para clientes (Enter para omitir)"

    $base = $ip_s.Substring(0,$ip_s.LastIndexOf('.')) + ".0"

    $r_i = $ip_s.Substring(0,$ip_s.LastIndexOf('.')) + "." +
           ([int]$ip_s.Split('.')[3] + 1)

    $r_f = $ip_f.Substring(0,$ip_f.LastIndexOf('.')) + "." +
           ([int]$ip_f.Split('.')[3] + 1)

    New-NetIPAddress `
        -InterfaceAlias $int `
        -IPAddress $ip_s `
        -PrefixLength 24 `
        -ErrorAction SilentlyContinue | Out-Null

    if (Get-Command Add-DhcpServerv4Scope -ErrorAction SilentlyContinue) {

        Remove-DhcpServerv4Scope -ScopeId $base -Force -ErrorAction SilentlyContinue

        Add-DhcpServerv4Scope `
            -Name "Red_Pecas" `
            -StartRange $r_i `
            -EndRange $r_f `
            -SubnetMask 255.255.255.0 `
            -State Active

        if ($dns) {
            Set-DhcpServerv4OptionValue `
                -ScopeId $base `
                -OptionId 6 `
                -Value $dns
        }

        Write-Host "[OK] DHCP configurado." -ForegroundColor Green
    }
    else {
        Write-Host "[!] Error cargando modulo DHCP." -ForegroundColor Red
    }

    pause
}

# -------------------------------
# MENU PRINCIPAL
# -------------------------------
do {
    Clear-Host
    Write-Host "===== GESTOR TOTAL =====" -ForegroundColor Cyan
    Write-Host "1) DHCP"
    Write-Host "2) DNS (directa + inversa)"
    Write-Host "3) Salir"

    $m = Read-Host "Opcion"

    if ($m -eq "1") { Ejecutar-DHCP }
    if ($m -eq "2") { Menu-DNS }

} while ($m -ne "3")

