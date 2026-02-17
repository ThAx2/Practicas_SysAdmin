# --- 1. VERIFICACIÓN DE ADMINISTRADOR (Tu código) ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " [!] ERROR: Ejecuta como ADMINISTRADOR." -ForegroundColor Red; Pause; exit
}

# --- 2. VALIDACIÓN DE IP (Tu lógica completa, corregida para .303 y vacíos) ---
function Test-IsValidIP {
    param([string]$IP, $IPReferencia = $null, [string]$Tipo = "host", [switch]$PermitirVacio)
    if ([string]::IsNullOrWhiteSpace($IP)) { return $PermitirVacio }
    $regex = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    if ($IP -match $regex) {
        $octetos = $IP.Split('.'); $ultimo = [int]$octetos[3]; $primero = [int]$octetos[0]
        if (@("0.0.0.0", "127.0.0.1", "255.255.255.255") -contains $IP -or $primero -eq 127) { return $false }
        switch ($Tipo) {
            "mask" { if (@("255.0.0.0", "255.255.0.0", "255.255.255.0") -notcontains $IP) { return $false } }
            "host" { if ($ultimo -eq 255 -or $ultimo -eq 0) { return $false } }
        }
        if ($null -ne $IPReferencia) {
            if ($octetos[0..2] -join '.' -ne ($IPReferencia.Split('.')[0..2] -join '.')) { return $false }
        }
        return $true
    }
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


# --- 4. EL PUTO ABC DE DNS ---
function Menu-DNS-ABC {
    Check-Feature -Nombre "DNS"
    do {
        Clear-Host
        Write-Host "--- ABC DE DNS ---" -ForegroundColor Cyan
        Write-Host " 1) Alta (Crear Zona y Registro A)`n 2) Baja (Eliminar Registro/Zona)`n 3) Consulta (Ver Registros)`n 4) Volver"
        $abc = Read-Host " Seleccion"
        switch ($abc) {
            "1" {
                $zona = Read-Host " Nombre de Zona (ej. pecas.com)"
                $host = Read-Host " Nombre Host (ej. www o @)"
                $ip = Read-Host " IP del Host"
                Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns" -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name $host -ZoneName $zona -IPv4Address $ip -Force
                Write-Host " [OK] Alta exitosa."; Pause
            }
            "2" {
                $zona = Read-Host " Zona"; $host = Read-Host " Host"
                Remove-DnsServerResourceRecord -ZoneName $zona -Name $host -RRType A -Force
                Write-Host " [OK] Registro eliminado."; Pause
            }
            "3" {
                $zona = Read-Host " Zona a consultar"
                Get-DnsServerResourceRecord -ZoneName $zona | Format-Table -AutoSize; Pause
            }
        }
    } while ($abc -ne "4")
}

# --- 5. CONFIGURACIÓN DHCP (Tu lógica con Desplazamiento +1) ---
function Ejecutar-DHCP {
    Check-Feature -Nombre "DHCP"
    $int = Read-Host " Interfaz (ej. Ethernet)"
    do { $mask = Read-Host " Mascara" } until (Test-IsValidIP $mask -Tipo "mask")
    do { $ip_i = Read-Host " IP Servidor" } until (Test-IsValidIP $ip_i -Tipo "host")
    do { $ip_f = Read-Host " Rango Final" } until (Test-IsValidIP $ip_f -IPReferencia $ip_i)
    
    $gw = Read-Host " Gateway (Enter para saltar)"; $dns = Read-Host " DNS (Enter para saltar)"
    $octs = $ip_i.Split('.'); $base = "$($octs[0..2] -join '.').0"
    
    # Tu lógica +1
    $r_i = "$($octs[0..2] -join '.').$([int]$octs[3] + 1)"
    $r_f = "$($ip_f.Split('.')[0..2] -join '.').$([int]$ip_f.Split('.')[3] + 1)"

    New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_i -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    Remove-DhcpServerv4Scope -ScopeId $base -Force -ErrorAction SilentlyContinue
    Add-DhcpServerv4Scope -Name "Ambito_Pecas" -StartRange $r_i -EndRange $r_f -SubnetMask $mask -State Active
    
    if ($gw -and (Test-IsValidIP $gw)) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw }
    if ($dns -and (Test-IsValidIP $dns)) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns }
    Write-Host " [OK] DHCP Configurado."; Pause
}

# --- MENÚ PRINCIPAL UNIDO ---
do {
    Clear-Host
    Write-Host "=== GESTOR WINDOWSITO (DHCP + DNS ABC) ===" -ForegroundColor Yellow
    Write-Host " 1) DHCP (Con IP Fija y Desplazamiento)`n 2) DNS (ABC COMPLETO)`n 3) Salir"
    $op = Read-Host " Selecciona"
    switch ($op) {
        "1" { Ejecutar-DHCP }
        "2" { Menu-DNS-ABC }
    }
} while ($op -ne "3")
