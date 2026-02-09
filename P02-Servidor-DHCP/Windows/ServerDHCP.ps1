# --- Configuración Inicial ---
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "   CONFIGURACIÓN DE SERVICIO DHCP v4   " -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# --- Petición de Datos al Usuario ---
$interface = Read-Host "Nombre de la interfaz (ej. Ethernet 2)"
$ip_fija = Read-Host "IP fija para este servidor (ej. 192.168.100.1)"
$mask_bits = Read-Host "Prefijo de red (ej. 24)"
$scopeName = Read-Host "Nombre del Ámbito (Scope)"
$startIP = Read-Host "IP inicial del rango"
$endIP = Read-Host "IP final del rango"
$dns = Read-Host "Servidor DNS (ej. 8.8.8.8)"

# --- 1. Configurar IP Fija en la Tarjeta ---
Write-Host "`n[1/5] Configurando IP fija $ip_fija..." -ForegroundColor Cyan
New-NetIPAddress -InterfaceAlias $interface -IPAddress $ip_fija -PrefixLength $mask_bits -ErrorAction SilentlyContinue

# --- 2. Instalar el Rol DHCP ---
Write-Host "[2/5] Instalando Rol DHCP..." -ForegroundColor Cyan
Install-WindowsFeature DHCP -IncludeManagementTools

# --- 3. Crear el Ámbito ---
Write-Host "[3/5] Creando Ámbito: $scopeName..." -ForegroundColor Cyan
# Convertimos el prefijo (24) a máscara completa (255.255.255.0) para el comando
$fullMask = "255.255.255.0" 
Add-DhcpServerv4Scope -Name $scopeName -StartRange $startIP -EndRange $endIP -SubnetMask $fullMask -State Active

# --- 4. Configurar Opciones (Gateway y DNS) ---
Write-Host "[4/5] Configurando opciones del ámbito..." -ForegroundColor Cyan
Set-DhcpServerv4OptionValue -OptionId 3 -Value $ip_fija   # El servidor es el Gateway
Set-DhcpServerv4OptionValue -OptionId 6 -Value $dns      # DNS

# --- 5. Seguridad y Firewall ---
Write-Host "[5/5] Autorizando y abriendo Firewall..." -ForegroundColor Cyan
Add-DhcpServerInDC -IPAddress $ip_fija -ErrorAction SilentlyContinue
Set-NetFirewallRule -DisplayName "DHCP Server (UDP-In)" -Enabled True
netsh advfirewall set allprofiles state off

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " SERVIDOR DHCP CONFIGURADO CORRECTAMENTE " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
