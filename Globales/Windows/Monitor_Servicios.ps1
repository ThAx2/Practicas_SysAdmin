function Mon-Servicer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Servicio,

        [ValidateSet('latest','previous')]
        [string]$CanalVersion = 'latest',

        [string]$Version,

        [switch]$Reinstalar,
        [switch]$ReiniciarSiActivo
    )

    Write-Host "============================================" -ForegroundColor Gray
    Write-Host "Monitoreando: $Servicio" -ForegroundColor Cyan

    $servicioNorm = $Servicio.ToLower()
    $svcName = $null
    $instalado = $false

    # Servicios que se instalan como Windows Feature (no por Chocolatey)
    $featureMap = @{
        "dhcpserver" = @{
            Features = @("DHCP")
            Service  = "DHCPServer"
        }
        "dns" = @{
            Features = @("DNS")
            Service  = "DNS"
        }
        "iis" = @{
            Features = @("Web-Server")
            Service  = "W3SVC"
        }
        "web-http" = @{
            Features = @("Web-Server")
            Service  = "W3SVC"
        }
        "ftp" = @{
            Features = @("Web-Server","Web-Mgmt-Console","Web-FTP-Server","Web-FTP-Ext")
            Service  = "FTPSVC"
        }
    }

    # Mapeo general de nombre de paquete -> nombre real del servicio en Windows
    $serviceMap = @{
        "nginx"          = "nginx"
        "apache2"        = "Apache2.4"
        "httpd"          = "Apache2.4"
        "mysql"          = "MySQL"
        "mariadb"        = "MariaDB"
        "openssh-server" = "sshd"
        "ssh"            = "sshd"
        "dhcpserver"     = "DHCPServer"
        "dns"            = "DNS"
        "iis"            = "W3SVC"
        "web-http"       = "W3SVC"
        "ftp"            = "FTPSVC"
    }

    # 1) INSTALACION: Windows Feature
    if ($featureMap.ContainsKey($servicioNorm)) {
        $features = $featureMap[$servicioNorm].Features
        $svcName  = $featureMap[$servicioNorm].Service

        try {
            if ($Reinstalar) {
                Write-Host "Reinstalando features de $Servicio..." -ForegroundColor Yellow
                foreach ($featureName in $features) {
                    $f = Get-WindowsFeature -Name $featureName -ErrorAction Stop
                    if ($f.Installed) {
                        Uninstall-WindowsFeature -Name $featureName -ErrorAction Stop | Out-Null
                    }
                }
            }

            foreach ($featureName in $features) {
                $f = Get-WindowsFeature -Name $featureName -ErrorAction Stop
                if (-not $f.Installed) {
                    Write-Host "Instalando Feature '$featureName'..." -ForegroundColor Yellow
                    Install-WindowsFeature -Name $featureName -IncludeManagementTools -ErrorAction Stop | Out-Null
                } else {
                    Write-Host "Feature '$featureName' ya esta instalada." -ForegroundColor Green
                }
            }
        }
        catch {
            throw "Error instalando feature(s) de '$Servicio': $($_.Exception.Message)"
        }
    }
    # 2) INSTALACION: Chocolatey
    else {
        $choco = "C:\ProgramData\chocolatey\bin\choco.exe"
        if (-not (Test-Path $choco)) {
            throw "Chocolatey no encontrado en $choco"
        }

        $vSel = $null
        if ($Version) {
            $vSel = $Version
        } else {
            $listaV = & $choco search $Servicio --exact --all-versions --limit-output 2>$null |
                Select-Object -First 2 |
                ForEach-Object {
                    $parts = $_.ToString().Split('|')
                    if ($parts.Count -ge 2) { $parts[1] }
                }

            $versiones = @($listaV)
            if ($versiones.Count -gt 0) {
                $vSel = if ($CanalVersion -eq 'previous' -and $versiones.Count -gt 1) { $versiones[1] } else { $versiones[0] }
            }
        }

        $localList = & $choco list --local-only --exact $Servicio 2>$null
        if ($localList | Select-String -SimpleMatch $Servicio) { $instalado = $true }

        if (-not $instalado -or $Reinstalar) {
            if ($instalado -and $Reinstalar) {
                Write-Host "Reinstalando $Servicio..." -ForegroundColor Yellow
                $args = @('install', $Servicio, '--force', '-y')
            } else {
                Write-Host "Instalando $Servicio..." -ForegroundColor Yellow
                $args = @('install', $Servicio, '-y')
            }

            if ($vSel) { $args += @('--version', $vSel) }
            & $choco @args

            $localList = & $choco list --local-only --exact $Servicio 2>$null
            if (-not ($localList | Select-String -SimpleMatch $Servicio)) {
                throw "Error al instalar/reinstalar $Servicio."
            }
        } else {
            Write-Host "$Servicio ya esta instalado." -ForegroundColor Green
        }

        # Hardening opcional
        if ($servicioNorm -eq "nginx") {
            $nginxConf = "C:\tools\nginx\conf\nginx.conf"
            if (Test-Path $nginxConf) {
                (Get-Content $nginxConf) -replace '# server_tokens off;', 'server_tokens off;' | Set-Content $nginxConf
                Write-Host "[*] nginx.conf actualizado: server_tokens off." -ForegroundColor Cyan
            }
        } elseif ($servicioNorm -eq "apache2" -or $servicioNorm -eq "httpd") {
            $apacheConf = "C:\Apache24\conf\extra\httpd-security.conf"
            if (Test-Path $apacheConf) {
                $content = Get-Content $apacheConf | Where-Object { $_ -notmatch 'ServerTokens' }
                $content += "ServerTokens Prod"
                Set-Content $apacheConf $content
                Write-Host "[*] httpd-security.conf actualizado: ServerTokens Prod." -ForegroundColor Cyan
            }
        }

        if (-not $svcName) {
            $svcName = if ($serviceMap.ContainsKey($servicioNorm)) { $serviceMap[$servicioNorm] } else { $Servicio }
        }
    }

    # 3) ESTADO DEL SERVICIO (iniciar/reiniciar)
    if (-not $svcName) {
        $svcName = if ($serviceMap.ContainsKey($servicioNorm)) { $serviceMap[$servicioNorm] } else { $Servicio }
    }

    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Write-Host "[!] Servicio '$svcName' no encontrado en el sistema." -ForegroundColor Yellow
    } elseif ($svc.Status -ne "Running") {
        Start-Service -Name $svcName
        Write-Host "Estado: $svcName iniciado." -ForegroundColor Green
    } else {
        if ($ReiniciarSiActivo) {
            Restart-Service -Name $svcName
            Write-Host "Estado: $svcName reiniciado." -ForegroundColor Green
        } else {
            Write-Host "Estado: $svcName ya esta activo." -ForegroundColor Green
        }
    }

    Write-Host "Procesamiento de $Servicio finalizado."
    Write-Host "============================================`n" -ForegroundColor Gray
}
