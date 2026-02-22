function Menu-DNS {
    Comprobar-Instalacion -Feature "DNS"
    do {
        Clear-Host
        Monitor-Servicios
        Write-Host "=== GESTION DNS ===" -ForegroundColor Yellow
        Write-Host "1) ALTA (Directa + Inversa)"
        Write-Host "2) BAJA (Directa + Inversa)"
        Write-Host "3) CONSULTA TOTAL"
        Write-Host "4) Volver"
        $op = Read-Host "Opcion"

        switch ($op) {
            "1" {
                $zona = Read-Host "Nombre Dominio"
                if (-not $Global:InterfazActiva) { $Global:InterfazActiva = Read-Host "Nombre Interfaz" }
                $ip_def = (Get-NetIPAddress -InterfaceAlias $Global:InterfazActiva -AddressFamily IPv4).IPAddress[0]
                $ip = Read-Host "IP Destino (Enter para $ip_def)"
                if (-not $ip) { $ip = $ip_def }

                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns" -ErrorAction SilentlyContinue
                }
                Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                
                $oct = $ip.Split('.'); $inv = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
                if (-not (Get-DnsServerZone -Name $inv -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $inv -ZoneFile "$inv.dns" -ErrorAction SilentlyContinue
                }
                Add-DnsServerResourceRecordPtr -Name $oct[3] -ZoneName $inv -PtrDomainName "$zona." -ErrorAction SilentlyContinue
                Write-Host "[OK] Alta completada." -ForegroundColor Green; Pause
            }
            "2" {
                $zona = Read-Host "Dominio a borrar"
                $rec = Get-DnsServerResourceRecord -ZoneName $zona -Name "@" -RRType A -ErrorAction SilentlyContinue
                $ip_z = if ($rec) { $rec.RecordData.IPv4Address.IPAddressToString } else { $null }
                
                Remove-DnsServerZone -Name $zona -Force -ErrorAction SilentlyContinue
                if ($ip_z) {
                    $oct = $ip_z.Split('.'); $inv = "$($oct[2]).$($oct[1]).$($oct[0]).in-addr.arpa"
                    Remove-DnsServerZone -Name $inv -Force -ErrorAction SilentlyContinue
                    Write-Host "[!] Borrada zona directa e inversa ($inv)." -ForegroundColor Yellow
                }
                Pause
            }
            "3" {
                Get-DnsServerZone | ForEach-Object { 
                    Write-Host "`n>> $($_.ZoneName)" -ForegroundColor Magenta
                    Get-DnsServerResourceRecord -ZoneName $_.ZoneName | ft HostName,RecordType,RecordData -AutoSize
                }
                Pause
            }
        }
    } while ($op -ne "4")
}
