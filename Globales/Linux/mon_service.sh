#!/bin/bash
# ===========================================================================
# Script: Monitor servicios
# Author: Alexander Vega /  Ax2 
# Fecha: 06/02/2026
# Funcion = mon_service()
# Descripcion = Implementa la lógica de "Idempotencia" palabras de herman. Verifica la existencia del servicio, lo instala si falta y lo activa si está apagado.
# Parametros = $1 - Nombre del servicio (Por ejemplo ssh, isc-dhcp-server, mysql...)
mon_servicer () {
    local servicio=$1
    echo -e "============================================"
    echo -e "Script monitoreo de servicios\n"
    echo "Monitoreo: $servicio"

    local lista_v=$(apt-cache madison "$servicio" | awk '{print $3}' | sort -ur | head -n 2)
    local versiones=($lista_v)

    if [ ${#versiones[@]} -ge 1 ]; then
        echo "Versiones encontradas:"
        echo "1) ${versiones[0]}"
        [ -n "${versiones[1]}" ] && echo "2) ${versiones[1]}" || echo "2) No hay versión anterior disponible"
        
        read -p "Seleccione versión (1/2): " v_opt
        if [[ "$v_opt" == "2" && -n "${versiones[1]}" ]]; then
            v_sel=${versiones[1]}
        else
            v_sel=${versiones[0]}
        fi
    else
        v_sel=""
    fi

    if command -v "$servicio" >/dev/null 2>&1 || dpkg -s "$servicio" 2>/dev/null | grep -q "ok installed"; then
        echo "Estado: $servicio ya se encuentra instalado."
        read -p "¿Desea REINSTALAR $servicio? (s/n): " confirm
        if [[ "$confirm" =~ ^[sS]$ ]]; then
            if [ -n "$v_sel" ]; then
                apt-get install --reinstall -y --allow-downgrades "$servicio=$v_sel" > /dev/null 2>&1
            else
                apt-get install --reinstall -y "$servicio" > /dev/null 2>&1
            fi
        fi
    else
        echo "Estado: $servicio no detectado. Instalando..."
        apt-get update > /dev/null 2>&1
        if [ -n "$v_sel" ]; then
            apt-get install -y --allow-downgrades "$servicio=$v_sel" > /dev/null 2>&1
        else
            apt-get install -y "$servicio" > /dev/null 2>&1
        fi
        
        if ! dpkg -s "$servicio" >/dev/null 2>&1; then
            echo "Estado: Error al instalar $servicio."
            return 1
        fi
    fi

    if [ "$servicio" == "nginx" ]; then
        sed -i 's/# server_tokens off;/server_tokens off;/g' /etc/nginx/nginx.conf
    elif [ "$servicio" == "apache2" ]; then
        sed -i '/ServerTokens/d' /etc/apache2/conf-available/security.conf
        echo "ServerTokens Prod" >> /etc/apache2/conf-available/security.conf
    fi

    if ! systemctl is-active --quiet "$servicio"; then
        systemctl start "$servicio" > /dev/null 2>&1
    else
        echo "Estado: $servicio ya está activo."
        read -p "¿Desea REINICIAR el servicio? (s/n): " restart_conf
        [[ "$restart_conf" =~ ^[sS]$ ]] && systemctl restart "$servicio"
    fi

    echo "Procesamiento de $servicio finalizado."
    echo -e "============================================\n"
}
