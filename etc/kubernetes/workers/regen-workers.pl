#!/usr/bin/perl

use strict;
use v5.10;

my $hpa_cpu = sub {
    return [ 'hpa-cpu.yaml.template', TARGET_UTILIZATION => $_[0] ];
};

my $hpa_sqs = sub {
    return [ 'hpa-sqs.yaml.template', QUEUE_NAME => $_[0] ];
};

my %workers = (
    # Name                    MinCt, MaxCt, Memory, MilliCpu, TgtCpu

    # New SQS based workers
    'dw-esn-cluster-subs' => [    5,    10,  '300M',  '100m',  $hpa_sqs->('dw-prod-dw-task-esn-findsubsbycluster') ],
    'dw-esn-filter-subs'  => [    5,    10,  '300M',  '300m',  $hpa_sqs->('dw-prod-dw-task-esn-filtersubs') ],
    'dw-esn-fired-event'  => [    5,    10,  '300M',  '100m',  $hpa_sqs->('dw-prod-dw-task-esn-firedevent') ],
    'dw-esn-process-sub'  => [   20,    40,  '300M',  '100m',  $hpa_sqs->('dw-prod-dw-task-esn-processsub') ],

    # Old style ESN workers, mostly deprecated, we keep one each around just
    # in case something ends up in the queue
    'esn-cluster-subs'    => [    1,    10,  '300M',   '50m',  undef ],
    'esn-filter-subs'     => [    1,    10,  '300M',   '50m',  undef ],
    'esn-fired-event'     => [    1,    10,  '300M',   '50m',  undef ],
    'esn-process-sub'     => [    1,    10,  '300M',   '50m',  undef ],

    # Other workers
    'dw-send-email'       => [    5,    20,  '300M',  '100m',  $hpa_sqs->('dw-prod-dw-task-sendemail') ],
    'send-email-ses'      => [    1,     1,  '300M',   '50m',  undef ],
    'synsuck'             => [   10,    15,  '300M',  '100m',  undef ],

    # Misc site utilities
    'codebuild-notifier'  => [    1,     1,  '300M',   '50m',  undef ],
    'metrics-emitter'     => [    1,     1,  '300M',   '50m',  undef ],
);

foreach my $worker (keys %workers) {
    my ($min, $max, $mem, $cpu, $hpa) = @{$workers{$worker}};

    my %attrs = (
        WORKER => $worker,
        MIN_REPLICAS => $min,
        MAX_REPLICAS => $max,
        CPU_REQUEST => $cpu,
        MEMORY_REQUEST => $mem,
    );

    my $yaml = template ('worker.yaml.template', %attrs );
    if ( defined $hpa ) {
        my $tmplate = shift @$hpa;
        $yaml .= "---\n";
        $yaml .= template( $tmplate, %attrs, @$hpa );
    }

    open FILE, ">generated/$worker.yaml" or die;
    print FILE $yaml;
    close FILE;
}

sub template {
    my ( $fn, %vars ) = @_;

    my $template;
    {
        local $/ = undef;
        open FILE, "<$fn" or die;
        $template = <FILE>;
        close FILE;
    }
    foreach my $var ( keys %vars ) {
        $template =~ s/\$$var/$vars{$var}/g;
    }
    return $template;
}
