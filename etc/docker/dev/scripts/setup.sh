#!/bin/bash
#
# Designed to be run as part of the Docker setup. Do not run this
# script manually.
#

set -xe

service mysql start

# Make the databases
for DB in dw_global dw_cluster01 dw_schwartz; do
    echo "CREATE DATABASE $DB;" | mysql -uroot -ppassword || true
done
cat $LJHOME/doc/schwartz-schema.sql | mysql -uroot -ppassword dw_schwartz || true

# Validate that the system is set up and working correctly.
perl -I$LJHOME/extlib/lib/perl5 $LJHOME/bin/checkconfig.pl

# initial database update, these run twice since we need dbnotes so we can run
# the alters and record them
perl -I$LJHOME/extlib/lib/perl5 $LJHOME/bin/upgrading/update-db.pl -r
perl -I$LJHOME/extlib/lib/perl5 $LJHOME/bin/upgrading/update-db.pl -r
perl -I$LJHOME/extlib/lib/perl5 $LJHOME/bin/upgrading/update-db.pl -r --cluster=all
perl -I$LJHOME/extlib/lib/perl5 $LJHOME/bin/upgrading/update-db.pl -r --cluster=all
perl -I$LJHOME/extlib/lib/perl5 $LJHOME/bin/upgrading/update-db.pl -r -p

# populate some language files
perl -I$LJHOME/extlib/lib/perl5 $LJHOME/bin/upgrading/texttool.pl load

# make the system account
# commented out until this works to create a random password (or a boring default
# like 'password')
# perl -I$LJHOME/extlib/lib/perl5 $LJHOME/bin/upgrading/make_system.pl

# config apache
mkdir $LJHOME/ext/local/etc/apache2/sites-enabled || true
cp $LJHOME/ext/local/dreamwidth-dev.conf $LJHOME/ext/local/etc/apache2/sites-enabled/dreamwidth.conf
rm -rf /etc/apache2
ln -s $LJHOME/ext/local/etc/apache2 /etc/apache2
