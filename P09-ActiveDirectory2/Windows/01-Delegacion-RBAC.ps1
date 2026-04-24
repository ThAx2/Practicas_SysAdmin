# ==============================================================================
# P09 - 01-Delegacion-RBAC.ps1
# Crea 4 usuarios admin delegados y aplica ACLs granulares en AD
# ==============================================================================
Import-Module ActiveDirectory

$DomainDN    = "DC=ayala,DC=local"
$OU_Cuates   = "OU=Cuates,$DomainDN"
$OU_NoCuates = "OU=NoCuates,$DomainDN"
$NetBIOS     = "AYALA"

# ----------------------------------------------------------------
# 1. Crear usuarios delegados
# ----------------------------------------------------------------
Write-Host "--- Creando Usuarios de Administracion Delegada ---" -ForegroundColor Cyan

$PassAdmin = ConvertTo-SecureString "Uas2026*Admin" -AsPlainText -Force

$Usuarios = @(
    @{ Name="admin_identidad"; Desc="Operador de Identidad IAM"        },
    @{ Name="admin_storage";   Desc="Operador de Almacenamiento"        },
    @{ Name="admin_politicas"; Desc="Administrador GPO Compliance"      },
    @{ Name="admin_auditoria"; Desc="Auditor de Seguridad Read-Only"    }
)

foreach ($u in $Usuarios) {
    $existe = Get-ADUser -Filter "SamAccountName -eq '$($u.Name)'" -ErrorAction SilentlyContinue
    if (-not $existe) {
        New-ADUser `
            -Name                  $u.Name `
            -SamAccountName        $u.Name `
            -UserPrincipalName     "$($u.Name)@ayala.local" `
            -Description           $u.Desc `
            -AccountPassword       $PassAdmin `
            -Enabled               $true `
            -ChangePasswordAtLogon $false `
            -Path                  "CN=Users,$DomainDN"
        Write-Host "[OK] Creado: $($u.Name)" -ForegroundColor Green
    } else {
        Write-Host "[*] Ya existe: $($u.Name)" -ForegroundColor Yellow
    }
}

# ----------------------------------------------------------------
# 2. ROL 1 — admin_identidad: Control total sobre OUs Cuates y NoCuates
#    Puede crear/modificar/eliminar usuarios y resetear contraseñas
# ----------------------------------------------------------------
Write-Host "`n--- ROL 1: admin_identidad (IAM Operator) ---" -ForegroundColor Cyan

foreach ($ou in @($OU_Cuates, $OU_NoCuates)) {
    # Control total sobre objetos de usuario en la OU
    dsacls $ou /G "${NetBIOS}\admin_identidad:CCDC;user" /I:S | Out-Null
    # Permiso de Reset Password
    dsacls $ou /G "${NetBIOS}\admin_identidad:CA;Reset Password;user" /I:S | Out-Null
    # Permiso de escritura en atributos básicos
    dsacls $ou /G "${NetBIOS}\admin_identidad:WP;telephoneNumber;user" /I:S | Out-Null
    dsacls $ou /G "${NetBIOS}\admin_identidad:WP;mail;user" /I:S | Out-Null
    dsacls $ou /G "${NetBIOS}\admin_identidad:WP;physicalDeliveryOfficeName;user" /I:S | Out-Null
    Write-Host "[OK] Permisos IAM aplicados en: $ou" -ForegroundColor Green
}

# ----------------------------------------------------------------
# 3. ROL 2 — admin_storage: DENEGADO explícitamente Reset Password
#    Solo gestiona FSRM; no puede resetear contraseñas en AD
# ----------------------------------------------------------------
Write-Host "`n--- ROL 2: admin_storage (Storage Operator) ---" -ForegroundColor Cyan

foreach ($ou in @($OU_Cuates, $OU_NoCuates)) {
    # DENY explícito de Reset Password
    dsacls $ou /D "${NetBIOS}\admin_storage:CA;Reset Password;user" /I:S | Out-Null
    Write-Host "[OK] DENEGADO Reset Password para admin_storage en: $ou" -ForegroundColor Green
}

# Agregar al grupo local de FSRM para que pueda gestionar cuotas y apantallamiento
$fsrmGroup = "File Server Resource Manager Users"
$fsrmExists = Get-LocalGroup -Name $fsrmGroup -ErrorAction SilentlyContinue
if (-not $fsrmExists) {
    New-LocalGroup -Name $fsrmGroup -Description "Gestores de FSRM" -ErrorAction SilentlyContinue
}
Add-LocalGroupMember -Group $fsrmGroup -Member "${NetBIOS}\admin_storage" -ErrorAction SilentlyContinue
Write-Host "[OK] admin_storage agregado a grupo FSRM." -ForegroundColor Green

# ----------------------------------------------------------------
# 4. ROL 3 — admin_politicas: Lectura en dominio + escritura en GPOs
#    Acceso a Group Policy Creator Owners para vincular/desvincular GPOs
# ----------------------------------------------------------------
Write-Host "`n--- ROL 3: admin_politicas (GPO Compliance) ---" -ForegroundColor Cyan

# Lectura en todo el dominio
dsacls $DomainDN /G "${NetBIOS}\admin_politicas:GR" | Out-Null

# Agregar a Group Policy Creator Owners (puede crear/editar GPOs)
Add-ADGroupMember -Identity "Group Policy Creator Owners" -Members "admin_politicas" -ErrorAction SilentlyContinue
Write-Host "[OK] admin_politicas agregado a Group Policy Creator Owners." -ForegroundColor Green

# DENY de escritura sobre objetos usuario (no puede modificar cuentas)
foreach ($ou in @($OU_Cuates, $OU_NoCuates)) {
    dsacls $ou /D "${NetBIOS}\admin_politicas:WP;;user" /I:S | Out-Null
}
Write-Host "[OK] DENEGADA escritura sobre usuarios para admin_politicas." -ForegroundColor Green

# ----------------------------------------------------------------
# 5. ROL 4 — admin_auditoria: Solo lectura — Event Log Readers
# ----------------------------------------------------------------
Write-Host "`n--- ROL 4: admin_auditoria (Security Auditor) ---" -ForegroundColor Cyan

# Agregar al grupo Event Log Readers para leer Security Logs
Add-LocalGroupMember -Group "Event Log Readers" -Member "${NetBIOS}\admin_auditoria" -ErrorAction SilentlyContinue
Write-Host "[OK] admin_auditoria agregado a Event Log Readers." -ForegroundColor Green

# Solo lectura en el dominio — sin permisos de escritura
dsacls $DomainDN /G "${NetBIOS}\admin_auditoria:GR" | Out-Null
# DENY explícito de escritura en todo el dominio
dsacls $DomainDN /D "${NetBIOS}\admin_auditoria:GW" | Out-Null
Write-Host "[OK] admin_auditoria: solo lectura en el dominio." -ForegroundColor Green

Write-Host "`n[OK] Delegacion RBAC configurada correctamente." -ForegroundColor Cyan
Pause