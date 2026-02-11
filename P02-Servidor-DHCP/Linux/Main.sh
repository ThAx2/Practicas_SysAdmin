#!/bin/bash
source ./Validar_Red.sh
source ./mon_service.sh
servicio="isc-dhcp-server"
interfaz="enp0s8"

configurar_dhcp() {
    base_ip=""; mask=""; ip_i=""; ip_f=""; lease_time=""; gateway=""; dns_server=""; scope=""
    
    mon_service $servicio
    
    read -p "Nombre del Ámbito: " scope
    while [[ -z "$scope" ]]; do
        echo "Error: El nombre no puede estar vacío."
        read -p "Nombre del Ámbito: " scope
    done

    until valid_ip "$mask" "" "mask"; do 
        read -p "Máscara de Subred: " mask
    done

    while true; do
        read -p "IP Inicial del Rango (Será la IP del Servidor): " ip_i
        if [[ "$ip_i" == "0.0.0.0" || "$ip_i" == "1.0.0.0" || "$ip_i" == "127.0.0.0" || "$ip_i" == "127.0.0.1" || "$ip_i" == "255.255.255.255" ]]; then
            echo "Error: La IP $ip_i está prohibida."
        elif valid_ip "$ip_i" "" "host"; then
            break
        fi
    done

    until valid_ip "$ip_f" "$ip_i" "rango"; do 
        read -p "Rango Final (mayor o igual a $ip_i): " ip_f
    done

    while true; do
        read -p "Tiempo de concesión (segundos): " lease_time
        if [[ $lease_time =~ ^[0-9]+$ ]] && [[ $lease_time -ne 0 ]]; then 
            break
        fi
        echo "Error: Debe ser un valor numérico mayor a 0."
    done

    IFS='.' read -r -a oct_i <<< "$ip_i"
    IFS='.' read -r -a oct_f <<< "$ip_f"
    
    base_ip="${oct_i[0]}.${oct_i[1]}.${oct_i[2]}.0"
    rango_real_inicio="${oct_i[0]}.${oct_i[1]}.${oct_i[2]}.$((oct_i[3] + 1))"
    rango_real_final="${oct_f[0]}.${oct_f[1]}.${oct_f[2]}.$((oct_f[3] + 1))"

    while true; do
        read -p "Puerta de enlace (Enter para omitir): " gateway
        [[ -z "$gateway" ]] && break
        valid_ip "$gateway" "$base_ip" "host" && break
    done

    while true; do
        read -p "Servidor DNS (Enter para omitir): " dns_server
        [[ -z "$dns_server" ]] && break
        valid_ip "$dns_server" "" "host" && break
    done

    echo -e "\n========================================"
    echo "        RESUMEN DE CONFIGURACIÓN"
    echo "========================================"
    echo "RED CALCULADA:    $base_ip"
    echo "IP FIJA SERVIDOR: $ip_i"
    echo "RANGO DHCP REAL:  $rango_real_inicio - $rango_real_final"
    echo "GATEWAY: ${gateway:-Ninguno} | DNS: ${dns_server:-Ninguno}"
    echo "========================================"
    read -p "¿Deseas aplicar la configuración? (s/n): " respuesta

    if [[ $respuesta =~ ^[Ss]$ ]]; then
        ip addr flush dev $interfaz
        ip addr add $ip_i/$mask dev $interfaz
        ip link set $interfaz up

        cat <<EOF > /etc/dhcp/dhcpd.conf
authoritative;
default-lease-time $lease_time;
max-lease-time 7200;

subnet $base_ip netmask $mask {
    range $rango_real_inicio $rango_real_final;
    ${gateway:+option routers $gateway;}
    ${dns_server:+option domain-name-servers $dns_server;}
}
EOF
        echo "INTERFACESv4=\"$interfaz\"" > /etc/default/isc-dhcp-server
        
        systemctl restart $servicio
        if systemctl is-active --quiet $servicio; then
            echo -e "\n[OK] ¡SERVICIO ACTIVO! Servidor en $ip_i"
        else
            echo -e "\n[!] Error crítico. Registro de errores:"
            /usr/sbin/dhcpd -t -cf /etc/dhcp/dhcpd.conf
        fi
    fi
}

while true; do
    echo -e "\n================================"
    echo "          Menu DHCP             "
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
        4) exit 0 ;;
        *) echo "Opción no válida." ;;
    esac
done
