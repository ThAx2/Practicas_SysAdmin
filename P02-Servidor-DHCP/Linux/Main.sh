#!/bin/bash
source ./Validar_Red.sh
source ./mon_service.sh
servicio="isc-dhcp-server"
mon_service $servicio

read -p "Nombre del Ámbito (ej. Red_Sistemas): " scope

until valid_ip "$base_ip"; do
    read -p "Dirección de Red (Network ID, ej. 192.168.100.0): " base_ip
done

read -p "Máscara de Subred (Mask, ej. 255.255.255.0): " mask

until valid_ip "$ip_i"; do
    read -p "Rango inicial de IPs: " ip_i
done

until valid_ip "$ip_f" "$ip_i"; do
    read -p "Rango final de IPs: " ip_f
done

read -p "Tiempo de concesión (en segundos): " lease_time
until valid_ip $gateway; do
read -p "Puerta de enlace (Gateway): " gateway
done 
until valid_ip $dns_server; do
read -p "Servidor DNS (IP Práctica 1): " dns_server
done
echo "Todo correcto"
sleep 1
clear
echo "Nombre ambito: $scope";
echo "Segmento de red: $base_ip";
echo "Mascara de subred: $mask";
echo "Rango de: $ip_i al $ip_f";
echo "Tiempo de cocesion: $lease_time";
echo "Puerta de enlace: $gateway";
echo "Servidor DNS: $dns_server";
read -p "¿Deseas continuar con la configuracion? (s/n): " respuesta

if [[ $respuesta =~ "s" ]]; then
cat <<EOF > /tmp/dhcpd.conf
	subnet $base_ip netmask $mask {
    range $ip_i $ip_f;
    option routers $gateway;
    option domain-name-servers $dns_server;
    default-lease-time $lease_time;
    max-lease-time 7200;
}
EOF
    sudo mv /tmp/dhcpd.conf /etc/dhcp/dhcpd.conf
    dhcpd -t
    sudo systemctl restart $servicio
    echo "Servidor DHCP Configurado correctamente."
else
    echo "Saliendo sin aplicar cambios."
fi


while true; do
    echo " "
    echo "============MENÚ====================="
    echo "1) Consultar estado del servicio"
    echo "2) Listar concesiones (Equipos conectados)"
    echo "3) Salir"
    read -p "Seleccione una opción: " opcion

    case $opcion in
        1)
            echo "Muestra de logs: "
            sleep 1
            # -u filtra por servicio, -f es tiempo real (follow)
            sudo journalctl -u $servicio -f
            ;;
        2)
            echo "Equipos conectados"
            if [ -f /var/lib/dhcp/dhcpd.leases ]; then
                grep -E "lease|client-hostname" /var/lib/dhcp/dhcpd.leases | sort | uniq
            else
                echo "Aún no hay equipos conectados"
            fi
            ;;
        3)
            echo "Saliendo."
            break
            ;;
        *)
            echo "Opción no válida."
            ;;
    esac
done
