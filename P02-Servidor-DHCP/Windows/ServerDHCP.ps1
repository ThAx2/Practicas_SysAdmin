# 0. Verificación de privilegios de Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " [!] ERROR: Debes ejecutar este script como ADMINISTRADOR." -ForegroundColor Red
    Pause
    exit
}

function Test-IsValidIP {
    param(
        [string]$IP,
        $IPInicio = $null,
        [switch]$EsRed
    )
    if ([string]::IsNullOrWhiteSpace($IP)) { return $false }
    $IP = $IP.Trim()
    $regex = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    
    if ($IP -match $regex) {
        $octetos = $IP.Split('.')
        $ultimo = [int]$octetos[3]

        if ($IP -eq "0.0.0.0" -or $IP -eq "255.255.255.255") {
            Write-Host " [!] IP Prohibida (0.0.0.0 / 255.255.255.255)." -ForegroundColor Red
            return $false
        }

        if ($EsRed) {
            if ($ultimo -ne 0) {
                Write-Host " [!] Error: Una Direccion de Red DEBE terminar en .0" -ForegroundColor Red
                return $false
            }
        } else {
            if ($ultimo -eq 0 -or $ultimo -eq 255) {
                Write-Host " [!] Error: Un host no puede ser .0 (red) ni .255 (broadcast)." -ForegroundColor Red
                return $false
            }
        }

        if ($null -ne $IPInicio -and $IPInicio -ne "") {
            $octIni = $IPInicio.Trim().Split('.')
            for ($i = 0; $i -lt 3; $i++) {
                if ($octetos[$i] -ne $octIni[$i]) {
                    Write-Host " [!] Error: No pertenece a la red $($octIni[0..2] -join '.').X" -ForegroundColor Red
                    return $false
                }
            }
            # Validar orden en el rango
            if ($MyInvocation.Line -match "endIP" -and $ultimo -le [int]$octIni[3]) {
                Write-Host " [!] Error: El host final ($ultimo) debe ser mayor al inicial ($($octIni[3]))." -ForegroundColor Red
                return $false
            }
        }
        return $true
    }
    Write-Host " [!] Formato de IP invalido." -ForegroundColor Red
    return $false
}

function Check-Service {
    param($ServiceName)
    Write-Host " [+] Verificando Rol DHCP..." -ForegroundColor Cyan
    $feature = Get-WindowsFeature DHCP
    if (-not $feature.Installed) {
        Write-Host " [!] Instalando Rol DHCP y herramientas de administración..." -ForegroundColor Yellow
        Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
    }

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service.Status -ne 'Running') {
        Write-Host " [+] Iniciando servicio $ServiceName..." -ForegroundColor Cyan
        Start-Service $ServiceName
    }
}

# --- MENU PRINCIPAL ---
do {
    Clear-Host
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host "        DHCP Windowsito (CORREGIDO)    " -ForegroundColor Yellow
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host " 1) Configurar Servidor (IP Fija y Ambito)"
    Write-Host " 2) Ver Ambitos y Concesiones"
    Write-Host " 3) Reiniciar Servicio DHCP"
    Write-Host " 4) Salir"
    Write-Host "------------------------------------------------"
    $opcion = Read-Host " Opcion"
    
    switch ($opcion) {
        "1" {
            $base_red = ""; $ip_fija = ""; $startIP = ""; $endIP = ""; $interface = ""; $scopeName = ""
            
            Check-Service -ServiceName "DHCPServer"
            
            # Recolección de datos
            do { $interface = Read-Host " Nombre de la Interfaz (ej. Ethernet)" } while ([string]::IsNullOrWhiteSpace($interface))
            do { $base_red = Read-Host " Direccion de Red (ID de Red, ej. 192.168.100.0)" } until (Test-IsValidIP -IP $base_red -EsRed)
            do { $ip_fija = Read-Host " IP Fija para este Servidor" } until (Test-IsValidIP -IP $ip_fija -IPInicio $base_red)
            do { $scopeName = Read-Host " Nombre para el Ambito" } while ([string]::IsNullOrWhiteSpace($scopeName))
            do { $startIP = Read-Host " Rango Inicial de IPs" } until (Test-IsValidIP -IP $startIP -IPInicio $base_red)
            do { $endIP = Read-Host " Rango Final de IPs" } until (Test-IsValidIP -IP $endIP -IPInicio $startIP)
            
            Write-Host "`n [+] Aplicando configuracion de red..." -ForegroundColor Cyan
            # Configurar IP Fija en la tarjeta
            Remove-NetIPAddress -InterfaceAlias $interface -Confirm:$false -ErrorAction SilentlyContinue
            New-NetIPAddress -InterfaceAlias $interface -IPAddress $ip_fija -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
            
            Write-Host " [+] Creando ambito DHCP..." -ForegroundColor Cyan
            
            # --- CORRECCIÓN: Limpieza previa para evitar error si ya existe ---
            Remove-DhcpServerv4Scope -ScopeId $base_red -Force -ErrorAction SilentlyContinue
            
            # --- CORRECCIÓN: Se usa -ScopeId en lugar de -SubnetId ---
            Add-DhcpServerv4Scope -Name $scopeName -ScopeId $base_red -StartRange $startIP -EndRange $endIP -SubnetMask 255.255.255.0 -State Active
            
            # Opciones adicionales: Puerta de enlace y DNS
            Set-DhcpServerv4OptionValue -ScopeId $base_red -OptionId 3 -Value $ip_fija # Router
            Set-DhcpServerv4OptionValue -ScopeId $base_red -OptionId 6 -Value "8.8.8.8", "8.8.4.4" # DNS
            
            Write-Host "`n [OK] Servidor DHCP configurado y activo." -ForegroundColor Green
            Pause
        }
        "2" {
            Write-Host "`n --- AMBITOS CONFIGURADOS ---" -ForegroundColor Cyan
            Get-DhcpServerv4Scope | Select-Object ScopeId, Name, StartRange, EndRange, State | Format-Table -AutoSize
            
            Write-Host " --- CONCESIONES (LEASES) ---" -ForegroundColor Cyan
            Get-DhcpServerv4Scope | ForEach-Object { Get-DhcpServerv4Lease -ScopeId $_.ScopeId } | Format-Table -AutoSize
            Pause
        }
        "3" {
            Restart-Service DHCPServer
            Write-Host " [OK] Servicio reiniciado." -ForegroundColor Green
            Pause
        }
    }
} while ($opcion -ne "4")
