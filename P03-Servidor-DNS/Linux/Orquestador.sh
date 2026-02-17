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

# --- MÓDULO DNS ACTUALIZADO (Servidor + Dominios) ---
Gestionar_DNS_Modular() {
    local servicio="bind9"
    local conf_options="/etc/bind/named.conf.options"
    
    # --- BLOQUE DE CONFIGURACIÓN DEL SERVIDOR ---
    # Esto permite que el servidor reciba consultas de otros equipos
    echo "[*] Aplicando configuración global del servidor DNS..."
    cat <<EOF > $conf_options
options {
    directory "/var/cache/bind";

    # Escuchar en todas las interfaces (necesario para que el cliente lo vea)
    listen-on port 53 { any; };
    
    # Permitir consultas desde cualquier IP
    allow-query { any; };

    # Permitir que resuelva nombres externos
    recursion yes;

    dnssec-validation auto;
    listen-on-v6 { any; };
};
EOF

    mon_service "$servicio"

    while true; do
        echo -e "\n===================================="
        echo "        MODULO GESTIÓN DNS          "
        echo "===================================="
        echo "1) Listar Dominios"
        echo "2) Crear Nuevo Dominio (Subir)"
        echo "3) Borrar Dominio"
        echo "4) Volver al Orquestador"
        read -p "Seleccione una opción: " opt_dns

        case $opt_dns in
            1)
                echo -e "\n[*] Dominios configurados actualmente:"
                grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2
                read -p "Presione Enter para continuar..."
                ;;
            2)
                local dominio=""
                until valid_dominio "$dominio"; do
                    read -p "Nombre dominio: " dominio
                done

                check_red_lista || configurar_Red "$interfaz"
                local IP_SERVIDOR=$(ip -4 addr show "$interfaz" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)

                read -p "IP DE DESTINO DEL DOMINIO (Enter para apuntar al servidor $IP_SERVIDOR): " ip_usuario
                local ip_final=${ip_usuario:-$IP_SERVIDOR}

                echo "[*] Configurando zona: $dominio -> $ip_final"
                
                # Registro en named.conf.local
                echo "zone \"$dominio\" { type master; file \"/etc/bind/db.$dominio\"; };" >> /etc/bind/named.conf.local

                # Creación del archivo de zona (db.dominio)
                cat <<EOF > /etc/bind/db.$dominio
\$TTL    604800
@       IN      SOA     ns.$dominio. root.$dominio. ( 1; 604800; 86400; 2419200; 604800 )
@       IN      NS      ns.$dominio.
@       IN      A       $ip_final
ns      IN      A       $IP_SERVIDOR
www     IN      A       $ip_final
EOF
                systemctl restart "$servicio"
                echo -e "\e[32m[OK] Servidor y dominio $dominio configurados.\e[0m"
                ;;
            3)
                read -p "Ingrese dominio a borrar: " borrar
                if grep -q "zone \"$borrar\"" /etc/bind/named.conf.local; then
                    sed -i "/zone \"$borrar\"/,/};/d" /etc/bind/named.conf.local
                    rm -f "/etc/bind/db.$borrar"
                    systemctl restart "$servicio"
                    echo -e "\e[32m[OK] Dominio eliminado.\e[0m"
                else
                    echo -e "\e[31m[!] No existe.\e[0m"
                fi
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
        echo "2) Configurar Servidor DNS (Módulo)"
        echo "3) Configuración de Red Manual"
        echo "4) Estatus de Servicios"
        echo "5) Salir"
        read -p "Opción: " opcion 
        
        case $opcion in
            1)
                # Entramos directo al menú para evitar bloqueos
                menu_dhcp
                ;;
            2) Gestionar_DNS_Modular ;;
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
