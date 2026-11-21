#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::EmailPost::Base;

use strict;

require 'ljlib.pl';
use LJ::Emailpost::Web;
use DW::Formats;

use Encode;
use HTML::TokeParser ();
use MIME::Words      ();
use Unicode::MapUTF8 ();

my $workdir = "/tmp";

=head1 NAME

DW::EmailPost::Base - Basic email posting behavior

=head1 SYNOPSIS

This is the basic email posting behavior. Subclasses should implement the following:

=over

=item  _find_destination - given a list of email addresses, return one you're interested in (or undef if none)

=item _parse_destination - given an auth string taken from the "to:" email header, set the user/journal/validated information

=item _process - process the email. Call $self->_extract_post_headers before applying post
options and $self->cleanup_body_final before submitting the body.

=back

=cut

=head2 C<< $class->new( $mime_entity ) >>

Create an instance of DW::EmailPost::Base

=cut

sub new {
    my ( $class, $mime_entity ) = @_;

    my $self = bless {

        _entity      => $mime_entity,
        _entity_head => $mime_entity->head,

        dequeue => 1,

    }, $class;

    return $self;
}

=head1 CLASS METHODS

=head2 C<< $class->find_destination( $mime_entity ) >>

Given a mime entity object, return the scalar $user journal
(or undef) that this email is destined to post to

Subclasses must implement a _find_destination sub

=cut

sub find_destination {
    my ( $class, $mime_entity ) = @_;

    my @to_addresses = map { $_->address } Mail::Address->parse( $mime_entity->head->get('To') );

    return $class->_find_destination(@to_addresses);
}

=head2 C<< $class->should_handle( $mime_entity ) >>

Given a mime entity object, return 1 if we're interested in handling this.
Return 0 if not.

=cut

sub should_handle {
    my ( $class, $mime_entity ) = @_;
    return $class->find_destination($mime_entity) ? 1 : 0;
}

=head1 INSTANCE METHODS

=head2 C<< $self->process >>

Process the email. Returns a status message indicating either success or reason for failure

This base implementation pulls out subject/body, finds the important metadata from the email
(such as address, username, etc) and does character decoding.

Subclasses must implement a _process sub for subclass-specific handling

=cut

sub process {
    my ($self) = @_;

    # pull out the head, and remove extra newlines
    $self->{_entity_head}->unfold;

    $self->_init_required;
    return unless $self->{from};

    # left side of "to" address
    $self->{destination} ||= $self->find_destination( $self->{_entity} );
    $self->parse_destination( $self->{destination} ) or return $self->send_error;

    return $self->send_error("Email gateway access denied for your account type.")
        unless $LJ::T_ALLOW_EMAILPOST || $self->{u}->can_emailpost;

    # metadata that's not strictly needed, but could be useful later
    $self->_init_optional;

    # get the body and subject from the email
    # processed character encoding, but not cleaned up further than that
    # will probably need further processing before using as entry/comment text
    $self->_extract_text or return $self->send_error;

    return $self->_process;
}

=head2 C<< $self->parse_destination( $auth_string ) >>

Given an auth string (lefthand side of "to:" header), set authorization options

Must set: u, journal

Subclasses must implement a _parse_destination sub
=cut

sub parse_destination {
    my ( $self, $auth_string ) = @_;

    $self->_parse_destination($auth_string) or return 0;

    return 0 unless $self->{u} && $self->{u}->is_visible;

    return 1;
}

=head2 C<< $self->cleanup_body_final >>

Final cleanup of the body text: remove signatures, adjust whitespace, etc.
Subclass should call this when doing _process

=cut

sub cleanup_body_final {
    my $self = $_[0];

    $self->{body} =~ s/^(?:\- )?[\-_]{2,}(\s|&nbsp;)*\r?\n.*//ms;    # trim sigs

    my $content_type = $self->{content_type};

    # respect flowed text
    if ( lc $content_type->{format} eq 'flowed' ) {
        if ( $content_type->{delsp} && lc $content_type->{delsp} eq 'yes' ) {
            $self->{body} =~ s/ \n//g;
        }
        else {
            $self->{body} =~ s/ \n/ /g;
        }
    }

    # trim off excess whitespace (html cleaner converts to breaks)
    $self->{body} =~ s/\n+$/\n/;
}

# convenience methods
# discover the from/user to post as/journal to post to
sub _init_required {
    my $self = $_[0];

    # from address
    $self->{from} =
        ${ ( Mail::Address->parse( $self->{_entity_head}->get('From:') ) )[0] || [] }[1];
}

sub _init_optional {
    my $self = $_[0];

    my $head = $self->{_entity_head};

    # The return path should normally not ever be messed up enough to require this,
    # but some mailers nowadays do some very strange things.
    $self->{return_path} = ${ ( Mail::Address->parse( $head->get('Return-Path') ) )[0] || [] }[1];

    $self->{email_date} = $head->get('Date:');
}

# body / subject / content_type
sub _extract_text {
    my $self = $_[0];

    # Use text/plain piece first - if it doesn't exist, then fallback to text/html
    my $tent = $self->get_entity( $self->{_entity} )
        || $self->get_entity( $self->{_entity}, 'html' );
    $self->{_tent} = $tent;

    # $self->{content_type}
    $self->_parse_content_type( $tent ? $tent->head->get('Content-type:') : '' );

    # $self->{body}, $self->{subject}
    $self->_clean_body_and_subject( $tent ? $tent->bodyhandle->as_string : "",
        $self->{_entity_head}->get('Subject:') )
        or return;

    return 1;
}

# Extract leading lj-* and post-* lines, including unrecognized header names.
# The post-* values take precedence over their legacy lj-* equivalents.
sub _extract_post_headers {
    my ( $self, $headers ) = @_;
    $headers //= { lj => {}, post => {} };

    my $body = $self->{body};
    pos($body) = 0;

    my $is_html = $self->{_tent} && $self->{_tent}->head->mime_type eq 'text/html';
    pos($body) = _html_header_offset($body) if $is_html;

    my $start       = pos($body);
    my $end         = $start;
    my $markup      = '';
    my $inline_tag  = qr{</?(?:b|em|i|s|small|span|strong|u)[ \t]*>}i;
    my $value_text  = $is_html ? qr/(?:[^<\r\n]|$inline_tag)*+/ : qr/[^\r\n]*/;
    my $value_start = $is_html ? qr/(?:[^ \t\r\n<>]|$inline_tag)/ : qr/[^ \t\r\n<>]/;
    my $value_end   = $is_html ? qr/(?=<)|\r?\n|\z/ : qr/\r?\n|\z/;
    while (1) {
        if ( $is_html && $end > $start && $body =~ /\G(?=[ \t\r\n]*<)/gc ) {
            pos($body) = _html_header_offset( $body, $end );
        }
        my $line_start = pos($body);
        last if $is_html && $body =~ /\G(?:[ \t]*\r?\n)*(?:lj|post)-[^:<\r\n]*</igc;
        last unless $body =~ /\G(?:[ \t]*\r?\n)*(lj|post)-([^:\r\n]+):($value_text)$value_end/igc;
        my ( $prefix, $name, $value ) = ( lc($1), lc($2), $3 );
        $value =~ s/$inline_tag//g if $is_html;
        $value = LJ::trim($value);
        if ( !length($value) && $body =~ /\G[ \t]+(?=$value_start)($value_text)$value_end/gc ) {
            $value = $1;
            $value =~ s/$inline_tag//g if $is_html;
            $value = LJ::trim($value);
        }
        $headers->{$prefix}{$name} = $value;
        $markup .= substr( $body, $end, $line_start - $end );
        $end = pos($body);
    }

    substr( $body, $start, $end - $start, $markup );
    $body =~ s/\A\s*//;
    $self->{body}         = $body;
    $self->{post_headers} = { %{ $headers->{lj} }, %{ $headers->{post} } };

    return $headers;
}

sub _html_header_offset {
    my ( $body, $after_header ) = @_;
    my $offset       = $after_header // _html_body_offset($body);
    my $line_start   = $offset;
    my $body_content = substr( $body, $offset );
    my $parser       = HTML::TokeParser->new( \$body_content );
    my $wrapper =
        defined $after_header
        ? qr{<(?:div|p)[ \t]*>|<br[ \t]*/?>}i
        : qr{<(?:div|p)[ \t]*>|<(?:!doctype[ \t]+html|html|body)(?:[ \t][^<>\r\n]*)?>}i;

    while ( my $token = $parser->get_token ) {
        my ( $type, $text ) = @$token;
        if ( $type eq 'C' ) {
            last if defined $after_header && $text !~ /\A<!--(?!-?>)(?:(?!--!?>)[\s\S])*+-->\z/;
            $offset += length $text;
        }
        elsif ( $type eq 'S' || $type eq 'D' ) {
            my $raw = $type eq 'S' ? $token->[4] : $text;
            last unless $raw =~ /\A$wrapper\z/;
            $offset += length $raw;
            $line_start = $offset if $type eq 'S';
        }
        elsif ( $type eq 'E' && defined $after_header && $token->[2] =~ m{\A</(?:div|p)[ \t]*>\z}i )
        {
            $offset += length $token->[2];
        }
        elsif ( $type eq 'T' ) {
            $text =~ /\A((?:[ \t]*\r?\n)*)[ \t]*/;
            $line_start = $offset + length $1 if length $1;
            last if $+[0] != length $text;
            $offset += length $text;
        }
        else {
            last;
        }
    }

    return $line_start;
}

sub _html_body_offset {
    my ($body) = @_;
    my $parser = HTML::TokeParser->new( \$body );
    my ( $offset, $seen_head, $closed_head ) = ( 0, 0, 0 );
    my @head_content;

    while ( my $token = $parser->get_token ) {
        my ( $type, $tag ) = @$token;
        if ( $type eq 'S' ) {
            if (@head_content) {
                if ( $head_content[-1] eq 'template' ) {
                    last if $tag =~ /\A(?:html|head|body|frameset)\z/;
                    push @head_content, $tag if $tag eq 'template';
                }
                else {
                    last
                        unless $head_content[-1] eq 'noscript' && $tag =~ /\A(?:link|meta|style)\z/;
                    push @head_content, $tag if $tag eq 'style';
                }
            }
            elsif ( $tag eq 'body' ) {
                return $offset + length $token->[4];
            }
            elsif ( $tag ne 'html' || $seen_head ) {
                last if $closed_head;
                if ( $tag =~ /\A(?:title|style|script|noscript|template)\z/ ) {
                    push @head_content, $tag;
                }
                elsif ( $tag !~ /\A(?:base|link|meta)\z/ && ( $tag ne 'head' || $seen_head ) ) {
                    last;
                }
                $seen_head = 1;
            }
            $offset += length $token->[4];
        }
        elsif ( $type eq 'E' ) {
            if (@head_content) {
                if ( $tag eq $head_content[-1] ) {
                    pop @head_content;
                }
                elsif ($head_content[-1] ne 'template'
                    || $tag =~ /\A(?:html|head|body|frameset)\z/ )
                {
                    last;
                }
            }
            elsif ( !$closed_head && $tag eq 'head' ) {
                $seen_head = $closed_head = 1;
            }
            else {
                last;
            }
            $offset += length $token->[2];
        }
        elsif ($type eq 'C'
            || ( $type eq 'D' && $tag =~ /\A<!doctype\s+html\b/i )
            || ( $type eq 'T' && $tag !~ /[^ \t\r\n\f]/ )
            || ( $type eq 'T' && @head_content && $head_content[-1] ne 'noscript' ) )
        {
            $offset += length $tag;
        }
        else {
            last;
        }
    }

    return @head_content ? 0 : $offset;
}

# given a content-type header, return a hash of content-type attributes
sub _parse_content_type {
    my ( $self, $content_type ) = @_;

    my %content_type_opts;

    # Snag charset
    $content_type_opts{_orig} = $content_type;

    $content_type_opts{charset} = $1
        if $content_type =~ /\bcharset=['\"]?(\S+?)['\"]?[\s\;]/i;

    $content_type_opts{format} = $1
        if $content_type =~ /\bformat=['\"]?(\S+?)['\"]?[\s\;]/i;

    $content_type_opts{delsp} = $1
        if $content_type =~ /\bdelsp=['\"]?(\w+?)['\"]?[\s\;]/i;

    $self->{content_type} = \%content_type_opts;
}

# clean up the body and subject
sub _clean_body_and_subject {
    my ( $self, $body, $subject ) = @_;

    my $content_type = $self->{content_type};

    # set before processing to original version
    $self->{body}    = $body;
    $self->{subject} = $subject;

    # remove leading and trailing whitespace
    $body =~ s/^\s+//;
    $body =~ s/\s+$//;

    # do utf-8 conversion
    my $body_charset = $content_type->{charset};
    if ( defined($body_charset)
        && $body_charset !~ /^UTF-?8$/i )
    {    # no charset? assume us-ascii

        unless ( Unicode::MapUTF8::utf8_supported_charset($body_charset) ) {
            $self->{error} = "Unknown charset encoding type. ($body_charset)";
            return;
        }

        $body = Unicode::MapUTF8::to_utf8(
            {
                -string  => $body,
                -charset => $body_charset,
            }
        );
    }

    # check subject for rfc-1521 junk
    chomp $subject;
    if ( $subject =~ /^=\?/ ) {
        my @subj_data = MIME::Words::decode_mimewords($subject);
        my ( $string, $subject_charset ) = ( $subj_data[0][0], $subj_data[0][1] );
        if (@subj_data) {
            if ( $subject =~ /utf-8/i ) {
                $subject = $string;
            }
            else {
                unless ( Unicode::MapUTF8::utf8_supported_charset($subject_charset) ) {
                    $self->{error} = "Unknown charset encoding type. ($subject_charset)";
                    return;
                }

                $subject = Unicode::MapUTF8::to_utf8(
                    {
                        -string  => $string,
                        -charset => $subject_charset,
                    }
                );
            }
        }
    }

    # set after processing to processed version
    $self->{body}    = $body;
    $self->{subject} = $subject;

    return 1;
}

# Convert special email format keywords to the real format IDs used by
# DW::Formats and LJ::CleanHTML.
sub _choose_editor {
    my ( $self, $format ) = @_;
    $format = lc($format);

    # Support email-only short names for the active formats:
    $format = 'markdown_latest'    if $format eq 'markdown';
    $format = 'html_casual_latest' if $format eq 'html';

    $format = DW::Formats::validate($format);

    # If validate returns '', use an email-specific default.
    $format = DW::Formats::validate('markdown_latest') unless $format;

    return $format;
}

# By default, returns first plain text entity from email message.
# Specifying a type will return an array of MIME::Entity handles
# of that type. (image, application, etc)
# Specifying a type of 'all' will return all MIME::Entities,
# regardless of type.
sub get_entity {
    my ( $self, $entity, $type ) = @_;

    # old arguments were a hashref
    $type = $type->{type} if ref $type eq "HASH";

    # default to text
    $type ||= 'text';

    my $head      = $entity->head;
    my $mime_type = $head->mime_type;

    return $entity if $type eq 'text' && $mime_type eq "text/plain";
    return $entity if $type eq 'html' && $mime_type eq "text/html";
    my @entities;

    # Only bother looking in messages that advertise attachments
    my $mimeattach_re = qr{ m|^multipart/(?:alternative|signed|mixed|related)$| };
    if ( $mime_type =~ $mimeattach_re ) {
        my $partcount = $entity->parts;
        for ( my $i = 0 ; $i < $partcount ; $i++ ) {
            my $alte = $entity->parts($i);

            return $alte if $type eq 'text' && $alte->mime_type eq "text/plain";
            return $alte if $type eq 'html' && $alte->mime_type eq "text/html";
            push @entities, $alte if $type eq 'all';

            if (   $type eq 'image'
                && $alte->mime_type =~ m#^application/octet-stream# )
            {
                my $alte_head = $alte->head;
                my $filename  = $alte_head->recommended_filename;
                push @entities, $alte if $filename =~ /\.(?:gif|png|tiff?|jpe?g)$/;
            }
            push @entities, $alte
                if $alte->mime_type =~ /^$type/
                && $type ne 'all';

            # Recursively search through nested MIME for various pieces
            if ( $alte->mime_type =~ $mimeattach_re ) {
                if ( $type =~ /^(?:text|html)$/ ) {
                    my $text_entity = $self->get_entity( $entity->parts($i), $type );
                    return $text_entity if $text_entity;
                }
                else {
                    push @entities, $self->get_entity( $entity->parts($i), $type );
                }
            }
        }
    }

    return @entities if $type ne 'text' && scalar @entities;
    return;
}

# sets the error message
sub err {
    my ( $self, $error, $error_args ) = @_;
    $self->{error}      = $error;
    $self->{error_args} = $error_args;
    return;
}

# fires off error notifications, etc
sub send_error {
    my ( $self, $msg, %opt ) = @_;

    $msg ||= $self->{error};
    %opt = ( %{ $self->{error_args} || {} }, %opt );

    my $errbody;
    $errbody .= "There was an error during your email posting:\n\n";
    $errbody .= $msg;

    if ( $self->{body} ) {
        $errbody .= "\n\n\nOriginal posting follows:\n\n";
        $errbody .= $self->{body};
    }

    my $err_addr = $self->find_error_address;

    # Rate limit email to 1/5min/address
    if (   !$opt{nomail}
        && !$opt{retry}
        && $err_addr
        && LJ::MemCache::add( "rate_eperr:$err_addr", 5, 300 ) )
    {

        LJ::send_mail(
            {
                to       => $err_addr,
                from     => $LJ::BOGUS_EMAIL,
                fromname => "$LJ::SITENAME Error",
                subject  => "$LJ::SITENAME posting error: $self->{subject}",
                body     => $errbody
            }
        );
    }

    $self->{dequeue} = 0 if $opt{retry};

    $opt{m} = $msg;
    $opt{s} = $self->{subject};
    $opt{e} = 1;
    $self->dblog(%opt) unless $opt{nolog};

    return ( 0, $msg );
}

sub dblog {
    my ( $self, %info ) = @_;
    return unless $self->{u};

    %info = ( %info, $self->dblog_opts );

    chomp $info{s};
    $self->{u}->log_event( 'emailpost', \%info );
    return;
}

=head2 C<< $self->dblog_opts >>

Class-specific options

=cut

sub dblog_opts { (); }

=head2 C<< $self->set_error_address >>

Given a user object and an email address, discover the appropriate email
to send any error messages to.

Fallback to raw address if no explicit allowed senders.

=cut

sub find_error_address {
    my ($self) = $_[0];
    return unless $self->{u};

    my $err_addr;
    my $addrlist = LJ::Emailpost::Web::get_allowed_senders( $self->{u} );
    my $from     = $self->{from};
    foreach my $allowed_sender ( keys %$addrlist ) {
        if ( lc $from eq lc $allowed_sender
            && $addrlist->{$allowed_sender}->{get_errors} )
        {
            $err_addr = $from;
            last;
        }
    }

    $err_addr ||= $self->{u}->email_raw if $self->{u};
    return $err_addr;
}

=head1 GETTERS / SETTERS

=head2 C<< $self->destination( [ $destination ] ) >>

Get/set the destination this was sent to (left part of the To:)

=cut

sub destination {
    my ( $self, $destination ) = @_;

    $self->{destination} = $destination
        if $destination;

    return $destination;
}

=head2 C<< $self->dequeue >>

Returns whether this email post should be dequeued (1) or retried (0).

=cut

sub dequeue {
    return $_[0]->{dequeue};
}

1;
