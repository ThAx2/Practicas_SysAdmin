#!/bin/bash
source ./Validar_Red.sh
source ./mon_service.sh
servicio="isc-dhcp-server"

configurar_dhcp() {
    base_ip=""; mask=""; ip_i=""; ip_f=""; lease_time=""; gateway=""; dns_server=""; scope=""
    
    mon_service $servicio
    
    read -p "Nombre del Ámbito: " scope
    while [[ -z "$scope" ]]; do
        echo "Error: El nombre no puede estar vacío."
        read -p "Nombre del Ámbito: " scope
    done

    until valid_ip "$base_ip" "" "red"; do 
        read -p "Dirección de Red (ej. 192.168.1.0): " base_ip
    done

    until valid_ip "$mask" "" "mask"; do 
        read -p "Máscara de Subred (ej. 255.255.255.0): " mask
    done

    until valid_ip "$ip_i" "$base_ip" "host"; do 
        read -p "Rango Inicial (en la red $base_ip): " ip_i
    done
  until valid_ip "$ip_f" "$ip_i" "rango"; do 
        read -p "Rango Final (mayor a $ip_i): " ip_f
    done

    while true; do
        read -p "Tiempo de concesión (segundos): " lease_time
        if [[ $lease_time =~ ^[0-9]+$ ]] && [[ $lease_time -ne 0 ]]; then 
            break
        fi
        echo "Error: Debe ser un valor numérico mayor a 0."
    done
    while true; do
        read -p "Puerta de enlace: " gateway
        if valid_ip "$gateway" "$base_ip" "host"; then
            if [[ "$gateway" != "$ip_i" && "$gateway" != "$ip_f" ]]; then
                break
            else
                echo "Error: El Gateway no puede ser el inicio o fin del rango DHCP."
            fi
        fi
    done 

    while true; do
        read -p "Servidor DNS: " dns_server
        valid_ip "$dns_server" "" "host" && break
    done

    echo -e "\n========================================"
    echo "        RESUMEN DE CONFIGURACIÓN"
    echo "========================================"
    echo "Red: $base_ip | Máscara: $mask"
    echo "Rango: $ip_i - $ip_f"
    echo "Gateway: $gateway | DNS: $dns_server"
    echo "========================================"
    read -p "¿Deseas aplicar la configuración? (s/n): " respuesta

    if [[ $respuesta =~ ^[Ss]$ ]]; then
        cat <<EOF > /etc/dhcp/dhcpd.conf
subnet $base_ip netmask $mask {
    range $ip_i $ip_f;
    option routers $gateway;
    option domain-name-servers $dns_server;
    default-lease-time $lease_time;
    max-lease-time 7200;
}
EOF
        echo 'INTERFACESv4="enp0s8"' > /etc/default/isc-dhcp-server
        
        systemctl restart $servicio
        if systemctl is-active --quiet $servicio; then
            echo -e "\n[OK] ¡SERVICIO ACTIVO Y FUNCIONANDO!"
        else
            echo -e "\n[!] Error: Revisa la configuración. Reintentando..."
            journalctl -u $servicio --no-pager | tail -n 10
        fi
    else
        echo "Configuración cancelada."
    fi
}

while true; do
    echo -e "\n================================"
    echo "         Menu DHCP             "
    echo "================================"
    echo "1) Crear / Configurar DHCP"
    echo "2) Consultar estado del servicio"
    echo "3) Listar concesiones (Leases)"
    echo "4) Salir"
    echo "--------------------------------"
    read -p "Opción: " opcion

    case $opcion in
        1) configurar_dhcp ;;
        2) systemctl status $servicio --no-pager ;;
        3) 
            echo -e "\n--- Equipos Conectados ---"
            [ -f /var/lib/dhcp/dhcpd.leases ] && grep "lease" /var/lib/dhcp/dhcpd.leases | sort | uniq || echo "Sin concesiones."
            ;;
        4) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción no válida." ;;
    esac
done
