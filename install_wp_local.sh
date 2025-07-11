#!/usr/bin/env bash
set -euo pipefail

#####  CONFIGURA AQUÍ TUS VARIABLES  #####
WP_VERSION="6.8.1"                # Última versión estable (30 abr 2025) :contentReference[oaicite:0]{index=0}
SITE_PATH="/var/www/html/the-caftan-co"
DB_NAME="caftan_db"
DB_USER="caftan_user"
DB_PASS="changeme"
WP_URL="http://localhost/the-caftan-co"
WP_TITLE="The Caftan Co"
WP_ADMIN="admin"
WP_ADMIN_PASS="admin123"
WP_ADMIN_EMAIL="admin@example.com"
#########################################

echo "==> Instalando dependencias del servidor web y PHP"
if command -v apt-get &>/dev/null; then
  PM="apt-get"
elif command -v dnf &>/dev/null; then
  PM="dnf"
elif command -v pacman &>/dev/null; then
  PM="pacman -S --noconfirm"
else
  echo "❌ No se encontró un gestor de paquetes compatible (apt, dnf, pacman)."
  exit 1
fi

sudo $PM update -y
sudo $PM install -y apache2 mariadb-server php php-mysql php-xml php-curl php-gd php-zip php-mbstring php-intl unzip curl

echo "==> Habilitando y arrancando Apache y MariaDB"
sudo systemctl enable --now apache2 mariadb

echo "==> Creando base de datos y usuario"
sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
sudo mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"

echo "==> Instalando WP-CLI (método phar recomendado) :contentReference[oaicite:1]{index=1}"
if ! command -v wp &>/dev/null; then
  curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  php wp-cli.phar --info   # prueba rápida
  chmod +x wp-cli.phar
  sudo mv wp-cli.phar /usr/local/bin/wp
fi

echo "==> Descargando WordPress $WP_VERSION"
sudo mkdir -p "$SITE_PATH" && sudo chown "$USER":www-data "$SITE_PATH"
cd "$SITE_PATH"
wp core download --version="$WP_VERSION"

echo "==> Generando wp-config.php y salts"
cp wp-config-sample.php wp-config.php
wp config set DB_NAME "$DB_NAME"
wp config set DB_USER "$DB_USER"
wp config set DB_PASSWORD "$DB_PASS"
wp config set WP_DEBUG true
wp config shuffle-salts

echo "==> Instalando WordPress"
wp core install \
  --url="$WP_URL" \
  --title="$WP_TITLE" \
  --admin_user="$WP_ADMIN" \
  --admin_password="$WP_ADMIN_PASS" \
  --admin_email="$WP_ADMIN_EMAIL"

echo "==> Ajustando permisos finales"
sudo chown -R www-data:www-data "$SITE_PATH"

echo "✅ WordPress $WP_VERSION está listo en $WP_URL"
