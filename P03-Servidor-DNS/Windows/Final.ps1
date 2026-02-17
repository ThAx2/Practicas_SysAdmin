# -------------------------------
# COMPROBAR ADMIN
# -------------------------------
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Ejecuta como Administrador" -ForegroundColor Red
    pause; exit
}

# -------------------------------
# INSTALACION FORZADA (Corregida)
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
        Write-Host "=== GESTION DNS COMPLETA (FIXED) ===" -ForegroundColor Cyan
        Write-Host "1) Alta (A + www + raiz + PTR)"
        Write-Host "2) Baja (A + PTR)"
        Write-Host "3) Consulta completa"
        Write-Host "4) Volver"
        $op = Read-Host "Opcion"

        switch ($op) {
            "1" {
                $zona = Read-Host "Zona directa (ej: pecas.local)"
                # CAMBIADO: $host por $nombreHost para evitar error de solo lectura
                $nombreHost = Read-Host "Nombre del host (ej: servidor)" 
                $ip = Read-Host "IP (ej: 192.168.100.20)"

                # ZONA DIRECTA
                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns"
                }

                # Registro A del host específico
                if ($nombreHost -and $nombreHost -ne "@") {
                    Add-DnsServerResourceRecordA -Name $nombreHost -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                }

                # Registro A para la raíz (@) y WWW
                Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue

                # ZONA INVERSA (Corregida la lógica del NetworkId)
                $oct = $ip.Split('.')
                $redBase = "$($oct[0]).$($oct[1]).$($oct[2]).0/24"
                $reverseZone = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"

                if (-not (Get-DnsServerZone -Name $reverseZone -ErrorAction SilentlyContinue)) {
                    # Usamos el formato de RedId que Windows espera
                    Add-DnsServerPrimaryZone -NetworkId "$($oct[0]).$($oct[1]).$($oct[2]).0/24"
                }

                # PTR (Apunta a la zona directa)
                Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $reverseZone -PtrDomainName "$zona." -ErrorAction SilentlyContinue

                Write-Host "`n[OK] Registros A, WWW, Raiz y PTR creados correctamente." -ForegroundColor Green
                pause
            }
            "2" {
                $zona = Read-Host "Zona directa"
                $ip = Read-Host "IP del host a borrar"
                $oct = $ip.Split('.')
                $reverseZone = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"

                Remove-DnsServerZone -Name $zona -Force -ErrorAction SilentlyContinue
                Remove-DnsServerZone -Name $reverseZone -Force -ErrorAction SilentlyContinue
                Write-Host "[OK] Zonas eliminadas." -ForegroundColor Yellow
                pause
            }
            "3" {
                Clear-Host
                Write-Host "--- DETALLE DE ZONAS ---" -ForegroundColor Cyan
                Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | ForEach-Object {
                    Write-Host "`nZona: $($_.ZoneName)" -ForegroundColor Yellow
                    Get-DnsServerResourceRecord -ZoneName $_.ZoneName | Format-Table HostName, RecordType, @{n="Data";e={$_.RecordData.IPv4Address, $_.RecordData.PtrDomainName}} -AutoSize
                }
                pause
            }
        }
    } while ($op -ne "4")
}

# -------------------------------
# DHCP (Saneado)
# -------------------------------
function Ejecutar-DHCP {
    Forzar-Instalacion -NombrePS "DHCP" -NombreDISM "DHCPServer"
    
    $int = Read-Host "Interfaz (ej. Ethernet 2)"
    $ip_s = Read-Host "IP del servidor (ej. 192.168.100.10)"
    $ip_f = Read-Host "IP final del rango (ej. 192.168.100.50)"
    $dns = Read-Host "DNS para clientes (Enter para usar la IP del servidor)"
    if (-not $dns) { $dns = $ip_s }

    # Configurar IP estática en la tarjeta
    New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_s -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null

    # Importar modulo si no está (Arregla error de comando no encontrado)
    Import-Module DhcpServer -ErrorAction SilentlyContinue

    $base = $ip_s.Substring(0,$ip_s.LastIndexOf('.')) + ".0"
    $r_inicio = $ip_s.Substring(0,$ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)

    Remove-DhcpServerv4Scope -ScopeId $base -Force -ErrorAction SilentlyContinue
    
    Add-DhcpServerv4Scope -Name "Red_Local" -StartRange $r_inicio -EndRange $ip_f -SubnetMask 255.255.255.0 -State Active
    Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns

    Write-Host "[OK] DHCP configurado y activo." -ForegroundColor Green
    pause
}

# -------------------------------
# MENU PRINCIPAL
# -------------------------------
do {
    Clear-Host
    Write-Host "===== GESTOR TOTAL REPARADO =====" -ForegroundColor Cyan
    Write-Host "1) DHCP (Red Interna)"
    Write-Host "2) DNS (Directa + Inversa)"
    Write-Host "3) Salir"
    $m = Read-Host "Opcion"

    if ($m -eq "1") { Ejecutar-DHCP }
    if ($m -eq "2") { Menu-DNS }
} while ($m -ne "3")
