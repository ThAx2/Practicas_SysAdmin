if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " [!] ERROR: Debes ejecutar este script como ADMINISTRADOR." -ForegroundColor Red
    Pause
    exit
}

do {
    Clear-Host
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host "        DNS          " -ForegroundColor Yellow
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host " 1) Configurar servidor DHCP"
    Write-Host " 2) Configurar servidor DNS"
    Write-Host " 3) Configuracion de Red Manual"
    Write-Host " 4) Estatus de servicios"
    Write-Host " 5) Salir"

    $opcion = Read-Host "`n Selecciona una opcion"
    
    switch ($opcion) {
        "1" {
            Check-Service -ServiceName "DHCPServer"
            $interface = Read-Host " Nombre de la Interfaz (ej. Ethernet)"
            
            do { $mask = Read-Host " Mascara de Subred" } until (Test-IsValidIP -IP $mask -Tipo "mask")
            do { $ip_i = Read-Host " IP Inicial Sera la IP Servidor " } until (Test-IsValidIP -IP $ip_i -Tipo "host")
            
            $octs = $ip_i.Split('.')
            $base_red = "$($octs[0..2] -join '.').0"
            
            do { $ip_f = Read-Host " Rango Final (>= $ip_i)" } until (Test-IsValidIP -IP $ip_f -IPReferencia $ip_i -Tipo "rango")
            
            $scopeName = Read-Host " Nombre para el Ambito"
	    do {
		$lease_seconds = Read-Host " Tiempo de concesion"
	    } while ($lease_seconds -notmatch '^[0-9]+$' -or [int]$lease_seconds -le 0) 
            $gw = Read-Host " Puerta de enlace (Enter para omitir)"
            $dns = Read-Host " Servidor DNS (Enter para omitir)"

            # Lógica de Desplazamiento +1
            $rango_real_inicio = "$($octs[0..2] -join '.').$([int]$octs[3] + 1)"
            $octsF = $ip_f.Split('.')
            $rango_real_final = "$($octsF[0..2] -join '.').$([int]$octsF[3] + 1)"

            Write-Host "`n [+] Configurando IP Fija $ip_i..." -ForegroundColor Cyan
            Remove-NetIPAddress -InterfaceAlias $interface -Confirm:$false -ErrorAction SilentlyContinue
            New-NetIPAddress -InterfaceAlias $interface -IPAddress $ip_i -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null

            Write-Host " [+] Creando Ambito DHCP en $base_red..." -ForegroundColor Cyan
            Remove-DhcpServerv4Scope -ScopeId $base_red -Force -ErrorAction SilentlyContinue
            Add-DhcpServerv4Scope -Name $scopeName -StartRange $rango_real_inicio -EndRange $rango_real_final -SubnetMask $mask -LeaseDuration (New-TimeSpan -Seconds $lease_seconds) -State Active
            
            if ($gw) { Set-DhcpServerv4OptionValue -ScopeId $base_red -OptionId 3 -Value $gw }
            if ($dns) { Set-DhcpServerv4OptionValue -ScopeId $base_red -OptionId 6 -Value $dns }

            Write-Host "`n [OK] Servidor en $ip_i | DHCP: $rango_real_inicio - $rango_real_final" -ForegroundColor Green
            Pause
        }
        "2" {
            Write-Host "`n --- AMBITOS ---" -ForegroundColor Cyan
            Get-DhcpServerv4Scope | Select-Object ScopeId, Name, StartRange, EndRange, State | Format-Table -AutoSize
            Write-Host " --- CONCESIONES ---" -ForegroundColor Cyan
            Get-DhcpServerv4Scope | ForEach-Object { Get-DhcpServerv4Lease -ScopeId $_.ScopeId } | Format-Table -AutoSize
            Pause
        }
        "3" { Restart-Service DHCPServer; Write-Host " [+] Servicio reiniciado."; Pause }
    }
} while ($opcion -ne "4")
