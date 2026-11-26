# DW::Setting::SharedAdminPosts
#
# Controls whether community administrators can edit each other's official posts.
#
# Authors:
#      Dreamwidth contributors
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::SharedAdminPosts;

use strict;
use warnings;
use base 'LJ::Setting::BoolSetting';

sub should_render {
    my ( $class, $journal ) = @_;
    my $remote = LJ::get_remote();
    return
           $journal
        && $journal->is_community
        && $remote
        && $remote->is_visible
        && !$remote->is_expunged
        && $remote->can_manage($journal);
}

sub save {
    my ( $class, $journal, $args ) = @_;
    return unless $class->should_render($journal);
    return $journal->set_prop( $class->prop_name, $args->{val} ? 1 : 0 );
}

sub label { 'Shared admin posts' }
sub des   { 'Allow any admin of the community to edit official community posts.' }

sub prop_name       { 'shared_admin_posts' }
sub checked_value   { 1 }
sub unchecked_value { 0 }

sub option { shift->as_html(@_) }

1;
