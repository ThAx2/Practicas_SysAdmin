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

function Menu-DNS{
    do {
        Clear-Host
        Write-Host "=== ABC DE DNS (SIN ERRORES) ===" -ForegroundColor Yellow
        Write-Host " 1) ALTA (Crear Zona y Registro A)"
        Write-Host " 2) BAJA (Eliminar Registro)"
        Write-Host " 3) CONSULTA (Ver Registros)"
        Write-Host " 4) Volver al Menú Principal"
        $abc = Read-Host " Selecciona una opción"

        switch ($abc) {
            "1" {
                $zona = Read-Host " Nombre de la Zona (ej: pecas.com)"
                $hostName = Read-Host " Nombre del Host (ej: www o @)"
                $ipAddr = Read-Host " Dirección IP para el registro"
                
                # Crear la zona solo si no existe para evitar errores
                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Write-Host " [*] Creando zona $zona..." -ForegroundColor Cyan
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns" -ErrorAction SilentlyContinue
                }

                # ALTA: Sin el parametro -Force que causa el error
                try {
                    Add-DnsServerResourceRecordA -Name $hostName -ZoneName $zona -IPv4Address $ipAddr -ErrorAction Stop
                    Write-Host " [OK] Registro '$hostName' creado en '$zona'." -ForegroundColor Green
                } catch {
                    Write-Host " [!] Error al crear registro. Revisa que no exista ya." -ForegroundColor Red
                }
                Pause
            }
            "2" {
                $zona = Read-Host " Nombre de la Zona"
                $hostName = Read-Host " Nombre del Host a eliminar"
                # BAJA: Aqui el -Force si funciona para no pedir confirmacion
                Remove-DnsServerResourceRecord -ZoneName $zona -Name $hostName -RRType A -Force
                Write-Host " [OK] Registro eliminado si existía." -ForegroundColor Yellow
                Pause
            }
            "3" {
                $zona = Read-Host " Zona a consultar"
                Write-Host " --- Registros en $zona ---" -ForegroundColor Cyan
                # CONSULTA: Listado limpio
                Get-DnsServerResourceRecord -ZoneName $zona | Format-Table HostName, RecordType, RecordData -AutoSize
                Pause
            }
        }
    } while ($abc -ne "4")
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
