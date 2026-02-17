#!/bin/bash

cargar_dependencias() {
    export interfaz="enp0s8"
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    P02_DIR="$SCRIPT_DIR/../../P02-Servidor-DHCP/Linux"

    if [ -d "$P02_DIR" ]; then
        source "$P02_DIR/Validar_Red.sh"
        source "$P02_DIR/mon_service.sh"
        source "$P02_DIR/DHCP.sh"
        return 0
    else
        exit 1
    fi
}

check_red_lista() {
    local ip_actual=$(ip -4 addr show "$interfaz" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    if [[ -z "$ip_actual" || "$ip_actual" == *.0 ]]; then
        return 1
    fi
    return 0
}

Configurar_DNS(){
    local servicio="bind9"
    local conf_local="/etc/bind/named.conf.local"
    local interfaz="enp0s8"
    local IP_SRV=$(ip -4 addr show "$interfaz" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)

    while true; do
        echo -e "\n------------------------------------"
        echo "        MODULO GESTIÓN DNS          "
        echo "------------------------------------"
        echo "1) Listar Dominios (Consulta)"
        echo "2) Crear Nuevo Dominio (Alta)"
        echo "3) Borrar Dominio (Baja)"
        echo "4) Volver al Orquestador"
        read -p "Opción: " opt_dns

        case $opt_dns in
            1)
                grep "zone" "$conf_local" | cut -d'"' -f2 || echo "No hay dominios."
                ;;
            2)
                read -p "Nombre del dominio: " dominio
                [[ -z "$dominio" ]] && continue
                read -p "IP de DESTINO (Enter para $IP_SRV): " ip_dest
                local IP_FINAL=${ip_dest:-$IP_SRV}
                
                sed -i "/zone \"$dominio\"/,/};/d" "$conf_local"
                echo "zone \"$dominio\" { type master; file \"/etc/bind/db.$dominio\"; };" >> "$conf_local"

                cat <<EOF > "/etc/bind/db.$dominio"
\$TTL 604800
@ IN SOA ns.$dominio. root.$dominio. ( 1 604800 86400 2419200 604800 )
@ IN NS ns.$dominio.
@ IN A $IP_FINAL
ns IN A $IP_SRV
www IN A $IP_FINAL
EOF
                if named-checkconf "$conf_local" && named-checkzone "$dominio" "/etc/bind/db.$dominio"; then
                    systemctl restart "$servicio"
                    echo -e "\e[32m[OK] Alta exitosa.\e[0m"
                else
                    echo -e "\e[31m[!] Error de sintaxis.\e[0m"
                fi
                ;;
            3)
                read -p "Dominio a eliminar: " borrar
                sed -i "/zone \"$borrar\"/,/};/d" "$conf_local"
                rm -f "/etc/bind/db.$borrar"
                systemctl restart "$servicio"
                echo -e "\e[32m[OK] Baja exitosa.\e[0m"
                ;;
            4) return 0 ;;
        esac
    done
}

menu_principal(){
    cargar_dependencias 
    while true; do
        echo -e "\n===================================="
        echo "      ORQUESTADOR MULTIMÓDULO       "
        echo "===================================="
        echo "1) Configurar Servidor DHCP"
        echo "2) Configurar Servidor DNS"
        echo "3) Configuración de Red Manual"
        echo "4) Estatus de Servicios"
        echo "5) Salir"
        read -p "Opción: " opcion 

        case $opcion in
            1) check_red_lista || configurar_Red "$interfaz"; menu_dhcp ;;
            2) Configurar_DNS ;;
            3) configurar_Red "$interfaz" ;;
            4) 
                echo -e "\n--- Estatus ---"
                echo "DHCP: $(systemctl is-active isc-dhcp-server)"
                echo "DNS:  $(systemctl is-active bind9)"
                ip -4 addr show "$interfaz" | grep inet
                ;;
            5) exit 0 ;;
            *) echo "Opción no válida." ;;
        esac
    done
}

[[ $EUID -ne 0 ]] && echo "Ejecutar con sudo" && exit 1
menu_principal
