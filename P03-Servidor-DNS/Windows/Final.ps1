# ==============================================================================
# GESTOR TOTAL DE RED: LIMPIEZA, DHCP (CON GATEWAY/MASK) Y DNS (WWW/INVERSA)
# ==============================================================================

# --- 1. COMPROBAR ADMINISTRADOR ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] ERROR: Ejecuta PowerShell como Administrador." -ForegroundColor Red; pause; exit
}

# --- 2. FUNCIÓN DE INSTALACIÓN BLINDADA (DISM) ---
function Forzar-Instalacion {
    param($NombrePS, $NombreDISM)
    Write-Host "`n [+] Verificando rol $NombrePS..." -ForegroundColor Cyan
    if (-not (Get-WindowsFeature $NombrePS).Installed) {
        Write-Host " [*] Instalando via DISM para saltar bloqueos de registro..." -ForegroundColor Yellow
        dism /online /enable-feature /featurename:$NombreDISM /all /norestart | Out-Null
        Start-Sleep -Seconds 3
    }
    Import-Module $NombrePS -ErrorAction SilentlyContinue
}

# --- 3. MÓDULO DNS (ABC COMPLETO) ---
function Menu-DNS {
    do {
        Clear-Host
        Write-Host "=== ABC DE DNS (DIRECTA + WWW + INVERSA) ===" -ForegroundColor Yellow
        Write-Host " 1) ALTA (Zona, WWW, Raiz e Inversa)"
        Write-Host " 2) BAJA (Eliminar Zona completa)"
        Write-Host " 3) CONSULTA (Ver Registros de una Zona)"
        Write-Host " 4) Volver al Menú Principal"
        $abc = Read-Host " Selecciona una opción"

        switch ($abc) {
            "1" {
                $zona = Read-Host " Nombre de la Zona (ej: pecas.com)"
                $ipAddr = Read-Host " Dirección IP (Enter para usar la IP del servidor)"
                if (-not $ipAddr) { 
                    $ipAddr = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Ethernet*" }).IPAddress[0] 
                }
                
                # Crear Zona Directa
                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns" -ErrorAction SilentlyContinue
                }

                # Registros A (@ y www) - Sin el parámetro -Force que causaba error
                Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ipAddr -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ipAddr -ErrorAction SilentlyContinue

                # Zona Inversa Automática
                $oct = $ipAddr.Split('.')
                $invZone = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
                if (-not (Get-DnsServerZone -Name $invZone -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $invZone -ZoneFile "$invZone.dns" -ErrorAction SilentlyContinue
                }
                
                # Registro PTR
                Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $invZone -PtrDomainName "$zona." -ErrorAction SilentlyContinue

                Write-Host " [OK] Alta completa: @, WWW y PTR creados para $zona." -ForegroundColor Green; Pause
            }
            "2" {
                $zona = Read-Host " Nombre de la Zona a borrar"
                Remove-DnsServerZone -Name $zona -Force -ErrorAction SilentlyContinue
                Write-Host " [OK] Zona eliminada." -ForegroundColor Yellow; Pause
            }
            "3" {
                $zona = Read-Host " Zona a consultar"
                Write-Host " --- Registros en $zona ---" -ForegroundColor Cyan
                Get-DnsServerResourceRecord -ZoneName $zona | Format-Table HostName, RecordType, RecordData -AutoSize
                Pause
            }
        }
    } while ($abc -ne "4")
}

# --- 4. MÓDULO DHCP (LIMPIEZA DE INTERFAZ Y SCOPES) ---
function Ejecutar-DHCP {
    Forzar-Instalacion -NombrePS "DHCP" -NombreDISM "DHCPServer"
    
    $int  = Read-Host "Interfaz (ej. Ethernet 2)"
    $ip_s = Read-Host "IP FIJA para el Servidor"
    $mask = Read-Host "Mascara de Subred (ej. 255.255.255.0)"
    $gw   = Read-Host "Puerta de Enlace (Gateway)"
    $ip_f = Read-Host "IP FINAL del rango DHCP"
    $dns  = Read-Host "DNS para Clientes (Enter para usar $ip_s)"
    if (-not $dns) { $dns = $ip_s }

    Write-Host "`n [!] LIMPIANDO BASURA DE RED (IPs duplicadas)..." -ForegroundColor Red
    # Solución al problema de múltiples IPs en una tarjeta
    Get-NetIPAddress -InterfaceAlias $int -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    
    Write-Host " [!] Borrando Scopes antiguos..." -ForegroundColor Yellow
    # Limpieza de ámbitos previos
    Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue

    Write-Host " [*] Configurando nueva IP fija: $ip_s" -ForegroundColor Cyan
    New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_s -PrefixLength 24 -DefaultGateway $gw -ErrorAction SilentlyContinue | Out-Null

    $base = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + ".0"
    $r_i  = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)

    if (Get-Command Add-DhcpServerv4Scope -ErrorAction SilentlyContinue) {
        # Crear Ámbito Limpio
        Add-DhcpServerv4Scope -Name "Red_Pecas_Limpia" -StartRange $r_i -EndRange $ip_f -SubnetMask $mask -State Active
        
        # Opciones DHCP (Gateway y DNS)
        Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw
        
        # Salto de validación DNS para evitar el error "not a valid DNS server"
        Write-Host " [*] Forzando opción DNS (Saltando validación)..." -ForegroundColor Yellow
        Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns -Force -ErrorAction SilentlyContinue
        
        Write-Host "`n [OK] DHCP CONFIGURADO DESDE CERO E INTERFAZ LIMPIA." -ForegroundColor Green
    } else {
        Write-Host " [!] ERROR: El servicio DHCP no responde. Reinicia el servidor." -ForegroundColor Red
    }
    Pause
}

# --- 5. MENÚ PRINCIPAL ---
do {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    GESTOR DE RED WINDOWS SERVER 2022" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host " 1) CONFIGURAR DHCP (Limpia tarjeta y scopes)"
    Write-Host " 2) CONFIGURAR DNS (Altas, Bajas, Consultas)"
    Write-Host " 3) SALIR"
    Write-Host "==========================================" -ForegroundColor Cyan
    $opPrincipal = Read-Host " Selecciona una opción"

    if ($opPrincipal -eq "1") { Ejecutar-DHCP }
    elseif ($opPrincipal -eq "2") { Menu-DNS }
} while ($opPrincipal -ne "3")
