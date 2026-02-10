# ===========================================================================
# Script: Validador de Red
# Author: Alexander Vega / Ax2 - / Codigo principal tomado de: https://www.linuxjournal.com/content/validating-ip-address-bash-script + Validacion que IP Inicial sea menor a la IP Final
# Fecha: 06/02/2026
# Funcion = valid_ip()
# Descripcion = Valida el formato IPv4 (0-255) mediante Regex y asegura la 
#               integridad del rango comparando el cuarto octeto final vs inicial, obtiene la ip una vez validada, la deshace en un array separando los octetos y analizandolos/comparandolos individualmente a excepcion del ultimo octeto que compara con ip de incio para verificar la coherencia en el rango.
# Parametros = $1 - IP a validar / $2 - IP de inicio (para comparar rangos) | Funciona con un parametro para verificar la base de la ip y dos para verificar rangos.
# ===========================================================================
#!/bin/bash
# ===========================================================================
# Script: Validador de Red (Librería)
# Author: Alexander Vega / Ax2
# ===========================================================================
function valid_ip() {
    # Limpiamos espacios en blanco
    local ip=$(echo "$1" | xargs)
    local ip_referencia=$(echo "$2" | xargs)
    local tipo=$3

    # Si está vacía, fallamos en silencio para no ensuciar la pantalla
    [[ -z "$ip" ]] && return 1

    # 1. Regex y IPs Prohibidas
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || [[ $ip == "0.0.0.0" ]] || [[ $ip == "255.255.255.255" ]]; then
        echo -e "\e[31m[!] Error: Formato inválido o IP prohibida ($ip)\e[0m"
        return 1
    fi

    IFS='.' read -r -a ip_array <<< "$ip"
    for octeto in "${ip_array[@]}"; do
        if [[ $octeto -gt 255 ]]; then
            echo -e "\e[31m[!] Error: Octeto fuera de rango ($octeto)\e[0m"
            return 1
        fi
    done

    local ultimo=${ip_array[3]}

    case $tipo in
        "red")
            if [[ $ultimo -ne 0 ]]; then
                echo -e "\e[31m[!] Error: Una dirección de RED debe terminar en .0\e[0m"
                return 1
            fi ;;
        "mask")
            if [[ ${ip_array[0]} -ne 255 ]]; then
                echo -e "\e[31m[!] Error: Una máscara válida debe empezar por 255\e[0m"
                return 1
            fi ;;
        "host"|"rango")
            if [[ $ultimo -eq 0 || $ultimo -eq 255 ]]; then
                echo -e "\e[31m[!] Error: No usar .0 ni .255 para Hosts\e[0m"
                return 1
            fi ;;
    esac

    # Validación de Subred y Rango
    if [[ -n $ip_referencia ]]; then
        IFS='.' read -r -a ref_array <<< "$ip_referencia"
        if [[ ${ip_array[0]} -ne ${ref_array[0]} || ${ip_array[1]} -ne ${ref_array[1]} || ${ip_array[2]} -ne ${ref_array[2]} ]]; then
            echo -e "\e[31m[!] Error: La IP $ip no pertenece a la subred ${ref_array[0]}.${ref_array[1]}.${ref_array[2]}.x\e[0m"
            return 1
        fi
        if [[ $tipo == "rango" ]]; then
            if [[ ${ip_array[3]} -le ${ref_array[3]} ]]; then
                echo -e "\e[31m[!] Error: El fin (.${ip_array[3]}) debe ser mayor al inicio (.${ref_array[3]})\e[0m"
                return 1
            fi
        fi
    fi
    return 0
}
