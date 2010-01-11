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
#
# This module knows about all LJ configuration variables, their types,
# and validator functions, so missing, incorrect, deprecated, or
# outdated configuration can be brought to the admin's attention.
#

package LJ::ConfCheck;

use strict;
no strict 'refs';

my %singleton;  # key -> 1

my %conf;

require LJ::ConfCheck::General;
eval { require LJ::ConfCheck::Local; };
die "eval error: $@" if $@ && $@ !~ /^Can\'t locate/;

# these variables are LJ-application singletons, and not configuration:

sub add_singletons {
    foreach (@_) {
        $singleton{$_} = 1;
    }
}

sub add_conf {
    my $key = shift;
    my %opts = @_;
    $conf{$key} = \%opts;
}

sub get_keys {
    my %seen;   # $FOO -> 1

    my $package = "main::LJ::";
    use vars qw(*stab *thingy);
    *stab = *{"main::"};

    while ($package =~ /(\w+?::)/g) {
        *stab = ${stab}{$1};
    }

    while (my ($key,$val) = each(%stab)) {
        return if $DB::signal;
        next if $key =~ /[a-z]/ || $key =~ /::$/;

        my @new;
        local *thingy = $val;
        if (defined $thingy) {
            push @new, "\$$key";
        }
        if (defined @thingy) {
            push @new, "\@$key";
        }
        if (defined %thingy) {
            push @new, "\%$key";
        }
        foreach my $sym (@new) {
            $seen{$sym} = 1;
        }
    }

    if ($ENV{READ_LJ_SOURCE}) {
        chdir $LJ::HOME or die;
        my @lines = `grep -Er '[\$\@\%]LJ::[A-Z_]+\\b' cgi-bin htdocs bin ssldocs`;
        foreach my $line (@lines) {
            next if $line =~ m!~:!;  # ignore emacs backup files
            $line =~ s/\#.*//; # ignore everything after the start of a comment
            while ($line =~ s/[^\\]([\$\@\%])LJ::(([A-Z0-9_]|::)+)\b([\{\[]?)//) {
                my ($sigil, $sym, $deref) = ($1, $2, $4);
                next if $sym =~ /^(CACHE|REQ_)/; # these are all internal caches/memoizations.
                next if $sym =~ /^(HAVE|OPTMOD)_/; # these are all module-check booleans
                $sigil = "%" if $sigil eq '$' && $deref eq "{";
                $sigil = '@' if $sigil eq '$' && $deref eq "[";
                $seen{"$sigil$sym"} = 1;
            }
        }
    }

    return sort keys %seen;
}

sub config_errors {
    my %ok;
    my @errors;

    # iter through all config, check if okay

    my @keys = get_keys();
    foreach my $k (@keys) {
        if (!$conf{$k} && !$singleton{$k}) {
            push @errors, "Unknown config option: $k";
        }
    }
    return @errors;
}

sub conf { %conf }

1;
