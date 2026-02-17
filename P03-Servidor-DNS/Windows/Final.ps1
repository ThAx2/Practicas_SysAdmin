# --- 1. VERIFICACIÓN DE ADMINISTRADOR ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " [!] EJECUTA COMO ADMINISTRADOR." -ForegroundColor Red; Pause; exit
}

# --- 2. VALIDACIÓN DE IP (Tu lógica exacta) ---
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

# --- 3. INSTALACIÓN BLINDADA (Aquí arreglamos tus dos errores) ---
function Forzar-Instalacion {
    param($NombreRol, $NombreDISM)
    Write-Host " [+] Verificando $NombreRol..." -ForegroundColor Cyan
    
    # Intentamos verificar si está instalado
    if (-not (Get-WindowsFeature $NombreRol).Installed) {
        Write-Host " [*] Intentando instalación estándar..." -ForegroundColor Yellow
        try {
            # Intento 1: Normal
            Install-WindowsFeature $NombreRol -IncludeManagementTools -ErrorAction Stop | Out-Null
        } catch {
            # Intento 2: Si falla con 0x800f081f, usamos DISM (Fuerza Bruta)
            Write-Host " [!] Falló instalación estándar. ACTIVANDO DISM DE EMERGENCIA..." -ForegroundColor Red
            dism /online /enable-feature /featurename:$NombreDISM /all /norestart | Out-Null
        }
    }
    
    # Verificación final
    if ((Get-WindowsFeature $NombreRol).Installed) {
        Write-Host " [OK] $NombreRol instalado correctamente." -ForegroundColor Green
    } else {
        Write-Host " [X] ERROR CRÍTICO: Ni DISM pudo instalarlo. Revisa tu ISO de Windows." -ForegroundColor Red
    }
}

# --- 4. DNS ABC (Tu petición) ---
function Menu-DNS {
    Forzar-Instalacion -NombreRol "DNS" -NombreDISM "DNS-Server-Full-Role"
    do {
        Clear-Host
        Write-Host "--- GESTIÓN DNS (ABC) ---" -ForegroundColor Cyan
        Write-Host " 1) Alta (Zona + Host A)`n 2) Baja (Borrar)`n 3) Consulta`n 4) Volver"
        $op = Read-Host " Selecciona"
        switch ($op) {
            "1" {
                $z = Read-Host " Zona (ej. pecas.local)"; $h = Read-Host " Host (ej. www)"; $i = Read-Host " IP"
                Add-DnsServerPrimaryZone -Name $z -ZoneFile "$z.dns" -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name $h -ZoneName $z -IPv4Address $i -Force
                Write-Host " [OK] Creado."; Pause
            }
            "2" {
                $z = Read-Host " Zona"; $h = Read-Host " Host a borrar"
                Remove-DnsServerResourceRecord -ZoneName $z -Name $h -RRType A -Force; Pause
            }
            "3" {
                $z = Read-Host " Zona a consultar"
                Get-DnsServerResourceRecord -ZoneName $z | Format-Table -AutoSize; Pause
            }
        }
    } while ($op -ne "4")
}

# --- 5. DHCP CONFIG (Con lógica +1) ---
function Ejecutar-DHCP {
    # Aquí llamamos a la función con el nombre CORRECTO
    Forzar-Instalacion -NombreRol "DHCP" -NombreDISM "DHCPServer"
    
    $int = Read-Host " Interfaz (ej. Ethernet)"
    do { $mask = Read-Host " Mascara" } until (Test-IsValidIP $mask -Tipo "mask")
    do { $ip_i = Read-Host " IP Servidor" } until (Test-IsValidIP $ip_i -Tipo "host")
    do { $ip_f = Read-Host " Rango Final" } until (Test-IsValidIP $ip_f -IPReferencia $ip_i)
    
    $gw = Read-Host " Gateway (Enter para saltar)"; $dns = Read-Host " DNS (Enter para saltar)"
    $octs = $ip_i.Split('.'); $base = "$($octs[0..2] -join '.').0"
    
    # Tu lógica de desplazamiento +1
    $r_i = "$($octs[0..2] -join '.').$([int]$octs[3] + 1)"
    $r_f = "$($ip_f.Split('.')[0..2] -join '.').$([int]$ip_f.Split('.')[3] + 1)"

    # Configuración de red e instalación de ámbito
    New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_i -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    
    # Si DISM funcionó arriba, este comando YA NO dará error rojo
    if (Get-Command Add-DhcpServerv4Scope -ErrorAction SilentlyContinue) {
        Remove-DhcpServerv4Scope -ScopeId $base -Force -ErrorAction SilentlyContinue
        Add-DhcpServerv4Scope -Name "Ambito_Auto" -StartRange $r_i -EndRange $r_f -SubnetMask $mask -State Active
        if ($gw -and (Test-IsValidIP $gw)) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw }
        if ($dns -and (Test-IsValidIP $dns)) { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns }
        Write-Host " [OK] DHCP Configurado." -ForegroundColor Green
    } else {
        Write-Host " [!] No se puede configurar DHCP porque la instalación falló." -ForegroundColor Red
    }
    Pause
}

# --- MENÚ PRINCIPAL ---
do {
    Clear-Host
    Write-Host "=== FINAL DEFINITIVO ===" -ForegroundColor Yellow
    Write-Host " 1) DHCP`n 2) DNS (ABC)`n 3) Salir"
    $m = Read-Host " Opcion"
    switch ($m) {
        "1" { Ejecutar-DHCP }
        "2" { Menu-DNS }
    }
} while ($m -ne "3")
