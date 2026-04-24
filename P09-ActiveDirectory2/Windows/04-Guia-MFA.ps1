# ==============================================================================
# P09 - 04-Guia-MFA.ps1 (FIXED v5)
# Lee usuarios desde CSV, crea en AD automaticamente y asigna seed TOTP
# ==============================================================================

$MFA_Path   = "C:\MultiOTP\windows"
$QR_Path    = "$MFA_Path\QR_Codes"
$CSV_Path   = "C:\Users\Administrator\Practicas_SysAdmin\P08-ActiveDirectory\Windows\Usuarios.csv"

# Seeds por rol
$SeedAdmins   = "JBSWY3DPEHPK3PXP"
$SeedCuates   = "MFRA2YTBMJQXIZLT"
$SeedNoCuates = "GEZDGNBVGY3TQOJQ"

Write-Host "=== P09 - Configuracion MFA (MultiOTP + Google Authenticator) ===" -ForegroundColor Cyan

Set-Location $MFA_Path

if (-not (Test-Path ".\multiotp.exe")) {
    Write-Host "[!] multiotp.exe no encontrado en $MFA_Path" -ForegroundColor Red
    Pause; return
}

if (-not (Test-Path $CSV_Path)) {
    Write-Host "[!] CSV no encontrado en $CSV_Path" -ForegroundColor Red
    Pause; return
}

if (-not (Test-Path $QR_Path)) {
    New-Item -Path $QR_Path -ItemType Directory -Force | Out-Null
}

Write-Host "[OK] multiotp.exe encontrado. Directorio: $MFA_Path" -ForegroundColor Green

$ver = .\multiotp.exe -version 2>&1
Write-Host "[INFO] Version: $($ver | Where-Object { $_ -match '\d' } | Select-Object -First 1)" -ForegroundColor Cyan

# ----------------------------------------------------------------
# 1. Politica de bloqueo y timezone
# ----------------------------------------------------------------
Write-Host "`n--- Configurando Politica de Bloqueo MFA ---" -ForegroundColor Cyan
.\multiotp.exe -config max-failed-attempts=3
.\multiotp.exe -config failure-delayed-time=1800
.\multiotp.exe -config display-log=1
.\multiotp.exe -config timezone=America/Hermosillo
Write-Host "[OK] Bloqueo: 3 intentos -> 30 minutos." -ForegroundColor Green
Write-Host "[OK] Timezone: America/Hermosillo (UTC-7)" -ForegroundColor Green

# ----------------------------------------------------------------
# 2. Bypass MFA para Administrator via registro
# ----------------------------------------------------------------
Write-Host "`n--- Configurando Bypass MFA para Administrator ---" -ForegroundColor Cyan
$RegPath = "HKLM:\SOFTWARE\multiOTP"
if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
Set-ItemProperty -Path $RegPath -Name "ExcludedUsers" -Value "administrator" -Force
Write-Host "[OK] Administrator excluido del MFA" -ForegroundColor Green

# ----------------------------------------------------------------
# 3. Crear grupo SSH-Users
# ----------------------------------------------------------------
Write-Host "`n--- Configurando Grupo SSH-Users ---" -ForegroundColor Cyan
if (-not (Get-ADGroup -Filter "Name -eq 'SSH-Users'" -ErrorAction SilentlyContinue)) {
    New-ADGroup -Name "SSH-Users" -GroupScope Global -GroupCategory Security -Path "CN=Users,DC=ayala,DC=local"
    Write-Host "[OK] Grupo SSH-Users creado" -ForegroundColor Green
} else {
    Write-Host "[*] Grupo SSH-Users ya existe" -ForegroundColor Yellow
}
Add-ADGroupMember -Identity "Domain Admins" -Members "SSH-Users" -ErrorAction SilentlyContinue
Write-Host "[OK] SSH-Users agregado a Domain Admins" -ForegroundColor Green

# ----------------------------------------------------------------
# 4. Registrar admins delegados con seed Admins
# ----------------------------------------------------------------
Write-Host "`n--- Registrando Admins Delegados ---" -ForegroundColor Cyan

$UsuariosAdmin = @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")

foreach ($user in $UsuariosAdmin) {
    Write-Host "`n[+] $user" -ForegroundColor Yellow
    .\multiotp.exe -delete $user 2>&1 | Out-Null
    .\multiotp.exe -create $user TOTP $SeedAdmins 6 2>&1 | Out-Null
    .\multiotp.exe -set $user request_prefix_pin=0 2>&1 | Out-Null
    $qrFile = "$QR_Path\QR_$user.png"
    .\multiotp.exe -qrcode $user "$qrFile" 2>&1 | Out-Null
    $url = .\multiotp.exe -urllink $user 2>&1
    Add-ADGroupMember -Identity "SSH-Users" -Members $user -ErrorAction SilentlyContinue
    Write-Host "  [OK] Creado | URL: $url" -ForegroundColor Green
}

# ----------------------------------------------------------------
# 5. Leer CSV, crear en AD automaticamente y registrar en multiOTP
# ----------------------------------------------------------------
Write-Host "`n--- Registrando Usuarios desde CSV ---" -ForegroundColor Cyan

$CSV = Import-Csv $CSV_Path
$UsuariosCuates   = @()
$UsuariosNoCuates = @()

foreach ($row in $CSV) {
    $user  = $row.Cuenta
    $depto = $row.Departamento.Trim()
    $pass  = ConvertTo-SecureString $row.Password -AsPlainText -Force

    if ($depto -eq "Cuates") {
        $seed = $SeedCuates
        $ou   = "OU=Cuates,DC=ayala,DC=local"
        $UsuariosCuates += $user
    } elseif ($depto -eq "No Cuates") {
        $seed = $SeedNoCuates
        $ou   = "OU=NoCuates,DC=ayala,DC=local"
        $UsuariosNoCuates += $user
    } else {
        Write-Host "  [!] Departamento desconocido para $user : '$depto'" -ForegroundColor Red
        continue
    }

    Write-Host "[+] $user ($depto)" -ForegroundColor Yellow

    # Crear en AD si no existe
    $adUser = Get-ADUser -Filter "SamAccountName -eq '$user'" -ErrorAction SilentlyContinue
    if (-not $adUser) {
        try {
            New-ADUser -Name $row.Nombre -SamAccountName $user `
                -UserPrincipalName "$user@ayala.local" `
                -AccountPassword $pass `
                -Enabled $true `
                -ChangePasswordAtLogon $false `
                -Path $ou
            Write-Host "  [OK] Usuario creado en AD: $user -> $ou" -ForegroundColor Green
        } catch {
            Write-Host "  [!] Error creando en AD: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "  [*] Ya existe en AD: $user" -ForegroundColor Yellow
    }

    # Registrar en multiOTP
    .\multiotp.exe -delete $user 2>&1 | Out-Null
    .\multiotp.exe -create $user TOTP $seed 6 2>&1 | Out-Null
    .\multiotp.exe -set $user request_prefix_pin=0 2>&1 | Out-Null
    $qrFile = "$QR_Path\QR_$user.png"
    .\multiotp.exe -qrcode $user "$qrFile" 2>&1 | Out-Null

    # Agregar a SSH-Users
    Add-ADGroupMember -Identity "SSH-Users" -Members $user -ErrorAction SilentlyContinue
    Write-Host "  [OK] $user registrado con seed $depto y agregado a SSH-Users" -ForegroundColor Green
}

# ----------------------------------------------------------------
# 6. Resync delta de tiempo por grupo
# ----------------------------------------------------------------
Write-Host "`n--- Resync Delta de Tiempo ---" -ForegroundColor Cyan
Write-Host "Agrega estas 3 entradas en Google Authenticator:" -ForegroundColor White
Write-Host "  Admins   : $SeedAdmins" -ForegroundColor Yellow
Write-Host "  Cuates   : $SeedCuates" -ForegroundColor Yellow
Write-Host "  NoCuates : $SeedNoCuates" -ForegroundColor Yellow

$grupos = @(
    @{ Nombre="Admins";   Seed=$SeedAdmins;   Usuarios=$UsuariosAdmin },
    @{ Nombre="Cuates";   Seed=$SeedCuates;   Usuarios=$UsuariosCuates },
    @{ Nombre="NoCuates"; Seed=$SeedNoCuates; Usuarios=$UsuariosNoCuates }
)

foreach ($g in $grupos) {
    Write-Host "`nResync grupo $($g.Nombre) (seed: $($g.Seed))" -ForegroundColor Cyan
    $c1 = Read-Host "  Codigo actual Google Auth ($($g.Nombre))"
    $c2 = Read-Host "  Siguiente codigo (espera 30 seg)"
    foreach ($u in $g.Usuarios) {
        .\multiotp.exe -unlock $u 2>&1 | Out-Null
        $r = .\multiotp.exe -resync $u $c1 $c2 2>&1
        if ("$r" -match "resynchronized") {
            Write-Host "  [OK] $u sincronizado" -ForegroundColor Green
        } else {
            Write-Host "  [!] $u : $r" -ForegroundColor Red
        }
    }
}

# ----------------------------------------------------------------
# 7. SSH ForceCommand para todos excepto Administrator
# ----------------------------------------------------------------
Write-Host "`n--- Actualizando SSH sshd_config ---" -ForegroundColor Cyan

$todosUsuarios = ($UsuariosAdmin + $UsuariosCuates + $UsuariosNoCuates) -join ","

$config = Get-Content "C:\ProgramData\ssh\sshd_config"
$config | Where-Object { $_ -notmatch "ForceCommand|Match User" } |
    Set-Content "C:\ProgramData\ssh\sshd_config"

Add-Content "C:\ProgramData\ssh\sshd_config" @"

Match User $todosUsuarios
    ForceCommand cmd /c C:\MultiOTP\windows\ssh_mfa.cmd
"@

Restart-Service sshd
Write-Host "[OK] SSH MFA activado para todos excepto Administrator" -ForegroundColor Green

# ----------------------------------------------------------------
# 8. Sincronizar lockout con AD
# ----------------------------------------------------------------
Write-Host "`n--- Sincronizando Bloqueo con Active Directory ---" -ForegroundColor Cyan
try {
    Set-ADDefaultDomainPasswordPolicy `
        -Identity                 "ayala.local" `
        -LockoutDuration          "00:30:00" `
        -LockoutObservationWindow "00:30:00" `
        -LockoutThreshold         3 `
        -ErrorAction Stop
    Write-Host "[OK] AD Lockout: 3 intentos / 30 min." -ForegroundColor Green
} catch {
    Write-Host "[!] Error AD: $($_.Exception.Message)" -ForegroundColor Red
}

# ----------------------------------------------------------------
# 9. Credential Provider
# ----------------------------------------------------------------
Write-Host "`n--- Credential Provider ---" -ForegroundColor Cyan
$cpMsi = Get-ChildItem -Path "C:\MultiOTP" -Filter "multiotp_cp*.msi" -ErrorAction SilentlyContinue |
         Select-Object -First 1
if ($cpMsi) {
    msiexec /i "$($cpMsi.FullName)" MULTIOTPPATH="$MFA_Path\multiotp.exe" /quiet
    Write-Host "[OK] CP instalado desde $($cpMsi.FullName)" -ForegroundColor Green
} else {
    Write-Host "[!] MSI no encontrado en C:\MultiOTP" -ForegroundColor Yellow
}

Set-ItemProperty -Path "HKLM:\SOFTWARE\multiOTP" -Name "server_url"    -Value "http://127.0.0.1:8112" -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\multiOTP" -Name "server_secret" -Value "multiotpsecret" -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\multiOTP" -Name "enabled"       -Value 1 -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\multiOTP" -Name "cpus_logon"    -Value 1 -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\multiOTP" -Name "cpus_unlock"   -Value 1 -Force
Write-Host "[OK] Credential Provider configurado" -ForegroundColor Green

# ----------------------------------------------------------------
# Resumen
# ----------------------------------------------------------------
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "  Seeds:" -ForegroundColor White
Write-Host "    Admins   : $SeedAdmins" -ForegroundColor Yellow
Write-Host "    Cuates   : $SeedCuates" -ForegroundColor Yellow
Write-Host "    NoCuates : $SeedNoCuates" -ForegroundColor Yellow
Write-Host "  Usuarios CSV procesados : $($CSV.Count)" -ForegroundColor White
Write-Host "  Grupo SSH  : SSH-Users (Domain Admins)" -ForegroundColor White
Write-Host "  QR Codes   : $QR_Path" -ForegroundColor White
Write-Host "  Bloqueo    : 3 intentos / 30 minutos" -ForegroundColor White
Write-Host "  Timezone   : America/Hermosillo (UTC-7)" -ForegroundColor White
Write-Host "  Bypass     : administrator (sin MFA)" -ForegroundColor White
Write-Host "========================================================" -ForegroundColor Cyan

Pause