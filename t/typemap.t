# t/typemap.t
#
# Test LJ::Typemap
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More tests => 42;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Typemap;
use LJ::Test;

my $table = 'statkeylist';
my $classfield = 'name';
my $idfield = 'statkeyid';

sub run_tests {
    my $tm;

    {
        # create bogus typemaps
        eval { LJ::Typemap->new() };
        like($@, qr/No table/, "No table passed");
        eval { LJ::Typemap->new(table => 'bogus"', idfield => $idfield, classfield => $classfield) };
        like($@, qr/Invalid arguments/, "Invalid arguments");

        # create a typemap
        $tm = eval { LJ::Typemap->new(table => $table, idfield => $idfield, classfield => $classfield) };
        ok($tm, "Got typemap");

        # test singletonage
        my $tm2 = eval { LJ::Typemap->new(table => $table, idfield => $idfield, classfield => $classfield) };
        is($tm2, $tm, "Got singleton");

    }

    {
        # try to look up nonexistant typeid
        eval { $tm->typeid_to_class(9999) };
        like($@, qr/No class for id/, "Invalid class id");

        my $class = 'oogabooga';

        # insert a new class that shouldn't exist, should get a typeid
        my $id = $tm->class_to_typeid($class);
        ok(defined $id, "$class id is $id");

        # now look up the id and see if it matches the class
        my $gotclass = $tm->typeid_to_class($id);
        is($gotclass, $class, "Got class: $class for id $id");

        # try and add a typeid for the class ""
        $id = eval { $tm->class_to_typeid("") };
        # make sure it didn't create an id for "NULL"
        like($@, qr/no class specified/i, "Did not create a null mapping");


        # get all classes, make sure our class is in it
        my @classes = $tm->all_classes;
        ok(scalar (grep { $_ eq $class } @classes), "Our class is in list of all classes");

        # delete the map
        ok($tm->delete_class($class), "Deleting class");

        # make sure class is gone
        ok(! eval { $tm->typeid_to_class($id) }, "Deleted class");

        # recreate class with map_classes function
        ok($id = ($tm->map_classes($class))[0], "Recreated class");

        # make sure class was made
        ok($tm->typeid_to_class($id), "ID lookup on new class");

        # and delete the map once again
        ok($tm->delete_class($class), "Deleted class");
    }
}

memcache_stress {
    run_tests();
}
