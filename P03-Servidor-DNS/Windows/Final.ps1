# --- 1. PREPARACIÓN Y CARGA DE MÓDULOS ---
# Esto evita el error rojo de "command not found"
Import-Module DhcpServer -ErrorAction SilentlyContinue
Import-Module DnsServer -ErrorAction SilentlyContinue

function Menu-DNS {
    do {
        Clear-Host
        Write-Host "=== GESTIÓN DNS: DIRECTA + WWW + INVERSA ===" -ForegroundColor Yellow
        Write-Host " 1) ALTA Dominio (Crea todo automáticamente)"
        Write-Host " 2) BAJA Dominio"
        Write-Host " 3) CONSULTA de Zonas"
        Write-Host " 4) Volver"
        $opt = Read-Host " Opción"

        switch ($opt) {
            "1" {
                $zona = Read-Host " Dominio (ej: lol.com)"
                $ip = Read-Host " IP Destino (ej: 192.168.100.30)"
                
                # Crear Zona Directa si no existe
                if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns"
                }

                # Crear Zona Inversa (Corrige el error de 'No response from server')
                $octetos = $ip.Split('.')
                $redInv = "$($octetos[2]).$($octetos[1]).$($octetos[0]).in-addr.arpa"
                if (-not (Get-DnsServerZone -Name $redInv -ErrorAction SilentlyContinue)) {
                    Add-DnsServerPrimaryZone -NetworkId "$($octetos[0]).$($octetos[1]).$($octetos[2]).0/24" -ReplicationScope "Forest"
                }

                # Registros A (Raíz y WWW) - Sin parámetros extra que den error
                Add-DnsServerResourceRecordA -Name "@" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecordA -Name "www" -ZoneName $zona -IPv4Address $ip -ErrorAction SilentlyContinue
                
                # Registro PTR (Reversa)
                Add-DnsServerResourceRecordPointer -Name $octetos[3] -ZoneName $redInv -PtrDomainName "$zona." -ErrorAction SilentlyContinue
                
                Write-Host " [OK] Dominio y Reversa configurados." -ForegroundColor Green
                Pause
            }
            "2" {
                $z = Read-Host " Nombre de la zona a borrar"
                Remove-DnsServerZone -Name $z -Force
                Pause
            }
            "3" {
                Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | ft ZoneName, ZoneStatus
                Pause
            }
        }
    } while ($opt -ne "4")
}

function Configurar-DHCP {
    # Limpiar ámbitos antiguos (como el 103.5.93.0) para evitar conflictos
    Write-Host " [*] Purgando ámbitos antiguos..." -ForegroundColor Cyan
    Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue

    $ip_srv = Read-Host " IP Estática para el Servidor (Ethernet 2)"
    $ip_fin = Read-Host " IP Final del Rango DHCP"
    
    # Configurar la tarjeta interna (Ethernet 2)
    New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress $ip_srv -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    
    # Crear el ámbito nuevo
    $red = $ip_srv.SubString(0, $ip_srv.LastIndexOf('.')) + ".0"
    $inicio = $ip_srv.SubString(0, $ip_srv.LastIndexOf('.')) + "." + ([int]$ip_srv.Split('.')[3] + 1)
    
    Add-DhcpServerv4Scope -Name "Red_Interna" -StartRange $inicio -EndRange $ip_fin -SubnetMask 255.255.255.0 -State Active
    Set-DhcpServerv4OptionValue -ScopeId $red -OptionId 6 -Value $ip_srv # DNS para clientes
    
    Write-Host " [OK] DHCP configurado y limpio en Ethernet 2." -ForegroundColor Green
    Pause
}

# --- MENÚ PRINCIPAL ---
do {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   GESTOR DE SERVICIOS WINDOWS 2022     " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " 1) DHCP (Limpieza y Configuración)"
    Write-Host " 2) DNS (Zonas Directas, WWW e Inversas)"
    Write-Host " 3) Salir"
    $main = Read-Host " Selección"

    if ($main -eq "1") { Configurar-DHCP }
    if ($main -eq "2") { Menu-DNS }
} while ($main -ne "3")
