# --- 1. FUNCIÓN DE INSTALACIÓN BLINDADA ---
function Forzar-Instalacion {
    param($NombrePS, $NombreDISM)
    Write-Host "`n [+] Verificando $NombrePS..." -ForegroundColor Cyan
    if (-not (Get-WindowsFeature $NombrePS).Installed) {
        Write-Host " [*] Instalando vía DISM para saltar bloqueos..." -ForegroundColor Yellow
        dism /online /enable-feature /featurename:$NombreDISM /all /norestart | Out-Null
        Start-Sleep -Seconds 5
    }
    Import-Module $NombrePS -ErrorAction SilentlyContinue
}

function Menu-DNS {
    do {
        Clear-Host
        Write-Host "=== ABC DE DNS (DIRECTA + WWW + INVERSA) ===" -ForegroundColor Yellow
        Write-Host " 1) ALTA (Zona, WWW, Raiz e Inversa)"
        Write-Host " 2) BAJA (Eliminar Zona completa)"
        Write-Host " 3) CONSULTA (Ver Registros)"
        Write-Host " 4) Volver al Menú Principal"
        $abc = Read-Host " Selecciona una opción"

        switch ($abc) {
            "1" {
                $zona = Read-Host " Nombre de la Zona (ej: pecas.com)"
                $ipAddr = Read-Host " Dirección IP (Enter para usar la del servidor)"
                if (-not $ipAddr) { $ipAddr = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Ethernet*" }).IPAddress[0] }
                
                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns" -ErrorAction SilentlyContinue
                }

                Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ipAddr -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ipAddr -ErrorAction SilentlyContinue

                $oct = $ipAddr.Split('.')
                $invZone = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
                if (-not (Get-DnsServerZone -Name $invZone -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $invZone -ZoneFile "$invZone.dns" -ErrorAction SilentlyContinue
                }
                
                Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $invZone -PtrDomainName "$zona." -ErrorAction SilentlyContinue

                Write-Host " [OK] Configuración completa para $zona (A, WWW, PTR)." -ForegroundColor Green
                Pause
            }
            "2" {
                $zona = Read-Host " Nombre de la Zona a eliminar"
                Remove-DnsServerZone -Name $zona -Force -ErrorAction SilentlyContinue
                Write-Host " [OK] Zona eliminada." -ForegroundColor Yellow
                Pause
            }
            "3" {
                $zona = Read-Host " Zona a consultar"
                Get-DnsServerResourceRecord -ZoneName $zona | Format-Table HostName, RecordType, RecordData -AutoSize
                Pause
            }
        }
    } while ($abc -ne "4")
}

# --- 3. CONFIGURACIÓN DHCP (CON LIMPIEZA DE SCOPES ANTIGUOS) ---
function Ejecutar-DHCP {
    Forzar-Instalacion -NombrePS "DHCP" -NombreDISM "DHCPServer"
    
    $int = Read-Host "Interfaz (ej. Ethernet 2)"
    $ip_s = Read-Host "IP Fija del Servidor"
    $mask = Read-Host "Mascara de Subred (ej. 255.255.255.0)"
    $gw   = Read-Host "Puerta de Enlace (Gateway)"
    $ip_f = Read-Host "IP Final del Rango DHCP"
    $dns  = Read-Host "DNS para Clientes (Enter para usar $ip_s)"
    if (-not $dns) { $dns = $ip_s }

    Write-Host "`n[*] Iniciando limpieza de configuraciones antiguas..." -ForegroundColor Yellow
    
    # --- CAMBIO CLAVE: BORRAR TODOS LOS SCOPES EXISTENTES ---
    $oldScopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($oldScopes) {
        foreach ($scope in $oldScopes) {
            Write-Host " [-] Eliminando Scope antiguo: $($scope.ScopeId)" -ForegroundColor Gray
            Remove-DhcpServerv4Scope -ScopeId $scope.ScopeId -Force -ErrorAction SilentlyContinue
        }
    }

    $base = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + ".0"
    $r_i = $ip_s.SubString(0, $ip_s.LastIndexOf('.')) + "." + ([int]$ip_s.Split('.')[3] + 1)

    Write-Host "[*] Aplicando nueva configuración..." -ForegroundColor Cyan
    
    # Configurar IP fija en la tarjeta
    New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_s -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    
    if (Get-Command Add-DhcpServerv4Scope -ErrorAction SilentlyContinue) {
        # Crear el nuevo ámbito limpio
        Add-DhcpServerv4Scope -Name "Red_Pecas_Limpia" -StartRange $r_i -EndRange $ip_f -SubnetMask $mask -State Active
        
        # Opciones: Gateway (3) y DNS (6)
        Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw
        # Forzamos el DNS saltando validación
        Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns -ErrorAction SilentlyContinue
        
        Write-Host "[OK] DHCP CONFIGURADO DESDE CERO." -ForegroundColor Green
    } else {
        Write-Host "ERROR: EL SERVICIO NO RESPONDE." -ForegroundColor Red
    }
    Pause
}

# --- MENÚ PRINCIPAL ---
do {
    Clear-Host
    Write-Host "=== GESTOR TOTAL (LIMPIEZA DE SCOPES) ===" -ForegroundColor Cyan
    Write-Host "1) DHCP (Borrar antiguos y crear nuevo)"
    Write-Host "2) DNS (Altas Automáticas, Bajas, Consultas)"
    Write-Host "3) Salir"
    $m = Read-Host "Opcion"
    if ($m -eq "1") { Ejecutar-DHCP }
    if ($m -eq "2") { Menu-DNS }
} while ($m -ne "3")
