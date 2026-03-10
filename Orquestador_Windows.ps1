$BaseDir      = $PSScriptRoot
$RaizProyecto = $BaseDir   # FIX: el proyecto raíz ES la carpeta del orquestador
$RutaGlobal   = "$BaseDir\Globales\Windows"

# Carga de Funciones Base
if (Test-Path "$RutaGlobal\Herramientas_Red.ps1")  { . "$RutaGlobal\Herramientas_Red.ps1" }

# FIX #7: Proteger la carga de Monitor_Servicios.ps1 con Test-Path
if (Test-Path "$RutaGlobal\Monitor_Servicios.ps1") {
    . "$RutaGlobal\Monitor_Servicios.ps1"
} else {
    Write-Host "[!] ERROR CRÍTICO: Monitor_Servicios.ps1 no encontrado en $RutaGlobal" -ForegroundColor Red
    Pause
    exit 1
}

# Carga de módulos
if (Test-Path "$RaizProyecto\P02-Servidor-DHCP\Windows\DHCP.ps1")              { . "$RaizProyecto\P02-Servidor-DHCP\Windows\DHCP.ps1" }
if (Test-Path "$RaizProyecto\P03-Servidor-DNS\Windows\DNS.ps1")                { . "$RaizProyecto\P03-Servidor-DNS\Windows\DNS.ps1" }
if (Test-Path "$RaizProyecto\P04-SSH\Windows\SSH_Service.ps1")                 { . "$RaizProyecto\P04-SSH\Windows\SSH_Service.ps1" }
if (Test-Path "$RaizProyecto\P05-FTP\Windows\FTP_Service_Windows.ps1")         { . "$RaizProyecto\P05-FTP\Windows\FTP_Service_Windows.ps1" }
if (Test-Path "$RaizProyecto\P06-HTTP\Windows\HTTP_Service.ps1")               { . "$RaizProyecto\P06-HTTP\Windows\HTTP_Service.ps1" }

$global:PUERTO_ACTUAL = "80"

do {
    Clear-Host
    Monitor-Servicios
    Write-Host " 1) DHCP | 2) DNS | 3) FTP | 4) SSH | 5) HTTP | 6) Salir"
    $m = Read-Host " Selecciona"
    switch ($m) {
        "1" { if (Get-Command Menu-DHCP       -ErrorAction SilentlyContinue) { Menu-DHCP }       else { Write-Host "[!] Módulo DHCP no disponible."  -ForegroundColor Yellow; Pause } }
        "2" { if (Get-Command Menu-DNS        -ErrorAction SilentlyContinue) { Menu-DNS }        else { Write-Host "[!] Módulo DNS no disponible."   -ForegroundColor Yellow; Pause } }
        "3" { if (Get-Command Menu-FTP        -ErrorAction SilentlyContinue) { Menu-FTP }        else { Write-Host "[!] Módulo FTP no disponible."   -ForegroundColor Yellow; Pause } }
        "4" { if (Get-Command Configurar-SSH  -ErrorAction SilentlyContinue) { Configurar-SSH }  else { Write-Host "[!] Módulo SSH no disponible."   -ForegroundColor Yellow; Pause } }
        "5" { if (Get-Command Menu-HTTP       -ErrorAction SilentlyContinue) { Menu-HTTP }       else { Write-Host "[!] Módulo HTTP no disponible."  -ForegroundColor Yellow; Pause } }
        "6" { Write-Host "Saliendo..." -ForegroundColor Cyan }
        # FIX #9: Manejar entradas inválidas con default
        default { Write-Host "[!] Opción no válida. Elige entre 1 y 6." -ForegroundColor Yellow; Pause }
    }
} while ($m -ne "6")
