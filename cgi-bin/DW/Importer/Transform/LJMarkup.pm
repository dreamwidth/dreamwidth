#!/usr/bin/perl
#
# DW::Importer::Transform::LJMarkup
#
# Rewrites LiveJournal markup in imported text.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Importer::Transform::LJMarkup;

=head1 NAME

DW::Importer::Transform::LJMarkup - Pure rewrites of LiveJournal markup

=head1 DESCRIPTION

LiveJournal text has tags with no equivalent here: C<< <lj user="x"> >> must point at
the other site, polls can't be copied, and embedded or templated content can't be
reproduced. These functions rewrite text, touch nothing else, and return what they
changed as warnings for the caller to report.

Entries and comments are treated a little differently, and have always been: entries
link polls back to the site and tell the user about every embed or template they lost,
comments silently drop them and leave a note in the text.

=cut

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw( remap_user_tags entry_text comment_text );

=head2 C<< remap_user_tags( $text, $hostname ) >>

Rewrites C<< <lj user="x"> >> (and C<comm> and C<syn>) to a C<< <user site="..."> >>
tag for the site the content came from.

=cut

sub remap_user_tags {
    my ( $text, $hostname ) = @_;
    return $text unless defined $text;

    $text =~
s/(<lj[^>]+?(user|comm|syn)=["']?(.+?)["' ]?(?:\s*\/\s*)?>)/<user site="$hostname" $2="$3">/gi;
    return $text;
}

=head2 C<< entry_text( $text, $hostname ) >>

Returns C<( $text, @warnings )> for the body of an entry: polls become a link back to
the poll on the source, embeds and templates are removed with a warning for each kind
that was found, and user tags are rewritten.

=cut

sub entry_text {
    my ( $text, $hostname ) = @_;
    my @warnings;

    # we just link polls to the original site
    # FIXME: this URL should be from some method and not manually constructed
    $text =~ s!<.+?-poll-(\d+?)>![<a href="http://www.$hostname/poll/?id=$1">Poll #$1</a>]!g;

    if ( $text =~ m/<.+?-embed-.+?>/ ) {
        $text =~ s/<.+?-embed-.+?>//g;
        push @warnings,
            "Entry contained an embed tag, please manually re-add the embedded content.";
    }

    if ( $text =~ m/<.+?-template-.+?>/ ) {
        $text =~ s/<.+?-template-.+?>//g;
        push @warnings,
            "Entry contained a template tag, please manually re-add the templated content.";
    }

    return ( remap_user_tags( $text, $hostname ), @warnings );
}

=head2 C<< comment_text( $text, $hostname ) >>

Returns C<( $text, @warnings )> for the body of a comment: user tags are rewritten, and
embeds and templates are replaced by a note in the text. Polls are left alone.

=cut

sub comment_text {
    my ( $text, $hostname ) = @_;
    my @warnings;

    $text = remap_user_tags( $text, $hostname );
    $text = '' unless defined $text;

    push @warnings, 'Comment contained an embed tag.' if $text =~ m/<.+?-embed-.+?>/;
    $text =~ s/<.+?-embed-.+?>/[Embedded content removed during import.]/g;

    push @warnings, 'Comment contained a template tag.' if $text =~ m/<.+?-template-.+?>/;
    $text =~ s/<.+?-template-.+?>/[Templated content removed during import.]/g;

    return ( $text, @warnings );
}

=head1 AUTHORS

=over

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
