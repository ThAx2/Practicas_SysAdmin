# --- 1. FUNCIÓN DE INSTALACIÓN (SERVER 2022) ---
function Forzar-Instalacion {
    param($NombrePS, $NombreDISM)
    Write-Host "`n [+] Verificando $NombrePS..." -ForegroundColor Cyan
    if (-not (Get-WindowsFeature $NombrePS).Installed) {
        Write-Host " [*] Instalando vía DISM para Server 2022..." -ForegroundColor Yellow
        # Nombres correctos: DHCP -> DHCPServer, DNS -> DNS
        dism /online /enable-feature /featurename:$NombreDISM /all /norestart | Out-Null
    }
}

# --- 2. MÓDULO DNS AVANZADO (DIRECTA + INVERSA + WWW) ---
function Menu-DNS {
    do {
        Clear-Host
        Write-Host "=== GESTIÓN DNS PROFESIONAL (WINDOWS) ===" -ForegroundColor Yellow
        Write-Host " 1) ALTA (Dominio, WWW y Zona Inversa)"
        Write-Host " 2) BAJA (Eliminar Zona completa)"
        Write-Host " 3) CONSULTA (Listado de Dominios)"
        Write-Host " 4) Volver"
        $abc = Read-Host " Opción"

        switch ($abc) {
            "1" {
                $zona = Read-Host " Nombre del Dominio (ej: lol.com)"
                $ipAddr = Read-Host " IP de Destino (ej: 192.168.100.30)"
                
                # A. Crear Zona Directa
                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns"
                }

                # B. Crear Zona Inversa (Extraer red de la IP)
                $redInversa = $ipAddr.SubString(0, $ipAddr.LastIndexOf('.')) + ".0/24"
                if (-not (Get-DnsServerZone -Name "*in-addr.arpa" | Where-Object { $_.ZoneName -like "*$($ipAddr.Split('.')[2])*"})) {
                    Write-Host " [*] Creando Zona de Búsqueda Inversa..." -ForegroundColor Cyan
                    Add-DnsServerPrimaryZone -NetworkId $redInversa -ReplicationScope "Forest" -ErrorAction SilentlyContinue
                }

                # C. Crear Registros (Raíz y WWW) - Sin -Force para evitar error
                try {
                    Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ipAddr -ErrorAction SilentlyContinue
                    Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ipAddr -ErrorAction SilentlyContinue
                    # Registro PTR para resolución inversa
                    Add-DnsServerResourceRecordPointer -Name ($ipAddr.Split('.')[-1]) -ZoneName "$($ipAddr.Split('.')[2]).$($ipAddr.Split('.')[1]).$($ipAddr.Split('.')[0]).in-addr.arpa" -PtrDomainName "$zona." -ErrorAction SilentlyContinue
                    
                    Write-Host " [OK] Dominio '$zona', 'www.$zona' y PTR creados." -ForegroundColor Green
                } catch {
                    Write-Host " [!] Error al crear registros. Verifique la IP." -ForegroundColor Red
                }
                Pause
            }
            "2" {
                $zona = Read-Host " Nombre de la Zona a borrar"
                Remove-DnsServerZone -Name $zona -Force
                Write-Host " [OK] Zona eliminada." -ForegroundColor Yellow
                Pause
            }
            "3" {
                Write-Host "`n--- DOMINIOS CONFIGURADOS ---" -ForegroundColor Cyan
                # Filtrar zonas del sistema para ver solo las creadas
                Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false -and $_.ZoneType -eq "Primary" } | Select-Object ZoneName, ZoneStatus | Format-Table -AutoSize
                Pause
            }
        }
    } while ($abc -ne "4")
}

# --- 3. CONFIGURACIÓN DHCP (LIMPIEZA TOTAL) ---
function Ejecutar-DHCP {
    Forzar-Instalacion -NombrePS "DHCP" -NombreDISM "DHCPServer"
    
    $int = Read-Host "Interfaz (ej. Ethernet 2)"
    $ip_s = Read-Host "IP Servidor"
    $ip_f = Read-Host "IP Final del Rango"
    $dns = Read-Host "DNS para Clientes"

    # --- LIMPIEZA DE ÁMBITOS ANTIGUOS ---
    Write-Host " [*] Purgando scopes antiguos para evitar conflictos..." -ForegroundColor Yellow
    Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue

    # Cálculo de Red
    $base = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + ".0"
    $r_i = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)

    # Configurar IP Estática
    New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_s -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    
    if (Get-Command Add-DhcpServerv4Scope -ErrorAction SilentlyContinue) {
        # Crear Ámbito Limpio
        Add-DhcpServerv4Scope -Name "Red_Principal" -StartRange $r_i -EndRange $ip_f -SubnetMask 255.255.255.0 -State Active
        if ($dns) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns }
        Write-Host " [OK] DHCP configurado sin residuos de scopes viejos." -ForegroundColor Green
    }
    Pause
}

# --- MENÚ PRINCIPAL ---
do {
    Clear-Host
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host "    ORQUESTADOR WINDOWS SERVER 2022   " -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host "1) DHCP (Limpieza y Configuración)"
    Write-Host "2) DNS (Directo, Inverso y WWW)"
    Write-Host "3) Salir"
    $m = Read-Host "Selección"
    if ($m -eq "1") { Ejecutar-DHCP }
    if ($m -eq "2") { Menu-DNS }
} while ($m -ne "3")
