set -xe

# Start services
service mysql start
service memcached start
mkdir -p $LJHOME/logs

# Plack/Starman on port 80
perl bin/starman --port 80 --log $LJHOME/logs --daemonize

# Apache available on port 8081 if needed: apache2ctl start
