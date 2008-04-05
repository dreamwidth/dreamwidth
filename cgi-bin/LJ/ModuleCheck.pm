package LJ::ModuleCheck;
use strict;
use warnings;

my %have;

sub have {
    my ($class, $modulename) = @_;
    return $have{$modulename} if exists $have{$modulename};
    die "Bogus module name" unless $modulename =~ /^[\w:]+$/;
    return $have{$modulename} = eval "use $modulename (); 1;";
}

sub have_xmlatom {
    my ($class) = @_;
    return $have{"XML::Atom"} if exists $have{"XML::Atom"};
    return $have{"XML::Atom"} = eval q{
        use XML::Atom::Feed;
        use XML::Atom::Entry;
        use XML::Atom::Link;
        XML::Atom->VERSION < 0.09 ? 0 : 1;
    };
}

1;
