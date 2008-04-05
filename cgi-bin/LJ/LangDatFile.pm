package LJ::LangDatFile;
use strict;
use warnings;
use Carp qw (croak);


sub new {
    my ($class, $filename) = @_;

    my $self = {
        # initialize
        filename => $filename,
        values    => {},          # string -> value mapping
        meta      => {},          # string -> {metakey => metaval}
    };

    bless $self, $class;
    $self->parse;

    return $self;
}

sub parse {
    my $self = shift;
    my $filename = $self->filename;

    open my $datfile, $filename
        or croak "Could not open file $filename: $!";

    my $lnum = 0;
    my ($code, $text);
    while ( my $line = <$datfile> ) {
        $lnum++;
        my $del;
        my $action_line;

        if ($line =~ /^(\S+?)=(.*)/) {
            ($code, $text) = ($1, $2);
            $action_line = 1;
        } elsif ($line =~ /^\!\s*(\S+)/) {
            $del = $code;
            $action_line = 1;
        } elsif ($line =~ /^(\S+?)\<\<\s*$/) {
            ($code, $text) = ($1, "");
            while (my $ln = <$datfile>) {
                $lnum++;
                last if $ln eq ".\n";
                $ln =~ s/^\.//;
                $text .= $ln;
            }
            chomp $text;  # remove file new-line (we added it)
            $action_line = 1;
        } elsif ($line =~ /^[\#\;]/) {
            # comment line
            next;
        } elsif ($line =~ /\S/) {
            croak "$filename:$lnum: Bogus format.";
        }

        if ($code && $code =~ s/\|(.+)//) {
            $self->{meta}->{$code} ||= {};
            $self->{meta}->{$code}->{$1} = $text;
            $action_line = 1;
        }

        next unless $action_line;
        $self->{values}->{$code} = $text;
    }

    close $datfile;
}

sub filename { $_[0]->{filename} }

sub meta {
    my ($self, $code) = @_;
    return %{$self->{meta}->{$code} || {}};
}

sub value {
    my ($self, $key) = @_;

    return undef unless $key;
    return $self->{values}->{$key};
}

sub foreach_key {
    my ($self, $callback) = @_;

    foreach my $k ($self->keys) {
        $callback->($k);
    }
}

sub keys {
    my $self = shift;
    my @keys = CORE::keys(%{$self->{values}});
    return sort @keys;
}
sub values {
    my $self = shift;
    return CORE::values(%{$self->{values}});
}

# set a key/value pair
sub set {
    my ($self, $k, $v) = @_;

    return 0 unless $k;
    $v ||= '';

    $self->{values}->{$k} = $v;
    return 1;
}

# save to file
sub save {
    my $self = shift;

    my $filename = $self->filename;

    open my $save, ">$filename"
        or croak "Could not open file $filename for writing: $!";

    # prefix file with utf-8 marker for emacs
    print $save ";; -*- coding: utf-8 -*-\n\n";

    # write out strings to file
    $self->foreach_key(sub {
        my $key = shift;
        return unless $key; # just to make sure

        my $val = $self->value($key) || '';

        # is there metadata?
        my $meta = $self->{meta}->{$key};
        if ($meta) {
            while ( my ($metakey, $metaval) = each %$meta ) {
                print $save "$key|$metakey=$metaval\n";
            }
        }

        # is it multiline?
        if ($val =~ /\n/) {
            print $save "$key<<\n$val\n.\n\n";
        } else {
            # normal key-value pair
            print $save "$key=$val\n\n";
        }
    });

    close $save;

    return 1;
}

1;
