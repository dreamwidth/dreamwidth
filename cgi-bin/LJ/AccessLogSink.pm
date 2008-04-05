package LJ::AccessLogSink;
use strict;
use warnings;
use LJ::ModuleCheck;

sub new {
    die "this is a base class\n";
}

sub log {
    my ($self, $rec) = @_;
    die "this is a base class\n";
}

my $need_rebuild = 1;
my @sinks = ();

sub forget_sink_objs {
    $need_rebuild = 1;
    @sinks = ();
}

sub extra_log_sinks {
    _build_sink_objs() if $need_rebuild;
    return @sinks;
}

sub _build_sink_objs {
    return unless $need_rebuild;
    $need_rebuild = 0;
    @sinks = ();
    foreach my $ci (@LJ::EXTRA_ACCESS_LOG_SINKS) {
        if (ref $ci eq "ARRAY") {
            # convert from [$class, @ctor_args] arrayref
            my @args = @$ci;
            my $class = shift @args;
            $class = "LJ::AccessLogSink::$class" unless $class =~ /::/;
            unless (LJ::ModuleCheck->have($class)) {
                warn "Can't load module: $class\n";
                next;
            }
            push @sinks, $class->new(@args);
        } else {
            # already an object in ljconfig.pl (old style)
            push @sinks, $ci;
        }
    }
}

1;
