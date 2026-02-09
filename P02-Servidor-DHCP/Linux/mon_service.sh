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
    local servicio=$1
    echo -e "============================================"
    echo -e "Script monitoreo de servicios\n"
    echo "Monitoreando servicio: $servicio"
  until systemctl is-active --quiet $servicio
    do
        if systemctl list-unit-files --type=service | grep -q $servicio; then
            echo "El servicio $servicio está desactivado. Intentando prender..."
            systemctl start $servicio 2>/dev/null
            sleep 1
            
            if [ $? -ne 0 ]; then
                echo "Aviso: El servicio requiere configuración previa para iniciar. Continuando..."
                break
            fi
        else
            echo "El servicio $servicio no se encuentra. Instalando..."
            apt update > /dev/null 2>&1
            apt install -y $servicio > /dev/null 2>&1
            echo "Instalación terminada."
            break 
        fi
    done
    echo "Estado: El servicio $servicio ha sido procesado.";
}
