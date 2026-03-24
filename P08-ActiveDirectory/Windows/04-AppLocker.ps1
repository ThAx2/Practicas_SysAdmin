Import-Module ActiveDirectory; Import-Module GroupPolicy
$Dominio = "ayala.local"; $GpoName = "AppLocker-P08"
$sidNoCuates = (Get-ADGroup "NoCuates").SID.Value
$sidAdmin = "S-1-5-32-544"; $sidTodos = "S-1-1-0"

# --- CONSTRUCCIÓN DEL XML COMPLETO ---
$xmlPolicy = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="$( [Guid]::NewGuid() )" Name="Deny Exe Notepad" UserOrGroupSid="$sidNoCuates" Action="Deny"><Conditions><FilePathCondition Path="*notepad.exe" /></Conditions></FilePathRule>
    <FilePathRule Id="11111111-1111-1111-1111-111111111111" Name="Allow All" UserOrGroupSid="$sidAdmin" Action="Allow"><Conditions><FilePathCondition Path="*" /></Conditions></FilePathRule>
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2" Name="Allow Win" UserOrGroupSid="$sidTodos" Action="Allow"><Conditions><FilePathCondition Path="%WINDIR%\*" /></Conditions></FilePathRule>
  </RuleCollection>
  
  <RuleCollection Type="Appx" EnforcementMode="Enabled">
    <FilePublisherRule Id="$( [Guid]::NewGuid() )" Name="Deny Appx Notepad" UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions>
        <FilePublisherCondition PublisherName="CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US" ProductName="Microsoft.WindowsNotepad" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="$( [Guid]::NewGuid() )" Name="Allow All Apps" UserOrGroupSid="$sidTodos" Action="Allow">
      <Conditions><FilePublisherCondition PublisherName="*" ProductName="*" BinaryName="*"><BinaryVersionRange LowSection="0.0.0.0" HighSection="*" /></FilePublisherCondition></Conditions>
    </FilePublisherRule>
  </RuleCollection>
</AppLockerPolicy>
"@

# --- GUARDADO SIN ERRORES DE CODIFICACIÓN ---
$tempXml = "$env:TEMP\final.xml"
$utf8NoBOM = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tempXml, $xmlPolicy, $utf8NoBOM)

# --- INYECCIÓN A LA GPO ---
$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (!$gpo) { $gpo = New-GPO -Name $GpoName }
$path = "C:\Windows\SYSVOL\domain\Policies\{$($gpo.Id)}\Machine\Microsoft\Windows\AppLocker"
if (!(Test-Path $path)) { New-Item $path -ItemType Directory -Force }
Copy-Item $tempXml "$path\Exe.Applocker" -Force

Invoke-GPUpdate -Force
Write-Host "[OK] GPO Actualizada. Ve al cliente." -ForegroundColor Green