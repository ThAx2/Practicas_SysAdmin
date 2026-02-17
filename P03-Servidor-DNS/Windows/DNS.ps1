. "$PSScriptRoot\Validacion_IP.ps1"
. "$PSScriptRoot\Mon_Service.ps1"
. "$PSScriptRoot\DHCP.ps1"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "EJECUTAR COMO ADMINISTRADOR" -ForegroundColor Red; exit
}

function Menu-DNS {
    $IP_S = (Get-NetIPAddress -InterfaceAlias "Ethernet" -AddressFamily IPv4).IPAddress | Select-Object -First 1
    Write-Host "1) Consultar`n2) Alta`n3) Baja`n4) Volver"
    $op = Read-Host "Opcion"
    switch ($op) {
        "1" { Get-DnsServerZone | Where-Object IsReverseLookupZone -eq $false | Select ZoneName; Pause }
        "2" {
            $dom = Read-Host "Dominio"
            $ip_d = Read-Host "IP Destino (Enter para $IP_S)"
            $fin = if ([string]::IsNullOrWhiteSpace($ip_d)) { $IP_S } else { $ip_d }
            Add-DnsServerPrimaryZone -Name $dom -ZoneFile "$dom.dns" -ErrorAction SilentlyContinue
            Add-DnsServerResourceRecordA -Name "@" -ZoneName $dom -IPv4Address $fin -Force
            Write-Host "Alta OK" -ForegroundColor Green; Pause
        }
        "3" {
            $b = Read-Host "Dominio a borrar"
            Remove-DnsServerZone -Name $b -Force -ErrorAction SilentlyContinue
            Write-Host "Baja OK" -ForegroundColor Green; Pause
        }
    }
}

while ($true) {
    Clear-Host
    Write-Host "=== ORQUESTADOR ==="
    Write-Host "1) DHCP`n2) DNS`n3) Estatus`n4) Salir"
    $m = Read-Host "Opcion"
    if ($m -eq "1") { Configurar-DHCP -interface "Ethernet" }
    elseif ($m -eq "2") { Check-Service -RoleName "DNS" -ServiceName "DNS"; Menu-DNS }
    elseif ($m -eq "3") { Get-Service DHCPServer, DNS | Select Name, Status; Pause }
    elseif ($m -eq "4") { break }
}
