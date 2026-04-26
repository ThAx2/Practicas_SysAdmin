# ==============================================================================
# DEPENDENCIAS - WINDOWS
# Equivalente a: Globales/Linux/Dependencias.sh
# ==============================================================================

$BaseDir      = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RaizProyecto = (Get-Item "$BaseDir\..\..").FullName

# Carga de funciones base
foreach ($f in @("$BaseDir\Monitor_Servicios.ps1", "$BaseDir\Herramientas_Red.ps1")) {
    if (Test-Path $f) {
        . $f
        Write-Host "[OK] Cargado: $(Split-Path $f -Leaf)" -ForegroundColor Green
    } else {
        Write-Host "[!] No encontrado: $f" -ForegroundColor Yellow
    }
}

# Carga de modulos del proyecto
$rutas = @(
    "$RaizProyecto\P02-Servidor-DHCP\Windows\DHCP.ps1",
    "$RaizProyecto\P03-Servidor-DNS\Windows\DNS.ps1",
    "$RaizProyecto\P04-SSH\Windows\SSH_Service.ps1",
    "$RaizProyecto\P05-FTP\Windows\FTP_Service_Windows.ps1",
    "$RaizProyecto\P06-HTTP\Windows\HTTP_Service.ps1",
    "$RaizProyecto\P07-HTTP-FTP\Windows\HTTP_FTP.ps1"
)

foreach ($ruta in $rutas) {
    if (Test-Path $ruta) {
        . $ruta
        Write-Host "[OK] Modulo cargado: $(Split-Path $ruta -Leaf)" -ForegroundColor Green
    } else {
        Write-Host "[X] No existe: $ruta" -ForegroundColor Yellow
    }
}
