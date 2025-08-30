set -xe

# Get database going, all we need for now
service mysql start

# Basic config
mysql -u root -e "\
    CREATE DATABASE IF NOT EXISTS dw_global CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
    CREATE DATABASE IF NOT EXISTS dw_cluster01 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
    CREATE DATABASE IF NOT EXISTS dw_schwartz CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
    CREATE USER IF NOT EXISTS 'dw'@'localhost' IDENTIFIED BY 'dw'; \
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

# Set up apache config
rm -rf /etc/apache2
ln -s $LJHOME/.devcontainer/config/etc/apache2 /etc/apache2

# Start services and boom!
service memcached start
/usr/sbin/apache2ctl -DFOREGROUND
