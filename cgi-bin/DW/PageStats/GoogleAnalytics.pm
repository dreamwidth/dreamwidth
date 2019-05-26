#!/usr/bin/perl
#
# DW::PageStats::GoogleAnalytics
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
package DW::PageStats::GoogleAnalytics;
use base 'LJ::PageStats';
use strict;

sub _render_head {
    my ($self) = @_;
    return '' unless $self->should_do_pagestats;

    my $ctx = $self->get_context;

    my $code;
    if ( $ctx eq 'app' ) {
        $code = $LJ::SITE_PAGESTAT_CONFIG{google_analytics};
    }
    elsif ( $ctx eq 'journal' ) {
        $code = LJ::get_active_journal()->google_analytics;

        # the ejs call isn't strictly necessary but catches any
        # dodgy analytics codes which may have been stored before
        # validation was implemented.
        $code = LJ::ejs($code);
    }

    return qq{<script type="text/javascript">
  var _gaq = _gaq || [];
  _gaq.push(['_setAccount', '$code']);
  _gaq.push(['_trackPageview']);</script>
};
}

sub _render {
    my ($self) = @_;

    return '' unless $self->should_do_pagestats;

    return qq{<script type="text/javascript">
  (function() {
    var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
    ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
    var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
  })();

</script>
};
}

sub should_render {
    my ($self) = @_;

    my $ctx = $self->get_context;
    return 0 unless $ctx && $ctx =~ /^(app|journal)$/;

    if ( $ctx eq 'app' ) {
        return 1 if defined $LJ::SITE_PAGESTAT_CONFIG{google_analytics};
    }
    elsif ( $ctx eq 'journal' ) {
        my $u = LJ::get_active_journal();
        return $u && $u->can_use_google_analytics && $u->google_analytics ? 1 : 0;
    }
    return 0;
}

1;
