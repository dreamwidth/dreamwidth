# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

package LJ::Widget::CreateAccountProfile;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::Constants;

sub need_res { qw( stc/widgets/createaccountprofile.css js/widgets/createaccountprofile.js ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = LJ::get_effective_remote();
    my $post = $opts{post};
    my $from_post = $opts{from_post};
    my $errors = $from_post->{errors};
    my $loc_post = LJ::Widget->post_fields_of_widget("Location");

    my $error_msg = sub {
        my ( $key, $pre, $post ) = @_;
        my $msg = $errors->{$key};
        return unless $msg;
        return "$pre $msg $post";
    };

    my $ret;
    $ret .= "<h2>" . $class->ml('widget.createaccountprofile.title') . "</h2>";
    $ret .= "<p>" . $class->ml('widget.createaccountprofile.info') . "</p>";

    $ret .= "<table cellspacing='3' cellpadding='0'>\n";

    ### name
    $ret .= "<tr valign='middle'><td class='field-name'>" . $class->ml('widget.createaccountprofile.field.name') . "</td>\n<td>";
    if (LJ::text_in($u->name_orig)) {
        $ret .= $class->html_text(
            name => 'name',
            size => 40,
            value => $post->{name} || $u->name_orig || "",
        );
    } else {
        $ret .= $class->html_hidden( name_absent => "yes" );
        $ret .= "<?inerr " . LJ::Lang::ml('/manage/profile/index.bml.error.invalidname2', { aopts => "href='$LJ::SITEROOT/utf8convert'" }) . " inerr?>";
    }
    $ret .= $error_msg->('name', '<br /><span class="formitemFlag">', '</span>');
    $ret .= "</td></tr>\n";

    ### gender
    $ret .= "<tr valign='middle'><td class='field-name'>" . $class->ml('widget.createaccountprofile.field.gender') . "</td>\n<td>";
    $ret .= $class->html_select(
        name => 'gender',
        selected => $post->{gender} || $u->prop( 'gender' ) || 'U',
        list => [
            F => LJ::Lang::ml('/manage/profile/index.bml.gender.female'),
            M => LJ::Lang::ml('/manage/profile/index.bml.gender.male'),
            O => LJ::Lang::ml('/manage/profile/index.bml.gender.other'),
            U => LJ::Lang::ml('/manage/profile/index.bml.gender.unspecified'),
        ],
    );
    $ret .= $error_msg->('gender', '<br /><span class="formitemFlag">', '</span>');
    $ret .= "</td></tr>\n";

    $ret .= "<tr valign='middle'><td class='field-name'>" . $class->ml('widget.createaccountprofile.field.location') . "</td>\n<td>";
    $ret .= LJ::Widget::Location->render( minimal_display => 1, skip_timezone => 1, $loc_post );
    $ret .= "</td></tr>\n";

    $ret .= "</table><br />\n";

    $ret .= "<p class='header'>" . $class->ml('widget.createaccountprofile.field.interests') . " ";
    $ret .= "<span class='header-note'>" . $class->ml('widget.createaccountprofile.field.interests.note') . "</p>\n";

    $ret .= "<table cellspacing='3' cellpadding='0'>\n";

    my @eintsl;
    my $interests = $u->interests;
    foreach (sort keys %$interests) {
        push @eintsl, $_ if LJ::text_in($_);
    }

    ### interests: music
    $ret .= "<tr valign='middle'><td class='field-name'>" . $class->ml('widget.createaccountprofile.field.interests.music') . "</td>\n<td>";
    $ret .= $class->html_text(
        name => 'interests_music',
        id => 'interests_music',
        size => 35,
        value => $post->{interests_music_changed} ? $post->{interests_music} : '',
    );
    $ret .= $class->html_hidden({ name => "interests_music_changed", value => 0, id => "interests_music_changed" });
    $ret .= "</td>\n";

    ### interests: movies/tv
    $ret .= "<td class='field-name'>" . $class->ml('widget.createaccountprofile.field.interests.moviestv') . "</td>\n<td>";
    $ret .= $class->html_text(
        name => 'interests_moviestv',
        id => 'interests_moviestv',
        size => 35,
        value => $post->{interests_moviestv_changed} ? $post->{interests_moviestv} : '',
    );
    $ret .= $class->html_hidden({ name => "interests_moviestv_changed", value => 0, id => "interests_moviestv_changed" });
    $ret .= "</td></tr>\n";

    ### interests: books
    $ret .= "<tr valign='middle'><td class='field-name'>" . $class->ml('widget.createaccountprofile.field.interests.books') . "</td>\n<td>";
    $ret .= $class->html_text(
        name => 'interests_books',
        id => 'interests_books',
        size => 35,
        value => $post->{interests_books_changed} ? $post->{interests_books} : '',
    );
    $ret .= $class->html_hidden({ name => "interests_books_changed", value => 0, id => "interests_books_changed" });
    $ret .= "</td>\n";

    ### interests: hobbies
    $ret .= "<td class='field-name'>" . $class->ml('widget.createaccountprofile.field.interests.hobbies') . "</td>\n<td>";
    $ret .= $class->html_text(
        name => 'interests_hobbies',
        id => 'interests_hobbies',
        size => 35,
        value => $post->{interests_hobbies_changed} ? $post->{interests_hobbies} : '',
    );
    $ret .= $class->html_hidden({ name => "interests_hobbies_changed", value => 0, id => "interests_hobbies_changed" });
    $ret .= "</td></tr>\n";

    ### interests: other
    $ret .= "<tr valign='middle'><td class='field-name'>" . $class->ml('widget.createaccountprofile.field.interests.other') . "</td>\n<td colspan='3'>";
    $ret .= $class->html_text(
        name => 'interests_other',
        id => 'interests_other',
        size => 88,
        value => $post->{interests_other_changed} ? $post->{interests_other} : join(", ", @eintsl),
    );
    $ret .= $class->html_hidden({ name => "interests_other_changed", value => 0, id => "interests_other_changed" });
    $ret .= $error_msg->('interests', '<br /><span class="formitemFlag">', '</span>');
    $ret .= "</td></tr>\n";

    $ret .= "</table><br />\n";

    $ret .= "<p class='header'>" . $class->ml('widget.createaccountprofile.field.bio') . "</p>\n";

    ### bio
    my $bio = $post->{bio} || $u->bio;
    LJ::EmbedModule->parse_module_embed($u, \$bio, edit => 1);
    LJ::text_out(\$bio, "force");

    if (LJ::text_in($u->bio)) {
        $ret .= $class->html_textarea(
            name => 'bio',
            rows => 7,
            cols => 75,
            wrap => "soft",
            value => $bio,
        );
    } else {
        $ret .= $class->html_hidden( bio_absent => "yes" );
        $ret .= "<?inerr " . LJ::Lang::ml('/manage/profile/index.bml.error.invalidbio', { aopts => "href='$LJ::SITEROOT/utf8convert'" }) . " inerr?>";
    }
    $ret .= $error_msg->('bio', '<br /><span class="formitemFlag">', '</span>');

    # hidden field to know if JS is on or not
    $ret .= $class->html_hidden({ name => "js_on", value => 0, id => "js_on" });

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $u = LJ::get_effective_remote();
    my %from_post;

    # name
    $from_post{errors}->{name} = LJ::Lang::ml('/manage/profile/index.bml.error.noname') unless LJ::trim($post->{name}) || defined $post->{name_absent};
    $from_post{errors}->{name} = LJ::Lang::ml('/manage/profile/index.bml.error.name.toolong') if length $post->{name} > 80;
    $post->{name} =~ s/[\n\r]//g;
    $post->{name} = LJ::text_trim($post->{name}, LJ::BMAX_NAME, LJ::CMAX_NAME);

    # gender
    $post->{gender} = 'U' unless $post->{gender} =~ m/^[UMFO]$/;

    # location is handled by LJ::Widget::Location

    # interests
    my @interests_strings;
    push @interests_strings, $post->{interests_music} if !$post->{js_on} || $post->{interests_music_changed};
    push @interests_strings, $post->{interests_moviestv} if !$post->{js_on} || $post->{interests_moviestv_changed};
    push @interests_strings, $post->{interests_books} if !$post->{js_on} || $post->{interests_books_changed};
    push @interests_strings, $post->{interests_hobbies} if !$post->{js_on} || $post->{interests_hobbies_changed};
    push @interests_strings, $post->{interests_other} if !$post->{js_on} || $post->{interests_other_changed};
    my $interests_string = join(", ", @interests_strings);
    my @ints = LJ::interest_string_to_list($interests_string);

    # count interests
    my $intcount = scalar @ints;
    my $maxinterests = $u->count_max_interests;

    $from_post{errors}->{interests} = LJ::Lang::ml('error.interest.excessive2', { intcount => $intcount, maxinterests => $maxinterests })
        if $intcount > $maxinterests;

    # clean interests, and make sure they're valid
    my @interrors;
    my @valid_ints = LJ::validate_interest_list(\@interrors, @ints);
    if (@interrors > 0) {
        my $err = $interrors[0];
        $from_post{errors}->{interests} = LJ::Lang::ml( $err->[0],
                                            { words => $err->[1]{words},
                                              words_max => $err->[1]{words_max},
                                              'int' => $err->[1]{int} } );
    }

    my $old_interests = $u->interests;

    # bio
    $from_post{errors}->{bio} = LJ::Lang::ml('/manage/profile/index.bml.error.bio.toolong') if length $post->{bio} >= LJ::BMAX_BIO;
    LJ::EmbedModule->parse_module_embed($u, \$post->{bio});

    unless (keys %{$from_post{errors}}) {
        LJ::update_user($u, { name => $post->{name} });
        $u->invalidate_directory_record;
        $u->set_prop('gender', $post->{gender});
        $u->set_interests($old_interests, \@valid_ints);
        $u->set_bio($post->{bio}, $post->{bio_absent});
    }

    return %from_post;
}

1;
