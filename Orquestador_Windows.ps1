if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] ERROR: Ejecuta como Administrador en Windows Server." -ForegroundColor Red; pause; exit
}

$Global:InterfazActiva = ""

$RutaDependencias = "$PSScriptRoot\Globales\Windows\Dependencias.ps1"
if (Test-Path $RutaDependencias) { . $RutaDependencias } 
else { Write-Host "[!] No se encontro dependencias." -ForegroundColor Red; pause; exit }

do {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "      GESTOR DE RED WINDOWS SERVER" -ForegroundColor Cyan
    Monitor-Servicios 
    Write-Host " 1) DHCP"
    Write-Host " 2) DNS"
	Write-HOst " 3) FTP"    
	Write-Host " 4) SSH"
    Write-Host " 5) Salir"
    $m = Read-Host " Selecciona"
    switch ($m) {
        "1" { Menu-DHCP }
        "2" { Menu-DNS }
		"3" { Menu_Principal }
        "4" { Configurar-SSH } 
    }
} while ($m -ne "5")
