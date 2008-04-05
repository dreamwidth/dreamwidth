package LJ::Portal::Box::UpdateJournal; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_description = 'A handy box for updating your journal.';
our $_box_name = "Quick Update";
our $_box_class = "UpdateJournal";

sub generate_content {
    my $self = shift;

    my $content = '';
    my $pboxid = $self->pboxid;
    my $u = $self->{'u'};

    my $subjectwidget = LJ::entry_form_subject_widget('UpdateBoxSubject');
    my $entrywidget = LJ::entry_form_entry_widget('UpdateBoxEvent');
    my $postto = LJ::entry_form_postto_widget($u, 'UpdateBoxPostTo');
    my $securitywidget = LJ::entry_form_security_widget($u, 'UpdateBoxSecurity');
    my $tagswidget = LJ::entry_form_tags_widget();

    $postto = $postto ? $postto . '<br/><br/>' : '';

    my $formauth = LJ::form_auth();

    $content .= "<form action='$LJ::SITEROOT/update.bml' method='POST' name='updateform'>";

    # translation stuff:
    my $subjecttitle =  BML::ml('portal.update.subject');
    my $eventtitle = BML::ml('portal.update.entry');
    my $updatetitle = BML::ml('/update.bml.btn.update');
    my $moreoptstitle = BML::ml('portal.update.moreopts');

    my $posttotitle = BML::ml('entryform.postto');
    my $securitytitle = BML::ml('entryform.security');
    my $tagstitle = BML::ml('entryform.tags');

    my $posttowidget = '';

    if ($postto) {
        $posttowidget = qq {
                <tr>
                <td valign="bottom" align="left" width="20%">
                $posttotitle</td><td>$postto</td>
                </tr>
            };
    }

    $content .= qq {
            $formauth
                <input type="hidden" name="realform" value="1" />

                <b>$subjecttitle</b><br/>
                $subjectwidget<br/>

                <b>$eventtitle</b><br/>
                $entrywidget<br/>

                <table width="100%">

                $posttowidget

                <tr>
                <td valign="bottom" align="left" width="20%">
                $securitytitle</td><td>$securitywidget</td>
                </tr>

                <tr>
                <td valign="bottom" align="left" width="20%">
                $tagstitle</td><td>$tagswidget</td>
                </tr>

                </table>

                <br/>
                <input type="submit" value="$updatetitle" name="postentry" onclick="return portal_settime();" /> <input type="submit" name="moreoptsbtn" value="$moreoptstitle"/>
                </form>
            };

    return $content;
}


#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }
#sub config_props { $_config_props; }
#sub prop_keys { $_prop_keys; }

1;
