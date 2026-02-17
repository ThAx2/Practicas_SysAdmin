function Test-IsValidIP {
    param([string]$IP, $IPReferencia = $null, [string]$Tipo = "host")
    if ([string]::IsNullOrWhiteSpace($IP)) { return $false }
    $regex = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    if ($IP -match $regex) {
        $octetos = $IP.Split('.'); $ultimo = [int]$octetos[3]; $primero = [int]$octetos[0]
        if ($primero -eq 127 -or $primero -eq 0 -or $IP -eq "255.255.255.255") { return $false }
        if ($Tipo -eq "mask") {
            $mValidas = @("255.0.0.0", "255.255.0.0", "255.255.255.0")
            if ($mValidas -notcontains $IP) { return $false }
        }
        return $true
    }
    return $false
}
