#!/usr/bin/perl
#
# DW::BusinessRules
#
# This module implements the business rules framework. It provides abstract
# functionality required for specific sets of business rules (eg, related to
# invite code distribution), including merging default and site-specific rules.
#
# Authors:
#      Pau Amma <pauamma@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::BusinessRules;
use strict;
use warnings;
use Carp ();
use DW;
use LJ::ModuleLoader;

=head1 NAME

DW::BusinessRules - abstract framework for business rules

=head1 SYNOPSIS

  # Generic (default) rules for pony allocation
  package DW::BusinessRules::Ponies;
  use base 'DW::BusinessRules';

  sub number { # Default pony quota determined by user cap.
      my ($u) = @_;
      return $u->get_cap( 'ponies' );
  }

  sub sparkly { 0 } # No sparkly ponies by default

  DW::BusinessRules::install_overrides(__PACKAGE__, qw(number sparkly) );
  1;

  # Site-specific rules for Foowidth pony allocation
  # Note that this package must be under DW::BusinessRules::Ponies::* for
  # DW::BusinessRules::install_overrides to work properly.
  package DW::BusinessRules::Ponies::Foo;
  use base 'DW::BusinessRules::Ponies';

  # Can have at most 1 sparkly pony
  sub sparkly {
      my ($u) = @_;
      return 0 if grep { $_->sparkly } $u->ponies;
      return 1;
  }

  # Note the conspicuous absence of ::number here.
  1;

  # .bml page somewhere:

  if (DW::BusinessRules::Ponies::number($remote) >= $remote->numponies) {
      # Exhausted pony quota
  } elsif (!DW::BusinessRules::Ponies::sparkly($u)) {
      # Can have a pony, but not a sparkly one
  } else {
      # Can have a sparkly pony
  }

=head1 API

=head2 C<< install_overrides( $pkgname, @funs ) >>

Loads (as if by use) all modules in ${pkgname}::*, then imports into $pkgname
any sub in @funs that one of those defines, after checking that it wasn't
already imported from another. (In other words, it does the same thing as
Exporter->import, and additionally enforces uniqueness across all loaded
modules.) Passing a name not defined as a subroutine in any of the loaded
modules leaves any definition in the caller module unaffected.

Note that you're allowed to pass a name not defined as a subroutine in the
caller module, just as for Exporter-style import.

=cut

sub install_overrides {
    my ( $callpkg, @funs ) = @_;
    my $selfpkg = __PACKAGE__;
    Carp::croak("$callpkg not a descendent of $selfpkg")
        unless $callpkg =~ /^\Q${selfpkg}::\E/;

    my $pkgpath = $callpkg;
    $pkgpath =~ s!::!/!g;
    my @dirs = LJ::get_all_directories("cgi-bin/$pkgpath");
    return unless @dirs;

    my %seen;
    foreach my $dpkg ( LJ::ModuleLoader->module_subclasses($callpkg) ) {
        $pkgpath = $dpkg;
        $pkgpath =~ s!::!/!g;
        require "${pkgpath}.pm";
        foreach my $fname (@funs) {
            no strict 'refs';
            my $subref = "${dpkg}::${fname}";
            next unless defined &$subref;
            Carp::croak("$fname defined in both $dpkg and $seen{$fname}")
                if $seen{$fname};
            $seen{$fname} = $dpkg;
            no warnings 'redefine';
            *{"${callpkg}::${fname}"} = \&$subref;
        }
    }
}

1;

=head1 BUGS

Bound to have some.

=head1 AUTHORS

Pau Amma <pauamma@dreamwidth.org>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.
