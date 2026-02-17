#!/bin/bash

# ===========================================================================
# Script: Orquestador Maestro (Libertad Total de IPs)
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

Configurar_DNS_Manual(){
    local servicio="bind9"
    local dominio="" 

    mon_service "$servicio"

    if ! check_red_lista; then
        echo -e "\n[*] Red no configurada. Iniciando asistente..."
        configurar_Red "$interfaz"
    fi
    
    local IP_SERVIDOR=$(ip -4 addr show "$interfaz" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)

    cat <<EOF > /etc/bind/named.conf.options
options {
    directory "/var/cache/bind";
    listen-on port 53 { any; };
    allow-query { any; };
    recursion yes;
    dnssec-validation auto;
    listen-on-v6 { any; };
};
EOF

    until [[ -n "$dominio" ]]; do
        read -p "Nombre del Dominio (ej: testeo.com): " dominio
    done

    echo "La IP del servidor DNS actual es: $IP_SERVIDOR"
    read -p "Ingresa la IP a donde quieres que apunte $dominio (Enter para usar $IP_SERVIDOR): " IP_DESTINO
    ue escribió.
    local IP_FINAL=${IP_DESTINO:-$IP_SERVIDOR}

    echo -e "\n[*] Configurando zona: $dominio apuntando a -> $IP_FINAL"
    
    echo "zone \"$dominio\" { type master; file \"/etc/bind/db.$dominio\"; };" >> /etc/bind/named.conf.local

    cat <<EOF > /etc/bind/db.$dominio
\$TTL    604800
@       IN      SOA     ns.$dominio. root.$dominio. ( 1; 604800; 86400; 2419200; 604800 )
@       IN      NS      ns.$dominio.
@       IN      A       $IP_FINAL
ns      IN      A       $IP_SERVIDOR
www     IN      A       $IP_FINAL
EOF

    if named-checkconf /etc/bind/named.conf.local; then
        systemctl restart "$servicio"
        echo -e "\e[32m[OK] Dominio $dominio creado. Apunta a $IP_FINAL\e[0m"
    else
        echo -e "\e[31m[!] Error de sintaxis en BIND9.\e[0m"
    fi
}

menu_principal(){
    cargar_dependencias 
    
    while true; do
        echo -e "\n===================================="
        echo "      ORQUESTADOR MULTIMÓDULO       "
        echo "===================================="
        echo "1) Configurar Servidor DHCP"
        echo "2) Configurar Servidor DNS (Manual)"
        echo "3) Configuración de Red Manual"
        echo "4) Estatus de Servicios"
        echo "5) Salir"
        read -p "Opción: " opcion 
        
        case $opcion in
            1) menu_dhcp ;;
            2) Configurar_DNS_Manual ;;
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
