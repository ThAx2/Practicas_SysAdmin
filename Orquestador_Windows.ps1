# --- AUTO-ELEVACIÓN ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] ERROR: Ejecuta como Administrador en Windows Server." -ForegroundColor Red; pause; exit
}

# Variable Global
$Global:InterfazActiva = ""

# CARGA DIRECTA DE DEPENDENCIAS (Para evitar errores de Scope)
$RutaDependencias = "$PSScriptRoot\Globales\Windows\Dependencias.ps1"

if (Test-Path $RutaDependencias) {
    . $RutaDependencias
} else {
    Write-Host "[!] No se encontro el archivo de dependencias en: $RutaDependencias" -ForegroundColor Red; pause; exit
}

do {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "      GESTOR DE RED WINDOWS SERVER" -ForegroundColor Cyan
    
    # Ahora sí reconocerá la función
    Monitor-Servicios
    
    Write-Host " 1) DHCP (Configurar Red)"
    Write-Host " 2) DNS (Zonas y Registros)"
    Write-Host " 3) Salir"
    $m = Read-Host " Selecciona"
    
    if ($m -eq "1") { Menu-DHCP }
    if ($m -eq "2") { Menu-DNS } 
} while ($m -ne "3")
