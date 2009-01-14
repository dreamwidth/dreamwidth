#!/usr/bin/perl

package LJ::ModuleLoader;

use strict;
use IO::Dir;
require Exporter;
use vars qw(@ISA @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(module_subclasses);

# given a module name, looks under cgi-bin/ for its patch and, if valid,
# returns (assumed) package names of all modules in the directory
sub module_subclasses {
    shift if @_ > 1; # get rid of classname
    my $base_class = shift;
    my $base_path  = "$LJ::HOME/cgi-bin/" . join("/", split("::", $base_class));
    die "invalid base: $base_class" unless -d $base_path;

    my @dirs = $base_path;
    my @files;
    while (@dirs) {
        my $dir = shift @dirs;
        my $d = IO::Dir->new($dir);
        while (my $file = $d->read) {
            if ($file =~ /^\./) {
                next;
            }
            elsif ($file =~ /\.pm$/) {
                push @files, "$dir/$file";
            }
            elsif (-d "$dir/$file") {
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
    shift if @_ > 1; # get rid of classname
    my $base_class = shift;

    foreach my $class (LJ::ModuleLoader->module_subclasses($base_class)) {
        eval "use Class::Autouse qw($class)";
        die "Error loading $class: $@" if $@;
    }
}

sub require_if_exists {
    shift if @_ > 1; # get rid of classname

    my $req_file = shift;

    # allow caller to pass in "filename.pl", which will be
    # assumed in $LJHOME/cgi-bin/, otherwise a full path
    $req_file = "$LJ::HOME/cgi-bin/$req_file"
        unless $req_file =~ m!/!;

    # lib should return 1
    if (-e $req_file) {
        my $rv = do $req_file;
        warn $@ if $@;
        return $rv;
    }

    # no library loaded, return 0
    return 0;
}

# FIXME: This should do more...

1;
