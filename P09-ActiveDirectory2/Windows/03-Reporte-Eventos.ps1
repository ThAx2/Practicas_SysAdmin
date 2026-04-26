
Write-Host "--- Generando Reporte de Accesos Denegados ---" -ForegroundColor Cyan

$PathReporte = "$env:USERPROFILE\Desktop\Reporte_Accesos_Fallidos.txt"


try {
    Write-Host "[...] Consultando el Visor de Eventos (Security Logs)..." -ForegroundColor Yellow
    
    $Eventos = Get-WinEvent -FilterHashtable @{LogName='Security';ID=4625} -MaxEvents 10 -ErrorAction Stop | 
               Select-Object TimeCreated, 
                             @{Name='Usuario';Expression={$_.Properties[5].Value}}, 
                             @{Name='IP_Origen';Expression={$_.Properties[18].Value}},
                             @{Name='Estado';Expression={"Acceso Denegado / Fallo de Credenciales"}}

    if ($Eventos) {
    
        $Cabecera = "=========================================================`r`n"
        $Cabecera += "   REPORTE DE AUDITORIA - INTENTOS DE ACCESO FALLIDOS    `r`n"
        $Cabecera += "   Generado el: $(Get-Date)                               `r`n"
        $Cabecera += "=========================================================`r`n"
        
        $Cabecera | Out-File $PathReporte
        $Eventos | Format-Table -AutoSize | Out-File $PathReporte -Append
        
        Write-Host "[OK] Reporte generado exitosamente en: $PathReporte" -ForegroundColor Green
      
     
    } else {
        Write-Host "[!] No se encontraron eventos de acceso fallido (ID 4625)." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[!] Error al consultar los logs: Puede que no existan eventos registrados aun." -ForegroundColor Red
}

Write-Host "`nProceso Finalizado." -ForegroundColor Cyan
Pause