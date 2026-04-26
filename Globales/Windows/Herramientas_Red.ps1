function Validar-IP {
    param($IP)
    if ($IP -notmatch "^\d{1,3}(\.\d{1,3}){3}$") { return $false }
    $octetos = $IP.Split('.')
    foreach ($o in $octetos) {
        if ([int]$o -lt 0 -or [int]$o -gt 255) { return $false }
    }
    return $true
}

function Validar-Dominio {
    param($Dominio)
    if ($Dominio -match "^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$") {
        return $true
    } else {
        return $false
    }
}

function Configurar-Red {
    param($Interfaz, $IP, $Mascara, $Gateway)
    Write-Host "[*] Aplicando IP estatica en $Interfaz..." -ForegroundColor Cyan
    Set-NetIPInterface -InterfaceAlias $Interfaz -DHCP Disabled -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceAlias $Interfaz -AddressFamily IPv4 |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    $prefix = 24
    if ($Mascara) {
        try {
            $bytes = ([System.Net.IPAddress]::Parse($Mascara)).GetAddressBytes()
            $bits  = ($bytes | ForEach-Object {
                [Convert]::ToString($_, 2).PadLeft(8, '0')
            }) -join ''
            $prefix = ($bits.ToCharArray() | Where-Object { $_ -eq '1' }).Count
        } catch {
            Write-Host "[!] Mascara invalida, usando /24 por defecto." -ForegroundColor Yellow
        }
    }
    $p = @{ InterfaceAlias = $Interfaz; IPAddress = $IP; PrefixLength = $prefix }
    if ($Gateway) { $p.DefaultGateway = $Gateway }
    New-NetIPAddress @p -ErrorAction SilentlyContinue | Out-Null
    Write-Host "[OK] Red configurada." -ForegroundColor Green
}

function Validar-Puerto {
    $p = Read-Host "Ingrese el puerto deseado"

    # Validar que sea numero
    if ($p -notmatch '^\d+$' -or [int]$p -lt 1 -or [int]$p -gt 65535) {
        Write-Host "[!] Error: Puerto invalido. Debe ser un numero entre 1 y 65535." -ForegroundColor Red
        return $false
    }

    # Puertos reservados del sistema
    if ($p -match '^(21|22|53|67|68|3389)$') {
        Write-Host "[!] Error: Puerto $p reservado por el sistema." -ForegroundColor Red
        return $false
    }

    # FIX: Si el puerto esta en uso, intentar liberar el proceso antes de rechazarlo
    $conexion = Get-NetTCPConnection -LocalPort ([int]$p) -State Listen -ErrorAction SilentlyContinue
    if ($conexion) {
        $pid = $conexion | Select-Object -ExpandProperty OwningProcess -First 1
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        $nombre = if ($proc) { $proc.ProcessName } else { "PID $pid" }

        Write-Host "[!] Puerto $p en uso por: $nombre (PID $pid)" -ForegroundColor Yellow
        $resp = Read-Host "   Desea liberar el puerto? (s/N)"
        if ($resp -match '^[sS]$') {
            Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            $check = Get-NetTCPConnection -LocalPort ([int]$p) -State Listen -ErrorAction SilentlyContinue
            if ($check) {
                Write-Host "[!] No se pudo liberar el puerto $p." -ForegroundColor Red
                return $false
            }
            Write-Host "[OK] Puerto $p liberado." -ForegroundColor Green
        } else {
            Write-Host "[!] Puerto $p no asignado." -ForegroundColor Red
            return $false
        }
    }

    $global:PUERTO_ACTUAL = [int]$p
    Write-Host "[OK] Puerto $p asignado." -ForegroundColor Green
    return $true
}

function Detener-Competencia {
    param($actual)
    $servicios = @{
        "nginx"  = "nginx"
        "apache" = "Apache"
        "tomcat" = "Tomcat9"
    }
    foreach ($key in $servicios.Keys) {
        if ($key -ne $actual) {
            $svc = Get-Service -Name $servicios[$key] -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq "Running") {
                Stop-Service $svc.Name -Force -ErrorAction SilentlyContinue
                Write-Host "  [->] Detenido: $($svc.Name)" -ForegroundColor Yellow
            }
            Get-Process -Name $key -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
}
