$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RaizProyecto = (Get-Item "$BaseDir\..\..").FullName

. "$BaseDir\Monitor_Servicios.ps1"
. "$BaseDir\Herramientas_Red.ps1"
if (Test-Path "$RaizProyecto\P02-Servidor-DHCP\Windows\DHCP.ps1") { . "$RaizProyecto\P02-Servidor-DHCP\Windows\DHCP.ps1" }
if (Test-Path "$RaizProyecto\P03-Servidor-DNS\Windows\DNS.ps1") { . "$RaizProyecto\P03-Servidor-DNS\Windows\DNS.ps1" }

$RutaSSH = "$RaizProyecto\P04-SSH\Windows\SSH_Service.ps1"
$RutaFTP = "$RaizProyecto\P05-FTP\Windows\FTP_Service_Windows.ps1"
if (Test-Path $RutaFTP) { . $RutaFTP }
if (Test-Path $RutaSSH) {
    . $RutaSSH
    Write-Host "[OK] Módulo SSH cargado." -ForegroundColor Green
} else {
    Write-Host "[!] ERROR: Archivo NO encontrado." -ForegroundColor Red
}
Pause
