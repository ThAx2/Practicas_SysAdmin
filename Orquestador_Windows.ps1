# --- AUTO-ELEVACIÓN (Mantenemos tu lógica) ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] ERROR: Ejecuta como Administrador en Windows Server." -ForegroundColor Red; pause; exit
}

# Variable Global
$Global:InterfazActiva = ""

# CARGA DIRECTA DE DEPENDENCIAS
$RutaDependencias = "$PSScriptRoot\Globales\Windows\Dependencias.ps1"
if (Test-Path $RutaDependencias) { . $RutaDependencias } 
else { Write-Host "[!] No se encontro dependencias." -ForegroundColor Red; pause; exit }

do {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "      GESTOR DE RED WINDOWS SERVER" -ForegroundColor Cyan
    
    # Tu monitor de siempre mostrando el estado en tiempo real
    Monitor-Servicios 
    
    Write-Host " 1) DHCP (Configurar Red)"
    Write-Host " 2) DNS (Zonas y Registros)"
    Write-Host " 3) SSH (Activar Administración Remota)"
    Write-Host " 4) Salir"
    $m = Read-Host " Selecciona"
    
    switch ($m) {
        "1" { Menu-DHCP }
        "2" { Menu-DNS }
        "3" { Configurar-SSH } 
    }
} while ($m -ne "4")
