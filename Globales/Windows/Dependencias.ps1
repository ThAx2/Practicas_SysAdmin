# Obtenemos la ruta base de donde está este archivo
$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RaizProyecto = (Get-Item "$BaseDir\..\..").FullName

# Cargamos los archivos de soporte
. "$BaseDir\Monitor_Servicios.ps1"
. "$BaseDir\Herramientas_Red.ps1"

# Cargamos los menús de las prácticas
if (Test-Path "$RaizProyecto\P02-Servidor-DHCP\Windows\DHCP.ps1") { . "$RaizProyecto\P02-Servidor-DHCP\Windows\DHCP.ps1" }
if (Test-Path "$RaizProyecto\P03-Servidor-DNS\Windows\DNS.ps1") { . "$RaizProyecto\P03-Servidor-DNS\Windows\DNS.ps1" }
