package LJ::Portal::Box::Tags;
use base 'LJ::Portal::Box';
use strict;

######################## configuration data ######################

our $_box_class = "Tags";
our $_prop_keys = { 'Show' => 1 };
our $_config_props = {
    'Show' => { 'type'    => 'integer',
                'desc'    => 'Number of tags to show, sorted by most used first',
                'max'     => 9999,
                'min'     => 1,
                'maxlength' => 4,
                'default' => 10 } };
our $_box_description = 'Show your most frequently used tags.';
our $_box_name = "Frequent Tags";

sub generate_content {
    my $self = shift;
    my $u = $self->{'u'};

    # get tags, sort by use, filter
    my $tags = LJ::Tags::get_usertags($u);
    unless ($tags && %$tags) {
        return "You haven't used any tags yet!";
    }

    my $show = $self->get_prop('Show');
    my @sorted = sort { $tags->{$b}->{uses} <=> $tags->{$a}->{uses} } keys %$tags;
    @sorted = splice(@sorted, 0, $show) if $show;

    my $content = "<table width='100%'>";
    foreach my $id (@sorted) {
        $content .= "<tr><td nowrap='nowrap'>";
        $content .= "<a href='";
        $content .= LJ::journal_base($u) . '/tag/' . LJ::eurl($tags->{$id}->{name});
        $content .= "'>";
        $content .= LJ::ehtml($tags->{$id}->{name});
        $content .= "</a> - " . $tags->{$id}->{uses} . " uses";
        $content .= "</td></tr>";
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
sub etag { time(); } # refreshes every 30 minutes

1;
