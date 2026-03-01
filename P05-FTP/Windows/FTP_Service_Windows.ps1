Import-Module WebAdministration

$Global:BASE_DATA = "C:\inetpub\ftproot"
$Global:FTP_ROOT = "C:\FTP_Users"
$Global:LOCAL_USER = "$Global:FTP_ROOT\LocalUser"

function Configurar_Servicio_FTP {
    $appcmd = "$env:windir\system32\inetsrv\appcmd.exe"

    if (!(Get-Website -Name "ServidorPracticas" -ErrorAction SilentlyContinue)) {
        if (!(Test-Path $Global:FTP_ROOT)) { New-Item $Global:FTP_ROOT -ItemType Directory | Out-Null }
        & $appcmd add site /name:"ServidorPracticas" /bindings:ftp://*:21 /physicalPath:"$Global:FTP_ROOT"
    }

    & $appcmd set site "ServidorPracticas" "-ftpServer.userIsolation.mode:IsolateAllDirectories"
    & $appcmd set site "ServidorPracticas" "-ftpServer.security.ssl.controlChannelPolicy:SslAllow"
    & $appcmd set site "ServidorPracticas" "-ftpServer.security.ssl.dataChannelPolicy:SslAllow"
    & $appcmd set site "ServidorPracticas" "-ftpServer.security.authentication.basicAuthentication.enabled:true"
    & $appcmd set site "ServidorPracticas" "-ftpServer.security.authentication.anonymousAuthentication.enabled:true"
    & $appcmd set config "ServidorPracticas" -section:system.ftpServer/security/authorization /+"[accessType='Allow',users='*',permissions='Read,Write']" /commit:apphost

    "general", "reprobados", "recursadores" | ForEach-Object {
        $path = Join-Path $Global:BASE_DATA $_
        if (!(Test-Path $path)) { New-Item $path -ItemType Directory -Force | Out-Null }
    }
    
    if (!(Test-Path $Global:LOCAL_USER)) { New-Item $Global:LOCAL_USER -ItemType Directory | Out-Null }

    $AnonPath = Join-Path $Global:LOCAL_USER "Public"
    if (!(Test-Path $AnonPath)) { 
        New-Item $AnonPath -ItemType Directory | Out-Null 
        cmd /c "mklink /D `"$AnonPath\general`" `"$Global:BASE_DATA\general`""
    }

    Restart-Service ftpsvc
    Write-Host "[OK] Servicio FTP Configurado." -ForegroundColor Green
}

function Crear_Usuarios {
    $input_N = Read-Host "Cantidad de usuarios a crear"
    if (!($input_N -as [int])) { Write-Host "Numero invalido."; return }
    $Cant = [int]$input_N

    for ($i=1; $i -le $Cant; $i++) {
        Write-Host "`n--- Usuario $i de $Cant ---"
        $User = Read-Host "Nombre de usuario"
        if (Get-LocalUser $User -ErrorAction SilentlyContinue) { Write-Host "Ya existe."; continue }

        $Pass = Read-Host "Contrasena" -AsSecureString
        $G_Opt = Read-Host "Grupo: 1) reprobados | 2) recursadores"
        $Grupo = if ($G_Opt -eq "1") { "reprobados" } else { "recursadores" }

        if (!(Get-LocalGroup $Grupo -ErrorAction SilentlyContinue)) { New-LocalGroup $Grupo | Out-Null }
        
        New-LocalUser -Name $User -Password $Pass -PasswordNeverExpires | Out-Null
        Add-LocalGroupMember -Group $Grupo -Member $User
        
        $UserHome = Join-Path $Global:LOCAL_USER $User
        New-Item $UserHome -ItemType Directory -Force | Out-Null

        cmd /c "mklink /D `"$UserHome\general`" `"$Global:BASE_DATA\general`""
        cmd /c "mklink /D `"$UserHome\$Grupo`" `"$Global:BASE_DATA\$Grupo`""
        New-Item (Join-Path $UserHome $User) -ItemType Directory -Force | Out-Null

        icacls $UserHome /grant "${User}:(OI)(CI)F" /T /Q | Out-Null
        Write-Host "[+] $User configurado en $Grupo." -ForegroundColor Green
    }
}

function Cambiar_Grupo {
    $User = Read-Host "Nombre del usuario"
    if (!(Get-LocalUser $User -ErrorAction SilentlyContinue)) { Write-Host "No existe."; return }

    $G_Opt = Read-Host "Nuevo Grupo: 1) reprobados | 2) recursadores"
    $NuevoG = if ($G_Opt -eq "1") { "reprobados" } else { "recursadores" }
    $ViejoG = if ($G_Opt -eq "1") { "recursadores" } else { "reprobados" }

    Remove-LocalGroupMember -Group $ViejoG -Member $User -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group $NuevoG -Member $User -ErrorAction SilentlyContinue

    $UserHome = Join-Path $Global:LOCAL_USER $User
    if (Test-Path "$UserHome\$ViejoG") { Remove-Item "$UserHome\$ViejoG" -Force }
    cmd /c "mklink /D `"$UserHome\$NuevoG`" `"$Global:BASE_DATA\$NuevoG`""

    Write-Host "[OK] $User movido a $NuevoG." -ForegroundColor Green
}

function Gestion_UG {
    while ($true) {
        Write-Host "`n[*] GESTION DE USUARIOS"
        Write-Host "1) Crear Usuarios (Masivo)"
        Write-Host "2) Cambiar Usuario de Grupo"
        Write-Host "3) Listar Usuarios"
        Write-Host "7) Volver"
        $op = Read-Host "Opcion"
        switch ($op) {
            "1" { Crear_Usuarios }
            "2" { Cambiar_Grupo }
            "3" { Get-LocalUser | Where-Object { $_.Name -notmatch "Admin|Guest|Default|WDAG" } | Select Name, Enabled }
            "7" { return }
        }
    }
}

function Menu_Principal {
    $cfg = "C:\Windows\Temp\sec.cfg"
    secedit /export /cfg $cfg | Out-Null
    (Get-Content $cfg) -replace "PasswordComplexity = 1", "PasswordComplexity = 0" | Set-Content $cfg
    secedit /configure /db $env:windir\security\local.sdb /cfg $cfg /areas SECURITYPOLICY | Out-Null

    Configurar_Servicio_FTP
    
    while ($true) {
        Write-Host "`n========================================"
        Write-Host "    SERVIDOR FTP AUTOMATIZADO (IIS)     "
        Write-Host "========================================"
        Write-Host "1) Gestion de Usuarios y Grupos"
        Write-Host "2) Reiniciar servicio (ftpsvc)"
        Write-Host "3) Probar Login (ftp localhost)"
        Write-Host "4) Salir"
        $op = Read-Host "Opcion"
        switch ($op) {
            "1" { Gestion_UG }
            "2" { Restart-Service ftpsvc; Write-Host "Reiniciado." }
            "3" { ftp localhost }
            "4" { return }
        }
    }
}

