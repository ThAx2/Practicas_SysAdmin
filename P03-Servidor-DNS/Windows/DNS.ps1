# Importar módulos hermanos (Asegúrate que estén en la misma carpeta)
. "$PSScriptRoot\Validacion_IP.ps1"
. "$PSScriptRoot\Mon_Service.ps1"
. "$PSScriptRoot\DHCP.ps1"

# Verificación de privilegios
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " [!] ERROR: Debes ejecutar como ADMINISTRADOR." -ForegroundColor Red
    Pause; exit
}

function Menu-DNS {
    # Obtener IP actual del servidor para usarla como referencia
    $IP_SRV = (Get-NetIPAddress -InterfaceAlias "Ethernet" -AddressFamily IPv4).IPAddress | Select-Object -First 1

    do {
        Clear-Host
        Write-Host "================================================" -ForegroundColor Cyan
        Write-Host "           GESTIÓN DNS (ABC) - WINDOWS          " -ForegroundColor Cyan
        Write-Host "================================================" -ForegroundColor Cyan
        Write-Host " 1) Mis dominios "
        Write-Host " 2) Alta de Dominio "
        Write-Host " 3) Baja de Dominio "
        Write-Host " 4) Volver al Orquestador"
        $optDns = Read-Host "`n Selecciona una opcion"

        switch ($optDns) {
            "1" {
                Write-Host "`n --- Dominios activos ---" -ForegroundColor Yellow
                Get-DnsServerZone | Where-Object { $_.IsReverseLookupZone -eq $false -and $_.ZoneName -ne "TrustAnchors" } | Select-Object ZoneName, ZoneType | Format-Table -AutoSize
                Pause
            }
            "2" {
                $dominio = Read-Host " Nombre del nuevo dominio (ej. pecas.com)"
                if ([string]::IsNullOrWhiteSpace($dominio)) { continue }

                # IP de Destino: Aquí puedes poner la .20, la .23 o la que sea
                $ip_dest = Read-Host " IP de DESTINO para $dominio (Enter para $IP_SRV)"
                $IP_FINAL = if ([string]::IsNullOrWhiteSpace($ip_dest)) { $IP_SRV } else { $ip_dest }

                if (Test-IsValidIP -IP $IP_FINAL) {
                    Write-Host " [*] Creando Zona y Registros..." -ForegroundColor Magenta
                    Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns" -ErrorAction SilentlyContinue
                    
                    # Registro @ (A) y www (CNAME)
                    Add-DnsServerResourceRecordA -Name "@" -ZoneName $dominio -IPv4Address $IP_FINAL -Force
                    Add-DnsServerResourceRecordCName -Name "www" -ZoneName $dominio -HostNameAlias "$dominio." -Force
                    
                    Write-Host " [OK] Dominio $dominio apunta a $IP_FINAL" -ForegroundColor Green
                }
                Pause
            }
            "3" {
                $borrar = Read-Host " Nombre del dominio a eliminar"
                if (Get-DnsServerZone -Name $borrar -ErrorAction SilentlyContinue) {
                    Remove-DnsServerZone -Name $borrar -Force
                    Write-Host " [OK] Zona $borrar eliminada correctamente." -ForegroundColor Green
                } else {
                    Write-Host " [!] La zona no existe." -ForegroundColor Red
                }
                Pause
            }
        }
    } while ($optDns -ne "4")
}

# --- MENU PRINCIPAL DEL ORQUESTADOR ---
do {
    Clear-Host
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host "       ORQUESTADOR MAESTRO WINDOWSITO           " -ForegroundColor Yellow
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host " 1) Configurar DHCP (IP Fija y Ambito)"
    Write-Host " 2) Gestionar DNS (Altas/Bajas/Consultas)"
    Write-Host " 3) Ver Estatus de Servicios"
    Write-Host " 4) Salir"
    $opcion = Read-Host "`n Selecciona una opcion"

    switch ($opcion) {
        "1" { Configurar-DHCP -interface "Ethernet" }
        "2" { 
            Check-Service -RoleName "DNS" -ServiceName "DNS"
            Menu-DNS 
        }
        "3" {
            Write-Host "`n--- ESTATUS ---" -ForegroundColor Cyan
            Get-Service DHCPServer, DNS | Select-Object Name, DisplayName, Status | Format-Table -AutoSize
            Get-NetIPAddress -InterfaceAlias "Ethernet" -AddressFamily IPv4 | Select-Object IPAddress, PrefixLength
            Pause
        }
    }
} while ($opcion -ne "4")
