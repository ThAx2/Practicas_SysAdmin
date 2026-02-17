# --- 1. FUNCIÓN DE INSTALACIÓN BLINDADA ---
function Forzar-Instalacion {
    param($NombrePS, $NombreDISM)
    Write-Host "`n [+] Verificando $NombrePS..." -ForegroundColor Cyan
    if (-not (Get-WindowsFeature $NombrePS).Installed) {
        Write-Host " [*] Instalando vía DISM para saltar bloqueos..." -ForegroundColor Yellow
        # Usamos los nombres correctos para Server 2022
        dism /online /enable-feature /featurename:$NombreDISM /all /norestart | Out-Null
    }
}

# --- 2. EL PUTO ABC DE DNS ---
function Menu-DNS {
    Forzar-Instalacion -NombrePS "DNS" -NombreDISM "DNS"
    do {
        Clear-Host
        Write-Host "=== ABC DE DNS ===" -ForegroundColor Yellow
        Write-Host "1) ALTA (Zona y Registro A)"
        Write-Host "2) BAJA (Borrar Registro)"
        Write-Host "3) CONSULTA"
        Write-Host "4) Volver"
        $op = Read-Host "Selecciona"
        switch ($op) {
            "1" {
                $z = Read-Host "Nombre de Zona"; $h = Read-Host "Host (www)"; $ip = Read-Host "IP"
                Add-DnsServerPrimaryZone -Name $z -ZoneFile "$z.dns" -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name $h -ZoneName $z -IPv4Address $ip -Force
                Write-Host "Hecho."; Pause
            }
            "2" {
                $z = Read-Host "Zona"; $h = Read-Host "Host"
                Remove-DnsServerResourceRecord -ZoneName $z -Name $h -RRType A -Force; Pause
            }
            "3" {
                $z = Read-Host "Zona"; Get-DnsServerResourceRecord -ZoneName $z | Format-Table; Pause
            }
        }
    } while ($op -ne "4")
}

# --- 3. CONFIGURACIÓN DHCP (Tu lógica +1) ---
function Ejecutar-DHCP {
    Forzar-Instalacion -NombrePS "DHCP" -NombreDISM "DHCPServer"
    
    $int = Read-Host "Interfaz (ej. Ethernet 2)"
    $ip_s = Read-Host "IP Servidor"
    $ip_f = Read-Host "IP Final del Rango"
    $dns = Read-Host "DNS para Clientes (Enter para saltar)"

    $base = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + ".0"
    $r_i = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)
    $r_f = $ip_f.SubString(0, $ip_f.LastIndexOf('.')) + "." + ([int]$ip_f.Split('.')[3] + 1)

    Write-Host "Configurando..." -ForegroundColor Cyan
    New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_s -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    
    # Verificamos si el comando ya existe tras el DISM
    if (Get-Command Add-DhcpServerv4Scope -ErrorAction SilentlyContinue) {
        Remove-DhcpServerv4Scope -ScopeId $base -Force -ErrorAction SilentlyContinue
        Add-DhcpServerv4Scope -Name "Red_Pecas" -StartRange $r_i -EndRange $r_f -SubnetMask 255.255.255.0 -State Active
        if ($dns) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns }
        Write-Host "DHCP CONFIGURADO." -ForegroundColor Green
    } else {
        Write-Host "ERROR: EL SERVICIO NO RESPONDE. REINICIA EL SERVIDOR." -ForegroundColor Red
    }
    Pause
}

# --- MENÚ PRINCIPAL ---
do {
    Clear-Host
    Write-Host "=== GESTOR TOTAL REPARADO ===" -ForegroundColor Cyan
    Write-Host "1) DHCP (Configurar)"
    Write-Host "2) DNS (ABC)"
    Write-Host "3) Salir"
    $m = Read-Host "Opcion"
    if ($m -eq "1") { Ejecutar-DHCP }
    if ($m -eq "2") { Menu-DNS }
} while ($m -ne "3")
