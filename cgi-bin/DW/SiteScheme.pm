#!/usr/bin/perl
#
# DW::SiteScheme
#
# SiteScheme related functions
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010-2013 by Dreamwidth Studios, LLC.
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

my %sitescheme_data = (
    blueshift              => { parent => 'common', title    => "Blueshift" },
    celerity               => { parent => 'common', title    => "Celerity" },
    common                 => { parent => 'global', internal => 1 },
    'gradation-horizontal' => { parent => 'common', title    => "Gradation Horizontal" },
    'gradation-vertical'   => { parent => 'common', title    => "Gradation Vertical" },
    lynx                   => { parent => 'common', title    => "Lynx (light mode)" },
    global                 => { engine => 'current' },
    tt_runner              => { engine => 'bml',    internal => 1 },
);

my $data_loaded = 0;

my @sitescheme_order = ();

=head2 C<< DW::SiteScheme->get( $scheme ) >>

$scheme defaults to the current sitescheme.

Returns a DW::SiteScheme object.

=cut

sub get {
    my ( $class, $scheme ) = @_;
    $class->__load_data;

    $scheme ||= $class->current;

    $scheme = $class->default unless exists $sitescheme_data{$scheme};

    return $class->new($scheme);
}

# should not be called directly
sub new {
    my ( $class, $scheme ) = @_;

    return bless { scheme => $scheme }, $class;
}

sub name {
    return $_[0]->{scheme};
}

sub tt_file {
    return undef unless $_[0]->supports_tt;
    return $_[0]->{scheme} . '.tt';
}

sub engine {
    $_[0]->__load_data;

    return $sitescheme_data{ $_[0]->{scheme} }->{engine} || 'tt';
}

sub supports_tt {
    return $_[0]->engine eq 'tt' || $_[0]->engine eq 'current';
}

sub supports_bml {
    return $_[0]->engine eq 'bml' || $_[0]->engine eq 'current';
}

=head2 C<< DW::SiteScheme->inheritance( $scheme ) >>

Scheme defaults to the current sitescheme.

Returns the inheritance array, with the provided scheme being at the start of the list.

Also works on a DW::SiteScheme object

=cut

sub inheritance {
    my ( $self, $scheme ) = @_;
    $self->__load_data;

    $scheme = $self->{scheme} if ref $self;
    $scheme ||= $self->current;

    my @scheme;
    push @scheme, $scheme;
    push @scheme, $scheme
        while exists $sitescheme_data{$scheme}
        && ( $scheme = $sitescheme_data{$scheme}->{parent} );
    return @scheme;
}

sub get_vars {
    return { remote => LJ::get_remote() };
}

sub __load_data {
    return if $data_loaded;
    $data_loaded = 1;

    # function to merge additional site schemes into our base site scheme data
    # new site scheme row overwrites original site schemes, if there is a conflict
    my $merge_data = sub {
        my (%data) = @_;

        foreach my $k ( keys %data ) {
            $sitescheme_data{$k} = { %{ $sitescheme_data{$k} || {} }, %{ $data{$k} } };
        }
    };

    my @schemes = @LJ::SCHEMES;

    LJ::Hooks::run_hooks( 'modify_scheme_list', \@schemes, $merge_data );

    # take the final site scheme list (after all modificatios)
    foreach my $row (@schemes) {
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

=item skin / usescheme GET argument

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
        $rv =
               $r->note('bml_use_scheme')
            || $r->get_args->{skin}
            || $r->get_args->{usescheme}
            || $r->cookie('BMLschemepref');
    }

    return $rv if defined $rv and defined $sitescheme_data{$rv};
    return $_[0]->default;
}

=head2 C<< DW::SiteScheme->default >>

Get the default sitescheme.

=cut

sub default {
    $_[0]->__load_data;

    return $sitescheme_order[0]
        || 'global';
}

=head2 C<< DW::SiteScheme->set_for_request( $scheme ) >>

Set the sitescheme for the request.

Note: this must be called early enough in a request
before calling into bml_handler for BML, or before render_template for TT
otherwise has no action.

=cut

sub set_for_request {
    my $r = DW::Request->get;

    return 0 unless exists $sitescheme_data{ $_[1] };
    $r->note( 'bml_use_scheme', $_[1] );

    return 1;
}

=head2 C<< DW::SiteScheme->set_for_user( $scheme, $u ) >>

Set the sitescheme for the user.

If $u does not exist, this will default to remote
if $u ( or remote ) is undef, this will only set the cookie.

Note: If done early enough in the process this will affect the current request.
See the note on set_for_request

=cut

sub set_for_user {
    my $r = DW::Request->get;

    my $scheme = $_[1];
    my $u      = exists $_[2] ? $_[2] : LJ::get_remote();

    return 0 unless exists $sitescheme_data{$scheme};
    my $cval = $scheme;
    if ( $scheme eq $sitescheme_order[0] && !$LJ::SAVE_SCHEME_EXPLICITLY ) {
        $cval = undef;
        $r->delete_cookie( domain => ".$LJ::DOMAIN", name => 'BMLschemepref' );
    }

    my $expires = undef;
    if ($u) {

        # set a userprop to remember their schemepref
        $u->set_prop( schemepref => $scheme );

        # cookie expires when session expires
        $expires = $u->{_session}->{timeexpire} if $u->{_session}->{exptype} eq "long";
    }

    $r->add_cookie(
        name    => 'BMLschemepref',
        value   => $cval,
        expires => $expires,
        domain  => ".$LJ::DOMAIN",
    ) if $cval;

    return 1;
}

1;
