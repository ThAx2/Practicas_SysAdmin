#!/bin/bash
# ===========================================================================
# Script: Monitor servicios
# Author: Alexander Vega /  Ax2 
# Fecha: 06/02/2026
# Funcion = mon_service()
# Descripcion = Implementa la lógica de "Idempotencia" palabras de herman. Verifica la existencia del servicio, lo instala si falta y lo activa si está apagado.
# Parametros = $1 - Nombre del servicio (Por ejemplo ssh, isc-dhcp-server, mysql...)
# ===========================================================================	

#source ./Validar_Red.sh
mon_service() {
    local servicio=$1
    echo -e "============================================"
    echo -e "Script monitoreo de servicios\n"
    echo "Monitoreando servicio: $servicio"

    if dpkg -l | grep -q "$servicio"; then
        echo "El servicio $servicio ya se encuentra instalado."
        read -p "¿Deseas reinstalarlo para asegurar una configuración limpia? (s/n): " confirm
        
        if [[ $confirm =~ ^[Ss]$ ]]; then
            echo "[*] Realizando limpieza profunda (purge)..."
            apt-get purge -y "$servicio" > /dev/null 2>&1
            apt-get autoremove -y > /dev/null 2>&1
            
            echo "[*] Instalando de nuevo $servicio..."
            apt-get update > /dev/null 2>&1
            apt-get install -y "$servicio" > /dev/null 2>&1
        fi
    else
        echo "El servicio $servicio no se detecta. Instalando..."
        apt-get update > /dev/null 2>&1
        apt-get install -y "$servicio" > /dev/null 2>&1
    fi

    if ! systemctl is-active --quiet "$servicio"; then
        echo "Intentando activar $servicio..."
        systemctl start "$servicio" 2>/dev/null
        sleep 1
        
        if ! systemctl is-active --quiet "$servicio"; then
            echo "Nota: El servicio está instalado pero requiere que el script Main.sh termine la configuración para arrancar."
        fi
    else
        echo "El servicio $servicio ya está activo y respondiendo."
    fi

    echo "Estado actual: Procesamiento de $servicio finalizado."
    echo -e "============================================\n"
}

