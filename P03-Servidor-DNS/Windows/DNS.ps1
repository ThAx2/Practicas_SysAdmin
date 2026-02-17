. "$PSScriptRoot\Validacion_IP.ps1"
. "$PSScriptRoot\Mon_Service.ps1"
. "$PSScriptRoot\DHCP.ps1"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " [!] ERROR: EJECUTAR COMO ADMINISTRADOR." -ForegroundColor Red
    Pause; exit
}

function Menu-DNS {
    $IP_SRV = (Get-NetIPAddress -InterfaceAlias "Ethernet" -AddressFamily IPv4).IPAddress | Select-Object -First 1
    do {
        Clear-Host
        Write-Host "--- GESTIÓN DNS (ABC) ---" -ForegroundColor Cyan
        Write-Host " 1) Consultar Dominios`n 2) Alta de Dominio`n 3) Baja de Dominio`n 4) Volver"
        $optDns = Read-Host "`n Selecciona una opcion"

        switch ($optDns) {
            "1" {
                Get-DnsServerZone | Where-Object { $_.IsReverseLookupZone -eq $false -and $_.ZoneName -ne "TrustAnchors" } | Select-Object ZoneName | Format-Table
                Pause
            }
            "2" {
                $dom = Read-Host " Dominio"
                $ip_d = Read-Host " IP Destino (Enter para $IP_SRV)"
                $final = if ([string]::IsNullOrWhiteSpace($ip_d)) { $IP_SRV } else { $ip_d }
                Add-DnsServerPrimaryZone -Name $dom -ZoneFile "$dom.dns" -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name "@" -ZoneName $dom -IPv4Address $final -Force
                Write-Host "[OK] $dom -> $final" -ForegroundColor Green
                Pause
            }
            "3" {
                $borrar = Read-Host " Dominio a borrar"
                Remove-DnsServerZone -Name $borrar -Force -ErrorAction SilentlyContinue
                Write-Host "[OK] Eliminado." -ForegroundColor Green
                Pause
            }
        }
    } while ($optDns -ne "4")
}

do {
    Clear-Host
    Write-Host "=== ORQUESTADOR WINDOWSITO ===" -ForegroundColor Yellow
    Write-Host " 1) Configurar DHCP`n 2) Gestionar DNS`n 3) Estatus`n 4) Salir"
    $opcion = Read-Host "`n Selecciona"

    switch ($opcion) {
        "1" { Configurar-DHCP -interface "Ethernet" }
        "2" { Check-Service -RoleName "DNS" -ServiceName "DNS"; Menu-DNS }
        "3" { Get-Service DHCPServer, DNS | Select Name, Status; Pause }
    }
} while ($opcion -ne "4")
