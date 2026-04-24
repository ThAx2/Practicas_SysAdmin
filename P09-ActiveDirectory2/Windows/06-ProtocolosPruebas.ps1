# ==============================================================
# 06-ProtocoloPruebas.ps1
# Script interactivo para ejecutar los 5 tests de la practica
# ==============================================================

function Show-Menu {
    Clear-Host
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "   PROTOCOLO DE PRUEBAS - P09 Seguridad AD + MFA" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Test 1 - Verificacion de Delegacion RBAC" -ForegroundColor Yellow
    Write-Host "  [2] Test 2 - Directiva de Contrasena FGPP" -ForegroundColor Yellow
    Write-Host "  [3] Test 3 - Flujo MFA (Google Authenticator)" -ForegroundColor Yellow
    Write-Host "  [4] Test 4 - Bloqueo de Cuenta por MFA Fallido" -ForegroundColor Yellow
    Write-Host "  [5] Test 5 - Reporte de Auditoria Automatizado" -ForegroundColor Yellow
    Write-Host "  [0] Salir" -ForegroundColor Red
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Cyan
}

function Test1-DelegacionRBAC {
    Clear-Host
    Write-Host "=== TEST 1: Verificacion de Delegacion RBAC ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Selecciona la accion a probar:" -ForegroundColor White
    Write-Host "  [A] Accion A - admin_identidad resetea contrasena (debe FUNCIONAR)" -ForegroundColor Green
    Write-Host "  [B] Accion B - admin_storage resetea contrasena (debe FALLAR)" -ForegroundColor Red
    Write-Host "  [V] Ver resultado actual en AD" -ForegroundColor Yellow
    Write-Host ""
    $op = Read-Host "Elige opcion"

    switch ($op.ToUpper()) {
        "A" {
            Write-Host "`n[Accion A] Reseteando contrasena de jperez como admin_identidad..." -ForegroundColor Green
            $cred = Get-Credential -UserName "AYALA\admin_identidad" -Message "Ingresa credenciales de admin_identidad"
            try {
                $nuevaPass = ConvertTo-SecureString "NuevoPass123!" -AsPlainText -Force
                Set-ADAccountPassword -Identity "jperez" -NewPassword $nuevaPass -Reset -Credential $cred -ErrorAction Stop
                Write-Host "[RESULTADO] EXITOSO - admin_identidad pudo resetear la contrasena de jperez" -ForegroundColor Green
         
            } catch {
                Write-Host "[RESULTADO] ERROR: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        "B" {
            Write-Host "`n[Accion B] Intentando resetear contrasena de jperez como admin_storage..." -ForegroundColor Red
            $cred = Get-Credential -UserName "AYALA\admin_storage" -Message "Ingresa credenciales de admin_storage"
            try {
                $nuevaPass = ConvertTo-SecureString "NuevoPass123!" -AsPlainText -Force
                Set-ADAccountPassword -Identity "jperez" -NewPassword $nuevaPass -Reset -Credential $cred -ErrorAction Stop
                Write-Host "[RESULTADO] INESPERADO - No deberia haber funcionado" -ForegroundColor Red
            } catch {
                Write-Host "[RESULTADO] ACCESO DENEGADO (correcto) - $($_.Exception.Message)" -ForegroundColor Green
           
            }
        }
        "V" {
            Write-Host "`nACLs actuales en OU Cuates para admin_storage:" -ForegroundColor Cyan
            dsacls "OU=Cuates,DC=ayala,DC=local" | Select-String "admin_storage|admin_identidad"
        }
    }
    Read-Host "`nPresiona Enter para continuar"
}

function Test2-FGPP {
    Clear-Host
    Write-Host "=== TEST 2: Directiva de Contrasena FGPP ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Intentando asignar contrasena de 8 caracteres a admin_identidad" -ForegroundColor White
    Write-Host "(Requiere minimo 12 - debe FALLAR)" -ForegroundColor Yellow
    Write-Host ""

    try {
        $passCorta = ConvertTo-SecureString "Pass123!" -AsPlainText -Force
        Set-ADAccountPassword -Identity "admin_identidad" -NewPassword $passCorta -Reset -ErrorAction Stop
        Write-Host "[RESULTADO] INESPERADO - La contrasena deberia haber sido rechazada" -ForegroundColor Red
    } catch {
        Write-Host "[RESULTADO] RECHAZADA (correcto) - $($_.Exception.Message)" -ForegroundColor Green

    }

    Write-Host "`nVerificando politica FGPP aplicada a admin_identidad:" -ForegroundColor Cyan
    Get-ADUserResultantPasswordPolicy -Identity "admin_identidad" | 
        Select-Object MinPasswordLength, LockoutThreshold, LockoutDuration | 
        Format-List

    Read-Host "`nPresiona Enter para continuar"
}

function Test3-MFA {
    Clear-Host
    Write-Host "=== TEST 3: Flujo de Autenticacion MFA ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Para probar el MFA via SSH:" -ForegroundColor White
    Write-Host "  1. Abre CMD en la maquina Windows 10" -ForegroundColor Yellow
    Write-Host "  2. Ejecuta: ssh admin_identidad@192.168.1.233" -ForegroundColor Yellow
    Write-Host "  3. Ingresa la contrasena de AD" -ForegroundColor Yellow
    Write-Host "  4. El sistema pedira el codigo de Google Authenticator" -ForegroundColor Yellow
    Write-Host "  5. Ingresa el codigo de 6 digitos de la app" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Validacion directa desde este servidor:" -ForegroundColor Cyan
    $usuario = Read-Host "Ingresa el usuario a validar (ej: admin_identidad)"
    $token = Read-Host "Ingresa el codigo actual de Google Authenticator"
    
    Set-Location "C:\MultiOTP\windows"
    $resultado = & ".\multiotp.exe" $usuario $token 2>&1
    
    if ($resultado -match "OK") {
        Write-Host "`n[RESULTADO] TOKEN VALIDO - MFA funcionando correctamente" -ForegroundColor Green
    } else {
        Write-Host "`n[RESULTADO] $resultado" -ForegroundColor Red
    }
    
    Write-Host "[EVIDENCIA] Captura esta pantalla y la app de Google Authenticator" -ForegroundColor Cyan
    Read-Host "`nPresiona Enter para continuar"
}

function Test4-BloqueoMFA {
    Clear-Host
    Write-Host "=== TEST 4: Bloqueo de Cuenta por MFA Fallido ===" -ForegroundColor Cyan
    Write-Host ""
    $usuario = Read-Host "Ingresa el usuario a probar (ej: admin_identidad)"
    
    Write-Host "`nDesbloqueando cuenta antes de la prueba..." -ForegroundColor Yellow
    Set-Location "C:\MultiOTP\windows"
    & ".\multiotp.exe" -unlock $usuario | Out-Null

    Write-Host "Enviando 3 tokens incorrectos..." -ForegroundColor Red
    1..3 | ForEach-Object {
        $resultado = & ".\multiotp.exe" $usuario "000000" 2>&1
        Write-Host "  Intento $_ : $resultado" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }

    Write-Host "`nVerificando estado de bloqueo en multiOTP:" -ForegroundColor Cyan
    $info = & ".\multiotp.exe" $usuario "000000" 2>&1
    Write-Host "  $info" -ForegroundColor Yellow

    Write-Host "`nVerificando estado en Active Directory:" -ForegroundColor Cyan
    Get-ADUser -Identity $usuario -Properties LockedOut, BadLogonCount, AccountLockoutTime |
        Select-Object Name, LockedOut, BadLogonCount, AccountLockoutTime |
        Format-List

    Read-Host "`nPresiona Enter para continuar"
}

function Test5-ReporteAuditoria {
    Clear-Host
    Write-Host "=== TEST 5: Reporte de Auditoria Automatizado ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Generando reporte de los ultimos 10 eventos ID 4625..." -ForegroundColor Yellow

    $PathReporte = "C:\Users\Administrator\Desktop\Reporte_Accesos_Fallidos_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

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
            $usuario = $ev.Properties[5].Value
            $dominio = $ev.Properties[6].Value
            $ip      = $ev.Properties[18].Value
            $lineas += "[$i] Fecha    : $($ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"
            $lineas += "    Usuario  : $dominio\$usuario"
            $lineas += "    IP Origen: $ip"
            $lineas += "    Event ID : 4625"
            $lineas += "-" * 65
            $i++
        }

        $lineas += ""
        $lineas += "Total eventos: $($Eventos.Count)"
        $lineas | Out-File -FilePath $PathReporte -Encoding UTF8

        Write-Host "[OK] Reporte generado: $PathReporte" -ForegroundColor Green
        Write-Host "[OK] Eventos registrados: $($Eventos.Count)" -ForegroundColor Green
        Write-Host ""
        Get-Content $PathReporte | Select-Object -First 30
        Write-Host "[EVIDENCIA] Adjunta el archivo al reporte tecnico" -ForegroundColor Cyan

    } catch {
        Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
    }

    Read-Host "`nPresiona Enter para continuar"
}

# ==============================================================
# MENU PRINCIPAL
# ==============================================================
do {
    Show-Menu
    $opcion = Read-Host "Selecciona un test"
    switch ($opcion) {
        "1" { Test1-DelegacionRBAC }
        "2" { Test2-FGPP }
        "3" { Test3-MFA }
        "4" { Test4-BloqueoMFA }
        "5" { Test5-ReporteAuditoria }
        "0" { Write-Host "Saliendo..." -ForegroundColor Red }
        default { Write-Host "Opcion invalida" -ForegroundColor Red; Start-Sleep 1 }
    }
} while ($opcion -ne "0")