# ==============================================================================
# ORQUESTADOR MULTIMODULO - WINDOWS
# Ubicacion: C:\Users\Administrator\Practicas_SysAdm\Orquestador_Windows.ps1
# ==============================================================================

$global:PUERTO_ACTUAL = "N/A"
$Root = $PSScriptRoot

# Verificar privilegios
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $esAdmin) { Write-Host "[!] Ejecutar como Administrador." -ForegroundColor Red; Pause; exit 1 }

# Cargar modulos desde su ubicacion correcta en el proyecto
$Modulos = @(
    "$Root\Globales\Windows\Monitor_Servicios.ps1",
    "$Root\Globales\Windows\Herramientas_Red.ps1",
    "$Root\P02-Servidor-DHCP\Windows\DHCP.ps1",
    "$Root\P03-Servidor-DNS\Windows\DNS.ps1",
    "$Root\P04-SSH\Windows\SSH_Service.ps1",
    "$Root\P05-FTP\Windows\FTP_Service_Windows.ps1",
    "$Root\P06-HTTP\Windows\HTTP_Service.ps1",
    "$Root\P07-HTTP-FTP\Windows\HTTP_FTP.ps1"
)

foreach ($ruta in $Modulos) {
    if (Test-Path $ruta) {
        try {
            . $ruta
            Write-Host "[OK] $(Split-Path $ruta -Leaf)" -ForegroundColor Green
        } catch {
            Write-Host "[!] ERROR en $(Split-Path $ruta -Leaf): $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "[X] NO EXISTE: $ruta" -ForegroundColor Yellow
    }
}

Pause

# ================================================================
# MENU PRINCIPAL
# ================================================================
function menu_principal {
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "====================================" -ForegroundColor Cyan
        Write-Host "      ORQUESTADOR MULTIMODULO       " -ForegroundColor Cyan
        Write-Host "====================================" -ForegroundColor Cyan
        Write-Host "1) Estatus de Servicios"
        Write-Host "2) Configuracion de Red Manual"
        Write-Host "3) Configurar Servidor DHCP"
        Write-Host "4) Configurar Servidor DNS"
        Write-Host "5) Servidor FTP"
        Write-Host "6) Conectar a SSH"
        Write-Host "7) Configurar WEB HTTP"
        Write-Host "8) Configurar Servidor WEB HTTP/FTP"
        Write-Host "9) Salir"
        $opcion = Read-Host "Opcion"

        switch ($opcion) {
            "1" {
                Write-Host ""
                Write-Host "--- Estatus ---" -ForegroundColor Yellow

                $dhcp = Get-Service -Name "DHCPServer" -ErrorAction SilentlyContinue
                Write-Host "DHCP: $(if ($dhcp -and $dhcp.Status -eq 'Running') { 'active' } else { 'inactive' })"

                $dns = Get-Service -Name "DNS" -ErrorAction SilentlyContinue
                Write-Host "DNS:  $(if ($dns -and $dns.Status -eq 'Running') { 'active' } else { 'inactive' })"

                $stHTTP = "inactive"
                if ((Get-Service "nginx"  -ErrorAction SilentlyContinue).Status -eq "Running") { $stHTTP = "active (nginx)"  }
                elseif ((Get-Service "Apache" -ErrorAction SilentlyContinue).Status -eq "Running") { $stHTTP = "active (apache)" }
                elseif ((Get-Service "W3SVC"  -ErrorAction SilentlyContinue).Status -eq "Running") { $stHTTP = "active (IIS)"    }
                Write-Host "HTTP: $stHTTP"
                Write-Host "Puerto HTTP asignado: $global:PUERTO_ACTUAL"

                $ftp = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
                Write-Host "FTP: $(if ($ftp -and $ftp.Status -eq 'Running') { 'active' } else { 'inactive' })"

                $ssh = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
                Write-Host "SSH: $(if ($ssh -and $ssh.Status -eq 'Running') { 'active' } else { 'inactive' })"

                Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.InterfaceAlias -notmatch "Loopback" } |
                    ForEach-Object { Write-Host "    inet $($_.IPAddress)/$($_.PrefixLength) ($($_.InterfaceAlias))" }
                Pause
            }
            "2" { if (Get-Command Configurar-Red -ErrorAction SilentlyContinue) { Configurar-Red } else { Write-Host "[!] No disponible." -ForegroundColor Yellow; Pause } }
            "3" { if (Get-Command Menu-DHCP -ErrorAction SilentlyContinue) { Menu-DHCP } else { Write-Host "[!] DHCP no disponible." -ForegroundColor Yellow; Pause } }
            "4" { if (Get-Command Menu-DNS  -ErrorAction SilentlyContinue) { Menu-DNS  } else { Write-Host "[!] DNS no disponible."  -ForegroundColor Yellow; Pause } }
            "5" {
                Write-Host "Llamando MODULO FTP: " -ForegroundColor Cyan
                if (Get-Command Menu-FTP -ErrorAction SilentlyContinue) { Menu-FTP } else { Write-Host "[!] FTP no disponible." -ForegroundColor Yellow; Pause }
            }
            "6" {
                Write-Host "Llamando modulo SSH" -ForegroundColor Cyan
                if (Get-Command Configurar-SSH -ErrorAction SilentlyContinue) { Configurar-SSH } else { Write-Host "[!] SSH no disponible." -ForegroundColor Yellow; Pause }
            }
            "7" {
                if (Get-Command Menu-HTTP -ErrorAction SilentlyContinue) { Menu-HTTP } else { Write-Host "[!] HTTP no disponible." -ForegroundColor Yellow; Pause }
            }
            "8" {
                # Eliminar funciones viejas y recargar modulo fresco
                $rutaP07 = Join-Path $Root "P07-HTTP-FTP\Windows\HTTP_FTP.ps1"
                if (Test-Path $rutaP07) {
                    Remove-Item Function:\Listar-Archivos-FTP -ErrorAction SilentlyContinue
                    Remove-Item Function:\Menu-FTP-HTTP -ErrorAction SilentlyContinue
                    Remove-Item Function:\Instalar-Servicio -ErrorAction SilentlyContinue
                    Remove-Item Function:\Aplicar-Despliegue -ErrorAction SilentlyContinue
                    Remove-Item Function:\Generar-Certificado-SSL -ErrorAction SilentlyContinue
                    . $rutaP07
                }
                if (Get-Command Menu-FTP-HTTP -ErrorAction SilentlyContinue) { Menu-FTP-HTTP } else { Write-Host "[!] HTTP/FTP no disponible." -ForegroundColor Yellow; Pause }
            }
            "9" { Write-Host "Saliendo..." -ForegroundColor Cyan; exit 0 }
            default { Write-Host "Opcion no valida." -ForegroundColor Red }
        }
    }
}

menu_principal
