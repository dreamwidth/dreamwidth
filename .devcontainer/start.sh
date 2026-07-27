set -xe

# Start services
service mysql start
service memcached start
mkdir -p $LJHOME/logs

# Plack/Starman on port 8080
perl bin/starman --port 8080 --log $LJHOME/logs --daemonize
