#!/bin/bash

# ----------------------------------------------------------------
INFRA_RED="infra_red"
INFRA_SUBNET="172.20.0.0/16"
VOL_DB="db_data"
VOL_WEB="web_content"
DIR_BACKUP="/opt/docker/backups/postgres"
DIR_FTP="/opt/docker/ftp"
DIR_WEB="/opt/docker/web"



# ----------------------------------------------------------------
# MENU PRINCIPAL DOCKER
# ----------------------------------------------------------------
menu_docker() {
    while true; do
        echo -e "\n======================================"
        echo -e "     MODULO DOCKER - P10 INFRA"
        echo -e "======================================"
        echo "1)  Instalar Docker"
        echo "2)  Setup Completo (Red + Volumes + Servicios)"
        echo "3)  Listar Contenedores"
        echo "4)  Crear Contenedor Simple"
        echo "5)  Iniciar Contenedor"
        echo "6)  Detener Contenedor"
        echo "7)  Eliminar Contenedor"
        echo "8)  Ver Stats de Recursos"
        echo "9)  Backup Manual PostgreSQL"
        echo "10) Volver al Menu Principal"
        read -p "Opcion: " docker_opcion
        case $docker_opcion in
            1)  instalar_docker ;;
            2)  setup_completo ;;
            3)  listar_contenedores ;;
            4)  crear_contenedor ;;
            5)  iniciar_contenedor ;;
            6)  detener_contenedor ;;
            7)  eliminar_contenedor ;;
            8)  ver_stats ;;
            9)  backup_postgres ;;
            10) break ;;
            *) echo -e "\e[31m[!] Opcion invalida.\e[0m" ;;
        esac
    done
}

# ----------------------------------------------------------------
# INSTALAR DOCKER usando mon_servicer
# ----------------------------------------------------------------
instalar_docker() {
    echo -e "\n[*] Configurando repositorios Docker..."
    apt-get update > /dev/null 2>&1
    apt-get install -y ca-certificates curl gnupg lsb-release > /dev/null 2>&1
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | \
        gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg > /dev/null 2>&1
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update > /dev/null 2>&1

    mon_servicer "docker-ce"
    
    echo -e "\e[32m[OK] Docker instalado: $(docker --version)\e[0m"
}

# ----------------------------------------------------------------
# SETUP COMPLETO
# ----------------------------------------------------------------
setup_completo() {
    echo -e "\n[*] Iniciando Setup Completo de Infraestructura..."
    crear_red
    crear_volumenes
    crear_directorios
    crear_dockerfile_web
    construir_imagen_web
    crear_contenedor_web
    crear_contenedor_postgres
    crear_contenedor_ftp
    configurar_backup_automatico
    echo -e "\n\e[32m[OK] Setup completo finalizado.\e[0m"
    listar_contenedores
}

# ----------------------------------------------------------------
# RED PERSONALIZADA
# ----------------------------------------------------------------
crear_red() {
    echo -e "\n[*] Configurando red $INFRA_RED ($INFRA_SUBNET)..."
    if docker network ls | grep -q "$INFRA_RED"; then
        echo -e "\e[33m[*] Red $INFRA_RED ya existe.\e[0m"
    else
        docker network create --driver bridge --subnet "$INFRA_SUBNET" "$INFRA_RED"
        echo -e "\e[32m[OK] Red $INFRA_RED creada.\e[0m"
    fi
}

# ----------------------------------------------------------------
# VOLUMENES PERSISTENTES
# ----------------------------------------------------------------
crear_volumenes() {
    echo -e "\n[*] Creando volumenes persistentes..."
    for vol in "$VOL_DB" "$VOL_WEB"; do
        if docker volume ls | grep -q "$vol"; then
            echo -e "\e[33m[*] Volumen $vol ya existe.\e[0m"
        else
            docker volume create "$vol"
            echo -e "\e[32m[OK] Volumen $vol creado.\e[0m"
        fi
    done
}

# ----------------------------------------------------------------
# DIRECTORIOS EN EL HOST
# ----------------------------------------------------------------
crear_directorios() {
    echo -e "\n[*] Creando directorios en el host..."
    mkdir -p "$DIR_BACKUP" "$DIR_FTP" "$DIR_WEB"
    chmod 777 "$DIR_FTP"
    echo -e "\e[32m[OK] Directorios creados.\e[0m"
}

# ----------------------------------------------------------------
# DOCKERFILE PERSONALIZADO PARA WEB
# ----------------------------------------------------------------
crear_dockerfile_web() {
    echo -e "\n[*] Creando Dockerfile personalizado para servidor web..."
    mkdir -p "$DIR_WEB/html/css" "$DIR_WEB/html/img"

    cat > "$DIR_WEB/html/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Infraestructura P10 - ayala.local</title>
    <link rel="stylesheet" href="css/style.css">
</head>
<body>
    <div class="container">
        <h1>Servidor Web - Docker</h1>
        <p>Dominio: <strong>ayala.local</strong></p>
        <p>Imagen: <strong>Alpine Linux + Nginx</strong></p>
        <img src="img/logo.png" alt="Logo" onerror="this.style.display='none'">
        <div class="status">
            <span class="badge">Estado: Activo</span>
            <span class="badge">Red: infra_red</span>
        </div>
    </div>
</body>
</html>
EOF

    cat > "$DIR_WEB/html/css/style.css" << 'EOF'
body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee; margin: 0; }
.container { max-width: 800px; margin: 100px auto; text-align: center; padding: 2rem; background: #16213e; border-radius: 12px; }
h1 { color: #fff; background: #e94560; padding: 1rem; border-radius: 8px; }
.badge { display: inline-block; background: #0f3460; padding: 0.5rem 1rem; border-radius: 20px; margin: 0.5rem; }
EOF

    cat > "$DIR_WEB/Dockerfile" << 'EOF'
FROM alpine:3.19

RUN apk add --no-cache nginx && \
    adduser -D -H -s /sbin/nologin webuser && \
    mkdir -p /var/log/nginx /run/nginx && \
    chown -R webuser:webuser /var/log/nginx /run/nginx

COPY html/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/nginx.conf

USER webuser
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

    cat > "$DIR_WEB/nginx.conf" << 'EOF'
worker_processes 1;
events { worker_connections 1024; }
http {
    server_tokens off;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    server {
        listen 80;
        server_name localhost;
        root /usr/share/nginx/html;
        index index.html;
    }
}
EOF

    echo -e "\e[32m[OK] Dockerfile y archivos web creados en $DIR_WEB\e[0m"
}

# ----------------------------------------------------------------
# CONSTRUIR IMAGEN WEB
# ----------------------------------------------------------------
construir_imagen_web() {
    echo -e "\n[*] Construyendo imagen personalizada nginx-custom..."
    docker build -t nginx-custom "$DIR_WEB"
    if [ $? -eq 0 ]; then
        echo -e "\e[32m[OK] Imagen nginx-custom construida.\e[0m"
    else
        echo -e "\e[31m[!] Error al construir imagen.\e[0m"
    fi
}

# ----------------------------------------------------------------
# CONTENEDOR WEB
# ----------------------------------------------------------------
crear_contenedor_web() {
    echo -e "\n[*] Creando contenedor web..."
    docker rm -f web_server 2>/dev/null
    docker run -d \
        --name web_server \
        --network "$INFRA_RED" \
        --ip 172.20.0.10 \
        -p 80:80 \
        -v "$VOL_WEB":/usr/share/nginx/html \
        --memory="512m" \
        --cpus="0.5" \
        nginx-custom
    echo -e "\e[32m[OK] web_server creado (172.20.0.10:80)\e[0m"
}

# ----------------------------------------------------------------
# CONTENEDOR POSTGRESQL
# ----------------------------------------------------------------
crear_contenedor_postgres() {
    echo -e "\n[*] Creando contenedor PostgreSQL..."
    docker rm -f db_postgres 2>/dev/null
    docker run -d \
        --name db_postgres \
        --network "$INFRA_RED" \
        --ip 172.20.0.20 \
        -e POSTGRES_DB=infradb \
        -e POSTGRES_USER=admin \
        -e POSTGRES_PASSWORD=Admin1234! \
        -v "$VOL_DB":/var/lib/postgresql/data \
        -v "$DIR_BACKUP":/backups \
        --memory="512m" \
        --cpus="0.5" \
        postgres:15-alpine
    echo -e "\e[32m[OK] db_postgres creado (172.20.0.20)\e[0m"
}

# ----------------------------------------------------------------
# CONTENEDOR FTP
# ----------------------------------------------------------------
crear_contenedor_ftp() {
    echo -e "\n[*] Creando contenedor FTP..."
    docker rm -f ftp_server 2>/dev/null
    docker run -d \
        --name ftp_server \
        --network "$INFRA_RED" \
        --ip 172.20.0.30 \
        -p 21:21 \
        -p 30000-30009:30000-30009 \
        -e FTP_USER=ftpuser \
        -e FTP_PASS=Ftp1234! \
        -e PASV_MIN_PORT=30000 \
        -e PASV_MAX_PORT=30009 \
        -e PASV_ADDRESS=0.0.0.0 \
        -v "$DIR_FTP":/home/ftpuser \
        -v "$VOL_WEB":/web_content \
        --memory="256m" \
        --cpus="0.25" \
        garethflowers/ftp-server
    echo -e "\e[32m[OK] ftp_server creado (172.20.0.30:21)\e[0m"
}

# ----------------------------------------------------------------
# BACKUP AUTOMATICO POSTGRESQL
# ----------------------------------------------------------------
configurar_backup_automatico() {
    echo -e "\n[*] Configurando backup automatico de PostgreSQL..."
    CRON_CMD="0 2 * * * docker exec db_postgres pg_dump -U admin infradb > $DIR_BACKUP/backup_\$(date +\%Y\%m\%d_\%H\%M).sql 2>/dev/null"
    (crontab -l 2>/dev/null | grep -v "db_postgres"; echo "$CRON_CMD") | crontab -
    echo -e "\e[32m[OK] Backup automatico configurado (2:00 AM diario)\e[0m"
    echo -e "     Destino: $DIR_BACKUP"
}

backup_postgres() {
    echo -e "\n[*] Ejecutando backup manual..."
    BACKUP_FILE="$DIR_BACKUP/backup_$(date +%Y%m%d_%H%M).sql"
    docker exec db_postgres pg_dump -U admin infradb > "$BACKUP_FILE"
    if [ $? -eq 0 ]; then
        echo -e "\e[32m[OK] Backup: $BACKUP_FILE\e[0m"
        ls -lh "$BACKUP_FILE"
    else
        echo -e "\e[31m[!] Error al generar backup.\e[0m"
    fi
}

# ----------------------------------------------------------------
# VER STATS
# ----------------------------------------------------------------
ver_stats() {
    echo -e "\n[*] Stats de contenedores..."
    docker stats --no-stream
}

# ----------------------------------------------------------------
# FUNCIONES BASICAS
# ----------------------------------------------------------------
listar_contenedores() {
    echo -e "\n[*] Listando contenedores..."
    docker ps -a
}

crear_contenedor() {
    echo -e "\n[*] Creando contenedor simple..."
    read -p "Imagen (ej. alpine): " imagen
    read -p "Nombre del contenedor: " nombre_cont
    [[ "$imagen" == "alphine"* ]] && imagen="alpine"
    docker run -d --name "$nombre_cont" --network "$INFRA_RED" "$imagen" sleep 3600
    [ $? -eq 0 ] && echo -e "\e[32m[OK] Contenedor '$nombre_cont' creado.\e[0m" || \
                    echo -e "\e[31m[!] Error al crear contenedor.\e[0m"
}

iniciar_contenedor() {
    read -p "Nombre o ID: " contenedor
    docker start "$contenedor"
}

detener_contenedor() {
    read -p "Nombre o ID: " contenedor
    docker stop "$contenedor"
}

eliminar_contenedor() {
    read -p "Nombre o ID: " contenedor
    docker rm "$contenedor"
}