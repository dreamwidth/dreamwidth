#!/usr/bin/perl
#
# DW::PageStats::GoogleAnalytics4
#
# LJ::PageStats module for Google Analytics
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::PageStats::GoogleAnalytics4;
use base 'LJ::PageStats';
use strict;

sub _render_head {
    my ($self) = @_;
    return '' unless $self->should_do_pagestats;

    my $ctx = $self->get_context;

    my $code;
    if ( $ctx eq 'app' ) {
        $code = $LJ::SITE_PAGESTAT_CONFIG{ga4_analytics};
    }
    elsif ( $ctx eq 'journal' ) {
        $code = LJ::get_active_journal()->ga4_analytics;

        # the ejs call isn't strictly necessary but catches any
        # dodgy analytics codes which may have been stored before
        # validation was implemented.
        $code = LJ::ejs($code);
    }

    return qq{<!-- Global site tag (gtag.js) - Google Analytics -->
<script async src="https://www.googletagmanager.com/gtag/js?id=$code"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());

  gtag('config', '$code');
</script>
};
}


sub should_render {
    my ($self) = @_;

    my $ctx = $self->get_context;
    return 0 unless $ctx && $ctx =~ /^(app|journal)$/;

    if ( $ctx eq 'app' ) {
        return 1 if defined $LJ::SITE_PAGESTAT_CONFIG{ga4_analytics};
    }
    elsif ( $ctx eq 'journal' ) {
        my $u = LJ::get_active_journal();
        return $u && $u->can_use_google_analytics && $u->ga4_analytics ? 1 : 0;
    }
    return 0;
}

1;
