#!/bin/bash

cargar_dependencias() {
    # 1. Definición de Rutas
    export interfaz=""
    export FTP_IP=""  # Variable crítica para el Orquestador
    
    local DIR_GLOBALES=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local RAIZ=$(readlink -f "$DIR_GLOBALES/../..")
    
    # 2. Carga de Scripts Base
    if [ -f "$DIR_GLOBALES/Validar_Red.sh" ] && [ -f "$DIR_GLOBALES/mon_service.sh" ]; then
        source "$DIR_GLOBALES/Validar_Red.sh"
        source "$DIR_GLOBALES/mon_service.sh"
    else
        echo -e "\e[31m[!] Error: Scripts base no encontrados en $DIR_GLOBALES\e[0m"
        return 1
    fi

    # 3. Carga de Prácticas (Modular)
    [ -f "$RAIZ/P02-Servidor-DHCP/Linux/DHCP.sh" ] && source "$RAIZ/P02-Servidor-DHCP/Linux/DHCP.sh"
    [ -f "$RAIZ/P03-Servidor-DNS/Linux/DNS.sh" ]  && source "$RAIZ/P03-Servidor-DNS/Linux/DNS.sh"
    [ -f "$RAIZ/P04-SSH/Linux/SSH.sh" ]           && source "$RAIZ/P04-SSH/Linux/SSH.sh"
    [ -f "$RAIZ/P05-FTP/Linux/FTP_Service.sh" ]   && source "$RAIZ/P05-FTP/Linux/FTP_Service.sh"
    [ -f "$RAIZ/P06-HTTP/Linux/HTTP.sh" ]          && source "$RAIZ/P06-HTTP/Linux/HTTP.sh"
    [ -f "$RAIZ/P07-HTTP-FTP/Linux/HTTP_FTP.sh" ]  && source "$RAIZ/P07-HTTP-FTP/Linux/HTTP_FTP.sh"
    [ -f "$RAIZ/P10-Dockers/Linux/Dockers.sh" ]      && source "$RAIZ/P10-Dockers/Linux/Dockers.sh"
    # 4. Detección de Interfaces
    echo -e "\n[*] Detectando interfaces de red disponibles..."
    mapfile -t interfaces < <(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")

    if [ ${#interfaces[@]} -eq 0 ]; then
        echo -e "\e[31m[!] No se detectaron interfaces de red.\e[0m"
        return 1
    fi

    echo "Interfaces encontradas:"
    for i in "${!interfaces[@]}"; do
        echo "$((i+1))) ${interfaces[$i]}"
    done

    read -p "Seleccione la interfaz a usar para el Orquestador: " idx
    interfaz="${interfaces[$((idx-1))]}"

    if [ -z "$interfaz" ]; then
        echo -e "\e[31m[!] Opción inválida.\e[0m"
        return 1
    fi

    FTP_IP=$(ip -4 addr show "$interfaz" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)

    if [ -z "$FTP_IP" ]; then
        echo -e "\e[33m[!] Advertencia: La interfaz $interfaz no tiene una IP asignada.\e[0m"
        read -p "Ingrese la IP del servidor manualmente: " FTP_IP
    fi

    export FTP_IP
    export FTP_BASE="ftp://$FTP_IP/http/Linux"
    
    echo -e "\e[32m[OK] Interfaz: $interfaz | IP Detectada: $FTP_IP\e[0m"
    return 0
}
