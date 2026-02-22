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
    
    $stDHCP = "STOPPED"; $colDHCP = "Red"
    if ($dhcp.Status -eq "Running") { $stDHCP = "RUNNING"; $colDHCP = "Green" }

    $stDNS = "STOPPED"; $colDNS = "Red"
    if ($dns.Status -eq "Running") { $stDNS = "RUNNING"; $colDNS = "Green" }
    
    Write-Host "----------------------------------------------" -ForegroundColor Gray
    Write-Host " MONITOR -> DHCP: " -NoNewline
    Write-Host $stDHCP -ForegroundColor $colDHCP -NoNewline
    Write-Host " | DNS: " -NoNewline
    Write-Host $stDNS -ForegroundColor $colDNS
    Write-Host "----------------------------------------------" -ForegroundColor Gray
}
