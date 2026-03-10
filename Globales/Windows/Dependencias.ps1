$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RaizProyecto = (Get-Item "$BaseDir\..\..").FullName

# Carga de Funciones Base
. "$BaseDir\Monitor_Servicios.ps1"
. "$BaseDir\Herramientas_Red.ps1"

# Carga de Módulos (Roles Natividad)
if (Test-Path "$RaizProyecto\P02-Servidor-DHCP\Windows\DHCP.ps1") { . "$RaizProyecto\P02-Servidor-DHCP\Windows\DHCP.ps1" }
if (Test-Path "$RaizProyecto\P03-Servidor-DNS\Windows\DNS.ps1") { . "$RaizProyecto\P03-Servidor-DNS\Windows\DNS.ps1" }

# Carga de Módulos (Servicios Terceros/SSH/FTP)
$RutaSSH = "$RaizProyecto\P04-SSH\Windows\SSH_Service.ps1"
$RutaFTP = "$RaizProyecto\P05-FTP\Windows\FTP_Service_Windows.ps1"
$RutaHTTP = "$RaizProyecto\P06-HTTP\Windows\HTTP_Service.ps1" # <--- NUEVA RUTA

if (Test-Path $RutaFTP) { . $RutaFTP }
if (Test-Path $RutaSSH) {
    . $RutaSSH
    Write-Host "[OK] Módulo SSH cargado." -ForegroundColor Green
}

# Carga del Módulo HTTP
if (Test-Path $RutaHTTP) {
    . $RutaHTTP
    Write-Host "[OK] Módulo HTTP cargado." -ForegroundColor Green
} else {
    Write-Host "[!] ERROR: Archivo HTTP_Service_Windows.ps1 NO encontrado en $RutaHTTP" -ForegroundColor Red
}

Pause
