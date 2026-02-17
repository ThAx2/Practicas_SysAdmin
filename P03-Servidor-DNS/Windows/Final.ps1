# --- 1. FUNCIÓN DE INSTALACIÓN BLINDADA ---
function Forzar-Instalacion {
    param($NombrePS, $NombreDISM)

    Write-Host "`n [+] Verificando $NombrePS..." -ForegroundColor Cyan

    if (-not (Get-WindowsFeature $NombrePS).Installed) {

        Write-Host " [*] Instalando vía DISM..." -ForegroundColor Yellow

        dism /online /enable-feature /featurename:$NombreDISM /all /norestart | Out-Null
    }
}

# ---------------- DNS -----------------

function Crear-Zona-Reversa($ip){

    $partes = $ip.Split('.')
    $networkId = "$($partes[0]).$($partes[1]).$($partes[2]).0/24"

    $zonaReversa = "$($partes[2]).$($partes[1]).$($partes[0]).in-addr.arpa"

    if (-not (Get-DnsServerZone -Name $zonaReversa -ErrorAction SilentlyContinue)){

        Write-Host " [*] Creando zona reversa $zonaReversa" -ForegroundColor Cyan
        Add-DnsServerPrimaryZone -NetworkId $networkId -ReplicationScope Forest
    }

    return $zonaReversa
}


function Menu-DNS{
    do {
        Clear-Host
        Write-Host "=== ABC DE DNS (CON REVERSA) ===" -ForegroundColor Yellow
        Write-Host " 1) ALTA (A + PTR + www)"
        Write-Host " 2) BAJA (Eliminar A y PTR)"
        Write-Host " 3) CONSULTA COMPLETA"
        Write-Host " 4) Volver al Menú Principal"

        $abc = Read-Host " Selecciona una opción"

        switch ($abc) {

            "1" {

                $zona = Read-Host " Nombre de la Zona (ej: pecas.com)"
                $hostName = Read-Host " Nombre del Host (ej: servidor o @)"
                $ipAddr = Read-Host " Dirección IP"

                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Write-Host " [*] Creando zona directa $zona..." -ForegroundColor Cyan
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns"
                }

                try {

                    Add-DnsServerResourceRecordA -Name $hostName -ZoneName $zona -IPv4Address $ipAddr -ErrorAction Stop

                    # alias www
                    if ($hostName -ne "www"){

                        $destino = if ($hostName -eq "@") { $zona } else { "$hostName.$zona" }

                        if (-not (Get-DnsServerResourceRecord -ZoneName $zona -Name "www" -RRType CNAME -ErrorAction SilentlyContinue)){

                            Add-DnsServerResourceRecordCName -ZoneName $zona -Name "www" -HostNameAlias $destino
                        }
                    }

                    # ----- PTR -----

                    $zonaReversa = Crear-Zona-Reversa $ipAddr
                    $ultimo = $ipAddr.Split('.')[-1]

                    $fqdn = if ($hostName -eq "@") { "$zona." } else { "$hostName.$zona." }

                    Add-DnsServerResourceRecordPtr `
                        -ZoneName $zonaReversa `
                        -Name $ultimo `
                        -PtrDomainName $fqdn `
                        -ErrorAction SilentlyContinue

                    Write-Host " [OK] A, PTR y www creados." -ForegroundColor Green

                } catch {
                    Write-Host " [!] Error creando el registro." -ForegroundColor Red
                }

                Pause
            }

            "2" {

                $zona = Read-Host " Zona directa"
                $hostName = Read-Host " Host a eliminar"
                $ip = Read-Host " IP del host"

                Remove-DnsServerResourceRecord -ZoneName $zona -Name $hostName -RRType A -Force -ErrorAction SilentlyContinue

                $partes = $ip.Split('.')
                $zonaReversa = "$($partes[2]).$($partes[1]).$($partes[0]).in-addr.arpa"
                $ultimo = $partes[3]

                Remove-DnsServerResourceRecord -ZoneName $zonaReversa -Name $ultimo -RRType PTR -Force -ErrorAction SilentlyContinue

                Write-Host " [OK] Registros eliminados." -ForegroundColor Yellow
                Pause
            }

            "3" {

                $zona = Read-Host " Zona a consultar (directa o reversa)"

                Write-Host ""
                Write-Host "---------------- REGISTROS COMPLETOS ----------------" -ForegroundColor Cyan

                Get-DnsServerResourceRecord -ZoneName $zona |
                Select HostName,RecordType,TimeToLive,RecordClass,
                @{n="Data";e={
                    if($_.RecordData.IPv4Address){$_.RecordData.IPv4Address}
                    elseif($_.RecordData.PtrDomainName){$_.RecordData.PtrDomainName}
                    elseif($_.RecordData.HostNameAlias){$_.RecordData.HostNameAlias}
                    else{$_.RecordData}
                }} |
                Format-Table -AutoSize

                Pause
            }
        }

    } while ($abc -ne "4")
}


# ---------------- DHCP ----------------

function Ejecutar-DHCP {

    Forzar-Instalacion -NombrePS "DHCP" -NombreDISM "DHCPServer"

    $int = Read-Host "Interfaz (ej. Ethernet 2)"
    $ip_s = Read-Host "IP fija del servidor"
    $ip_f = Read-Host "IP final del rango"
    $dns = Read-Host "DNS para clientes"

    $base = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + ".0"

    $r_i = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)
    $r_f = $ip_f.SubString(0, $ip_f.LastIndexOf('.')) + "." + ([int]$ip_f.Split('.')[3] + 1)

    Write-Host "Configurando IP..." -ForegroundColor Cyan

    New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_s -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null

    if (Get-Command Add-DhcpServerv4Scope -ErrorAction SilentlyContinue) {

        Remove-DhcpServerv4Scope -ScopeId $base -Force -ErrorAction SilentlyContinue

        Add-DhcpServerv4Scope -Name "Red_Pecas" -StartRange $r_i -EndRange $r_f -SubnetMask 255.255.255.0 -State Active

        if ($dns) {

            Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns
        }

        Write-Host "DHCP CONFIGURADO." -ForegroundColor Green

    } else {

        Write-Host "ERROR: EL SERVICIO NO RESPONDE." -ForegroundColor Red
    }

    Pause
}


# ---------------- MENÚ PRINCIPAL ----------------

do {
    Clear-Host
    Write-Host "=== GESTOR TOTAL REPARADO ===" -ForegroundColor Cyan
    Write-Host "1) DHCP (Configurar)"
    Write-Host "2) DNS (ABC + Reversa)"
    Write-Host "3) Salir"

    $m = Read-Host "Opcion"

    if ($m -eq "1") { Ejecutar-DHCP }
    if ($m -eq "2") { Menu-DNS }

} while ($m -ne "3")

