#!/usr/bin/perl

use strict;
use v5.10;

my %workers = (
    # Name                    MinCt, MaxCt, Memory, MilliCpu, TgtCpu

    # New SQS based workers
    'dw-esn-cluster-subs' => [    3,    20,  '300M',  '300m',   100  ],
    'dw-esn-filter-subs'  => [    3,    20,  '300M',  '300m',   100  ],
    'dw-esn-fired-event'  => [    3,    20,  '300M',  '300m',   100  ],
    'dw-esn-process-sub'  => [    3,    50,  '300M',  '300m',   100  ],

    # Old style ESN workers
    'esn-cluster-subs'    => [    1,    20,  '300M',  '100m',   100  ],
    'esn-filter-subs'     => [    1,    20,  '300M',  '300m',   100  ],
    'esn-fired-event'     => [    1,    20,  '300M',  '100m',   100  ],
    'esn-process-sub'     => [    1,    50,  '300M',   '50m',   100  ],

    # Other workers
    'send-email-ses'      => [   40,   100,  '300M',   '50m',   100  ],
    'synsuck'             => [   10,    30,  '300M',  '100m',   100  ],

    # Misc site utilities
    'codebuild-notifier'  => [    1,     1,  '300M',   '50m',   100  ],
);

my $template;
{
    local $/ = undef;
    open FILE, "<worker.yaml.template" or die;
    $template = <FILE>;
    close FILE;
}

foreach my $worker (keys %workers) {
    my ($min, $max, $mem, $cpu, $util) = @{$workers{$worker}};

    my $yaml = $template;
    $yaml =~ s/\$WORKER/$worker/g;
    $yaml =~ s/\$MIN_REPLICAS/$min/g;
    $yaml =~ s/\$MAX_REPLICAS/$max/g;
    $yaml =~ s/\$CPU_REQUEST/$cpu/g;
    $yaml =~ s/\$MEMORY_REQUEST/$mem/g;
    $yaml =~ s/\$TARGET_UTILIZATION/$util/g;

    open FILE, ">generated/$worker.yaml" or die;
    print FILE $yaml;
    close FILE;
}
