# ==============================================================================
# P08 - GPO: CIERRE DE SESION AL EXPIRAR HORARIO
# Aplica GPO de "Logoff cuando expira el tiempo de inicio de sesion"
# ==============================================================================

Import-Module ActiveDirectory
Import-Module GroupPolicy

$Dominio  = "ayala.local"
$DomainDN = "DC=ayala,DC=local"

function Crear-GPO-Logoff {
    param([string]$NombreGPO, [string]$OU)

    # Crear GPO si no existe
    $gpo = Get-GPO -Name $NombreGPO -ErrorAction SilentlyContinue
    if (!$gpo) {
        $gpo = New-GPO -Name $NombreGPO -Domain $Dominio
        Write-Host "[OK] GPO creada: $NombreGPO" -ForegroundColor Green
    } else {
        Write-Host "[*] GPO ya existe: $NombreGPO" -ForegroundColor Yellow
    }

    # Configurar: Seguridad de red - cerrar sesion al expirar logon hours
    # Clave: MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\EnableForcedLogOff = 1
    Set-GPRegistryValue `
        -Name $NombreGPO `
        -Key "HKLM\System\CurrentControlSet\Services\LanManServer\Parameters" `
        -ValueName "EnableForcedLogOff" `
        -Type DWord `
        -Value 1

    # Configurar via Security Settings (NetworkLogon)
    # Usar secedit para aplicar "Network security: Force logoff when logon hours expire"
    $tmpInf = "$env:TEMP\logoff_policy.inf"
    $content = @"
[Unicode]
Unicode=yes
[System Access]
ForceLogoffWhenHourExpire = 1
[Version]
signature="`$CHICAGO`$"
Revision=1
"@
    Set-Content $tmpInf $content -Encoding Unicode

    # Vincular GPO a la OU
    $ouPath = "OU=$OU,$DomainDN"
    $links  = (Get-GPInheritance -Target $ouPath).GpoLinks | Where-Object { $_.DisplayName -eq $NombreGPO }
    if (!$links) {
        New-GPLink -Name $NombreGPO -Target $ouPath -LinkEnabled Yes
        Write-Host "[OK] GPO vinculada a: $ouPath" -ForegroundColor Green
    } else {
        Write-Host "[*] GPO ya vinculada a: $ouPath" -ForegroundColor Yellow
    }

    # Forzar actualizacion de politicas
    Invoke-GPUpdate -Force -ErrorAction SilentlyContinue

    Remove-Item $tmpInf -Force -ErrorAction SilentlyContinue
}

# ----------------------------------------------------------------
# Aplicar GPO a ambos grupos
# ----------------------------------------------------------------
Write-Host "=== P08 GPO LOGOFF ===" -ForegroundColor Cyan

Crear-GPO-Logoff -NombreGPO "GPO-Logoff-Cuates"   -OU "Cuates"
Crear-GPO-Logoff -NombreGPO "GPO-Logoff-NoCuates" -OU "NoCuates"

# ----------------------------------------------------------------
# Aplicar secedit globalmente en el DC
# ----------------------------------------------------------------
Write-Host "[*] Aplicando politica de cierre de sesion..." -ForegroundColor Cyan

$infContent = @"
[Unicode]
Unicode=yes
[System Access]
ForceLogoffWhenHourExpire = 1
[Version]
signature="`$CHICAGO`$"
Revision=1
"@

$infPath = "$env:TEMP\force_logoff.inf"
$dbPath  = "$env:TEMP\force_logoff.sdb"
Set-Content $infPath $infContent -Encoding Unicode
secedit /configure /db $dbPath /cfg $infPath /areas SECURITYPOLICY /quiet
Remove-Item $infPath, $dbPath -Force -ErrorAction SilentlyContinue

Write-Host "[OK] Politica de cierre de sesion aplicada." -ForegroundColor Green
Write-Host "[OK] GPOs configuradas correctamente." -ForegroundColor Green

Pause