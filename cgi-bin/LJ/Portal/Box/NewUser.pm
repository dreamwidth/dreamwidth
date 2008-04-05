package LJ::Portal::Box::NewUser; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "NewUser";
our $_box_description = "New Users - Start Here";
our $_box_name = "New Users - Start Here";

sub generate_content {
    my $self = shift;
    my $content = '';
    my $pboxid = $self->pboxid;
    my $u = $self->{'u'};

    my $profile_url = $u->profile_url;
    my $base = $u->journal_base;

    $content .= qq {
        <table style="width: 100%; border: 0px;">
            <tr>
                <td style="width: 50%;">
                    1) <a href="$LJ::SITEROOT/update.bml">Write</a> a journal entry<br />
                    2) <a href="$LJ::SITEROOT/editpics.bml">Upload</a> userpics<br />
                    3) <a href="$LJ::SITEROOT/manage/profile/">Fill out</a> your <a href="$profile_url">profile</a><br />
                </td>
                <td style="width: 50%;">
                     4) <a href="$LJ::SITEROOT/customize/">Customize</a> the look of your journal<br />
                     5) <a href="$LJ::SITEROOT/interests.bml">Find</a> friends and communities by interests<br />
                     6) <a href="$base/friends">Read</a> your Friends page<br />
                </td>
            </tr>
        </table>
    <span class="NewUserMoreLink"><a href="$LJ::SITEROOT/manage/">more</a></span>
    };

    return $content;
}

# add by default if new user (account created after portal goes live date)
sub default_added {
    my ($self, $u) = @_;

    return 1;
}

#######################################

sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }

1;
