#!/bin/bash
# ===========================================================================
# Script: Monitor servicios
# Author: Alexander Vega /  Ax2 
# Fecha: 06/02/2026
# Funcion = mon_service()
# Descripcion = Implementa la lógica de "Idempotencia" palabras de herman. Verifica la existencia del servicio, lo instala si falta y lo activa si está apagado.
# Parametros = $1 - Nombre del servicio (Por ejemplo ssh, isc-dhcp-server, mysql...)
# ===========================================================================	

source ./Validar_Red.sh
mon_service() {

    local servicio=$1
    echo -e "============================================"
    echo -e "Script monitoreo de servicios\n"
    echo "Monitoreando servicio: $servicio"

    until systemctl is-active --quiet $servicio; do
        if dpkg -l | grep -q $servicio; then
            echo "El servicio $servicio esta desactivado. Intentando prender..."
            systemctl start $servicio 2>/dev/null
            sleep 1
            if ! systemctl is-active --quiet $servicio; then
                echo "El servicio requiere configuración para arrancar. Continuando..."
                break
            fi
        else
            echo "El servicio $servicio no se encuentra. Instalando..."
            apt-get update > /dev/null 2>&1
            apt-get install -y $servicio > /dev/null 2>&1
            systemctl start $servicio > /dev/null 2>&1
            break 
        fi
    done
    echo "Estado actual: El servicio $servicio ha sido procesado."
}

