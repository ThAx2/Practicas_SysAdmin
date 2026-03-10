function Monitor-Servicios {
    $dhcp = Get-Service DHCPServer -ErrorAction SilentlyContinue
    $dns  = Get-Service DNS       -ErrorAction SilentlyContinue
    $ftp  = Get-Service ftpsvc   -ErrorAction SilentlyContinue

    $webActivo = "NINGUNO"; $colWeb = "Red"
    if ((Get-Service nginx -ErrorAction SilentlyContinue).Status -eq "Running") {
        $webActivo = "NGINX"; $colWeb = "Green"
    } elseif ((Get-Service -Name "*httpd*" -ErrorAction SilentlyContinue).Status -eq "Running") {
        $webActivo = "APACHE"; $colWeb = "Green"
    } elseif (Get-Service -Name "*tomcat*" -ErrorAction SilentlyContinue | Where-Object Status -eq "Running") {
        $webActivo = "TOMCAT"; $colWeb = "Green"
    }

    # FIX #1: Verificar $null antes de acceder a .Status
    $stDHCP = if ($dhcp -and $dhcp.Status -eq "Running") { "RUNNING" } else { "STOPPED" }
    $colDHCP = if ($stDHCP -eq "RUNNING") { "Green" } else { "Red" }
    $stDNS  = if ($dns  -and $dns.Status  -eq "Running") { "RUNNING" } else { "STOPPED" }
    $colDNS  = if ($stDNS  -eq "RUNNING") { "Green" } else { "Red" }
    $stFTP  = if ($ftp  -and $ftp.Status  -eq "Running") { "RUNNING" } else { "STOPPED" }
    $colFTP  = if ($stFTP  -eq "RUNNING") { "Green" } else { "Red" }

    $p = if ($global:PUERTO_ACTUAL) { $global:PUERTO_ACTUAL } else { "80" }

    Write-Host "----------------------------------------------------------" -ForegroundColor Gray
    Write-Host " MONITOR -> DHCP: " -NoNewline; Write-Host $stDHCP -ForegroundColor $colDHCP -NoNewline
    Write-Host " | DNS: "           -NoNewline; Write-Host $stDNS  -ForegroundColor $colDNS  -NoNewline
    Write-Host " | FTP: "           -NoNewline; Write-Host $stFTP  -ForegroundColor $colFTP
    Write-Host " WEB ACTIVO: "      -NoNewline; Write-Host $webActivo -ForegroundColor $colWeb -NoNewline
    Write-Host " | PUERTO: "        -NoNewline; Write-Host $p -ForegroundColor Cyan
    Write-Host "----------------------------------------------------------" -ForegroundColor Gray
}

function Comprobar-Instalacion {
    param($Feature, [bool]$esTercero = $false)

    if ($esTercero) {
        # FIX #2: Validar que choco.exe exista antes de usarlo
        $chocoExe = "$env:ChocolateyInstall\bin\choco.exe"
        if (!(Test-Path $chocoExe)) { $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe" }
        if (!(Test-Path $chocoExe)) {
            Write-Host "[!] ERROR: Chocolatey no encontrado. Instálalo desde https://chocolatey.org" -ForegroundColor Red
            return
        }

        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072

        $pkg = if ($Feature -eq "apache") { "apache-httpd" } else { $Feature }

        if ($Feature -eq "tomcat") {
            Write-Host "[*] Instalando Dependencia: Java..." -ForegroundColor Yellow
            & $chocoExe install openjdk -y
        }

        Write-Host "[*] Consultando Chocolatey para $pkg..." -ForegroundColor Cyan
        $v = & $chocoExe search $pkg --exact --limit-output | Select-Object -First 5

        if ($null -eq $v -or $v.Count -eq 0) {
            Write-Host "[!] Instalando version por defecto..." -ForegroundColor Yellow
            & $chocoExe install $pkg -y --force
        } else {
            Write-Host "Versiones encontradas:"
            for ($i = 0; $i -lt $v.Count; $i++) {
                $linea = $v[$i].ToString().Split('|')
                Write-Host "$($i+1)) $($linea[0]) v$($linea[1])"
            }
            $sel = Read-Host "Elija numero (o 'd' para ultima / ENTER para defecto)"

            if ($sel -eq 'd' -or [string]::IsNullOrWhiteSpace($sel)) {
                & $chocoExe install $pkg -y --force
            } else {
                # FIX #3: Validar rango del índice antes de usarlo
                $selInt = 0
                if ([int]::TryParse($sel, [ref]$selInt) -and $selInt -ge 1 -and $selInt -le $v.Count) {
                    $v_final = ($v[$selInt - 1].ToString().Split('|'))[1]
                    & $chocoExe install $pkg --version $v_final -y --force
                } else {
                    Write-Host "[!] Selección inválida. Instalando versión por defecto." -ForegroundColor Yellow
                    & $chocoExe install $pkg -y --force
                }
            }
        }
        Pause
    } else {
        if (!(Get-WindowsFeature $Feature).Installed) {
            Install-WindowsFeature $Feature -IncludeManagementTools
        }
    }
}
