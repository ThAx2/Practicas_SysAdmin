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

    while true; do
        read -p "Dirección de Red (ej. 192.168.100.0): " base_ip
        valid_ip "$base_ip" && break
    done

    while true; do
        read -p "Máscara de Subred (ej. 255.255.255.0): " mask
        valid_ip "$mask" && break
    done
while true; do
        read -p "Rango inicial: " ip_i
        valid_ip "$ip_i" && break
    done

    while true; do
        read -p "Rango final: " ip_f
        valid_ip "$ip_f" "$ip_i" && break
    done

    while true; do
        read -p "Tiempo de concesión (segundos): " lease_time
        if [[ $lease_time =~ ^[0-9]+$ ]]; then break; fi
        echo "Error: Debe ser un valor numérico."
    done

    while true; do
        read -p "Puerta de enlace: " gateway
        valid_ip "$gateway" && break
    done 

    while true; do
        read -p "Servidor DNS: " dns_server
        valid_ip "$dns_server" && break
    done

    echo -e "\n========================================"
    echo "       RESUMEN DE CONFIGURACIÓN"
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
            echo -e "\n[!] Error: Revisa 'journalctl -u $servicio'"
        fi
    else
        echo "Configuración cancelada."
    fi
}

while true; do
    echo -e "\n================================"
    echo "        Menu dhcp     "
    echo "================================"
    echo "1) Crear / Configurar DHCP"
    echo "2) Consultar estado del servicio"
    echo "3) Listar concesiones (Leases)"
    echo "4) Salir"
    echo "--------------------------------"
    read -p "Opción: " opcion

    case $opcion in
        1) configurar_dhcp ;;
        2) 
            echo -e "\n--- Estado del Servicio ---"
            systemctl status $servicio --no-pager
            ;;
        3) 
            echo -e "\n--- Equipos Conectados (Leases) ---"
            if [ -f /var/lib/dhcp/dhcpd.leases ]; then
                grep "lease" /var/lib/dhcp/dhcpd.leases | sort | uniq
            else
                echo "No se encontraron concesiones activas."
            fi
            ;;
        4) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción no válida." ;;
    esac
done
