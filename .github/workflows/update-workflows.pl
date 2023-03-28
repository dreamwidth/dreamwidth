#!/usr/bin/perl
#
# update-workflows.pl
#
# Update the worker workflow files. This file also contains information about
# the workers that run in ECS... that should really be somewhere else, but we
# have it here for now.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2022 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use v5.10;

use lib "$ENV{LJHOME}/extlib/lib/perl5";

use Template;

my %workers = (

    # Name                    MinCt, MaxCt, Memory, MilliCpu, TgtCpu

    # New SQS based workers
    'dw-esn-cluster-subs' => [ 1, 50, 512, 256, 50, ],
    'dw-esn-filter-subs'  => [ 1, 50, 512, 256, 50, ],
    'dw-esn-fired-event'  => [ 1, 50, 512, 256, 50, ],
    'dw-esn-process-sub'  => [ 1, 50, 512, 256, 50, ],
    'dw-sphinx-copier'    => [ 1, 50, 512, 256, 50, ],

    # Old style ESN workers, mostly deprecated, we keep one each around just
    # in case something ends up in the queue
    'esn-cluster-subs' => [ 1, 10, 512, 256, 50, ],
    'esn-filter-subs'  => [ 1, 10, 512, 256, 50, ],
    'esn-fired-event'  => [ 1, 10, 512, 256, 50, ],
    'esn-process-sub'  => [ 1, 10, 512, 256, 50, ],

    # Importer workers
    'content-importer-verify' => [ 1, 1, 512,  256, 50 ],
    'content-importer-lite'   => [ 4, 4, 512,  256, 50 ],
    'content-importer'        => [ 2, 2, 2048, 256, 50 ],

    # Other workers
    'birthday-notify'    => [ 1, 1,  512, 256, 50, ],
    'change-poster-id'   => [ 1, 1,  512, 256, 50, ],
    'directory-meta'     => [ 1, 1,  512, 256, 50, ],
    'distribute-invites' => [ 1, 1,  512, 256, 50, ],
    'dw-send-email'      => [ 1, 50, 512, 256, 50, ],
    'embeds'             => [ 1, 15, 512, 256, 50, ],
    'resolve-extacct'    => [ 1, 1,  512, 256, 50, ],
    'send-email-ses'     => [ 1, 1,  512, 256, 50, ],
    'spellcheck-gm'      => [ 1, 1,  512, 256, 50, ],
    'sphinx-copier'      => [ 1, 1,  512, 256, 50, ],
    'sphinx-search-gm'   => [ 1, 1,  512, 256, 50, ],
    'synsuck'            => [ 1, 20, 512, 256, 50, ],

    # Misc site utilities
    'codebuild-notifier' => [ 1, 1, 512, 256, 50, ],

    #'metrics-emitter'     => [    1,     1,  512,  256,  50, ],

    # DO NOT run these in k8s... until we have some way of having a dedicated IP,
    # we keep getting banned by LJ.
    # 'xpost'               => [    1,     1,  '300M',   '50m' ],
    # importers...
);

# Generate deployment workflow
my $tt = Template->new() or die;
$tt->process( 'worker-deploy.tt', { workers => \%workers }, 'worker-deploy.yml' )
    or die $tt->error;

# Generate task JSONs
foreach my $worker ( keys %workers ) {
    $tt->process(
        'tasks/worker-service.tt',
        {
            name   => $worker,
            cpu    => $workers{$worker}->[3],
            memory => $workers{$worker}->[2],
        },
        "tasks/worker-$worker-service.json"
    ) or die $tt->error;
}
