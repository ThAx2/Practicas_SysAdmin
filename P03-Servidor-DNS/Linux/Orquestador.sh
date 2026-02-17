#!/bin/bash
# Orquestador Maestro - VERSIÓN INTEGRADA FINAL

# ===========================================================================
# Script: Orquestador Maestro Modular (DNS / DHCP / RED)
# ===========================================================================

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
        echo -e "\e[31m[!] Error: No se encontró la carpeta P02.\e[0m"
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

# --- ESTA ES TU FUNCIÓN CON LO NUEVO INTEGRADO ---
Configurar_DNS(){
    local servicio="bind9"
    local conf_local="/etc/bind/named.conf.local"
    
    # 1. Asegurar que el servidor ESCUCHE a la red (lo que faltaba para el ping)
    cat <<EOF > /etc/bind/named.conf.options
options {
    directory "/var/cache/bind";
    listen-on port 53 { any; };
    allow-query { any; };
    recursion yes;
};
EOF

    while true; do
        echo -e "\n--- GESTIÓN DNS ---"
        echo "1) Listar Dominios"
        echo "2) Crear Dominio (Cualquier IP)"
        echo "3) Borrar Dominio"
        echo "4) Volver"
        read -p "Opción: " opt_dns

        case $opt_dns in
            1)
                echo -e "\n[*] Dominios actuales:"
                grep "zone" $conf_local | cut -d'"' -f2
                ;;
            2)
                local dominio=""
                until [[ -n "$dominio" ]]; do
                    read -p "Nombre de dominio: " dominio
                done

                local ip_fija=$(ip -4 addr show "$interfaz" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
                
                # LA IP DE DESTINO: Aquí eliges la que quieras
                read -p "IP de destino para $dominio (Enter para usar $ip_fija): " ip_user
                local ip_final=${ip_user:-$ip_fija}

                echo "[*] Configurando $dominio -> $ip_final"
                
                # USAR >> PARA NO BORRAR LOS ANTERIORES
                echo "zone \"$dominio\" { type master; file \"/etc/bind/db.$dominio\"; };" >> $conf_local

                cat <<EOF > /etc/bind/db.$dominio
\$TTL    604800
@       IN      SOA     ns.$dominio. root.$dominio. ( 1; 604800; 86400; 2419200; 604800 )
@       IN      NS      ns.$dominio.
@       IN      A       $ip_final
ns      IN      A       $ip_fija
www     IN      A       $ip_final
EOF
                systemctl restart "$servicio"
                echo -e "\e[32m[OK] Configurado.\e[0m"
                ;;
            3)
                read -p "Dominio a borrar: " borrar
                sed -i "/zone \"$borrar\"/,/};/d" $conf_local
                rm -f "/etc/bind/db.$borrar"
                systemctl restart "$servicio"
                echo "Borrado."
                ;;
            4) break ;;
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

# --- EJECUCIÓN ---
[[ $EUID -ne 0 ]] && echo "Ejecutar con sudo" && exit 1
menu_principal
