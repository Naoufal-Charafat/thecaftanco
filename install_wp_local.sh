#!/usr/bin/env bash
# install_wp_local.sh — despliega WordPress + dependencias en localhost
set -euo pipefail
IFS=$'\n\t'

##################### CONFIGURACIÓN ###########################################
SITE_DOMAIN="thecaftan.local"       # Nombre de dominio local (añadido a /etc/hosts)
DB_NAME="wp_caftan"
DB_USER="wp_user"
DB_PASS="$(openssl rand -base64 16)"   # Genera una contraseña aleatoria
WP_ADMIN="admin"
WP_ADMIN_PASS="$(openssl rand -base64 16)"
WP_ADMIN_EMAIL="admin@example.com"
WEB_ROOT="/var/www/$SITE_DOMAIN"
PHP_VERSION="8.4"                    # Cambiar si usas otra versión disponible
###############################################################################

log(){ printf "\e[32m>> %s\e[0m\n" "$1"; }

need_root(){
   if [[ $EUID -ne 0 ]]; then
      echo "Este script debe ejecutarse como root." >&2; exit 1
   fi
}

install_packages(){
  log "Actualizando repos e instalando paquetes..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -yq \
    apache2 mariadb-server php${PHP_VERSION} php${PHP_VERSION}-{common,curl,gd,mbstring,xml,zip,mysql} \
    libapache2-mod-php${PHP_VERSION} curl unzip wget less
}

configure_mariadb(){
  log "Configurando MariaDB y creando base de datos..."
  systemctl enable --now mariadb
  mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
}

download_wordpress(){
  log "Descargando WordPress..."
  mkdir -p "$WEB_ROOT"
  curl -sL https://wordpress.org/latest.tar.gz | tar -xz --strip-components=1 -C "$WEB_ROOT"
  cp "$WEB_ROOT/wp-config-sample.php" "$WEB_ROOT/wp-config.php"
  sed -i "s/database_name_here/${DB_NAME}/" "$WEB_ROOT/wp-config.php"
  sed -i "s/username_here/${DB_USER}/" "$WEB_ROOT/wp-config.php"
  sed -i "s/password_here/${DB_PASS}/" "$WEB_ROOT/wp-config.php"
  log "Añadiendo claves únicas de seguridad..."
  SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
  sed -i "/AUTH_KEY/,$ d" "$WEB_ROOT/wp-config.php"
  printf '%s\n' "$SALTS" >> "$WEB_ROOT/wp-config.php"
}

configure_apache(){
  log "Configurando host virtual en Apache..."
  cat > /etc/apache2/sites-available/${SITE_DOMAIN}.conf <<VHOST
<VirtualHost *:80>
    ServerName ${SITE_DOMAIN}
    DocumentRoot ${WEB_ROOT}
    <Directory ${WEB_ROOT}>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/${SITE_DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${SITE_DOMAIN}_access.log combined
</VirtualHost>
VHOST

  a2enmod rewrite
  a2ensite ${SITE_DOMAIN}.conf
  systemctl reload apache2
  echo "127.0.0.1  ${SITE_DOMAIN}" >> /etc/hosts
}

set_permissions(){
  log "Ajustando permisos..."
  chown -R www-data:www-data "$WEB_ROOT"
  find "$WEB_ROOT" -type d -exec chmod 755 {} \;
  find "$WEB_ROOT" -type f -exec chmod 644 {} \;
}

install_wp_cli(){
  log "Instalando WP-CLI..."
  curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  php wp-cli.phar --info >/dev/null
  chmod +x wp-cli.phar
  mv wp-cli.phar /usr/local/bin/wp
}

bootstrap_wordpress(){
  log "Inicializando sitio WordPress (WP-CLI)..."
  sudo -u www-data wp core install \
    --url="http://${SITE_DOMAIN}" \
    --title="The Caftan Co" \
    --admin_user="${WP_ADMIN}" \
    --admin_password="${WP_ADMIN_PASS}" \
    --admin_email="${WP_ADMIN_EMAIL}" \
    --path="${WEB_ROOT}" --skip-email
}

print_credentials(){
  cat <<EOF

========================================
WordPress instalado correctamente 🎉
URL:   http://${SITE_DOMAIN}
Admin: ${WP_ADMIN}
Pass:  ${WP_ADMIN_PASS}

Base de datos:
  nombre  : ${DB_NAME}
  usuario : ${DB_USER}
  clave   : ${DB_PASS}
========================================
Añade "127.0.0.1 ${SITE_DOMAIN}" a tu archivo hosts si no se añadió automáticamente.
EOF
}

main(){
  need_root
  install_packages
  configure_mariadb
  download_wordpress
  configure_apache
  set_permissions
  install_wp_cli
  bootstrap_wordpress
  print_credentials
}

main "$@"
