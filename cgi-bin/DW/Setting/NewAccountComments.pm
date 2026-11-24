# DW::Setting::NewAccountComments
#
# Minimum account age for commenting in a journal.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::NewAccountComments;
use base 'LJ::Setting';
use strict;
use warnings;

my %options = (
    none   => 'Just Now (no restriction)',
    3600   => '1 hour',
    86400  => '1 day',
    604800 => '1 week',
);

sub should_render {
    my ( $class, $u ) = @_;
    return $u && !$u->is_identity && LJ::get_prop( user => 'opt_min_comment_age' );
}

sub label { 'New Account Comments' }

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $name     = $class->pkgkey . 'min_age';
    my $selected = $class->get_arg( $args, 'min_age' ) || $u->prop('opt_min_comment_age') || 'none';

    my $select = LJ::html_select(
        { name => $name, id => $name, selected => $selected },
        map { $_ => $options{$_} } ( 'none', 3600, 86400, 604800 )
    );

    return
        "<label for='$name'>Prevent comments from accounts created less than $select ago</label>"
        . $class->errdiv( $errs, 'min_age' );
}

sub save {
    my ( $class, $u, $args ) = @_;
    my $age = $class->get_arg( $args, 'min_age' );

    $class->errors( min_age => 'Choose a valid minimum account age.' ) unless exists $options{$age};

    $u->set_prop( opt_min_comment_age => $age eq 'none' ? undef : $age );
    return 1;
}

1;
