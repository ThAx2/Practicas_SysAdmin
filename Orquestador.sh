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
		echo "3) Servidor FTP"
        echo "4) Estatus de Servicios"
		echo "5) Conectar a SSH"
        echo "6) Configuración de Red Manual"
        echo "7) Salir"
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
				echo "Llamando MODULO FTP: "
				menu_FTP
			 ;;
            
	4) 
                echo -e "\n--- Estatus ---"
                echo "DHCP: $(systemctl is-active isc-dhcp-server)"
                echo "DNS:  $(systemctl is-active bind9)"
				echo "SSH: $(systemctl is-active ssh)"
				echo "FTP: $(systemctl is-active vsftpd)"
                ip -4 addr show "$interfaz" | grep inet
                ;;
            5)
				
				echo -e "Llamando modulo conector SSH";					 
				SSH

			 ;;
						


            6) 
                configurar_Red "$interfaz" 
                ;;
			7) exit 0 ;;
            *) echo "Opción no válida." ;;
        esac
    done
}

[[ $EUID -ne 0 ]] && echo "Ejecutar con sudo" && exit 1
menu_principal
