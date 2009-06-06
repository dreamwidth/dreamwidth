package LJ::Portal::Box::Birthdays; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "Birthdays";
our $_prop_keys = { 'Show' => 1 };
our $_config_props = {
    'Show' => { 'type'    => 'integer',
                'desc'    => 'Maximum number of friends to show',
                'max'     => 50,
                'min'     => 1,
                'maxlength' => 2,
                'default' => 5} };
our $_box_description = 'Show upcoming birthdays of your friends.';
our $_box_name = "Friends' Birthdays";

sub generate_content {
    my $self = shift;
    my $u = $self->{'u'};
    my @bdays = $u->get_birthdays
        or return "(No upcoming friends' birthdays.)";

    my $content = '';

    my $now = $u->time_now;

    # cut the list down
    my $show = $self->get_prop('Show');
    if (@bdays > $show) { @bdays = @bdays[0..$show-1]; }

    $content .= "<table width='100%'>";
    my $add_ord = BML::get_language() =~ /^en/i;
    foreach my $bi (@bdays)
    {
        my $mon = LJ::Lang::month_short_ml( $bi->[0] );
        my $day = $bi->[1];
        $day .= LJ::Lang::day_ord($bi->[1]) if $add_ord;

        # if their birthday is today then say so
        my $datestr = ($bi->[1] == $now->day && $bi->[0] == $now->month) ? 'Today' : "$mon $day";

        $content .= "<tr><td nowrap='nowrap'><b>" . LJ::ljuser($bi->[2]) . "</b></td>";
        $content .= "<td align='right' nowrap='nowrap'>$datestr</td>";
        my $birthday_extra = LJ::run_hook("birthday_extra_html", $bi->[2]);
        $content .= $birthday_extra ? "<td>$birthday_extra</td>" : '';
        $content .= '</tr>';
    }
    $content .= "</table>";

    return $content;
}


#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub config_props { $_config_props; }
sub prop_keys { $_prop_keys; }
sub box_class { $_box_class; }

# caching options
sub cache_global { 0; } # cache per-user
sub cache_time { 30 * 60; } # check etag every 30 minutes
sub etag {
    my $self = shift;
    my $now = DateTime->now;

    return $self->get_prop('Show') + $now->day;
}

1;
