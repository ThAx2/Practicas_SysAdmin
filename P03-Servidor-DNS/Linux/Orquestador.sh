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
        configurar_Red() { echo "Configurando red en $1..."; }
        return 0
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
        echo "        MODULO GESTIÓN DNS (ABC)      "
        echo "------------------------------------"
        echo "1) Listar Dominios (Consulta)"
        echo "2) Crear Nuevo Dominio (Alta + Inversa)"
        echo "3) Borrar Dominio (Baja)"
        echo "4) Volver al Orquestador"
        read -p "Opción: " opt_dns

        case $opt_dns in
            1)
                echo "Dominios configurados:"
                grep "zone" "$conf_local" | cut -d'"' -f2 || echo "No hay dominios."
                ;;
            2)
                read -p "Nombre del dominio (ej. redes.com): " dominio
                [[ -z "$dominio" ]] && continue
                read -p "IP de DESTINO (Enter para $IP_SRV): " ip_dest
                local IP_FINAL=${ip_dest:-$IP_SRV}

                IFS='.' read -r o1 o2 o3 o4 <<< "$IP_FINAL"
                local ZONA_INV="$o3.$o2.$o1.in-addr.arpa"
                local FILE_INV="/etc/bind/db.$o1.$o2.$o3"

                sed -i "/zone \"$dominio\"/,/};/d" "$conf_local"
                echo "zone \"$dominio\" { type master; file \"/etc/bind/db.$dominio\"; };" >> "$conf_local"
                
                if ! grep -q "$ZONA_INV" "$conf_local"; then
                    echo "zone \"$ZONA_INV\" { type master; file \"$FILE_INV\"; };" >> "$conf_local"
                fi

                cat <<EOF > "/etc/bind/db.$dominio"
\$TTL 604800
@ IN SOA ns.$dominio. root.$dominio. ( $(date +%s) 604800 86400 2419200 604800 )
@ IN NS ns.$dominio.
@ IN A $IP_FINAL
ns IN A $IP_SRV
www IN A $IP_FINAL
EOF

                if [ ! -f "$FILE_INV" ]; then
                    cat <<EOF > "$FILE_INV"
\$TTL 604800
@ IN SOA ns.$dominio. root.$dominio. ( $(date +%s) 604800 86400 2419200 604800 )
@ IN NS ns.$dominio.
EOF
                fi
                if ! grep -q "^$o4" "$FILE_INV"; then
                    echo "$o4 IN PTR $dominio." >> "$FILE_INV"
                    echo "$o4 IN PTR www.$dominio." >> "$FILE_INV"
                fi

                if named-checkconf "$conf_local" && named-checkzone "$dominio" "/etc/bind/db.$dominio"; then
                    systemctl restart "$servicio"
                    echo -e "\e[32m[OK] Alta exitosa. Probando: nslookup $dominio y nslookup $IP_FINAL\e[0m"
                else
                    echo -e "\e[31m[!] Error de sintaxis en los archivos de zona.\e[0m"
                fi
                ;;
            3)
                read -p "Dominio a eliminar: " borrar
                sed -i "/zone \"$borrar\"/,/};/d" "$conf_local"
                rm -f "/etc/bind/db.$borrar"
                systemctl restart "$servicio"
                echo -e "\e[32m[OK] Baja exitosa del dominio directo.\e[0m"
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
