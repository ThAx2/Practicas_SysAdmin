# --- FUNCIONES DE APOYO ---
function Check-Service {
    param($ServiceName)
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        Write-Host "[!] El servicio $ServiceName no está instalado. Instalando..." -ForegroundColor Yellow
        Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
    }
    
    $service = Get-Service -Name $ServiceName
    if ($service.Status -ne 'Running') {
        Write-Host "[!] El servicio $ServiceName está $($service.Status). Iniciando..." -ForegroundColor Yellow
        Start-Service $ServiceName
    } else {
        Write-Host "[OK] El servicio $ServiceName ya está activo." -ForegroundColor Green
    }
}

function Mostrar-Menu {
    Clear-Host
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host "   GESTOR DHCP TIPO DEBIAN (WINDOWS SERVER)    " -ForegroundColor Yellow
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host "1) Configurar Servidor (IP Fija, Ámbito, etc.)"
    Write-Host "2) Consultar Estado y Ámbitos"
    Write-Host "3) Ver Concesiones (Leases)"
    Write-Host "4) Reiniciar / Forzar Inicio"
    Write-Host "5) Salir"
    Write-Host "------------------------------------------------"
}

# --- BUCLE PRINCIPAL ---
$servicio = "DHCPServer"

do {
    Mostrar-Menu
    $opcion = Read-Host "Opción"

    switch ($opcion) {
        "1" {
            # Verificación de pre-requisitos (como tu mon_service.sh)
            Check-Service -ServiceName $servicio

            # Petición de datos
            $interface = Read-Host "Interfaz (ej. Ethernet 2)"
            $ip_fija   = Read-Host "IP del Servidor (ej. 192.168.100.1)"
            $scopeName = Read-Host "Nombre del Ámbito"
            $startIP   = Read-Host "Rango Inicial"
            $endIP     = Read-Host "Rango Final"
            $dns       = Read-Host "DNS (ej. 8.8.8.8)"

            Write-Host "`n[+] Aplicando configuración..." -ForegroundColor Cyan
            
            # Configura IP Fija
            New-NetIPAddress -InterfaceAlias $interface -IPAddress $ip_fija -PrefixLength 24 -ErrorAction SilentlyContinue
            
            # Configura Ámbito
            Add-DhcpServerv4Scope -Name $scopeName -StartRange $startIP -EndRange $endIP -SubnetMask 255.255.255.0 -State Active -ErrorAction SilentlyContinue
            
            # Opciones
            Set-DhcpServerv4OptionValue -OptionId 3 -Value $ip_fija
            Set-DhcpServerv4OptionValue -OptionId 6 -Value $dns
            
            # Firewall (Matamos al estorbo)
            netsh advfirewall set allprofiles state off
            
            Write-Host "[OK] Configuración completada." -ForegroundColor Green
            Pause
        }

        "2" {
            Write-Host "`n--- ESTADO DEL SERVICIO ---" -ForegroundColor Cyan
            Get-Service $servicio | Select-Object Name, Status, StartType
            Write-Host "`n--- ÁMBITOS ACTIVOS ---" -ForegroundColor Cyan
            Get-DhcpServerv4Scope | Format-Table -AutoSize
            Pause
        }

        "3" {
            Write-Host "`n--- CLIENTES CONECTADOS ---" -ForegroundColor Cyan
            Get-DhcpServerv4Scope | ForEach-Object { Get-DhcpServerv4Lease -ScopeId $_.ScopeId } | Format-Table -AutoSize
            Pause
        }

        "4" {
            Write-Host "`n[!] Reiniciando servicio DHCP..." -ForegroundColor Yellow
            Restart-Service $servicio
            Write-Host "[OK] Servicio reiniciado." -ForegroundColor Green
            Pause
        }
    }
} while ($opcion -ne "5")
