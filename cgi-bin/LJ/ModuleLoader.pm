#!/usr/bin/perl
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

package LJ::ModuleLoader;

use strict;
use IO::Dir;
require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(module_subclasses);

use DW;
use LJ::Directories;

# given a module name, looks under cgi-bin/ for its patch and, if valid,
# returns (assumed) package names of all modules in the directory
sub module_subclasses {
    shift if @_ > 1;    # get rid of classname
    my $base_class = shift;
    my $base_path  = join( "/", 'cgi-bin', split( "::", $base_class ) );

    my @dirs = LJ::get_all_directories($base_path);

    my @files;
    while (@dirs) {
        my $dir = shift @dirs;
        my $d   = IO::Dir->new($dir);
        while ( my $file = $d->read ) {
            if ( $file =~ /^\./ ) {
                next;
            }
            elsif ( $file =~ /\.pm$/ ) {
                push @files, "$dir/$file";
            }
            elsif ( -d "$dir/$file" ) {
                push @dirs, "$dir/$file";
            }
        }
        $d->close;
    }

    return map {
        s!.+cgi-bin/!!;
        s!/!::!g;
        s/\.pm$//;
        $_;
    } @files;
}

sub autouse_subclasses {
    shift if @_ > 1;    # get rid of classname
    my $base_class = shift;

    foreach my $class ( LJ::ModuleLoader->module_subclasses($base_class) ) {
        eval "use Class::Autouse qw($class)";
        die "Error loading $class: $@" if $@;
    }
}

sub require_subclasses {
    shift if @_ > 1;    # get rid of classname
    my $base_class = shift;

    foreach my $class ( LJ::ModuleLoader->module_subclasses($base_class) ) {
        eval "use $class";
        die "Error loading $class: $@" if $@;
    }
}

sub require_if_exists {
    shift if @_ > 1;    # get rid of classname

    my $req_file = shift;

    # allow caller to pass in "filename.pl", which will be
    # assumed in $LJHOME/cgi-bin/, otherwise a full path
    $req_file = DW->home . "/cgi-bin/$req_file"
        unless $req_file =~ m!/!;

    # lib should return 1
    if ( -e $req_file ) {
        my $rv = do $req_file;
        warn $@ if $@;
        return $rv;
    }

    # no library loaded, return 0
    return 0;
}

# FIXME: This should do more...

1;
