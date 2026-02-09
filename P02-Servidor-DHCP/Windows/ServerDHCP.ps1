# ===========================================================================
# Script: Monitor DHCP Windows Server Core
# Author: Alexander Vega / Ax2
# Fecha: 08/02/2026
# Descripcion: Instalacion desatendida, orquestacion basica y monitoreo de leases.
# ===========================================================================

# --- Entregable 1: Idempotencia (Instalar si no existe) ---
Write-Host "============================================"
Write-Host "Verificando Rol DHCP..."
$check = Get-WindowsFeature DHCP
if ($check.Installed -ne $true) {
    Write-Host "El servicio no esta. Instalando de forma desatendida..."
    Install-WindowsFeature -Name DHCP -IncludeManagementTools
    Write-Host "Instalacion completada."
} else {
    Write-Host "El servicio DHCP ya se encuentra activo."
}

# --- Entregable 2: Orquestacion (Captura de datos) ---
Write-Host " "
$scopeName = Read-Host "Nombre del Ambito (ej. Red_Sistemas)"
$network   = Read-Host "ID de Red (ej. 192.168.100.0)"
$mask      = Read-Host "Mascara (ej. 255.255.255.0)"
$startIp   = Read-Host "IP Inicial del rango"
$endIp     = Read-Host "IP Final del rango"
$gw        = Read-Host "Puerta de enlace"
$dns       = Read-Host "Servidor DNS (Practica 1)"

Write-Host "Configurando ambito..."
# Crear el ambito
Add-DhcpServerv4Scope -Name $scopeName -StartRange $startIp -EndRange $endIp -SubnetMask $mask

# Configurar opciones (Router y DNS)
Set-DhcpServerv4OptionValue -OptionId 3 -Value $gw
Set-DhcpServerv4OptionValue -OptionId 6 -Value $dns

Write-Host "Configuracion finalizada con exito."

# --- Entregable 3: Modulo de Diagnostico (Menu) ---
while($true) {
    Write-Host " "
    Write-Host "============ MENÚ DE MONITOREO ============"
    Write-Host "1) Ver estado del servicio"
    Write-Host "2) Listar equipos conectados (Leases)"
    Write-Host "3) Salir"
    $op = Read-Host "Seleccione una opcion"

    switch ($op) {
        "1" { 
            Get-Service dhcpserver | Select-Object Name, Status, StartType 
        }
        "2" { 
            Write-Host "Buscando concesiones en la red $network..."
            Get-DhcpServerv4Lease -ScopeId $network 
        }
        "3" { 
            Write-Host "Saliendo..."
            break 
        }
        Default { Write-Host "Opcion no valida." }
    }
}
