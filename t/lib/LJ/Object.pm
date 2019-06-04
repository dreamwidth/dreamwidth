#!/usr/bin/perl
##############################################################################

=head1 NAME

LJ::Object - Base object class for LiveJournal object classes.

=head1 SYNOPSIS

  use base qw{LJ::Object};

  sub new {
    my $prot = shift;
    my $class = ref $proto || $proto;

    return $self->SUPER::new( @_ );
  }

=head1 REQUIRES

C<Carp>, C<Class::Translucent>, C<Danga::Exceptions>, C<Scalar::Util>,
C<constant>

=head1 DESCRIPTION

This is a base object class for LiveJournal object classes that provides some
basic useful functionality that would otherwise have to be repeated throughout
various object classes.

It currently provides methods for debugging and logging facilities, translucent
attributes, etc.

=head1 AUTHOR

Michael Granger E<lt>ged@danga.comE<gt>

Copyright (c) 2004 Danga Interactive. All rights reserved.

This module is free software. You may use, modify, and/or redistribute this
software under the terms of the Perl Artistic License. (See
http://language.perl.com/misc/Artistic.html)

THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF MERCHANTIBILITY AND
FITNESS FOR A PARTICULAR PURPOSE.

=cut

##############################################################################
package LJ::Object;
use strict;
use warnings qw{all};

###############################################################################
###  I N I T I A L I Z A T I O N
###############################################################################
BEGIN {
    ### Versioning stuff and custom includes
    use vars qw{$VERSION $RCSID};
    $VERSION = do { my @r = ( q$Revision: 4628 $ =~ /\d+/g ); sprintf "%d." . "%02d" x $#r, @r };
    $RCSID   = q$Id: Object.pm 4628 2004-10-30 02:07:22Z deveiant $;

    # Human-readable constants
    use constant TRUE  => 1;
    use constant FALSE => 0;

    # Modules
    use Carp qw{carp croak confess};
    use Scalar::Util qw{blessed};
    use Danga::Exceptions qw{:syntax};

    # Superclass + class template
    use Class::Translucent (
        {
            debugFunction => undef,
            logFunction   => undef,

            debugLevel => 0,
        }
    );

    # Inheritance
    use base qw{Class::Translucent};
}

#####################################################################
### C L A S S   V A R I A B L E S
#####################################################################

our ($AUTOLOAD);

###############################################################################
### P U B L I C   M E T H O D S
###############################################################################

### (CLASS) METHOD: DebugMsg( $level, $format, @args )
### If the debug level is C<$level> or above, and the debugFunction is defined,
### call it at the specified level with the given printf C<$format> and
### C<@args>. If the debug level would allow the message, but no debugFunction
### is defined, the LogMsg() method is called instead at the 'debug' priority.
sub DebugMsg {
    my $self       = shift or throw Danga::MethodError;
    my $level      = shift;
    my $debugLevel = $self->debugLevel;
    return unless $level && $debugLevel >= abs $level;

    my $message = shift;

    if ( $debugLevel > 1 ) {
        my $caller = caller;
        $message = "<$caller> $message";
    }

    if ( ( my $debugFunction = $self->debugFunction ) ) {
        $debugFunction->( $message, @_ );
    }
    else {
        $self->LogMsg( 'debug', $message, @_ );
    }
}

### (CLASS) METHOD: LogMsg( $level, $format, @args )
### Call the log function (if defined) at the specified level with the given
### printf C<$format> and C<@args>.
sub LogMsg {
    my $self = shift or throw Danga::MethodError;
    my $logFunction = $self->logFunction or return ();

    my ( @args, $level, $objectName, $format, );

    ### Massage the format a bit to include the object it's coming from.
    $level = shift;
    ( $objectName = ref $self ) =~ s{(Danga|LJ|FotoBilder)::}{}g;
    $format = sprintf( '%s: %s', $objectName, shift() );

    # Turn any references or undefined values in the arglist into dumped strings
    @args =
        map { defined $_ ? ( ref $_ ? Data::Dumper->Dumpxs( [$_], [ ref $_ ] ) : $_ ) : '(undef)' }
        @_;

    # Call the logging callback
    $logFunction->( $level, $format, @args );
}

### (PROXY) METHOD: AUTOLOAD( @args )
### Proxy method to build (non-translucent) object accessors.
sub AUTOLOAD {
    my $self = shift or throw Danga::MethodError;
    ( my $name = $AUTOLOAD ) =~ s{.*::}{};

    ### Build an accessor for extant attributes
    if ( blessed $self && exists $self->{$name} ) {
        $self->DebugMsg( 5, "AUTOLOADing '%s'", $name );

        ### Define an accessor for this attribute
        my $method = sub : lvalue {
            my $closureSelf = shift or throw Danga::MethodError;

            $closureSelf->{$name} = shift if @_;
            return $closureSelf->{$name};
        };

        ### Install the new method in the symbol table
    NO_STRICT_REFS: {
            no strict 'refs';
            *{$AUTOLOAD} = $method;
        }

        ### Now jump to the new method after sticking the self-ref back onto the
        ### stack
        unshift @_, $self;
        goto &$AUTOLOAD;
    }

    ### Try to delegate to our parent's version of the method
    my $parentMethod = "SUPER::$name";
    return $self->$parentMethod(@_);
}

### Destructors
END { }

### The package return value (required)
1;

###############################################################################
### D O C U M E N T A T I O N
###############################################################################

###	AUTOGENERATED DOCUMENTATION FOLLOWS

=head1 METHODS

=head2 Class Methods

=over 4

=item I<DebugMsg( $level, $format, @args )>

If the debug level is C<$level> or above, and the debugFunction is defined,
call it at the specified level with the given printf C<$format> and
C<@args>. If the debug level would allow the message, but no debugFunction
is defined, the LogMsg() method is called instead at the 'debug' priority.

=item I<LogMsg( $level, $format, @args )>

Call the log function (if defined) at the specified level with the given
printf C<$format> and C<@args>.

=back

=head2 Proxy Methods

=over 4

=item I<AUTOLOAD( @args )>

Proxy method to build (non-translucent) object accessors.

=back

=cut

