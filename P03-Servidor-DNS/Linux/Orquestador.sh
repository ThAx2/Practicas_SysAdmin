sh
# Orquestador

# ===========================================================================
# Script: Orquestador Maestro Modular (DNS / DHCP / RED)
# ===========================================================================

cargar_dependencias() {
    export interfaz="enp0s8"
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    P02_DIR="$SCRIPT_DIR/../../P02-Servidor-DHCP/Linux"

    echo "[*] Usando interfaz: $interfaz"
    echo "[*] Buscando dependencias en: $P02_DIR"

    if [ -d "$P02_DIR" ]; then
        source "$P02_DIR/Validar_Red.sh"
        source "$P02_DIR/mon_service.sh"
        source "$P02_DIR/DHCP.sh"
        return 0
    else
        echo -e "\e[31m[!] Error: No se encontró la carpeta P02.\e[0m"
        echo "Ruta intentada: $P02_DIR"
        exit 1
    fi
}

check_red_lista() {
    local ip_actual=$(ip -4 addr show "$interfaz" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    
    if [[ -z "$ip_actual" || "$ip_actual" == *.0 ]]; then
        return 1
    fi
    return 0
}

Configurar_DNS(){
    local servicio="bind9"
    local dominio="" 

    mon_service "$servicio"

    if ! check_red_lista; then
        echo -e "\n[*] Red no configurada. Iniciando asistente..."
        configurar_Red "$interfaz"
    fi

    until valid_dominio "$dominio"; do
        read -p "Ingrese el nombre de dominio a configurar (ej: reprobados.com): " dominio
        read -p "Ingrese el nombre de dominio a configurar (ej: yajalav.com): " dominio
    done

    configurar_Red 
    
    local ip_fija=$(ip -4 addr show $interfaz | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    local ip_fija=$(ip -4 addr show "$interfaz" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)

    if [[ -z "$ip_fija" ]]; then
        echo -e "\e[31m[!] Error: No hay IP en $interfaz.\e[0m"
        return 1
    fi
    echo -e "\n[*] Configurando zona: $dominio"
    echo "zone \"$dominio\" { type master; file \"/etc/bind/db.$dominio\"; };" > /etc/bind/named.conf.local

    echo -e "\n[*] Configurando zona: $dominio en named.conf.local"
    
    cat <<EOF > /etc/bind/named.conf.local
zone "$dominio" {
    type master;
    file "/etc/bind/db.$dominio";
};
EOF

    echo "[*] Creando archivo de zona: /etc/bind/db.$dominio"
    cat <<EOF > /etc/bind/db.$dominio
\$TTL    604800
@       IN      SOA     ns.$dominio. root.$dominio. (
                              1         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      SOA     ns.$dominio. root.$dominio. ( 1; 604800; 86400; 2419200; 604800 )
@       IN      NS      ns.$dominio.
@       IN      A       $ip_fija
ns      IN      A       $ip_fija
www     IN      CNAME   $dominio.
EOF

    named-checkconf /etc/bind/named.conf.local && named-checkzone "$dominio" "/etc/bind/db.$dominio"
    
    if [ $? -eq 0 ]; then
        systemctl restart "$servicio"
        echo -e "\e[32m[OK] DNS funcionando en $ip_fija\e[0m"
        nslookup "$dominio" 127.0.0.1
    else
        echo -e "\e[31m[!] Error de sintaxis en BIND9.\e[0m"
        echo -e "\e[31m[!] Error en archivos de zona.\e[0m"
    fi
}

menu_dns(){
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    P02_DIR="$SCRIPT_DIR/../../P02-Servidor-DHCP/Linux"
    interfaz="enp0s8" 
echo "[*] Usando interfaz: $interfaz"
    echo "[*] Buscando dependencias en: $P02_DIR"

    if [ -d "$P02_DIR" ]; then
        source "$P02_DIR/Validar_Red.sh"
        source "$P02_DIR/mon_service.sh"
        source "$P02_DIR/DHCP.sh" 
    else
        echo -e "\e[31m[!] Error: No se encontró la carpeta P02.\e[0m"
        echo "Ruta intentada: $P02_DIR"
        exit 1
    fi
menu_principal(){
    cargar_dependencias 
    
    while true; do
        echo -e "\n===================================="
        echo "            ORQUESTADOR             "
        echo "      ORQUESTADOR MULTIMÓDULO       "
        echo "===================================="
        echo "1) Configurar Servidor DHCP"
        echo "2) Configurar Servidor DNS"
        echo "3) Configuracion de Red"
        echo "4) Monitoreo de Servicios"
        echo "3) Configuración de Red Manual"
        echo "4) Estatus de Servicios"
        echo "5) Salir"
        echo "------------------------------------"
        read -p "Opción: " opcion 

        case $opcion in
            1) servicio="isc-dhcp-server"; configurar_dhcp ;;
            2) servicio="bind9"; Configurar_DNS ;;
            3) configurar_Red ;;
            1) check_red_lista || configurar_Red "$interfaz"; configurar_dhcp ;;
            2) Configurar_DNS ;;
            3) configurar_Red "$interfaz" ;;
            4) 
                echo -e "\n--- Estatus ---"
                echo "DHCP: $(systemctl is-active isc-dhcp-server)"
                echo "DNS:  $(systemctl is-active bind9)"
                ip -4 addr show "$interfaz" | grep inet
                ;;
            5) exit 0 ;;
            *) echo "Opción no válida." ;;
        esac
    done
}

[[ $EUID -ne 0 ]] && echo "Ocupas ejecutarlo como "sudo"	" && exit 1

menu_dns
[[ $EUID -ne 0 ]] && echo "Ejecutar con sudo" && exit 1
menu_principal
