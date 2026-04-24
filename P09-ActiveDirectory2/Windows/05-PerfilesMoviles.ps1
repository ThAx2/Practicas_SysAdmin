# ==============================================================
# 05-PerfilesMoviles.ps1 (FIXED)
# Perfiles Moviles reales con sincronizacion bidireccional
# ==============================================================

$ServidorNombre   = $env:COMPUTERNAME
$CarpetaBase      = "C:\PerfilesMoviles"
$CompartidoNombre = "Perfiles$"
$CSV = Import-Csv "C:\Users\Administrator\Practicas_SysAdmin\P08-ActiveDirectory\Windows\Usuarios.csv"

# 1. Crear carpeta base y compartirla con permisos correctos
New-Item -ItemType Directory -Path $CarpetaBase -Force | Out-Null

if (-not (Get-SmbShare -Name $CompartidoNombre -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name $CompartidoNombre -Path $CarpetaBase -FullAccess "Everyone"
    Write-Host "[OK] Compartido: \\$ServidorNombre\$CompartidoNombre" -ForegroundColor Green
} else {
    Write-Host "[*] Compartido ya existe" -ForegroundColor Yellow
}

# 2. Permisos NTFS en carpeta base — critico para perfiles moviles
$Acl = Get-Acl $CarpetaBase
# Quitar herencia
$Acl.SetAccessRuleProtection($true, $false)
# Administrators: control total
$Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow"
)))
# SYSTEM: control total
$Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
    "SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow"
)))
# Creator Owner: control total sobre subcarpetas propias
$Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
    "CREATOR OWNER","FullControl","ContainerInherit,ObjectInherit","InheritOnly","Allow"
)))
# Authenticated Users: solo crear carpetas en la raiz
$Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Authenticated Users","AppendData","None","None","Allow"
)))
$Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Authenticated Users","ReadAndExecute,ListDirectory","None","None","Allow"
)))
Set-Acl -Path $CarpetaBase -AclObject $Acl
Write-Host "[OK] Permisos NTFS base configurados correctamente" -ForegroundColor Green

# 3. Procesar cada usuario del CSV
foreach ($row in $CSV) {
    $user = $row.Cuenta
    Write-Host "`n[+] Procesando: $user" -ForegroundColor Yellow

    # CRITICO: Asignar ruta SIN extension — Windows agrega .V6 automaticamente
    try {
        $RutaPerfil = "\\$ServidorNombre\$CompartidoNombre\$user"
        Set-ADUser -Identity $user -ProfilePath $RutaPerfil -ErrorAction Stop
        Write-Host "  [OK] Perfil AD: $RutaPerfil (.V6 se agrega automatico)" -ForegroundColor Green
    } catch {
        Write-Host "  [!] Error AD: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Crear carpeta V6 con estructura completa
    $CarpetaV6 = "$CarpetaBase\$user.V6"
    if (-not (Test-Path $CarpetaV6)) {
        New-Item -ItemType Directory -Path $CarpetaV6 -Force | Out-Null
        foreach ($sub in @("Desktop","Documents","Downloads","Pictures","Music","Videos","Favorites","AppData","AppData\Roaming","AppData\Local")) {
            New-Item -ItemType Directory -Path "$CarpetaV6\$sub" -Force | Out-Null
        }
        Write-Host "  [OK] Carpeta V6 creada: $CarpetaV6" -ForegroundColor Green
    } else {
        Write-Host "  [*] Ya existe: $CarpetaV6" -ForegroundColor Yellow
    }

    # Permisos V6: solo el usuario dueno y Administrators
    try {
        $AclV6 = Get-Acl $CarpetaV6
        $AclV6.SetAccessRuleProtection($true, $false)
        $AclV6.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow"
        )))
        $AclV6.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow"
        )))
        $SID = (Get-ADUser $user).SID
        $AclV6.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            $SID,"FullControl","ContainerInherit,ObjectInherit","None","Allow"
        )))
        Set-Acl -Path $CarpetaV6 -AclObject $AclV6
        Write-Host "  [OK] Permisos V6 configurados" -ForegroundColor Green
    } catch {
        Write-Host "  [!] Error permisos: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 4. GPO Perfiles Moviles
Write-Host "`n--- Configurando GPO Perfiles Moviles ---" -ForegroundColor Cyan
try {
    if (-not (Get-GPO -Name "Perfiles Moviles" -ErrorAction SilentlyContinue)) {
        New-GPO -Name "Perfiles Moviles" | Out-Null
    }

    # Habilitar perfiles moviles
    Set-GPRegistryValue -Name "Perfiles Moviles" `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon" `
        -ValueName "RoamingProfilePath" `
        -Type ExpandString `
        -Value "\\$ServidorNombre\$CompartidoNombre\%USERNAME%" | Out-Null

    # Esperar siempre al perfil remoto aunque la red sea lenta
    Set-GPRegistryValue -Name "Perfiles Moviles" `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon" `
        -ValueName "SlowLinkTimeOut" `
        -Type DWord `
        -Value 0 | Out-Null

    # Eliminar copias locales al cerrar sesion (fuerza sincronizacion)
    Set-GPRegistryValue -Name "Perfiles Moviles" `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon" `
        -ValueName "DeleteRoamingCache" `
        -Type DWord `
        -Value 0 | Out-Null

    New-GPLink -Name "Perfiles Moviles" -Target "DC=ayala,DC=local" -ErrorAction SilentlyContinue | Out-Null
    Write-Host "[OK] GPO Perfiles Moviles configurada y vinculada" -ForegroundColor Green
} catch {
    Write-Host "[!] Error GPO: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. GPO Folder Redirection — redirige carpetas al servidor
# Esta es la clave para que los archivos siempre esten en el servidor
Write-Host "`n--- Configurando Folder Redirection ---" -ForegroundColor Cyan
try {
    if (-not (Get-GPO -Name "Redireccion Carpetas" -ErrorAction SilentlyContinue)) {
        New-GPO -Name "Redireccion Carpetas" | Out-Null
    }

    # Desktop -> servidor
    Set-GPRegistryValue -Name "Redireccion Carpetas" `
        -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
        -ValueName "Desktop" `
        -Type ExpandString `
        -Value "\\$ServidorNombre\$CompartidoNombre\%USERNAME%.V6\Desktop" | Out-Null

    # Documents -> servidor
    Set-GPRegistryValue -Name "Redireccion Carpetas" `
        -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
        -ValueName "Personal" `
        -Type ExpandString `
        -Value "\\$ServidorNombre\$CompartidoNombre\%USERNAME%.V6\Documents" | Out-Null

    # Downloads -> servidor
    Set-GPRegistryValue -Name "Redireccion Carpetas" `
        -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
        -ValueName "{374DE290-123F-4565-9164-39C4925E467B}" `
        -Type ExpandString `
        -Value "\\$ServidorNombre\$CompartidoNombre\%USERNAME%.V6\Downloads" | Out-Null

    # Pictures -> servidor
    Set-GPRegistryValue -Name "Redireccion Carpetas" `
        -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
        -ValueName "My Pictures" `
        -Type ExpandString `
        -Value "\\$ServidorNombre\$CompartidoNombre\%USERNAME%.V6\Pictures" | Out-Null

    New-GPLink -Name "Redireccion Carpetas" -Target "DC=ayala,DC=local" -ErrorAction SilentlyContinue | Out-Null
    Write-Host "[OK] Folder Redirection configurada" -ForegroundColor Green
} catch {
    Write-Host "[!] Error Folder Redirection: $($_.Exception.Message)" -ForegroundColor Red
}

# 6. Forzar actualizacion
gpupdate /force | Out-Null
Write-Host "[OK] Politicas actualizadas" -ForegroundColor Green

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " Perfiles moviles configurados para $($CSV.Count) usuarios" -ForegroundColor White
Write-Host " Ruta servidor : \\$ServidorNombre\$CompartidoNombre" -ForegroundColor White
Write-Host " Carpetas V6   : $CarpetaBase\<usuario>.V6" -ForegroundColor White
Write-Host " Sincronizacion: Desktop, Documents, Downloads, Pictures" -ForegroundColor White
Write-Host "========================================================" -ForegroundColor Cyan