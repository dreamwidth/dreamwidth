#!/usr/bin/perl
#

package LJ::cmize;
use strict;

use Carp qw/ confess /;

# <LJFUNC>
# name: LJ::cmize::s2_implicit_style_create
# des:  Common "create s2 style" skeleton.
# args: opts?, user, style*
# des-opts: Hash of options
#           - force: forces creation of a new style even if one already exists
# des-user: User to get layers of
# des-style: Hash of style information
#            - theme: theme id of style theme
#            - layout: layout id of style layout
#            Other keys as used by LJ::S2::set_style_layers
# returns: 1 if successful
# </LJFUNC>
sub s2_implicit_style_create
{
    my ($opts, $u, %style);

    # this is because the arguments aren't static
    # old callers don't pass in an options hashref, so we create a blank one
    if (ref $_[0] && ref $_[1]) {
        ($opts, $u) = (shift, shift);
    } else {
        ($opts, $u) = ({}, shift);
    }

    # everything else is part of the style hash
    %style = ( @_ );

    my $pub     = LJ::S2::get_public_layers();
    my $userlay = LJ::S2::get_layers_of_user($u);

    # Create new style if necessary
    my $s2style = LJ::S2::load_style($u->prop('s2_style'));
    if (! ($s2style && $s2style->{'userid'} eq $u->{'userid'}) || $opts->{'force'}) {
        my $themeid = $style{theme};
        my $layoutid = $style{layout};
        my $layer = $pub->{$themeid} || $userlay->{$themeid} || $userlay->{$layoutid};
        my $uniq = $layer->{uniq} || $layer->{s2lid};

        my $s2_style;
        unless ($s2_style = LJ::S2::create_style($u, "wizard-$uniq")) {
            die "Can't create style";
        }
        $u->set_prop("s2_style", $s2_style);
    }
    # save values in %style to db
    LJ::S2::set_style_layers($u, $u->prop('s2_style'), %style);

    return 1;
}

# <LJFUNC>
# name: LJ::cmize::validate_moodthemeid
# des: Spoof checking for mood theme ids
# args: user, themeid
# des-user: user attempting to use the mood theme
# des-themeid: mood theme user wants to use
# returns: themeid if public or owned by user, false otherwise
# </LJFUNC>
sub validate_moodthemeid {
    my ($u, $themeid) = @_;
    my $dbr = LJ::get_db_reader();
    if ($themeid) {
        my ($mownerid, $mpublic) = $dbr->selectrow_array("SELECT ownerid, is_public FROM moodthemes ".
                                                         "WHERE moodthemeid=?", undef, $themeid);
        $themeid = 0 unless $mpublic eq 'Y' || $mownerid == $u->{'userid'};
    }
    return $themeid
}

# <LJFUNC>
# name: LJ::cmize::get_moodtheme_select_list
# des: Gets mood theme list.
# args: user
# des-user: users whose private mood themes should be returned
# returns: Returns a list of mood themes that the user can select from,
#          suitable for [func[LJ::html_select]].
# </LJFUNC>
sub get_moodtheme_select_list
{
    my $u = shift;

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT moodthemeid, name FROM moodthemes WHERE is_public='Y' ORDER BY name");
    $sth->execute;

    my @themes;
    while (my $moodtheme = $sth->fetchrow_hashref) {
        my $is_active = LJ::run_hook("mood_theme_is_active", $moodtheme->{moodthemeid});
        next unless !defined $is_active || $is_active;
        push @themes, $moodtheme;
    }
    LJ::run_hook('modify_mood_theme_list', \@themes, user => $u, add_seps => 1);
    unshift @themes, { 'moodthemeid' => 0, 'name' => '(None)' };

    ### user's private themes
    {
        my @theme_user;
        $sth = $dbr->prepare("SELECT moodthemeid, name FROM moodthemes WHERE ownerid=? AND is_public='N'");
        $sth->execute($u->{'userid'});
        push @theme_user, $_ while ($_ = $sth->fetchrow_hashref);
        if (@theme_user) {
            push @themes, { 'moodthemeid' => 0, 'name' => "--- " . BML::ml('/modify_do.bml.moodicons.personal'). " ---", disabled => 1 };
            push @themes, @theme_user;
        }
    }

    return @themes;
}

1;
