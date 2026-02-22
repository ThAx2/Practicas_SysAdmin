#!/bin/bash

# ==============================================================================
# ORQUESTADOR MULTIMÓDULO
# ==============================================================================
source "Globales/Linux/Dependencias.sh"
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
            1) 
                check_red_lista 
                menu_dhcp 
                ;;
            2) 
                Configurar_DNS 
                ;;
            3) 
                configurar_Red "$interfaz" 
                ;;
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
