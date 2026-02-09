# ===========================================================================
# Script: Validador de Red
# Author: Alexander Vega / Ax2 - / Codigo principal tomado de: https://www.linuxjournal.com/content/validating-ip-address-bash-script + Validacion que IP Inicial sea menor a la IP Final
# Fecha: 06/02/2026
# Funcion = valid_ip()
# Descripcion = Valida el formato IPv4 (0-255) mediante Regex y asegura la 
#               integridad del rango comparando el cuarto octeto final vs inicial, obtiene la ip una vez validada, la deshace en un array separando los octetos y analizandolos/comparandolos individualmente a excepcion del ultimo octeto que compara con ip de incio para verificar la coherencia en el rango.
# Parametros = $1 - IP a validar / $2 - IP de inicio (para comparar rangos) | Funciona con un parametro para verificar la base de la ip y dos para verificar rangos.
# ===========================================================================
function valid_ip(){
    local ip=$1
    local ip_inicio=$2  
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip_array=($ip) 
        IFS=$OIFS
        
        [[ ${ip_array[0]} -le 255 && ${ip_array[1]} -le 255 \
            && ${ip_array[2]} -le 255 && ${ip_array[3]} -le 255 ]]
        stat=$?

        if [[ $stat -eq 0 && -n $ip_inicio ]]; then
            octeto_inicio=$(echo $ip_inicio | cut -d'.' -f4)
            octeto_final=${ip_array[3]}

            if [[ $octeto_final -le $octeto_inicio ]]; then
                echo "Error: La IP final ($octeto_final) debe ser mayor a la inicial ($octeto_inicio)."
                stat=1
            fi
        fi
    fi
    return $stat
}
