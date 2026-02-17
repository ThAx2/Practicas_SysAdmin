# --- 1. VERIFICACION DE ADMINISTRADOR ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " [!] EJECUTA COMO ADMINISTRADOR." -ForegroundColor Red
    Pause
    exit
}

# --- 2. VALIDACION DE IP ---
function Test-IsValidIP {
    param([string]$IP, $IPReferencia = $null, [string]$Tipo = "host", [switch]$PermitirVacio)
    if ([string]::IsNullOrWhiteSpace($IP)) { return $PermitirVacio }
    
    $regex = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    if ($IP -match $regex) {
        $octetos = $IP.Split('.')
        $primero = [int]$octetos[0]
        $ultimo = [int]$octetos[3]

        if ($primero -eq 127 -or $IP -eq "0.0.0.0" -or $IP -eq "255.255.255.255") { return $false }
        
        if ($Tipo -eq "mask") {
            $validas = @("255.0.0.0", "255.255.0.0", "255.255.255.0")
            if ($validas -notcontains $IP) { return $false }
        }
        if ($Tipo -eq "host") {
            if ($ultimo -eq 255 -or $ultimo -eq 0) { return $false }
        }
        if ($null -ne $IPReferencia) {
            $refOct = $IPReferencia.Split('.')
            if ("$($octetos[0]).$($octetos[1]).$($octetos[2])" -ne "$($refOct[0]).$($refOct[1]).$($refOct[2])") { return $false }
        }
        return $true
    }
    return $false
}

# --- 3. INSTALACION BLINDADA (SIN ERRORES) ---
function Forzar-Instalacion {
    param($NombreRol, $NombreDISM)
    Write-Host " [+] Verificando $NombreRol..." -ForegroundColor Cyan
    
    if (-not (Get-WindowsFeature $NombreRol).Installed) {
        Write-Host " [*] Intentando instalacion estandar..." -ForegroundColor Yellow
        try {
            Install-WindowsFeature $NombreRol -IncludeManagementTools -ErrorAction Stop | Out-Null
        } catch {
            Write-Host " [!] Fallo estandar. USANDO DISM (FUERZA BRUTA)..." -ForegroundColor Red
            dism /online /enable-feature /featurename:$NombreDISM /all /norestart | Out-Null
        }
    }
}

# --- 4. MENU DNS (SIMPLIFICADO) ---
function Menu-DNS {
    Forzar-Instalacion -NombreRol "DNS" -NombreDISM "DNS-Server-Full-Role"
    do {
        Clear-Host
        Write-Host "--- GESTION DNS (ABC) ---" -ForegroundColor Cyan
        Write-Host " 1) Alta (Zona + Host)"
        Write-Host " 2) Baja (Borrar)"
        Write-Host " 3) Consulta"
        Write-Host " 4) Volver"
        $op = Read-Host " Selecciona"
        
        if ($op -eq "1") {
            $z = Read-Host " Zona (ej. pecas.local)"
            $h = Read-Host " Host (ej. www)"
            $i = Read-Host " IP"
            Add-DnsServerPrimaryZone -Name $z -ZoneFile "$z.dns" -ErrorAction SilentlyContinue
            Add-DnsServerResourceRecordA -Name $h -ZoneName $z -IPv4Address $i -Force
            Write-Host " [OK] Creado."
            Pause
        }
        if ($op -eq "2") {
            $z = Read-Host " Zona"
            $h = Read-Host " Host a borrar"
            Remove-DnsServerResourceRecord -ZoneName $z -Name $h -RRType A -Force
            Pause
        }
        if ($op -eq "3") {
            $z = Read-Host " Zona a consultar"
            Get-DnsServerResourceRecord -ZoneName $z | Format-Table -AutoSize
            Pause
        }
    } while ($op -ne "4")
}

# --- 5. MENU DHCP (SIMPLIFICADO) ---
function Ejecutar-DHCP {
    Forzar-Instalacion -NombreRol "DHCP" -NombreDISM "DHCPServer"
    
    $int = Read-Host " Interfaz (ej. Ethernet)"
    do { $mask = Read-Host " Mascara" } until (Test-IsValidIP $mask -Tipo "mask")
    do { $ip_i = Read-Host " IP Servidor" } until (Test-IsValidIP $ip_i -Tipo "host")
    do { $ip_f = Read-Host " Rango Final" } until (Test-IsValidIP $ip_f -IPReferencia $ip_i)
    
    $gw = Read-Host " Gateway (Enter para saltar)"
    $dns = Read-Host " DNS (Enter para saltar)"
    
    # Calculo simple de red
    $octs = $ip_i.Split('.')
    $base = "$($octs[0]).$($octs[1]).$($octs[2]).0"
    
    # Calculo +1 simple
    $p3_inicio = [int]$octs[3] + 1
    $r_i = "$($octs[0]).$($octs[1]).$($octs[2]).$p3_inicio"
    
    $octsF = $ip_f.Split('.')
    $p3_fin = [int]$octsF[3] + 1
    $r_f = "$($octsF[0]).$($octsF[1]).$($octsF[2]).$p3_fin"

    Write-Host " [*] Configurando IP..."
    New-NetIPAddress -InterfaceAlias $int -IPAddress $ip_i -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    
    Write-Host " [*] Creando Ambito..."
    if (Get-Command Add-DhcpServerv4Scope -ErrorAction SilentlyContinue) {
        Remove-DhcpServerv4Scope -ScopeId $base -Force -ErrorAction SilentlyContinue
        Add-DhcpServerv4Scope -Name "Ambito_Auto" -StartRange $r_i -EndRange $r_f -SubnetMask $mask -State Active
        
        if ($gw -ne "") { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 3 -Value $gw }
        if ($dns -ne "") { Set-DhcpServerv4OptionValue -ScopeId $base -OptionId 6 -Value $dns }
        
        Write-Host " [OK] DHCP LISTO." -ForegroundColor Green
    } else {
        Write-Host " [!] ERROR: El rol no se instalo bien." -ForegroundColor Red
    }
    Pause
}

# --- MENU PRINCIPAL ---
do {
    Clear-Host
    Write-Host "=== FINAL DEFINITIVO ===" -ForegroundColor Yellow
    Write-Host " 1) DHCP (Configurar)"
    Write-Host " 2) DNS (ABC)"
    Write-Host " 3) Salir"
    $m = Read-Host " Opcion"
    
    if ($m -eq "1") { Ejecutar-DHCP }
    if ($m -eq "2") { Menu-DNS }
} while ($m -ne "3")
