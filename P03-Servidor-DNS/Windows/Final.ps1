if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " [!] ERROR: Debes ejecutar este script como ADMINISTRADOR." -ForegroundColor Red
    Pause
    exit
}

# --- FUNCIÓN DE VALIDACIÓN (Tu lógica intacta) ---
function Test-IsValidIP {
    param([string]$IP, $IPReferencia = $null, [string]$Tipo = "host")
    if ([string]::IsNullOrWhiteSpace($IP)) { return $false }
    $IP = $IP.Trim()
    $regex = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    if ($IP -match $regex) {
        $octetos = $IP.Split('.'); $ultimo = [int]$octetos[3]; $primero = [int]$octetos[0]
        $prohibidas = @("0.0.0.0", "1.0.0.0", "127.0.0.1", "255.255.255.255")
        if ($prohibidas -contains $IP -or $primero -eq 127 -or $primero -eq 0) { return $false }
        switch ($Tipo) {
            "mask" {
                $masksValidas = @("255.0.0.0", "255.255.0.0", "255.255.255.0", "255.255.255.192", "255.255.255.240") # Simplificado para el ejemplo
                if ($masksValidas -notcontains $IP) { return $false }
            }
            { $_ -eq "host" -or $_ -eq "rango" } { if ($ultimo -eq 255) { return $false } }
        }
        return $true
    }
    return $false
}

# --- REPARACIÓN Y CARGA DE ROL (Aquí estaba el fallo) ---
function Check-Service {
    param($ServiceName)
    Write-Host "`n [+] Verificando Rol DHCP..." -ForegroundColor Cyan
    
    # Si el comando no existe, es que el rol no está instalado de verdad
    if (-not (Get-Command Add-DhcpServerv4Scope -ErrorAction SilentlyContinue)) {
        Write-Host " [!] Rol no detectado o corrupto. Forzando instalacion con DISM..." -ForegroundColor Yellow
        
        # PASO CLAVE: DISM ignora el error 0x800f081f de archivos de origen en muchos casos
        dism /online /enable-feature /featurename:DHCPServer /all /norestart | Out-Null
        
        # Si aun así no carga, intentamos la reparación de imagen
        if (-not (Get-Command Add-DhcpServerv4Scope -ErrorAction SilentlyContinue)) {
            Write-Host " [*] Reparando almacen de componentes..." -ForegroundColor Magenta
            dism /online /cleanup-image /restorehealth | Out-Null
            Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
        }
    }

    # Intentar arrancar el servicio
    $svc = Get-Service $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Write-Host " [!] ERROR CRITICO: El servicio no se pudo instalar." -ForegroundColor Red
        Pause; exit
    }
    if ($svc.Status -ne 'Running') { Start-Service $ServiceName }
}

# --- MENU PRINCIPAL (Tu lógica intacta) ---
do {
    Clear-Host
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host "         DHCP WINDOWSITO REPARADO          " -ForegroundColor Yellow
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host " 1) Configurar Servidor (IP Fija y Ambito)"
    Write-Host " 2) Ver Ambitos y Concesiones"
    Write-Host " 3) Reiniciar Servicio DHCP"
    Write-Host " 4) Salir"
    $opcion = Read-Host "`n Selecciona una opcion"
    
    switch ($opcion) {
        "1" {
            Check-Service -ServiceName "DHCPServer"
            $interface = Read-Host " Nombre de la Interfaz (ej. Ethernet)"
            do { $mask = Read-Host " Mascara de Subred" } until (Test-IsValidIP -IP $mask -Tipo "mask")
            do { $ip_i = Read-Host " IP Servidor" } until (Test-IsValidIP -IP $ip_i -Tipo "host")
            
            $octs = $ip_i.Split('.')
            $base_red = "$($octs[0..2] -join '.').0"
            do { $ip_f = Read-Host " Rango Final" } until (Test-IsValidIP -IP $ip_f -IPReferencia $ip_i -Tipo "rango")
            
            $scopeName = Read-Host " Nombre del Ambito"
            do { $lease = Read-Host " Segundos de concesion" } while ($lease -notmatch '^[0-9]+$')

            # Lógica de Desplazamiento
            $r_inicio = "$($octs[0..2] -join '.').$([int]$octs[3] + 1)"
            $octsF = $ip_f.Split('.')
            $r_final = "$($octsF[0..2] -join '.').$([int]$octsF[3] + 1)"

            Write-Host " [+] Configurando Red..." -ForegroundColor Cyan
            New-NetIPAddress -InterfaceAlias $interface -IPAddress $ip_i -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null

            Write-Host " [+] Creando Ambito..." -ForegroundColor Cyan
            Remove-DhcpServerv4Scope -ScopeId $base_red -Force -ErrorAction SilentlyContinue
            Add-DhcpServerv4Scope -Name $scopeName -StartRange $r_inicio -EndRange $r_final -SubnetMask $mask -LeaseDuration (New-TimeSpan -Seconds $lease) -State Active
            
            Write-Host "`n [OK] DHCP Activo en $r_inicio - $r_final" -ForegroundColor Green
            Pause
        }
        "2" {
            Get-DhcpServerv4Scope | Select-Object ScopeId, Name, State | Format-Table -AutoSize
            Pause
        }
        "3" { Restart-Service DHCPServer; Pause }
    }
} while ($opcion -ne "4")
