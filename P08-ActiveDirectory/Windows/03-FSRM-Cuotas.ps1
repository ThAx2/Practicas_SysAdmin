# ==============================================================================
# P08 - FSRM: CUOTAS Y APANTALLAMIENTO DE ARCHIVOS
# Cuotas: Cuates=10MB, NoCuates=5MB
# Bloqueo: .mp3, .mp4, .exe, .msi
# ==============================================================================

$StorageBase = "C:\GestionAD\Storage"
$Dominio     = "ayala.local"
$DomainDN    = "DC=ayala,DC=local"

# ----------------------------------------------------------------
# 1. Instalar FSRM
# ----------------------------------------------------------------
function Instalar-FSRM {
    $feat = Get-WindowsFeature FS-Resource-Manager
    if (!$feat.Installed) {
        Write-Host "[*] Instalando FSRM..." -ForegroundColor Cyan
        Install-WindowsFeature FS-Resource-Manager -IncludeManagementTools | Out-Null
        Write-Host "[OK] FSRM instalado." -ForegroundColor Green
    } else {
        Write-Host "[*] FSRM ya instalado." -ForegroundColor Yellow
    }
    Import-Module FileServerResourceManager
}

# ----------------------------------------------------------------
# 2. Crear plantillas de cuota
# ----------------------------------------------------------------
function Crear-Plantillas-Cuota {
    # Cuates: 10 MB
    if (!(Get-FsrmQuotaTemplate -Name "Cuota-Cuates" -ErrorAction SilentlyContinue)) {
        New-FsrmQuotaTemplate `
            -Name "Cuota-Cuates" `
            -Size 10MB `
            -SoftLimit:$false
        Write-Host "[OK] Plantilla cuota Cuates (10MB) creada." -ForegroundColor Green
    } else {
        Write-Host "[*] Plantilla Cuota-Cuates ya existe." -ForegroundColor Yellow
    }

    # NoCuates: 5 MB
    if (!(Get-FsrmQuotaTemplate -Name "Cuota-NoCuates" -ErrorAction SilentlyContinue)) {
        New-FsrmQuotaTemplate `
            -Name "Cuota-NoCuates" `
            -Size 5MB `
            -SoftLimit:$false
        Write-Host "[OK] Plantilla cuota NoCuates (5MB) creada." -ForegroundColor Green
    } else {
        Write-Host "[*] Plantilla Cuota-NoCuates ya existe." -ForegroundColor Yellow
    }
}

# ----------------------------------------------------------------
# 3. Aplicar cuotas a carpetas de usuario
# ----------------------------------------------------------------
function Aplicar-Cuotas {
    Import-Module ActiveDirectory

    $usuarios = Get-ADUser -Filter * -SearchBase $DomainDN -Properties HomeDirectory, MemberOf |
        Where-Object { $_.HomeDirectory -ne $null }

    foreach ($u in $usuarios) {
        $carpeta = $u.HomeDirectory
        if (!(Test-Path $carpeta)) { continue }

        # Determinar grupo
        $grupos = $u.MemberOf | ForEach-Object { (Get-ADGroup $_).Name }
        if ($grupos -contains "Cuates") {
            $plantilla = "Cuota-Cuates"
            $limite    = "10MB"
        } elseif ($grupos -contains "NoCuates") {
            $plantilla = "Cuota-NoCuates"
            $limite    = "5MB"
        } else {
            continue
        }

        # Aplicar cuota
        $cuotaExistente = Get-FsrmQuota -Path $carpeta -ErrorAction SilentlyContinue
        if ($cuotaExistente) {
            Set-FsrmQuota -Path $carpeta -Template $plantilla
        } else {
            New-FsrmQuota -Path $carpeta -Template $plantilla
        }
        Write-Host "[OK] Cuota $limite aplicada: $($u.SamAccountName) -> $carpeta" -ForegroundColor Green
    }
}

# ----------------------------------------------------------------
# 4. Crear grupo de archivos bloqueados
# ----------------------------------------------------------------
function Crear-Grupo-Archivos-Bloqueados {
    $nombre = "Archivos-Prohibidos"
    $ext    = @("*.mp3","*.mp4","*.exe","*.msi","*.bat","*.cmd","*.vbs")

    if (!(Get-FsrmFileGroup -Name $nombre -ErrorAction SilentlyContinue)) {
        New-FsrmFileGroup -Name $nombre -IncludePattern $ext
        Write-Host "[OK] Grupo de archivos bloqueados creado." -ForegroundColor Green
    } else {
        Set-FsrmFileGroup -Name $nombre -IncludePattern $ext
        Write-Host "[*] Grupo de archivos bloqueados actualizado." -ForegroundColor Yellow
    }
}

# ----------------------------------------------------------------
# 5. Aplicar apantallamiento (Active Screening) a carpetas
# ----------------------------------------------------------------
function Aplicar-Apantallamiento {
    foreach ($grupo in @("Cuates","NoCuates")) {
        $carpetaGrupo = "$StorageBase\$grupo"
        if (!(Test-Path $carpetaGrupo)) { continue }

        $screenExistente = Get-FsrmFileScreen -Path $carpetaGrupo -ErrorAction SilentlyContinue
        if ($screenExistente) {
            Set-FsrmFileScreen -Path $carpetaGrupo -IncludeGroup @("Archivos-Prohibidos") -Active:$true
        } else {
            New-FsrmFileScreen -Path $carpetaGrupo -IncludeGroup @("Archivos-Prohibidos") -Active:$true
        }
        Write-Host "[OK] Apantallamiento activo en: $carpetaGrupo" -ForegroundColor Green

        # Aplicar tambien en subcarpetas de usuario
        Get-ChildItem $carpetaGrupo -Directory | ForEach-Object {
            $subPath = $_.FullName
            $scr = Get-FsrmFileScreen -Path $subPath -ErrorAction SilentlyContinue
            if ($scr) {
                Set-FsrmFileScreen -Path $subPath -IncludeGroup @("Archivos-Prohibidos") -Active:$true
            } else {
                New-FsrmFileScreen -Path $subPath -IncludeGroup @("Archivos-Prohibidos") -Active:$true
            }
            Write-Host "  [->] Apantallamiento en: $subPath" -ForegroundColor Cyan
        }
    }
}

# ----------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------
Write-Host "=== P08 FSRM CUOTAS Y APANTALLAMIENTO ===" -ForegroundColor Cyan

Instalar-FSRM
Crear-Plantillas-Cuota
Aplicar-Cuotas
Crear-Grupo-Archivos-Bloqueados
Aplicar-Apantallamiento

Write-Host "[OK] FSRM configurado correctamente." -ForegroundColor Green
Write-Host ""
Write-Host "RESUMEN:" -ForegroundColor Yellow
Write-Host "  Cuates   -> 10 MB por usuario" -ForegroundColor White
Write-Host "  NoCuates ->  5 MB por usuario" -ForegroundColor White
Write-Host "  Bloqueado: .mp3 .mp4 .exe .msi .bat .cmd .vbs" -ForegroundColor White

Pause