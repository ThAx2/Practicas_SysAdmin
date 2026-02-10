#!/bin/bash
# ===========================================================================
# Script: Monitor servicios
# Author: Alexander Vega /  Ax2 
# Fecha: 06/02/2026
# Funcion = mon_service()
# Descripcion = Implementa la lógica de "Idempotencia" palabras de herman. Verifica la existencia del servicio, lo instala si falta y lo activa si está apagado.
# Parametros = $1 - Nombre del servicio (Por ejemplo ssh, isc-dhcp-server, mysql...)
# ===========================================================================	

source ./valid_ip.sh
source ./valid_ip.sh

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

# --- INICIO DEL PROGRAMA ---
clear
mon_service "isc-dhcp-server"

echo -e "\n--- RECOLECCIÓN DE DATOS ---"
read -p "Nombre del Ámbito: " ambito

# Limpiamos y validamos cada campo por separado
red=""
until valid_ip "$red" "" "red"; do 
    read -p "Dirección de Red (ej. 192.168.1.0): " red
done

mask=""
until valid_ip "$mask" "" "mask"; do 
    read -p "Máscara de Subred (ej. 255.255.255.0): " mask
done

start=""
until valid_ip "$start" "$red" "host"; do 
    read -p "Rango Inicial: " start
done

end=""
until valid_ip "$end" "$start" "rango"; do 
    read -p "Rango Final: " end
done

echo -e "\n\e[32m[OK] Configuración validada para $ambito\e[0m"
echo "------------------------------------------------"
echo "RED: $red | MASK: $mask"
echo "RANGO: $start - $end"
echo "------------------------------------------------"
