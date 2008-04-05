package LJ::Widget::VerticalContentControl;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Vertical );

sub need_res { }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $get = $opts{get};
    my $post = $opts{post};

    my $action = $get->{action};
    my $ret;

    my @verticals = $class->verticals_remote_can_moderate;
    return "You do not have access to any verticals." unless @verticals;

    if ($action eq "add" || $action eq "remove") {
        $ret .= "<table><tr valign='top'><td>" if $action eq "add";

        $ret .= $class->start_form;

        $ret .= "<table border='0'>";
        $ret .= "<tr><td valign='top'>";
        $ret .= $action eq "add" ? "Add entry to vertical(s):" : "Remove entry from vertical(s):";
        $ret .= "</td><td>";
        if (@verticals > 1) {
            $ret .= $class->html_select(
                name => 'verticals',
                list => [ map { $_->vertid, $_->display_name } @verticals ],
                multiple => 'multiple',
                size => 5,
            );
        } else {
            $ret .= "<strong>" . $verticals[0]->display_name . "</strong>";
            $ret .= $class->html_hidden( verticals => $verticals[0]->vertid );
        }
        $ret .= "</td></tr>";

        $ret .= "<tr><td>Entry URL:</td><td>";
        $ret .= $class->html_text(
            name => 'entry_url',
            size => 50,
        ) . "</td></tr>";

        $ret .= "<tr><td colspan='2'>" . $class->html_submit( $action => $action eq "add" ? "Add Entry" : "Remove Entry" ) . " ";
        $ret .= "<a href='$LJ::SITEROOT/admin/verticals/'>Return to Options List</a></td></tr>";
        $ret .= "</table>";

        $ret .= $class->end_form;

        if ($action eq "add") {
            $ret .= "</td><td>";
            $ret .= "<p><strong>You will get an error unless the entry you're adding meets all of the following requirements:</strong></p>";
            $ret .= "<ul><li>The entry must be active, public, and not banned/excluded from verticals.</li>";
            $ret .= "<li>There must not be more than 3 images in the entry.</li>";
            $ret .= "<li>All of the images in the entry must work.</li>";
            $ret .= $class->ml('widget.verticalcontentcontrol.extrarestrictions');
            $ret .= "</ul></td></tr></table>";
        }
    } elsif ($action eq "view" || $action eq "cats") {
        die "You do not have access to this." if $action eq "cats" && ! LJ::run_hook("remote_can_get_categories_for_entry");

        unless ($post->{return_url}) {
            $ret .= $class->start_form;

            $ret .= "<?p Entry URL: ";
            $ret .= $class->html_text(
                name => 'entry_url',
                size => 50,
            ) . " p?>";

            my $btn_text = $action eq "view" ? "View Entry Verticals" : "View Entry Categories";
            $ret .= "<tr><td colspan='2'>" . $class->html_submit( $action => $btn_text ) . " ";
            $ret .= "<a href='$LJ::SITEROOT/admin/verticals/'>Return to Options List</a></td></tr>";

            $ret .= $class->end_form;
        }
    } elsif ($action eq "rules") {
        my $vertical_name = $get->{vertical_name};
        return "You must define a vertical name." unless $vertical_name;

        my $vertical_obj;
        foreach my $v (@verticals) {
            if ($v->name eq $vertical_name) {
                $vertical_obj = $v;
                last;
            }
        }

        return "You do not have permission to define the rules of this vertical." unless $vertical_obj;

        my $whitelist = $class->rules_array_to_string($vertical_obj->rules_whitelist);
        my $blacklist = $class->rules_array_to_string($vertical_obj->rules_blacklist);

        if ($post && keys %$post) {
            $whitelist = $post->{whitelist_rules};
            $blacklist = $post->{blacklist_rules};
        }

        $ret .= "<p><strong>Example Rules for Whitelist:</strong></p>";
        $ret .= "<table cellpadding='3' border='1'>";
        $ret .= "<tr><td><code>0.4 Life::Pets</code></td><td>entries with at least 40% certainty of the category Life::Pets will appear in this vertical</td></tr>";
        $ret .= "<tr><td><code>Lang::EN</code></td><td>entries written in English will appear in this vertical</td></tr>";
        $ret .= "<tr><td><code>WordCount::100</code></td><td>entries that are at least 100 words long will appear in this vertical (default is 50)</td></tr>";
        $ret .= "</table>";

        $ret .= "<p>The blacklist can use the first rule above, which does the same thing except that entries that match the defined category/ies will be excluded from this vertical.</p>";
        $ret .= "<hr />";

        $ret .= $class->start_form;
        $ret .= "<p>Define <strong>whitelist</strong> rules for vertical <strong>" . $vertical_obj->display_name . "</strong>:<br />";
        $ret .= $class->html_textarea(
            name => "whitelist_rules",
            value => $whitelist,
            rows => 15,
            cols => 60,
        ) . "</p>";

        $ret .= "<p>Define <strong>blacklist</strong> rules for vertical <strong>" . $vertical_obj->display_name . "</strong>:<br />";
        $ret .= $class->html_textarea(
            name => "blacklist_rules",
            value => $blacklist,
            rows => 15,
            cols => 60,
        ) . "</p>";

        $ret .= $class->html_hidden( vertical_name => $vertical_obj->name );
        $ret .= $class->html_submit( rules => "Define Rules" );
        $ret .= $class->end_form;
    } else {
        $ret .= "<strong>Options:</strong><br />";
        $ret .= "<a href='$LJ::SITEROOT/admin/verticals/?action=add'>Add an entry to vertical(s)</a><br />";
        $ret .= "<a href='$LJ::SITEROOT/admin/verticals/?action=remove'>Remove an entry from vertical(s)</a><br />";
        $ret .= "<a href='$LJ::SITEROOT/admin/verticals/?action=view'>View which vertical(s) an entry is in</a><br />";
        if (LJ::run_hook("remote_can_get_categories_for_entry")) {
            $ret .= "<a href='$LJ::SITEROOT/admin/verticals/?action=cats'>View category information for an entry</a><br />";
        }
        $ret .= "<a href='$LJ::SITEROOT/admin/verticals/editorials/'>Manage editorial content for vertical(s)</a><br />";
        $ret .= "<br />";

        $ret .= "<form method='GET'>";
        $ret .= "Define rules for vertical: ";
        if (@verticals > 1) {
            $ret .= LJ::html_select({ name => 'vertical_name' }, map { $_->name, $_->display_name } @verticals);
        } else {
            $ret .= "<strong>" . $verticals[0]->display_name . "</strong>";
            $ret .= LJ::html_hidden( vertical_name => $verticals[0]->name );
        }
        $ret .= LJ::html_hidden( action => "rules" );
        $ret .= " " . LJ::html_submit("Go");
        $ret .= "</form>";
    }

    return $ret;    
}

sub verticals_remote_can_moderate {
    my $class = shift;

    my $remote = LJ::get_remote();
    my @verticals;

    if (LJ::check_priv($remote, "vertical", "*") || $LJ::IS_DEV_SERVER) {
        @verticals = LJ::Vertical->load_all;
    } else {
        foreach my $vert (keys %LJ::VERTICAL_TREE) {
            my $v = LJ::Vertical->load_by_name($vert);
            if ($v->remote_is_moderator) {
                push @verticals, $v;
            }
        }
    }

    return sort { $a->name cmp $b->name } @verticals;
}

sub rules_array_to_string {
    my $class = shift;
    my @rules = @_;

    my $str;
    foreach my $rule (@rules) {
        $str .= "$rule->[0] " if $rule->[0];
        $str .= "$rule->[1]\n";
    }
    chomp $str;

    return $str;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $remote = LJ::get_remote();

    my $action;
    if ($post->{add}) {
        $action = "add";
    } elsif ($post->{remove}) {
        $action = "remove";
    } elsif ($post->{view}) {
        $action = "view";
    } elsif ($post->{cats} && LJ::run_hook("remote_can_get_categories_for_entry")) {
        $action = "cats";
    } elsif ($post->{rules}) {
        $action = "rules";
    } else {
        die "Invalid action.";
    }

    my $entry;
    unless ($action eq "rules") {
        die "An entry URL must be provided." unless $post->{entry_url};

        $entry = LJ::Entry->new_from_url($post->{entry_url});
        die "Invalid entry URL." unless $entry && $entry->valid;
    }

    my @verts;
    my $cat_info;
    if ($action eq "add" || $action eq "remove") {
        die "At least one vertical must be selected." unless $post->{verticals};

        my @verticals = split('\0', $post->{verticals});
        my @vert_names;
        foreach my $vertid (@verticals) {
            my $v = LJ::Vertical->load_by_id($vertid);
            die "You cannot perform this action." if $action eq "add" && !$v->remote_is_moderator;
            die "You cannot perform this action." if $action eq "remove" && !$v->remote_can_remove_entry($entry);

            push @vert_names, $v->name;
            if ($action eq "add") {
                if ($entry->can_be_added_to_verticals_by_admin) {
                    $v->add_entry($entry);
                } else {
                    die "This entry cannot be added to verticals.";
                }
            } else {
                $v->remove_entry($entry);
            }
        }

        my $vert_list = join(", ", @vert_names);
        LJ::statushistory_add($entry->journal, $remote, "vertical moderation", "$action to/from $vert_list (entry " . $entry->ditemid . ")");
    } elsif ($action eq "view") {
        my @verticals = keys %LJ::VERTICAL_TREE;

        foreach my $vert (@verticals) {
            my $v = LJ::Vertical->load_by_name($vert);
            die "You cannot perform this action." unless $v->remote_is_moderator;

            if ($v->entry_insert_time($entry)) {
                push @verts, $v;
            }
        }
    } elsif ($action eq "cats") {
        $cat_info = LJ::run_hook("get_categories_for_entry", $entry);
    } elsif ($action eq "rules") {
        my $name = $post->{vertical_name};
        my $v = LJ::Vertical->load_by_name($name);
        die "Invalid vertical." unless $v;
        die "You cannot define rules for this vertical." unless $v->remote_is_moderator;

        $v->set_rules( whitelist => $post->{whitelist_rules}, blacklist => $post->{blacklist_rules} );
    }

    return ( action => $action, verticals => \@verts, category_info => $cat_info, return_url => $post->{return_url} );
}

1;
