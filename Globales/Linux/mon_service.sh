#!/bin/bash
# ===========================================================================
# Script: Monitor servicios
# Author: Alexander Vega /  Ax2 
# Fecha: 06/02/2026
# Funcion = mon_service()
# Descripcion = Implementa la lógica de "Idempotencia" palabras de herman. Verifica la existencia del servicio, lo instala si falta y lo activa si está apagado.
# Parametros = $1 - Nombre del servicio (Por ejemplo ssh, isc-dhcp-server, mysql...)
# =======================================mon_service() {
#!/bin/bash
# ===========================================================================
# Script: Monitor servicios (Versión Interactiva)
# Author: Alexander Vega / Ax2 
# ===========================================================================

mon_service() {
    local servicio=$1
    echo -e "============================================"
    echo -e "Script monitoreo de servicios\n"
    echo "Monitoreo: $servicio"
if command -v "$servicio" >/dev/null 2>&1 || dpkg -s "$servicio" 2>/dev/null | grep -q "ok installed"; then
        echo "Estado: $servicio ya se encuentra instalado."
        
        read -p "¿Desea REINSTALAR el servicio $servicio? (s/n): " confirm
        if [[ "$confirm" =~ ^[sS]$ ]]; then
            echo "Estado: Reinstalando $servicio..."
            apt-get install --reinstall -y "$servicio" > /dev/null 2>&1
        else
            echo "Estado: Manteniendo versión actual."
        fi
    else
        echo "Estado: $servicio no detectado. Instalando..."
        apt-get update > /dev/null 2>&1
        apt-get install -y "$servicio" > /dev/null 2>&1
        
        if dpkg -s "$servicio" >/dev/null 2>&1; then
            echo "Estado: $servicio instalado correctamente."
        else
            echo "Estado: Error al instalar $servicio."
            return 1
        fi
    fi

    if ! systemctl is-active --quiet "$servicio"; then
        echo "Estado: Activando $servicio..."
        systemctl start "$servicio" > /dev/null 2>&1
    else
        echo "Estado: $servicio ya está activo."
        read -p "¿Desea REINICIAR el servicio para aplicar cambios? (s/n): " restart_conf
        [[ "$restart_conf" =~ ^[sS]$ ]] && systemctl restart "$servicio"
    fi

    echo "Procesamiento de $servicio finalizado."
    echo -e "============================================\n"
}
