#!/usr/bin/perl
#
# DW::SiteScheme
#
# SiteScheme related functions
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010-2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

=head1 NAME

DW::SiteScheme - SiteScheme related functions

=head1 SYNOPSIS

=cut

package DW::SiteScheme;
use strict;

our %sitescheme_data = (
    blueshift => { parent => 'common', title => "Blueshift" },
    celerity => { parent => 'common', title => "Celerity" },
    common => { parent => 'global', internal => 1 },
    'gradation-horizontal' => { parent => 'common', title => "Gradation Horizontal" },
    'gradation-vertical' => { parent => 'common', title => "Gradation Vertical" },
    lynx => { parent => 'common', title => "Lynx (light mode)" },
    global => { engine => 'bml' },
    tt_runner => { engine => 'bml', internal => 1 },
);

my $data_loaded = 0;

our @sitescheme_order = ();

sub get {
    my ( $class, $scheme ) = @_;
    $scheme ||= $class->current;

    $scheme = $sitescheme_order[0] unless exists $sitescheme_data{$scheme};

    return $class->new($scheme);
}

# should not be called directly
sub new {
    my ( $class, $scheme ) = @_;

    return bless { scheme => $scheme }, $class;
}

sub tt_file {
    return $_[0]->{scheme} . '.tt';
}

sub engine {
    return $sitescheme_data{$_[0]->{scheme}}->{engine} || 'tt';
}

=head2 C<< DW::SiteScheme->inheritance( $scheme ) >>

Scheme defaults to the current sitescheme.

Returns the inheritance array, with the provided scheme being at the start of the list.

Also works on a DW::SiteScheme object

=cut

sub inheritance {
    my ( $self, $scheme ) = @_;
    DW::SiteScheme->__load_data;

    $scheme = $self->{scheme} if ref $self;

    $scheme ||= $self->current;
    my @scheme;
    push @scheme, $scheme;
    push @scheme, $scheme while ( $scheme = $sitescheme_data{$scheme}->{parent} );
    return @scheme;
}

sub get_vars {
    return {
        remote => LJ::get_remote()
    };
}

sub __load_data {
    return if $data_loaded;
    $data_loaded = 1;

    # function to merge additional site schemes into our base site scheme data
    # new site scheme row overwrites original site schemes, if there is a conflict
    my $merge_data = sub {
        my ( %data ) = @_;

        foreach my $k ( keys %data ) {
            $sitescheme_data{$k} = { %{ $sitescheme_data{$k} || {} }, %{ $data{$k} } };
        }
    };

    my @schemes = @LJ::SCHEMES;

    LJ::Hooks::run_hooks( 'modify_scheme_list', \@schemes, $merge_data );

    # take the final site scheme list (after all modificatios)
    foreach my $row ( @schemes ) {
        my $scheme = $row->{scheme};

        # copy over any information from the modified scheme list
        # into the site scheme data
        my $targ = ( $sitescheme_data{$scheme} ||= {} );
        foreach my $k ( keys %$row ) {
            $targ->{$k} = $row->{$k};
        }
        next if $targ->{disabled};

        # and then add it to the list of site schemes
        push @sitescheme_order, $scheme;
    }
}

=head2 C<< DW::SiteScheme->available >>

=cut
sub available {
    $_[0]->__load_data;
    return map { $sitescheme_data{$_} } @sitescheme_order;
}

=head2 C<< DW::SiteScheme->current >>

Get the user's current sitescheme, using the following in order:

=over

=item bml_use_scheme note

=item usescheme GET argument

=item BMLschemepref cookie

=item Default sitescheme ( first sitescheme in sitescheme_order )

=item 'global'

=back

=cut

sub current {
    my $r = DW::Request->get;
    $_[0]->__load_data;

    my $rv;

    if ( defined $r ) {
        $rv = $r->note( 'bml_use_scheme' ) ||
            $r->get_args->{usescheme} ||
            $r->cookie( 'BMLschemepref' );
    }

    return $rv ||
        $sitescheme_order[0] ||
        'global';
}

1;
