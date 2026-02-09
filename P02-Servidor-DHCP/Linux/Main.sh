# IP FIJA 

#!/bin/bash
source ./Validar_Red.sh
source ./mon_service.sh
servicio="isc-dhcp-server"

mon_service $servicio
read -p "Nombre del Ámbito: " scope
until valid_ip "$base_ip"; do read -p "Dirección de Red (ej. 192.168.100.0): " base_ip; done
read -p "Máscara de Subred: " mask
until valid_ip "$ip_i"; do read -p "Rango inicial: " ip_i; done
until valid_ip "$ip_f" "$ip_i"; do read -p "Rango final: " ip_f; done
read -p "Tiempo de concesión: " lease_time
until valid_ip "$gateway"; do read -p "Puerta de enlace: " gateway; done 
until valid_ip "$dns_server"; do read -p "Servidor DNS: " dns_server; done

echo -e "\nResumen: Red $base_ip, Rango $ip_i - $ip_f"
read -p "¿Deseas aplicar la configuración? (s/n): " respuesta

if [[ $respuesta =~ "s" ]]; then
    # Generar el archivo de configuración (Lo que ya tienes)
    cat <<EOF > /etc/dhcp/dhcpd.conf
subnet $base_ip netmask $mask {
    range $ip_i $ip_f;
    option routers $gateway;
    option domain-name-servers $dns_server;
    default-lease-time $lease_time;
    max-lease-time 7200;
}
EOF
#OCUPAS TENER ESTÉ APARTADO, 
   echo 'INTERFACESv4="enp0s3"' > /etc/default/isc-dhcp-server
systemctl restart $servicio
    
    if systemctl is-active --quiet $servicio; then
        echo "¡SERVICIO ACTIVO Y FUNCIONANDO!"
    else
        echo "Error: Revisa 'journalctl -u isc-dhcp-server' para ver el detalle final"
    fi
else
    echo "Saliendo."
    exit
fi

# 3. Menú de Monitoreo
while true; do
    echo -e "\n============ MENÚ ============="
    echo "1) Consultar estado del servicio"
    echo "2) Listar concesiones"
    echo "3) Salir"
    read -p "Opción: " opcion

    case $opcion in
        1)
            echo "Estado actual:"
            systemctl status $servicio --no-pager
            echo -e "\nLogs recientes:"
            journalctl -u $servicio -n 10 --no-pager
            ;;
        2)
            echo "Equipos conectados:"
            [ -f /var/lib/dhcp/dhcpd.leases ] && grep "lease" /var/lib/dhcp/dhcpd.leases || echo "Sin conexiones."
            ;;
        3) break ;;
    esac
done
