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
# name: LJ::cmize::s2_get_lang
# des:  Gets the lang code for the user's style
# args: user, styleid
# des-user: user to return the style lang code for
# des-styleid: S2 style ID to return lang code for
# returns: lang code if found, undef otherwise
# </LJFUNC>
sub s2_get_lang {
    my ($u, $styleid) = @_;
    my $pub     = LJ::S2::get_public_layers();
    my $userlay = LJ::S2::get_layers_of_user($u);

    foreach ($userlay, $pub) {
        return $_->{$styleid}->{'langcode'} if
            $_->{$styleid} && $_->{$styleid}->{'langcode'};
    }
    return undef;
}

# <LJFUNC>
# name: LJ::cmize::s2_custom_layer_list
# des: custom layers will be shown in the "Custom Layers" and "Disabled Layers"
#      groups depending on the user's account status.  if they don't have the
#      s2styles cap, then they will have all layers disabled, except for the one
#      they are currently using.
# args: user, type, ptype
# des-user: User whose layers to return
# des-type: Type of layers to return
# des-ptype: Parent type of layers to return (used to restrict layers to
#            children of the layer of that type in the user's current S2 style)
# returns: A list of layer ids and names, suitable for [func[LJ::html_select]].
#          The list include separators labels for available layers and disabled
#          layers if appropriate.
# </LJFUNC>
sub s2_custom_layer_list {
    my ($u, $type, $ptype) = @_;
    my @layers = ();

    my $has_cap = LJ::get_cap($u, "s2styles");
    my $pub     = LJ::S2::get_public_layers();
    my $userlay = LJ::S2::get_layers_of_user($u);
    my %style   = LJ::S2::get_style($u, "verify");

    my @user = map { $_, $userlay->{$_}->{'name'} ? $userlay->{$_}->{'name'} : "\#$_" }
    sort { $userlay->{$a}->{'name'} cmp $userlay->{$b}->{'name'} || $a <=> $b }
    grep { /^\d+$/ && $userlay->{$_}->{'b2lid'} == $style{$ptype} &&
               $userlay->{$_}->{'type'} eq $type &&
               ($has_cap || $_ == $style{$type}) }
    keys %$userlay;
    if (@user) {
        push @layers, { value    => "",
                        text     => "--- Custom Layers: ---",
                        disabled => 1 }, @user;
    }

    unless ($has_cap) {
        my @disabled =
            map { { value    => $_,
                    text     => $userlay->{$_}->{'name'} ? $userlay->{$_}->{'name'} : "\#$_",
                    disabled => 1 } }
        sort { $userlay->{$a}->{'name'} cmp $userlay->{$b}->{'name'} ||
                   $userlay->{$a}->{'s2lid'} <=> $userlay->{$b}->{'s2lid'} }
        grep { /^\d+$/ && $userlay->{$_}->{'b2lid'} == $style{$ptype} &&
                   $userlay->{$_}->{'type'} eq $type && $_ != $style{$type} }
        keys %$userlay;
        if (@disabled) {
            push @layers, { value    => "",
                            text     => "--- Disabled Layers: ---",
                            disabled => 1 }, @disabled;
        }
    }
    return @layers;
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

# <LJFUNC>
# name: LJ::cmize::js_redirect
# des: Function to determine the correct redirect when clicking on a tab link.
# args: opts
# des-opts: Hash of options
#           - getextra: extra arguments appended to the redirected URL
# returns: Nothing
# </LJFUNC>
sub js_redirect
{
    my $POST = shift;
    my %opts = @_;

    my %redirect = (
                    "display_index" => "index",
                    "display_style" => "style",
                    "display_options" => "options",
                    "display_advanced" => "advanced",
                    );

    if ($POST->{"action:redir"} ne "" && $redirect{$POST->{"action:redir"}}) {
        BML::redirect("$LJ::SITEROOT/customize/$redirect{$POST->{'action:redir'}}$opts{getextra}");
    }
}

# <LJFUNC>
# name: LJ::cmize::get_style_thumbnails
# des: Get style thumbnail information from per-process caches,
#      or load if not available or cache is more than 5 minutes old.
# returns: {style name => thumbnail URL} hash reference, or undef on failure.
# </LJFUNC>
sub get_style_thumbnails
{
    my $now = time;
    return \%LJ::CACHE_STYLE_THUMBS if $LJ::CACHE_STYLE_THUMBS{'_loaded'} > $now - 300;
    %LJ::CACHE_STYLE_THUMBS = ();

    open (my $pfh, "$LJ::HOME/htdocs/img/stylepreview/pics.autogen.dat") or return undef;
    while (my $line = <$pfh>) {
        chomp $line;
        my ($style, $url) = split(/\t/, $line);
        $LJ::CACHE_STYLE_THUMBS{$style} = $url;
    }
    $LJ::CACHE_STYLE_THUMBS{'_loaded'} = $now;
    return \%LJ::CACHE_STYLE_THUMBS;
}

### HTML helper functions

# <LJFUNC>
# name: LJ::cmize::display_current_summary
# des: HTML helper function: Returns a block of HTML that summarizes the
#      user's current display options.
# args: user
# des-user: user whose settings to display
# returns: HTML wrapped inside a BML <?standout ... standout?> block.
# </LJFUNC>
sub display_current_summary
{
    my $u = shift;
    my $ret;
    $ret .= "<?standout <strong>Current Display Summary</strong>";

    $ret .= "<table><tr>";
    my $style_settings = "None";
    if ($u->prop('stylesys') == 2) {
        my $ustyle = LJ::S2::load_user_styles($u);
        if (%$ustyle) {
            $style_settings = $ustyle->{$u->prop('s2_style')};
        }
    } else {
        confess 'S1 deprecated.';
    }
    $ret .= "<tr valign='top'><th>Name:</th><td>" . LJ::ehtml($style_settings) . "</td></tr>";

    my $style_type = $u->prop('stylesys') == 2 ? "Wizard" : "Template" ;
    $ret .= "<th valign='top'>Type:</th><td>$style_type</td></tr>";

    my $mood_settings = "None";
    my $dbr = LJ::get_db_reader();
    if ($u->prop('moodthemeid') > 0) {
        $mood_settings = $dbr->selectrow_array("SELECT name FROM moodthemes WHERE moodthemeid=?",
                                               undef, $u->prop('moodthemeid'));
    }
    $ret .= "<tr valign='top'><th>Mood Theme:</th><td>" . LJ::ehtml($mood_settings) . "</td></tr>";

    $ret .= "</table> standout?>";
    return $ret;
}

# <LJFUNC>
# name: LJ::cmize::html_tablinks
# des: HTML helper function: Common HTML for links on top of tabs.
# args: page, getextra, opts*
# des-page: name of the current page/tab
# des-getextra: get parameters added to URLs for other pages/tabs
# returns: HTML fragment
# </LJFUNC>
sub html_tablinks
{
    my ($page, $getextra) = @_;
    my $ret;

    my %strings;
    my @tabs;

    %strings = (
        "index" => "Basics",
        "style" => "Look and Feel",
        "options" => "Custom Options",
        "advanced" => "Advanced",
    );
    @tabs = qw( index style options advanced );

    $ret .= "<ul id='Tabs'>";
    foreach my $tab (@tabs) {
        if ($page eq $tab) {
            $ret .= "<li class='SelectedTab'>$strings{$tab}</li>";
        } else {
            $ret .= "<li><a id='display_$tab' href='$tab$getextra'>$strings{$tab}</a></li>";
        }
    }
    $ret .= "</ul>";
    return $ret;
}

# <LJFUNC>
# name: LJ::cmize::html_save
# des: HTML helper function: Common HTML for the "save changes" button
#      in a tab.
# args: opts
# des-opts: hashref of options
#           - remove = add a "Remove changes" button
# returns: HTML fragment
# </LJFUNC>
sub html_save
{
    my $opts = shift;
    my $ret;

    $ret .= LJ::html_hidden({ 'name' => "action:redir", value => "", 'id' => "action:redir" });
    $ret .= "<div style='text-align: center'>";
    $ret .= LJ::html_submit('action:save', "Save Changes", { 'id' => "action:save" });
    $ret .= " " . LJ::html_submit('action:remove', "Remove Changes", {
                'id' => "action:remove",
                'onclick' => "return confirm('" . LJ::ejs("Are you sure you want to remove your changes?") . "')" }) if $opts->{remove};
    $ret .= "</div>";

    return $ret;
}

1;
