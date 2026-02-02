set -xe

# Instantiate our configs
mkdir -p $LJHOME/ext/local
ln -ns $LJHOME/.devcontainer/config/etc/dw-etc $LJHOME/ext/local/etc || true

# Get database going, all we need for now
service mysql start

# Basic config
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
cat $LJHOME/doc/schwartz-schema.sql | mysql -u root dw_schwartz

# Configure database and load initial data
bin/upgrading/update-db.pl -r
bin/upgrading/update-db.pl -r --cluster=all
bin/upgrading/update-db.pl -r -p
bin/upgrading/texttool.pl load

# Set up testing database(s)
t/bin/initialize-db

# Compile static files for usage
mkdir $LJHOME/ext/yuicompressor/ && \
    curl -s -L --output $LJHOME/ext/yuicompressor/yuicompressor.jar \
        https://github.com/yui/yuicompressor/releases/download/v2.4.8/yuicompressor-2.4.8.jar
bin/build-static.sh

# Set up apache config
rm -rf /etc/apache2
ln -ns $LJHOME/.devcontainer/config/etc/apache2 /etc/apache2 || true
