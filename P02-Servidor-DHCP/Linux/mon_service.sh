#!/bin/bash
# ===========================================================================
# Script: Monitor servicios
# Author: Alexander Vega /  Ax2 
# Fecha: 06/02/2026
# Funcion = mon_service()
# Descripcion = Implementa la lógica de "Idempotencia" palabras de herman. Verifica la existencia del servicio, lo instala si falta y lo activa si está apagado.
# Parametros = $1 - Nombre del servicio (Por ejemplo ssh, isc-dhcp-server, mysql...)
# ===========================================================================	
mon_service(){
local servicio=$1;
echo -e "============================================"
echo -e "Script monitoreo de servicios";

echo " ";
echo "Monitoreando servicio: $servicio";
until systemctl is-active --quiet $servicio
do
    if systemctl is-active --quiet $servicio; then
        echo "EL servicio se encuentra activo"
    elif systemctl list-units --type=service | grep -q $servicio; then
        echo "EL servicio $servicio esta desactivado."
        echo "Prendiendo servicio..."
        systemctl start $servicio
        sleep 1    
    else
        echo "EL servicio $servicio no se encuentra."
        sudo apt update > /dev/null 2>&1
        sudo apt install -y $servicio > /dev/null 2>&1
        break 
    fi
done
echo "El servicio $servicio está activo";
}


