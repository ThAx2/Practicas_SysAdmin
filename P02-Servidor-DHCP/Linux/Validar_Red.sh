#!/bin/bash

# ===========================================================================
# Script: Validador de Red
# Author: Alexander Vega / Ax2 - / Codigo principal tomado de: https://www.linuxjournal.com/content/validating-ip-address-bash-script + Validacion que IP Inicial sea menor a la IP Final
    # Limpiamos espaci
# Fecha: 06/02/2026
# Funcion = valid_ip()
# Descripcion = Valida el formato IPv4 (0-255) mediante Regex y asegura la 
#               integridad del rango comparando el cuarto octeto final vs inicial, obtiene la ip una vez validada, la deshace en un array separando los octetos y analizandolos/comparandolos individualmente a excepcion del ultimo octeto que compara con ip de incio para verificar la coherencia en el rango.
# Parametros = $1 - IP a validar / $2 - IP de inicio (para comparar rangos) | Funciona con un parametro para verificar la base de la ip y dos para verificar rangos.



configurar_Red(){
    local interfaz=$1
    local base_ip="" mask="" ip_i="" gateway="" dns_server="" respuesta=""
    
    echo -e "\n[*] Iniciando Configuración de Interfaz: $interfaz"
   until valid_ip "$mask" "" "mask"; do 
        read -p "Máscara de Subred (ej. 255.255.255.0): " mask
    done
   while true; do
        read -p "IP Estática para este Servidor: " ip_i
        if valid_ip "$ip_i" "" "host"; then
            break
        fi
    done

    IFS='.' read -r -a oct_i <<< "$ip_i"
    base_ip="${oct_i[0]}.${oct_i[1]}.${oct_i[2]}.0"

    while true; do
        read -p "Puerta de enlace (Enter para omitir): " gateway
        [[ -z "$gateway" ]] && break
        valid_ip "$gateway" "$base_ip" "host" && break
    done

    while true; do
        read -p "DNS Forwarder / Externo (Enter para omitir): " dns_server
        [[ -z "$dns_server" ]] && break
        valid_ip "$dns_server" "" "host" && break
    done

    echo -e "\n========================================"
    echo "         RESUMEN DE RED (ESTÁTICA)"
    echo "========================================"
    echo "INTERFAZ:          $interfaz"
    echo "IP SERVIDOR:       $ip_i"
    echo "MÁSCARA:           $mask"
    echo "RED PERTENECIENTE: $base_ip"
    echo "GATEWAY:           ${gateway:-Ninguno}"
    echo "DNS EXTERNO:       ${dns_server:-Ninguno}"
    echo "========================================"
    read -p "¿Deseas aplicar estos cambios? (s/n): " respuesta

    if [[ $respuesta =~ ^[Ss]$ ]]; then
        echo "[*] Aplicando cambios con comando 'ip'..."
        ip addr flush dev "$interfaz"
        ip addr add "$ip_i/$mask" dev "$interfaz"
        ip link set "$interfaz" up
        
        if [[ -n "$gateway" ]]; then
            ip route add default via "$gateway" dev "$interfaz" 2>/dev/null
        fi

        echo -e "\e[32m[OK] Red configurada correctamente.\e[0m"
    else
        echo -e "\e[33m[!] Configuración cancelada.\e[0m"
    fi
}


valid_ip(){
    local ip=$(echo "$1" | xargs)            
    local ip_referencia=$(echo "$2" | xargs) 
    local tipo=$3                            

    if [[ -z "$ip" ]]; then return 1; fi
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "\e[31m[!] Error: Formato incorrecto. Use IPv4.\e[0m"
        return 1
    fi

    IFS='.' read -r -a ip_array <<< "$ip"
    for octeto in "${ip_array[@]}"; do
        if [[ "$octeto" -lt 0 || "$octeto" -gt 255 ]]; then
            echo -e "\e[31m[!] Error: Octeto fuera de rango ($octeto).\e[0m"
            return 1
        fi
    done

    if [[ $ip == "0.0.0.0" ]]; then
        echo -e "\e[31m[!] Error: Dirección nula prohibida (0.0.0.0).\e[0m"
        return 1
    fi

    if [[ ${ip_array[0]} -eq 127 ]]; then
        echo -e "\e[31m[!] Error: Direcciones de Loopback (127.x.x.x) son reservadas.\e[0m"
        return 1
    fi

    if [[ $ip == "1.0.0.0" ]]; then
        echo -e "\e[31m[!] Error: IP fuera de rango. Mínimo aceptable 1.0.0.1\e[0m"
        return 1
    fi

    if [[ $ip == "255.255.255.255" ]]; then
        echo -e "\e[31m[!] Error: Dirección de Broadcast Global prohibida.\e[0m"
        return 1
    fi

    if [[ ${ip_array[0]} -eq 0 ]]; then
         echo -e "\e[31m[!] Error: El primer octeto no puede ser 0.\e[0m"
         return 1
    fi

    local ultimo=${ip_array[3]}
    case $tipo in
        "red")
            if [[ $ultimo -ne 0 ]]; then
                echo -e "\e[31m[!] Error: La dirección de RED debe terminar en .0\e[0m"
                return 1
            fi 
            ;;
        "mask")
            local masks_validas="255.0.0.0 255.128.0.0 255.192.0.0 255.224.0.0 255.240.0.0 255.248.0.0 255.252.0.0 255.254.0.0 255.255.0.0 255.255.128.0 255.255.192.0 255.255.224.0 255.255.240.0 255.255.248.0 255.255.252.0 255.255.254.0 255.255.255.0 255.255.255.128 255.255.255.192 255.255.255.224 255.255.255.240 255.255.255.248 255.255.255.252"
            
            if [[ ! $masks_validas =~ $ip ]]; then
                echo -e "\e[31m[!] Error: Máscara $ip no es válida. Debe ser una máscara de subred real.\e[0m"
                return 1
            fi
            ;;
        "host"|"rango")
            if [[ $ultimo -eq 255 ]]; then
                echo -e "\e[31m[!] Error: No use .255 (Broadcast) para hosts.\e[0m"
                return 1
            fi 
            ;;
    esac

    if [[ -n $ip_referencia ]]; then
        IFS='.' read -r -a ref_array <<< "$ip_referencia"
        if [[ ${ip_array[0]} -ne ${ref_array[0]} ]] || \
           [[ ${ip_array[1]} -ne ${ref_array[1]} ]] || \
           [[ ${ip_array[2]} -ne ${ref_array[2]} ]]; then
            echo -e "\e[31m[!] Error: La IP $ip no pertenece a la red ${ref_array[0]}.${ref_array[1]}.${ref_array[2]}.0\e[0m"
            return 1
        fi

        if [[ $tipo == "rango" ]]; then
            if [[ ${ip_array[3]} -lt ${ref_array[3]} ]]; then
                echo -e "\e[31m[!] Error: Rango ilógico. El final (.${ip_array[3]}) debe ser mayor o igual al inicio (.${ref_array[3]})\e[0m"
                return 1
            fi
        fi
        fi
    

    return 0
}

valid_dominio() {
    local dominio=$1
    local regex="^([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,}$"

    if [[ -z "$dominio" ]]; then
        echo -e "\e[31m[!] Error: El dominio no puede estar vacío.\e[0m"
        return 1
    fi
    if [[ $dominio =~ $regex ]]; then
        return 0
    else
        echo -e "\e[31m[!] Error: '$dominio' no es un formato de dominio válido (ej: dominio.com).\e[0m"
        return 1
    fi
}
