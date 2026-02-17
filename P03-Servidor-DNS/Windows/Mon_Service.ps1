function Check-Service {
    param([string]$RoleName, [string]$ServiceName)
    Write-Host "[*] Verificando Rol $RoleName..." -ForegroundColor Cyan
    $feature = Get-WindowsFeature $RoleName
    if (-not $feature.Installed) {
        Write-Host "[!] Instalando $RoleName..." -ForegroundColor Yellow
        Install-WindowsFeature $RoleName -IncludeManagementTools | Out-Null
    }
    if ((Get-Service $ServiceName).Status -ne 'Running') {
        Start-Service $ServiceName
    }
}
