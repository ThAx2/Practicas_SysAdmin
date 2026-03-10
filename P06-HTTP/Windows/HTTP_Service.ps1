function Detener-Competencia {
    param($actual)
    Write-Host "[*] Deteniendo otros servidores para evitar conflictos..." -ForegroundColor Cyan
    $servicios = @{
        "nginx"  = "nginx"
        "apache" = "Apache"
        "tomcat" = "Tomcat9"
    }
    foreach ($key in $servicios.Keys) {
        if ($key -ne $actual) {
            $svc = Get-Service -Name $servicios[$key] -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq "Running") {
                Stop-Service $svc.Name -Force -ErrorAction SilentlyContinue
                Write-Host "  [->] Detenido: $($svc.Name)" -ForegroundColor Yellow
            }
        }
    }
}

function Crear-IndexHTML {
    param($servicio, $puerto)

    switch -Regex ($servicio) {
        "nginx" {
            $htmlPath = "C:\tools\nginx\html\index.html"
            if (Test-Path (Split-Path $htmlPath)) {
                $html = @"
<!DOCTYPE html>
<html><head><meta charset='UTF-8'><title>NGINX - Puerto $puerto</title>
<style>body{font-family:Arial;background:#1a1a2e;color:#eee;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;}
.box{text-align:center;padding:40px;background:#16213e;border-radius:12px;border:2px solid #0f9b58;}
h1{color:#0f9b58;}p{color:#aaa;}</style></head>
<body><div class='box'><h1>&#9989; NGINX Activo</h1><p>Servidor desplegado en puerto <strong>$puerto</strong></p></div></body></html>
"@
                [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.UTF8Encoding]::new($false))
                Write-Host "  [OK] index.html creado en $htmlPath" -ForegroundColor Green
            }
        }
        "apache|httpd" {
            # Buscar htdocs de Apache en rutas conocidas
            $posibles = @(
                "C:\tools\Apache24\htdocs",
                "C:\Apache24\htdocs",
                "$env:APPDATA\Apache24\htdocs",
                "$env:APPDATA\Apache2.4\htdocs"
            )
            $htdocs = $posibles | Where-Object { Test-Path $_ } | Select-Object -First 1
            if (-not $htdocs) {
                # Búsqueda más amplia
                $htdocs = (Get-ChildItem "$env:APPDATA\Apache*", "C:\tools\Apache*" -ErrorAction SilentlyContinue |
                           ForEach-Object { "$($_.FullName)\htdocs" } |
                           Where-Object { Test-Path $_ } |
                           Select-Object -First 1)
            }
            if ($htdocs) {
                $html = @"
<!DOCTYPE html>
<html><head><meta charset='UTF-8'><title>APACHE - Puerto $puerto</title>
<style>body{font-family:Arial;background:#1a1a2e;color:#eee;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;}
.box{text-align:center;padding:40px;background:#16213e;border-radius:12px;border:2px solid #d4380d;}
h1{color:#d4380d;}p{color:#aaa;}</style></head>
<body><div class='box'><h1>&#9989; APACHE Activo</h1><p>Servidor desplegado en puerto <strong>$puerto</strong></p></div></body></html>
"@
                [System.IO.File]::WriteAllText("$htdocs\index.html", $html, [System.Text.UTF8Encoding]::new($false))
                Write-Host "  [OK] index.html creado en $htdocs" -ForegroundColor Green
            } else {
                Write-Host "  [!] No se encontró htdocs de Apache." -ForegroundColor Yellow
            }
        }
        "tomcat" {
            # CATALINA_BASE primero, luego CATALINA_HOME
            $webapps = @(
                "C:\ProgramData\Tomcat9\webapps\ROOT",
                "C:\ProgramData\chocolatey\lib\Tomcat\tools\apache-tomcat-9.0.115\webapps\ROOT"
            ) | Where-Object { Test-Path $_ } | Select-Object -First 1

            if (-not $webapps) {
                $webapps = "C:\ProgramData\Tomcat9\webapps\ROOT"
                New-Item -ItemType Directory -Path $webapps -Force | Out-Null
            }
            $html = @"
<!DOCTYPE html>
<html><head><meta charset='UTF-8'><title>TOMCAT - Puerto $puerto</title>
<style>body{font-family:Arial;background:#1a1a2e;color:#eee;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;}
.box{text-align:center;padding:40px;background:#16213e;border-radius:12px;border:2px solid #f5a623;}
h1{color:#f5a623;}p{color:#aaa;}</style></head>
<body><div class='box'><h1>&#9989; TOMCAT Activo</h1><p>Servidor desplegado en puerto <strong>$puerto</strong></p></div></body></html>
"@
            [System.IO.File]::WriteAllText("$webapps\index.html", $html, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  [OK] index.html creado en $webapps" -ForegroundColor Green
        }
    }
}

function aplicar_puerto_http {
    param($servicio)

    $p = if ($global:PUERTO_ACTUAL) { [int]$global:PUERTO_ACTUAL } else { 80 }

    # Detener competencia antes de configurar
    Detener-Competencia $servicio

    # Deshabilitar firewall y abrir puerto
    Write-Host "[*] Configurando firewall..." -ForegroundColor Cyan
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False -ErrorAction SilentlyContinue
    $ruleName = "HTTP-Puerto-$p"
    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  [OK] Firewall desactivado y puerto $p abierto" -ForegroundColor Green

    # Verificar puerto ocupado
    Write-Host "[*] Verificando puerto $p..." -ForegroundColor Cyan
    $conexiones = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if ($conexiones) {
        $pids = $conexiones | Select-Object -ExpandProperty OwningProcess -Unique
        Write-Host "[!] Puerto $p ocupado por PID(s): $($pids -join ', '). Limpiando..." -ForegroundColor Yellow
        foreach ($pid in $pids) {
            Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
    }

    # Buscar servicio instalado
    $nombreServicio = switch ($servicio) {
        "nginx"  { "nginx" }
        "apache" { "Apache" }
        "tomcat" { "Tomcat9" }
    }
    $s = Get-Service -Name $nombreServicio -ErrorAction SilentlyContinue
    if (-not $s) {
        Write-Host "[!] Servicio '$nombreServicio' no encontrado. ¿Está instalado?" -ForegroundColor Red
        Pause; return
    }

    Write-Host "[*] Configurando $($s.Name) en puerto $p..." -ForegroundColor Cyan

    switch ($servicio) {
        "nginx" {
            $confPath = "C:\tools\nginx\conf\nginx.conf"
            if (!(Test-Path $confPath)) {
                Write-Host "[!] No se encontró $confPath" -ForegroundColor Red; Pause; return
            }
            # Reemplazar solo el listen principal (igual que el sed del bash)
            $conf = Get-Content $confPath
            $dentroServer = $false; $yaReemplazado = $false
            $conf = $conf | ForEach-Object {
                if ($_ -match "^\s*server\s*\{") { $dentroServer = $true }
                if ($dentroServer -and !$yaReemplazado -and $_ -match "^\s*listen\s+\d+") {
                    $yaReemplazado = $true
                    $_ -replace "listen\s+\d+", "listen       $p"
                } else { $_ }
            }
            # FIX BOM: nginx no soporta UTF-8 con BOM, usar WriteAllLines
            [System.IO.File]::WriteAllLines($confPath, $conf, [System.Text.UTF8Encoding]::new($false))
        }
        "apache" {
            # Buscar httpd.conf igual que el sed del bash sobre ports.conf
            $posiblesConf = @(
                "C:\tools\Apache24\conf\httpd.conf",
                "C:\Apache24\conf\httpd.conf",
                "$env:APPDATA\Apache24\conf\httpd.conf",
                "$env:APPDATA\Apache2.4\conf\httpd.conf"
            )
            $confPath = $posiblesConf | Where-Object { Test-Path $_ } | Select-Object -First 1
            if (-not $confPath) {
                $confPath = (Get-ChildItem "$env:APPDATA\Apache*", "C:\tools\Apache*" -ErrorAction SilentlyContinue |
                             ForEach-Object { "$($_.FullName)\conf\httpd.conf" } |
                             Where-Object { Test-Path $_ } | Select-Object -First 1)
            }
            if (-not $confPath) {
                Write-Host "[!] No se encontró httpd.conf de Apache." -ForegroundColor Red; Pause; return
            }
            $contenido = (Get-Content $confPath) -replace 'Listen \d+', "Listen $p"
            [System.IO.File]::WriteAllLines($confPath, $contenido, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  [->] httpd.conf actualizado: Listen $p" -ForegroundColor Cyan
        }
        "tomcat" {
            # Buscar server.xml en CATALINA_BASE primero (igual lógica que bash con /etc/tomcat10/server.xml)
            $posiblesXml = @(
                "C:\ProgramData\Tomcat9\conf\server.xml",
                "C:\ProgramData\chocolatey\lib\Tomcat\tools\apache-tomcat-9.0.115\conf\server.xml"
            )
            $confPath = $posiblesXml | Where-Object { Test-Path $_ } | Select-Object -First 1
            if (-not $confPath) {
                Write-Host "[!] No se encontró server.xml de Tomcat." -ForegroundColor Red; Pause; return
            }
            # Mismo reemplazo que el bash: Connector port="xxxx"
            $xmlContenido = (Get-Content $confPath) -replace 'Connector port="[0-9]*"', "Connector port=`"$p`""
            [System.IO.File]::WriteAllLines($confPath, $xmlContenido, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  [->] server.xml actualizado: port=$p" -ForegroundColor Cyan
        }
    }

    # Crear index.html personalizado (lógica equivalente al bash)
    Crear-IndexHTML $servicio $p

    # Reiniciar y verificar (igual que systemctl restart + is-active del bash)
    Write-Host "[*] Reiniciando $($s.Name)..." -ForegroundColor Cyan
    Restart-Service $s.Name -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "[OK] $($s.Name) ONLINE en http://localhost:$p" -ForegroundColor Green
        try { Start-Process "http://localhost:$p" -ErrorAction Stop }
        catch { Write-Host "[!] Abra manualmente http://localhost:$p" -ForegroundColor Yellow }
    } else {
        Write-Host "[!] Error al iniciar $($s.Name) en puerto $p. Revisa los logs." -ForegroundColor Red
    }

    Pause
}

function Menu-HTTP {
    while ($true) {
        Clear-Host
        Monitor-Servicios
        $mostrarPuerto = if ($global:PUERTO_ACTUAL) { $global:PUERTO_ACTUAL } else { "80 (Default)" }
        Write-Host "================================================" -ForegroundColor Gray
        Write-Host "              MODULO HTTP                       " -ForegroundColor Cyan
        Write-Host "  Puerto configurado para despliegue: $mostrarPuerto" -ForegroundColor Yellow
        Write-Host "================================================" -ForegroundColor Gray
        Write-Host " 1) Instalar Nginx    | 2) Instalar Apache  | 3) Instalar Tomcat"
        Write-Host " 4) Desplegar Nginx   | 5) Desplegar Apache | 6) Desplegar Tomcat"
        Write-Host " 7) Configurar Puerto | 8) Volver"
        Write-Host "------------------------------------------------" -ForegroundColor Gray
        $op = Read-Host "Seleccione"

        switch ($op) {
            "1" { Comprobar-Instalacion "nginx"  $true }
            "2" { Comprobar-Instalacion "apache" $true }
            "3" { Comprobar-Instalacion "tomcat" $true }
            "4" { aplicar_puerto_http "nginx" }
            "5" { aplicar_puerto_http "apache" }
            "6" { aplicar_puerto_http "tomcat" }
            "7" { if (Get-Command Validar-Puerto -ErrorAction SilentlyContinue) { Validar-Puerto } }
            "8" { return }
            default { Write-Host "[!] Opción no válida. Elige entre 1 y 8." -ForegroundColor Yellow; Pause }
        }
    }
}
