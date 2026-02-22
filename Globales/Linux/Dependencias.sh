#!/bin/bash

cargar_dependencias() {

    export interfaz="enp0s8"
    local DIR_GLOBALES=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local RAIZ=$(readlink -f "$DIR_GLOBALES/../..")

    if [ -f "$DIR_GLOBALES/Validar_Red.sh" ] && [ -f "$DIR_GLOBALES/mon_service.sh" ]; then
        source "$DIR_GLOBALES/Validar_Red.sh"
        source "$DIR_GLOBALES/mon_service.sh"
    else
        echo -e "\e[31m[!] Error: No se encontraron Validar_Red.sh o mon_service.sh en $DIR_GLOBALES\e[0m"
        return 1
    fi

    [ -f "$RAIZ/P02-Servidor-DHCP/Linux/DHCP.sh" ] && source "$RAIZ/P02-Servidor-DHCP/Linux/DHCP.sh"
    [ -f "$RAIZ/P03-Servidor-DNS/Linux/DNS.sh" ] && source "$RAIZ/P03-Servidor-DNS/Linux/DNS.sh"
    [ -f "$RAIZ/P04-SSH/Linux/SSH.sh" ] && source "$RAIZ/P04-SSH/Linux/SSH.sh"
	[ -f "$RAIZ/P05-FTP/Linux/FTP_Service.sh" ] && source "$RAIZ/P05-FTP/Linux/FTP_Service.sh"
    return 0

}

