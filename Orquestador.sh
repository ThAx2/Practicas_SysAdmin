#!/bin/bash

# ==============================================================================
# ORQUESTADOR MULTIMÓDULO
# ==============================================================================
source "Globales/Linux/Dependencias.sh"
export PUERTO_ACTUAL="N/A"
menu_principal(){
    cargar_dependencias 
    while true; do
        echo -e "\n===================================="
        echo "      ORQUESTADOR MULTIMÓDULO       "
        echo "===================================="

        echo "1) Estatus de Servicios"
        echo "2) Configuración de Red Manual"
        echo "3) Configurar Servidor DHCP"
        echo "4) Configurar Servidor DNS"
		echo "5) Servidor FTP"
		echo "6) Conectar a SSH"
		echo "7) Configurar HTTP"
        echo "8) Salir"
        read -p "Opción: " opcion 
 
        case $opcion in
			1)
             
    echo -e "\n--- Estatus ---"
    echo "DHCP: $(systemctl is-active isc-dhcp-server)"
    echo "DNS:  $(systemctl is-active bind9)"
    echo "HTTP: $(systemctl is-active nginx 2>/dev/null || systemctl is-active apache2 2>/dev/null)"
    echo "Puerto HTTP asignado: $PUERTO_ACTUAL" 
    ip -4 addr show "$interfaz" | grep inet

                ;;
            2) 
                configurar_Red "$interfaz" 
                ;;
            3) 
                check_red_lista 
                menu_dhcp 
                ;;
            4) 
                Configurar_DNS 
                ;;
			5)
				echo "Llamando MODULO FTP: "
				menu_FTP
			 ;;
            
            6)
				
				echo -e "Llamando modulo conector SSH";					 
				SSH

			 ;;
						
			7)
				menu_http
	;;

			8) exit 0 ;;
            *) echo "Opción no válida." ;;
        esac
    done
}

[[ $EUID -ne 0 ]] && echo "Ejecutar con sudo" && exit 1
menu_principal
