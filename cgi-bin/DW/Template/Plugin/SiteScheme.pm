#!/usr/bin/perl
#
# DW::Template::Plugin::SiteScheme
#
# Template Toolkit plugin for Dreamwidth siteschemes
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Template::Plugin::SiteScheme;
use base 'Template::Plugin';
use strict;
use DW::Logic::MenuNav;

=head1 NAME

DW::Template::Plugin - Template Toolkit plugin for Dreamwidth

=head1 SYNOPSIS

=cut

sub load {
    return $_[0];
}

sub new {
    my ( $class, $context, @params ) = @_;

    my $self = bless {
        _CONTEXT => $context,
    }, $class;

    return $self;
}

=head1 METHODS

=cut

sub need_res {
    my $self = shift;

    my $hash_arg = {};
    $hash_arg = shift @_ if ref $_[0] eq 'HASH';
    $hash_arg->{priority} = $LJ::SCHEME_RES_PRIORITY;

    my @args = @_;
    @args = @{$args[0]} if ref $_[0] eq 'ARRAY';

    return LJ::need_res($hash_arg,@args);
}

sub res_includes {
    return ( $LJ::ACTIVE_RES_GROUP || "" ) eq "foundation"
                ? LJ::res_includes_head()
                : LJ::res_includes();
}

sub final_head_html {
    return LJ::final_head_html();
}

sub final_body_html {
    return ( $LJ::ACTIVE_RES_GROUP || "" ) eq "foundation"
                ? LJ::res_includes_body() . LJ::final_body_html()
                : LJ::final_body_html();
}

sub menu_nav {
    return DW::Logic::MenuNav->get_menu_navigation;
}

sub search_render {
    return LJ::Widget::Search->render;
}

sub challenge_generate {
    my $self = shift;
    return LJ::challenge_generate(@_);
}

sub show_logout_button {
    return DW::Request->get->uri !~ m!^/logout!;
}

sub show_invite_link {
    return $LJ::USE_ACCT_CODES ? 1 : 0;
}

=head1 AUTHOR

=over

=item Andrea Nall <anall@andreanall.com>

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
