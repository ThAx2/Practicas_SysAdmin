# 0. Verificación de privilegios de Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " [!] ERROR: Debes ejecutar este script como ADMINISTRADOR." -ForegroundColor Red
    Pause
    exit
}

function Test-IsValidIP {
    param(
        [string]$IP,
        $IPReferencia = $null,
        [string]$Tipo = "host"
    )
    if ([string]::IsNullOrWhiteSpace($IP)) { return $false }
    $IP = $IP.Trim()
    
    $regex = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    
    if ($IP -match $regex) {
        $octetos = $IP.Split('.')
        $ultimo = [int]$octetos[3]
        $primero = [int]$octetos[0]

        $prohibidas = @("0.0.0.0", "1.0.0.0", "127.0.0.1", "255.255.255.255")
        if ($prohibidas -contains $IP -or $primero -eq 127 -or $primero -eq 0) {
            Write-Host " [!] Error: IP Prohibida o reservada ($IP)." -ForegroundColor Red
            return $false
        }

        switch ($Tipo) {
            "mask" {
                $masksValidas = @("255.0.0.0", "255.128.0.0", "255.192.0.0", "255.224.0.0", "255.240.0.0", "255.248.0.0", "255.252.0.0", "255.254.0.0", "255.255.0.0", "255.255.128.0", "255.255.192.0", "255.255.224.0", "255.255.240.0", "255.255.248.0", "255.255.252.0", "255.255.254.0", "255.255.255.0", "255.255.255.128", "255.255.255.192", "255.255.255.224", "255.255.255.240", "255.255.255.248", "255.255.255.252")
                if ($masksValidas -notcontains $IP) { Write-Host " [!] Error: Mascara invalida." -ForegroundColor Red; return $false }
            }
            { $_ -eq "host" -or $_ -eq "rango" } {
                if ($ultimo -eq 255) { Write-Host " [!] Error: No se puede usar .255 (Broadcast)." -ForegroundColor Red; return $false }
            }
        }

        if ($null -ne $IPReferencia) {
            $octRef = $IPReferencia.Split('.')
            if ($octetos[0..2] -join '.' -ne ($octRef[0..2] -join '.')) {
                Write-Host " [!] Error: No pertenece a la red $($octRef[0..2] -join '.').X" -ForegroundColor Red
                return $false
            }
            if ($Tipo -eq "rango" -and $ultimo -lt [int]$octRef[3]) {
                Write-Host " [!] Error: El final debe ser mayor o igual al inicio." -ForegroundColor Red
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
    Write-Host "`n [+] Verificando Rol DHCP..." -ForegroundColor Cyan
    $feature = Get-WindowsFeature DHCP
    
    if ($feature.Installed) {
        Write-Host " [!] El Rol DHCP ya está instalado." -ForegroundColor Yellow
        $confirm = Read-Host "¿Deseas REINSTALARLO por completo (limpieza profunda)? (s/n)"
        if ($confirm -match "[Ss]") {
            Write-Host " [*] Eliminando Rol y configuraciones previas..." -ForegroundColor Magenta
            Uninstall-WindowsFeature DHCP -Remove -IncludeManagementTools | Out-Null
            Write-Host " [*] Reinstalando Rol DHCP..." -ForegroundColor Magenta
            Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
        }
    } else {
        Write-Host " [!] Instalando Rol DHCP y herramientas..." -ForegroundColor Yellow
        Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
    }

    if ((Get-Service $ServiceName).Status -ne 'Running') {
        Start-Service $ServiceName
    }
}

# --- MENU PRINCIPAL ---
do {
    Clear-Host
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host "         DHCP WINDOWSITO - AX2 EDITION          " -ForegroundColor Yellow
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
            do { $ip_i = Read-Host " IP Inicial / IP Servidor (Acepta .0)" } until (Test-IsValidIP -IP $ip_i -Tipo "host")
            
            $octs = $ip_i.Split('.')
            $base_red = "$($octs[0..2] -join '.').0"
            
            do { $ip_f = Read-Host " Rango Final (>= $ip_i)" } until (Test-IsValidIP -IP $ip_f -IPReferencia $ip_i -Tipo "rango")
            
            $scopeName = Read-Host " Nombre para el Ambito"
            $gw = Read-Host " Puerta de enlace (Enter para omitir)"
            $dns = Read-Host " Servidor DNS (Enter para omitir)"

            # Lógica de Desplazamiento +1
            $rango_real_inicio = "$($octs[0..2] -join '.').$([int]$octs[3] + 1)"
            $octsF = $ip_f.Split('.')
            $rango_real_final = "$($octsF[0..2] -join '.').$([int]$octsF[3] + 1)"

            Write-Host "`n [+] Configurando IP Fija $ip_i..." -ForegroundColor Cyan
            Remove-NetIPAddress -InterfaceAlias $interface -Confirm:$false -ErrorAction SilentlyContinue
            New-NetIPAddress -InterfaceAlias $interface -IPAddress $ip_i -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null

            Write-Host " [+] Creando Ambito DHCP en $base_red..." -ForegroundColor Cyan
            Remove-DhcpServerv4Scope -ScopeId $base_red -Force -ErrorAction SilentlyContinue
            Add-DhcpServerv4Scope -Name $scopeName -StartRange $rango_real_inicio -EndRange $rango_real_final -SubnetMask $mask -State Active
            
            if ($gw) { Set-DhcpServerv4OptionValue -ScopeId $base_red -OptionId 3 -Value $gw }
            if ($dns) { Set-DhcpServerv4OptionValue -ScopeId $base_red -OptionId 6 -Value $dns }

            Write-Host "`n [OK] Servidor en $ip_i | DHCP: $rango_real_inicio - $rango_real_final" -ForegroundColor Green
            Pause
        }
        "2" {
            Write-Host "`n --- AMBITOS ---" -ForegroundColor Cyan
            Get-DhcpServerv4Scope | Select-Object ScopeId, Name, StartRange, EndRange, State | Format-Table -AutoSize
            Write-Host " --- CONCESIONES ---" -ForegroundColor Cyan
            Get-DhcpServerv4Scope | ForEach-Object { Get-DhcpServerv4Lease -ScopeId $_.ScopeId } | Format-Table -AutoSize
            Pause
        }
        "3" { Restart-Service DHCPServer; Write-Host " [+] Servicio reiniciado."; Pause }
    }
} while ($opcion -ne "4")
