#!/bin/bash

set -xe

# Make the databases
for DB in dw_global dw_cluster1 dw_schwartz; do
    echo "CREATE DATABASE $DB;" | mysql -hmysql -uroot -ppassword || true
done
cat $LJHOME/doc/schwartz-schema.sql | mysql -hmysql -uroot -ppassword dw_schwartz || true

perl -I$LJHOME/extlib/ $LJHOME/bin/upgrading/update-db.pl -r -p
perl -I$LJHOME/extlib/ $LJHOME/bin/upgrading/update-db.pl -r -p
perl -I$LJHOME/extlib/ $LJHOME/bin/upgrading/update-db.pl -r --cluster=all
perl -I$LJHOME/extlib/ $LJHOME/bin/upgrading/update-db.pl -r --cluster=all
perl -I$LJHOME/extlib/ $LJHOME/bin/upgrading/texttool.pl load

# Validate that the system is set up and working correctly.
perl -I$LJHOME/extlib/ $LJHOME/bin/checkconfig.pl

# Kick off Starman in the foreground (port 8080). exec so it replaces this shell
# as PID 1 and receives SIGTERM/SIGINT directly.
exec perl $LJHOME/bin/starman --port 8080
