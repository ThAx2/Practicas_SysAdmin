# ==============================================================================
# P09 - 02-FGPP-Auditoria.ps1
# Fine-Grained Password Policy + Hardening de Auditoría + Reporte de Eventos
# ==============================================================================
Import-Module ActiveDirectory

# ----------------------------------------------------------------
# 1. FGPP — Política de 12 caracteres para admins delegados
# ----------------------------------------------------------------
Write-Host "--- Fine-Grained Password Policy (FGPP) ---" -ForegroundColor Cyan

$PolicyAdmins = "Politica_Admins_12"
$PolicyUsers  = "Politica_Usuarios_8"

if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$PolicyAdmins'" -ErrorAction SilentlyContinue)) {
    New-ADFineGrainedPasswordPolicy `
        -Name                        $PolicyAdmins `
        -DisplayName                 "Admins - Minimo 12 Caracteres" `
        -Description                 "Politica alta para administradores delegados" `
        -Precedence                  1 `
        -MinPasswordLength           12 `
        -ComplexityEnabled           $true `
        -PasswordHistoryCount        5 `
        -LockoutThreshold            3 `
        -LockoutDuration             "00:30:00" `
        -LockoutObservationWindow    "00:30:00" `
        -ReversibleEncryptionEnabled $false
    Write-Host "[OK] Politica '$PolicyAdmins' creada." -ForegroundColor Green
} else {
    Write-Host "[*] Politica '$PolicyAdmins' ya existe." -ForegroundColor Yellow
}

# Política de 8 caracteres para usuarios estándar (Cuates y NoCuates)
if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$PolicyUsers'" -ErrorAction SilentlyContinue)) {
    New-ADFineGrainedPasswordPolicy `
        -Name                        $PolicyUsers `
        -DisplayName                 "Usuarios Estandar - Minimo 8 Caracteres" `
        -Description                 "Politica estandar para usuarios de las OUs" `
        -Precedence                  10 `
        -MinPasswordLength           8 `
        -ComplexityEnabled           $true `
        -PasswordHistoryCount        3 `
        -LockoutThreshold            5 `
        -LockoutDuration             "00:15:00" `
        -LockoutObservationWindow    "00:15:00" `
        -ReversibleEncryptionEnabled $false
    Write-Host "[OK] Politica '$PolicyUsers' creada." -ForegroundColor Green
} else {
    Write-Host "[*] Politica '$PolicyUsers' ya existe." -ForegroundColor Yellow
}

# Aplicar FGPP a los 4 admins delegados
$Admins = @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")
foreach ($adm in $Admins) {
    try {
        Add-ADFineGrainedPasswordPolicySubject -Identity $PolicyAdmins -Subjects $adm -ErrorAction Stop
        Write-Host "  [OK] $PolicyAdmins aplicada a: $adm" -ForegroundColor Green
    } catch {
        Write-Host "  [*] $adm ya tiene la politica asignada." -ForegroundColor Yellow
    }
}

# Aplicar política de 8 chars a los grupos de usuarios estándar
foreach ($grupo in @("Cuates","NoCuates")) {
    try {
        Add-ADFineGrainedPasswordPolicySubject -Identity $PolicyUsers -Subjects $grupo -ErrorAction Stop
        Write-Host "  [OK] $PolicyUsers aplicada al grupo: $grupo" -ForegroundColor Green
    } catch {
        Write-Host "  [*] Grupo $grupo ya tiene la politica asignada." -ForegroundColor Yellow
    }
}

# ----------------------------------------------------------------
# 2. Hardening de Auditoría
# ----------------------------------------------------------------
Write-Host "`n--- Hardening de Auditoria ---" -ForegroundColor Cyan

$categorias = @(
    @{ sub = "Logon";                     area = "exito y fallo" },
    @{ sub = "Logoff";                    area = "exito" },
    @{ sub = "Account Lockout";           area = "exito y fallo" },
    @{ sub = "File System";               area = "exito y fallo" },
    @{ sub = "Handle Manipulation";       area = "exito y fallo" },
    @{ sub = "Other Account Logon Events";area = "exito y fallo" },
    @{ sub = "User Account Management";   area = "exito y fallo" },
    @{ sub = "Computer Account Management";area="exito y fallo" }
)

foreach ($cat in $categorias) {
    auditpol /set /subcategory:"$($cat.sub)" /success:enable /failure:enable | Out-Null
    Write-Host "  [OK] Auditoria activada: $($cat.sub)" -ForegroundColor Green
}

Write-Host "[OK] Hardening de auditoria completado." -ForegroundColor Green

# ----------------------------------------------------------------
# 3. Script de Reporte — Últimos 10 eventos ID 4625 (Acceso Denegado)
# ----------------------------------------------------------------
Write-Host "`n--- Reporte de Accesos Fallidos (ID 4625) ---" -ForegroundColor Cyan

$PathReporte = "$env:USERPROFILE\Desktop\Reporte_Accesos_Fallidos_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

try {
    $Eventos = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        Id      = 4625
    } -MaxEvents 10 -ErrorAction Stop

    $lineas = @()
    $lineas += "=" * 65
    $lineas += "   REPORTE DE AUDITORIA - INTENTOS DE ACCESO FALLIDOS"
    $lineas += "   Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lineas += "   Servidor: $env:COMPUTERNAME"
    $lineas += "=" * 65
    $lineas += ""

    $i = 1
    foreach ($ev in $Eventos) {
        $usuario  = $ev.Properties[5].Value
        $dominio  = $ev.Properties[6].Value
        $ip       = $ev.Properties[18].Value
        $motivo   = switch ($ev.Properties[7].Value) {
            "%%2304" { "Cuenta expirada" }
            "%%2305" { "Password expirado" }
            "%%2313" { "Password incorrecto" }
            "%%2312" { "Cuenta deshabilitada" }
            "%%2310" { "Cuenta bloqueada" }
            default  { "Credenciales invalidas" }
        }

        $lineas += "[$i] Fecha    : $($ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"
        $lineas += "    Usuario  : $dominio\$usuario"
        $lineas += "    IP Origen: $ip"
        $lineas += "    Motivo   : $motivo"
        $lineas += "    Event ID : 4625"
        $lineas += "-" * 65
        $i++
    }

    $lineas += ""
    $lineas += "Total de eventos encontrados: $($Eventos.Count)"

    $lineas | Out-File -FilePath $PathReporte -Encoding UTF8
    Write-Host "[OK] Reporte generado: $PathReporte" -ForegroundColor Green
    Write-Host "[->] Eventos registrados: $($Eventos.Count)" -ForegroundColor Cyan

} catch [System.Exception] {
    if ($_.Exception.Message -like "*No events*" -or $_.Exception.Message -like "*no se encontraron*") {
        Write-Host "[!] No hay eventos 4625 registrados aun. Intenta logins fallidos primero." -ForegroundColor Yellow
        # Crear reporte vacío con instrucciones
        @(
            "=" * 65,
            "   REPORTE DE AUDITORIA - SIN EVENTOS REGISTRADOS",
            "   Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "=" * 65,
            "",
            "No se encontraron eventos de acceso fallido (ID 4625).",
            "Para generar eventos de prueba, intenta iniciar sesion",
            "con credenciales incorrectas desde un cliente del dominio.",
            ""
        ) | Out-File -FilePath $PathReporte -Encoding UTF8
        Write-Host "[OK] Reporte vacio generado en: $PathReporte" -ForegroundColor Yellow
    } else {
        Write-Host "[!] Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n[OK] FGPP, Auditoria y Reporte finalizados." -ForegroundColor Cyan
Pause