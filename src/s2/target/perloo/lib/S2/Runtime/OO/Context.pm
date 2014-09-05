
package S2::Runtime::OO::Context;
use strict;

# Maybe make this "use fields" later
# For now, just keep the internals private so it can be changed later

use constant VTABLE => 0;
use constant OPTS => 1;
use constant PROPS => 2;
use constant CLASSES => 3;
use constant SCRATCH => 4;
use constant CALLBACK => 5;
use constant STACK => 6;

use constant STACKTRACE => 0;

use constant PRINT => 0;
use constant PRINT_SAFE => 1;
use constant ERROR => 2;

sub new {
    my ($class, @layers) = @_;

    my $vtable = {};
    my $props = {};
    my $classes = {};
    my $callbacks = [sub{},sub{},sub{}];

    ## Copy the functions and props from each layer in turn
    foreach my $lay (@layers) {

        my $functions = $lay->get_functions();
        foreach my $fn (keys %{$functions}) {
            $vtable->{$fn} = $functions->{$fn};
        }

        my $propsets = $lay->get_property_sets();
        foreach my $pn (keys %{$propsets}) {
            $props->{$pn} = $propsets->{$pn};
        }

        my $declclasses = $lay->get_class_docs();
        foreach my $cn (keys %{$declclasses}) {
            $classes->{$cn} = $declclasses->{$cn};
        }

    }

    ## If a property declares a set of acceptable values, make sure layers don't set anything else
    foreach my $lay (@layers) {
        my $declprops = $lay->get_property_attributes();
        foreach my $pname (keys %$declprops) {
            next unless defined $props->{$pname};

            my $prop = $declprops->{$pname};
            next unless defined $prop->{values};
            next if $prop->{allow_other};

            my %okay = split(/\|/, $prop->{values});
            unless (defined $okay{$props->{$pname}}) {
                delete $props->{$pname};
            }
        }
    }

    my $self = [$vtable, [1], $props, $classes, {}, $callbacks, []];

    return bless $self, $class;
}

sub set_print {
    my ($self, $print, $safe_print) = @_;

    $safe_print ||= $print;
    $self->[CALLBACK][PRINT] = $print;
    $self->[CALLBACK][PRINT_SAFE] = $safe_print;
}

sub set_error_handler {
    my ($self, $cb) = @_;

    $self->[CALLBACK][ERROR] = $cb;
}

sub run {
    my ($self, $fn, @args) = @_;

    if (! $self->[VTABLE]{$fn}) {
        $self->_error("Entry point function $fn does not exist", undef, undef);
        return;
    }

    my $ret;
    eval {
        $ret = $self->_call_function($fn, [@args], undef, undef);
    };
    if ($@) {
        my $msg = $@;
        print "<pre>$msg</pre>";
        $msg =~ s/\s+$//;
        $ret = undef;
        $self->_error($msg, undef, undef);
    }

    # Clean up any junk left on the call stack
    $self->[STACK] = [];

    return $ret;
}

sub get_stack_trace {
    return $_[0]->[STACK];
}

sub do_stack_trace {
    my ($self, $bool) = @_;

    if (defined $bool) {
        $self->[OPTS][STACKTRACE] = $bool;
        $bool ? $self->[OPTS][STACK] ||= [] : $self->[OPTS][STACK] = undef;
        return $bool;
    }
    else {
        return $self->[OPTS][STACKTRACE];
    }
}

# Functions called from layer code at runtime. Not public API.

sub _print {
    $_[0]->[CALLBACK][PRINT]->(@_);
}

sub _print_safe {
    $_[0]->[CALLBACK][PRINT_SAFE]->(@_);
}

sub _call_function {
    my ($self, $func, $args, $layer, $srcline) = @_;

    unless (defined $_[0]->[VTABLE]{$func}) {
        $self->_error("Unknown function $func", $layer, $srcline);
        die undef;
    }

    push @{$self->[STACK]}, [$func, $args, $layer, $srcline] if $self->[OPTS][STACKTRACE];
    my $ret = $_[0]->[VTABLE]{$func}->($self, @$args);
    pop @{$self->[STACK]} if $self->[OPTS][STACKTRACE];
    return $ret;
}

sub _call_method {
    my ($self, $obj, $meth, $class, $is_super, $args, $layer, $srcline) = @_;

    unless (_is_defined($obj)) {
        $self->_error("Method $meth called on null $class object", $layer, $srcline);
        die undef;
    }

    $class = $obj->{_type} unless $is_super;
    return $self->_call_function("${class}::${meth}", [$obj, @$args], $layer, $srcline);
}

sub _interpolate_object {
    my ($self, $obj, $meth, $class, $layer, $srcline) = @_;

    return "" unless _is_defined($obj);
    return $self->_call_method($obj, $meth, $class, 0, [], $layer, $srcline);
}

sub _downcast_object {
    my ($self, $obj, $toclass, $layer, $srcline) = @_;

    # If the object is null, just return it
    return $obj unless _is_defined($obj);

    my $fromclass = $obj->{_type};
    return undef unless $self->_object_isa($obj, $toclass);

    return $obj;
}

sub _object_isa {
    my ($self, $obj, $qclass) = @_;

    my $actclass = $obj->{_type};

    my $classes = $self->[CLASSES];

    my $tc = $actclass;
    my $okay = 0;
    while (defined $tc) {
        if ($tc eq $qclass) {
            $okay = 1;
            last;
        }
        my $ntc = $classes->{$tc};
        $tc = $ntc ? $ntc->{parent} : undef;
    }

    return $okay;
}

sub _is_defined {
    my $obj = shift;
    return ref $obj eq "HASH" && defined $obj->{'_type'} && ! $obj->{'_isnull'};
}

sub _get_properties {
    return $_[0]->[PROPS];
}

sub _error {
    $_[0]->[CALLBACK][ERROR]->(@_);
}

1;
