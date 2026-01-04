#!/bin/bash

# Script para configurar Chroot SSH de forma interactiva
# Requiere permisos de root

# Colores para mejor visualización
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # Sin color

# Verificar que se ejecuta como root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script debe ejecutarse como root${NC}"
   exit 1
fi

echo -e "${GREEN}=== Script de Configuración Chroot SSH ===${NC}\n"

# Función para crear el entorno chroot
crear_entorno_chroot() {
    local chroot_dir=$1
    
    echo -e "${YELLOW}Creando estructura de directorios...${NC}"
    
    # Crear directorios necesarios
    mkdir -p "$chroot_dir"/{bin,lib,lib64,dev,etc,home,usr/{bin,lib,lib64}}
    
    # Configurar permisos (el directorio chroot debe ser propiedad de root)
    chown root:root "$chroot_dir"
    chmod 755 "$chroot_dir"
    
    # Copiar binarios esenciales
    echo -e "${YELLOW}Copiando binarios esenciales...${NC}"
    local bins="bash ls cp mv rm mkdir cat less more nano vi"
    
    for bin in $bins; do
        if command -v $bin &> /dev/null; then
            bin_path=$(which $bin)
            cp "$bin_path" "$chroot_dir/bin/"
            
            # Copiar librerías necesarias
            for lib in $(ldd "$bin_path" | grep -o '/[^ ]*'); do
                if [[ -f "$lib" ]]; then
                    lib_dir=$(dirname "$lib")
                    mkdir -p "$chroot_dir$lib_dir"
                    cp "$lib" "$chroot_dir$lib"
                fi
            done
        fi
    done
    
    # Crear dispositivos necesarios
    echo -e "${YELLOW}Creando dispositivos...${NC}"
    if [ ! -e "$chroot_dir/dev/null" ]; then
        mknod -m 666 "$chroot_dir/dev/null" c 1 3
    fi
    if [ ! -e "$chroot_dir/dev/zero" ]; then
        mknod -m 666 "$chroot_dir/dev/zero" c 1 5
    fi
    
    # Copiar archivos de configuración básicos
    echo -e "${YELLOW}Copiando archivos de configuración...${NC}"
    cp /etc/passwd "$chroot_dir/etc/"
    cp /etc/group "$chroot_dir/etc/"
    
    echo -e "${GREEN}Entorno chroot creado exitosamente${NC}\n"
}

# Función para configurar usuario en chroot
configurar_usuario_chroot() {
    local usuario=$1
    local chroot_dir=$2
    
    # Verificar si el usuario existe
    if ! id "$usuario" &>/dev/null; then
        echo -e "${RED}El usuario '$usuario' no existe${NC}"
        return 1
    fi
    
    # Crear directorio home del usuario dentro del chroot
    local user_home="$chroot_dir/home/$usuario"
    mkdir -p "$user_home"
    chown "$usuario:$usuario" "$user_home"
    chmod 755 "$user_home"
    
    # Configurar sshd_config
    echo -e "${YELLOW}Configurando SSH para el usuario $usuario...${NC}"
    
    # Hacer backup de sshd_config
    if [ ! -f /etc/ssh/sshd_config.backup ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    fi
    
    # Verificar si ya existe configuración de chroot
    if ! grep -q "^Match User $usuario" /etc/ssh/sshd_config; then
        cat >> /etc/ssh/sshd_config << EOF

# Configuración Chroot para $usuario
Match User $usuario
    ChrootDirectory $chroot_dir
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
EOF
        echo -e "${GREEN}Configuración SSH añadida para $usuario${NC}"
    else
        echo -e "${YELLOW}El usuario ya tiene configuración chroot en sshd_config${NC}"
    fi
}

# Función para mostrar usuarios configurados
mostrar_usuarios_chroot() {
    echo -e "${GREEN}Usuarios con chroot configurado:${NC}"
    grep -A 4 "^Match User" /etc/ssh/sshd_config | grep "Match User" | sed 's/Match User /  - /'
    echo ""
}

# Función para eliminar configuración chroot de un usuario
eliminar_chroot_usuario() {
    local usuario=$1
    
    echo -e "${YELLOW}Eliminando configuración chroot para $usuario...${NC}"
    
    # Crear archivo temporal sin la configuración del usuario
    sed -i "/^# Configuración Chroot para $usuario$/,/^$/d" /etc/ssh/sshd_config
    sed -i "/^Match User $usuario$/,/^$/d" /etc/ssh/sshd_config
    
    echo -e "${GREEN}Configuración eliminada${NC}"
}

# Menú principal
while true; do
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}    Menú Configuración Chroot${NC}"
    echo -e "${GREEN}================================${NC}"
    echo "1) Crear/Verificar entorno chroot"
    echo "2) Configurar usuario para chroot"
    echo "3) Mostrar usuarios con chroot"
    echo "4) Eliminar chroot de un usuario"
    echo "5) Reiniciar servicio SSH"
    echo "6) Salir"
    echo -e "${GREEN}================================${NC}"
    read -p "Seleccione una opción: " opcion
    
    case $opcion in
        1)
            read -p "Ingrese el directorio para chroot [/home/chroot]: " chroot_dir
            chroot_dir=${chroot_dir:-/home/chroot}
            crear_entorno_chroot "$chroot_dir"
            read -p "Presione Enter para continuar..."
            ;;
        2)
            read -p "Ingrese el nombre del usuario: " usuario
            read -p "Ingrese el directorio chroot [/home/chroot]: " chroot_dir
            chroot_dir=${chroot_dir:-/home/chroot}
            
            if [ ! -d "$chroot_dir" ]; then
                echo -e "${YELLOW}El directorio chroot no existe. Se creará...${NC}"
                crear_entorno_chroot "$chroot_dir"
            fi
            
            configurar_usuario_chroot "$usuario" "$chroot_dir"
            echo -e "${YELLOW}Recuerde reiniciar el servicio SSH (opción 5)${NC}"
            read -p "Presione Enter para continuar..."
            ;;
        3)
            mostrar_usuarios_chroot
            read -p "Presione Enter para continuar..."
            ;;
        4)
            read -p "Ingrese el nombre del usuario: " usuario
            eliminar_chroot_usuario "$usuario"
            echo -e "${YELLOW}Recuerde reiniciar el servicio SSH (opción 5)${NC}"
            read -p "Presione Enter para continuar..."
            ;;
        5)
            echo -e "${YELLOW}Verificando configuración de SSH...${NC}"
            if sshd -t; then
                echo -e "${GREEN}Configuración SSH correcta${NC}"
                echo -e "${YELLOW}Reiniciando servicio SSH...${NC}"
                systemctl restart sshd || service ssh restart
                echo -e "${GREEN}Servicio SSH reiniciado${NC}"
            else
                echo -e "${RED}Error en la configuración de SSH. No se reiniciará el servicio.${NC}"
            fi
            read -p "Presione Enter para continuar..."
            ;;
        6)
            echo -e "${GREEN}Saliendo...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Opción inválida${NC}"
            read -p "Presione Enter para continuar..."
            ;;
    esac
    
    clear
done
