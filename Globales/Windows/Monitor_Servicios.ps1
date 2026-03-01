function Comprobar-Instalacion {
    param($Feature)
    $estado = Get-WindowsFeature $Feature
    if ($estado.Installed) {
        Write-Host "[v] El servicio $($Feature) ya está instalado." -ForegroundColor Green
        $resp = Read-Host "¿Desea reinstalarlo? (s/n)"
        if ($resp -eq "s") {
            Write-Host "[*] Reinstalando..." -ForegroundColor Yellow
            Uninstall-WindowsFeature $Feature -IncludeManagementTools | Out-Null
            Install-WindowsFeature $Feature -IncludeManagementTools | Out-Null
        }
    } else {
        Write-Host "[x] El servicio $($Feature) NO está instalado." -ForegroundColor Red
        $resp = Read-Host "¿Desea instalarlo ahora? (s/n)"
        if ($resp -eq "s") {
            Install-WindowsFeature $Feature -IncludeManagementTools | Out-Null
        }
    }
}
function Monitor-Servicios {
    $dhcp = Get-Service DHCPServer -ErrorAction SilentlyContinue
    $dns = Get-Service DNS -ErrorAction SilentlyContinue
    $ftp = Get-Service ftpsvc -ErrorAction SilentlyContinue 
    
    $stDHCP = if ($dhcp.Status -eq "Running") { "RUNNING" } else { "STOPPED" }
    $colDHCP = if ($stDHCP -eq "RUNNING") { "Green" } else { "Red" }

    $stDNS = if ($dns.Status -eq "Running") { "RUNNING" } else { "STOPPED" }
    $colDNS = if ($stDNS -eq "RUNNING") { "Green" } else { "Red" }

    $stFTP = if ($ftp.Status -eq "Running") { "RUNNING" } else { "STOPPED" }
    $colFTP = if ($stFTP -eq "RUNNING") { "Green" } else { "Red" }
    
    Write-Host "----------------------------------------------------------" -ForegroundColor Gray
    Write-Host " MONITOR -> DHCP: " -NoNewline; Write-Host $stDHCP -ForegroundColor $colDHCP -NoNewline
    Write-Host " | DNS: " -NoNewline; Write-Host $stDNS -ForegroundColor $colDNS -NoNewline
    Write-Host " | FTP: " -NoNewline; Write-Host $stFTP -ForegroundColor $colFTP
    Write-Host "----------------------------------------------------------" -ForegroundColor Gray
}
