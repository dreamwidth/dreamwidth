#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::XML::RSS;
use base qw(XML::RSS);

use DW::XML::Parser;
use strict;

=head1 NAME

DW::XML::RSS

=cut

# taken straight from XML::RSS, but switched to use DW::XML::Parser
sub _get_parser {
    my $self = shift;

    return DW::XML::Parser->new(
        Namespaces    => 1,
        NoExpand      => 1,
        ParseParamEnt => 0,
        Handlers      => {
            Char => sub {
                my ( $parser, $cdata ) = @_;
                $self->_parser($parser);
                $self->_handle_char($cdata);

                # Detach the parser to avoid reference loops.
                $self->_parser(undef);
            },
            XMLDecl => sub {
                my $parser = shift;
                $self->_parser($parser);
                $self->_handle_dec(@_);

                # Detach the parser to avoid reference loops.
                $self->_parser(undef);
            },
            Start => sub {
                my $parser = shift;
                $self->_parser($parser);
                $self->_handle_start(@_);

                # Detach the parser to avoid reference loops.
                $self->_parser(undef);
            },
            End => sub {
                my $parser = shift;
                $self->_parser($parser);
                $self->_handle_end(@_);

                # Detach the parser to avoid reference loops.
                $self->_parser(undef);
            },
        }
    );
}

1;
