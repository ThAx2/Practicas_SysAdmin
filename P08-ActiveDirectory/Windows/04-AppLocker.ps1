# ==============================================================================
# PROYECTO: P08 - CONTROL DE EJECUCIÓN CON APPLOCKER
# OBJETIVO: Bloqueo dinámico de Notepad para la OU NoCuates (Hash + Path)
# ENTORNO: Windows Server Core -> Windows 10 Enterprise
# ==============================================================================

Import-Module ActiveDirectory
Import-Module GroupPolicy

# --- CONFIGURACIÓN DE VARIABLES ---
$Dominio      = "ayala.local"
$DomainDN     = "DC=ayala,DC=local"
$GpoName      = "AppLocker-FINAL-P08"
$sidAdmin     = "S-1-5-32-544"   # Built-in Administrators
$sidTodos     = "S-1-1-0"        # Everyone
$ouNoCuates   = "NoCuates"
$ouCuates     = "Cuates"

Write-Host "[*] Iniciando despliegue de políticas de AppLocker..." -ForegroundColor Cyan

# 1. OBTENER SID DE LA OU DESTINO
try {
    $groupNoCuates = Get-ADGroup -Identity $ouNoCuates -ErrorAction Stop
    $sidNoCuates = $groupNoCuates.SID.Value
    Write-Host "[+] SID NoCuates detectado: $sidNoCuates" -ForegroundColor Green
} catch {
    Write-Host "[!] ERROR: No se encontró el grupo/OU $ouNoCuates en el AD." -ForegroundColor Red
    return
}

# 2. DEFINICIÓN DE HASHES (CLIENTE Y SERVIDOR)
$hashCliente  = "F9D9B9DED9A67AA3CFDBD5002F3B524B265C4086C188E1BE7C936AB25627BF01"
$sizeCliente  = 201216
$hashServidor = (Get-FileHash "$env:windir\System32\notepad.exe" -Algorithm SHA256).Hash
$sizeServidor = (Get-Item "$env:windir\System32\notepad.exe").Length

# 3. CONSTRUCCIÓN DEL XML COMPLETO (Sintaxis Estricta)
$xmlPolicy = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    
    <FileHashRule Id="$([Guid]::NewGuid())" Name="DENY_NOTEPAD_HASH_CLIENTE" Description="Bloqueo total por Hash" UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="0x$hashCliente" SourceFileName="notepad.exe" SourceFileLength="$sizeCliente" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>

    <FileHashRule Id="$([Guid]::NewGuid())" Name="DENY_NOTEPAD_HASH_SERVER" Description="Bloqueo por Hash del binario local" UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="0x$hashServidor" SourceFileName="notepad.exe" SourceFileLength="$sizeServidor" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>

    <FilePathRule Id="11111111-1111-1111-1111-111111111111" Name="ALLOW_ALL_ADMINS" Description="Acceso irrestricto" UserOrGroupSid="$sidAdmin" Action="Allow">
      <Conditions>
        <FilePathCondition Path="*" />
      </Conditions>
    </FilePathRule>

    <FilePathRule Id="$([Guid]::NewGuid())" Name="ALLOW_WINDOWS_DIR" UserOrGroupSid="$sidTodos" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*" /></Conditions>
    </FilePathRule>

    <FilePathRule Id="$([Guid]::NewGuid())" Name="ALLOW_PROGRAM_FILES" UserOrGroupSid="$sidTodos" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\*" /></Conditions>
    </FilePathRule>

  </RuleCollection>
  <RuleCollection Type="Msi" EnforcementMode="NotConfigured" />
  <RuleCollection Type="Script" EnforcementMode="NotConfigured" />
  <RuleCollection Type="Appx" EnforcementMode="NotConfigured" />
</AppLockerPolicy>
"@

# 4. MANEJO DE LA GPO Y CARGA DE POLÍTICA
$xmlPath = "$env:TEMP\AppLocker_Final_P08.xml"
$xmlPolicy | Out-File -FilePath $xmlPath -Encoding UTF8 -Force

$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (!$gpo) {
    $gpo = New-GPO -Name $GpoName -Comment "P08 - Control de Software"
    Write-Host "[+] GPO '$GpoName' creada desde cero." -ForegroundColor Green
}

# IMPORTANTE: Esto vincula el XML internamente y actualiza el número de versión (evita los 72 bytes)
Import-AppLockerPolicy -XmlPolicy $xmlPath -TargetGpo $GpoName
Write-Host "[+] Política importada exitosamente a la GPO." -ForegroundColor Green

# 5. VINCULACIÓN DINÁMICA A OUs
$targetOUs = @("OU=$ouNoCuates,$DomainDN")

foreach ($path in $targetOUs) {
    if (Test-Path "AD:\$path") {
        New-GPLink -Name $GpoName -Target $path -ErrorAction SilentlyContinue | Out-Null
        Write-Host "[+] GPO vinculada a $path" -ForegroundColor Green
    } else {
        Write-Host "[!] ADVERTENCIA: La ruta $path no existe." -ForegroundColor Yellow
    }
}

# 6. LIMPIEZA DE VÍNCULOS EN CUATES (Para asegurar que ellos sí puedan abrirlo)
try {
    Remove-GPLink -Name $GpoName -Target "OU=$ouCuates,$DomainDN" -ErrorAction SilentlyContinue
    Write-Host "[*] GPO desvinculada de $ouCuates (acceso libre)." -ForegroundColor Yellow
} catch {}

# 7. FINALIZACIÓN Y REFRESCO
Invoke-GPUpdate -Force
Write-Host "`n--- RESUMEN DE DESPLIEGUE ---" -ForegroundColor Cyan
Write-Host "NoCuates -> BLOQUEADO (Notepad por Hash)" -ForegroundColor Red
Write-Host "Cuates   -> PERMITIDO (Sin GPO)" -ForegroundColor Green
Write-Host "Admins   -> PERMITIDO (Regla de bypass)" -ForegroundColor White
Write-Host "`nPROCESO COMPLETADO. En el cliente ejecuta: gpupdate /force" -ForegroundColor Cyan
