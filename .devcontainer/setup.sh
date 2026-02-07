set -xe

# Instantiate our configs
mkdir -p $LJHOME/ext/local
ln -ns $LJHOME/.devcontainer/config/etc/dw-etc $LJHOME/ext/local/etc || true

# Get database going, all we need for now
service mysql start

# Basic config (all IF NOT EXISTS — instant no-op when pre-baked)
mysql -u root -e "\
    CREATE DATABASE IF NOT EXISTS dw_global CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
    CREATE DATABASE IF NOT EXISTS dw_cluster01 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
    CREATE DATABASE IF NOT EXISTS dw_schwartz CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
    CREATE USER IF NOT EXISTS 'dw'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY 'dw'; \
    CREATE USER IF NOT EXISTS 'dw'@'localhost' IDENTIFIED WITH mysql_native_password BY 'dw'; \
    GRANT ALL PRIVILEGES ON dw_global.* TO 'dw'@'127.0.0.1'; \
    GRANT ALL PRIVILEGES ON dw_cluster01.* TO 'dw'@'127.0.0.1'; \
    GRANT ALL PRIVILEGES ON dw_schwartz.* TO 'dw'@'127.0.0.1'; \
    GRANT ALL PRIVILEGES ON dw_global.* TO 'dw'@'localhost'; \
    GRANT ALL PRIVILEGES ON dw_cluster01.* TO 'dw'@'localhost'; \
    GRANT ALL PRIVILEGES ON dw_schwartz.* TO 'dw'@'localhost'; \
    FLUSH PRIVILEGES;"

# Configure database and load initial data (idempotent — instant when no new migrations)
bin/upgrading/update-db.pl -r
bin/upgrading/update-db.pl -r --cluster=all
bin/upgrading/update-db.pl -r -p
bin/upgrading/texttool.pl load

# Set up testing database(s)
t/bin/initialize-db

# Symlink pre-built static assets from the image.
# If you change CSS/JS, run bin/build-static.sh — writes go through the symlink.
mkdir -p $LJHOME/build
ln -snf /opt/dreamwidth-static $LJHOME/build/static

# Set up apache config
rm -rf /etc/apache2
ln -ns $LJHOME/.devcontainer/config/etc/apache2 /etc/apache2 || true
