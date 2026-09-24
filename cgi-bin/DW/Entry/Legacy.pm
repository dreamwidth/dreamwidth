#!/usr/bin/perl
#
# This code was extracted from LJ::Web, which was forked from the LiveJournal
# project owned and operated by Live Journal, Inc. The code has been modified
# and expanded by Dreamwidth Studios, LLC. These files were originally licensed
# under the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its modifications
# are provided under the GNU General Public License. A copy of that license can
# be found in the LICENSE file included as part of this distribution.

package DW::Entry::Legacy;

use strict;
use warnings;

use DW::Mood;
use Hash::MultiValue;
use LJ::HTMLControls;
use LJ::Lang;
use Scalar::Util qw(blessed);

# Flatten a Hash::MultiValue POST, joining repeated values with \0.
sub legacy_post_hash {
    my ($post) = @_;
    return $post unless blessed($post) && $post->isa('Hash::MultiValue');

    my %legacy;
    $post->each(
        sub {
            my ( $name, $value ) = @_;
            $legacy{$name} .= "\0" if exists $legacy{$name};
            $legacy{$name} .= $value;
        }
    );
    return \%legacy;
}

# Decode a legacy update/editjournal POST into the native canonical entry
# hash; tz stays guess unless the submitted date is trusted.
sub prepare_entry_form {
    my ($post) = @_;

    my $legacy_post = legacy_post_hash($post);
    my $canonical   = { tz => 'guess', props => {} };
    my $props       = $canonical->{props};

    # find security
    my $sec   = "public";
    my $amask = 0;
    if ( $legacy_post->{'security'} eq "private" ) {
        $sec = "private";
    }
    elsif ( $legacy_post->{'security'} eq "friends" ) {
        $sec   = "usemask";
        $amask = 1;
    }
    elsif ( $legacy_post->{'security'} eq "custom" ) {
        $sec = "usemask";
        foreach my $bit ( 1 .. 60 ) {
            next unless $legacy_post->{"custom_bit_$bit"};
            $amask |= ( 1 << $bit );
        }
    }
    $canonical->{'security'}  = $sec;
    $canonical->{'allowmask'} = $amask;

    # date/time
    my $date = LJ::html_datetime_decode( { 'name' => "date_ymd", }, $legacy_post );
    my ( $year, $mon, $day ) = split( /\D/, $date );
    my ( $hour, $min ) = ( $legacy_post->{'hour'}, $legacy_post->{'min'} );

    # TEMP: ease golive by using older way of determining differences
    my $date_old = LJ::html_datetime_decode( { 'name' => "date_ymd_old", }, $legacy_post );
    my ( $year_old, $mon_old, $day_old ) = split( /\D/, $date_old );
    my ( $hour_old, $min_old ) = ( $legacy_post->{'hour_old'}, $legacy_post->{'min_old'} );

    my $different = $legacy_post->{'min_old'}
        && ( ( $year ne $year_old )
        || ( $mon ne $mon_old )
        || ( $day ne $day_old )
        || ( $hour ne $hour_old )
        || ( $min ne $min_old ) );

    # this value is set when the JS runs, which means that the user-provided
    # time is sync'd with their computer clock. otherwise, the JS didn't run,
    # so let's guess at their timezone.
    if ( $legacy_post->{'date_diff'} || $legacy_post->{'date_diff_nojs'} || $different ) {
        delete $canonical->{'tz'};
        $canonical->{'year'} = $year;
        $canonical->{'mon'}  = $mon;
        $canonical->{'day'}  = $day;
        $canonical->{'hour'} = $hour;
        $canonical->{'min'}  = $min;
    }

    my $subject = $legacy_post->{'subject'};
    $subject = ""
        if $subject && $subject eq LJ::Lang::ml('entryform.subject.hint2');
    $canonical->{'subject'} = $subject;

    $props->{picture_keyword}  = $legacy_post->{prop_picture_keyword};
    $props->{current_moodid}   = $legacy_post->{prop_current_moodid};
    $props->{current_mood}     = $legacy_post->{prop_current_mood};
    $props->{current_music}    = $legacy_post->{prop_current_music};
    $props->{opt_screening}    = $legacy_post->{prop_opt_screening};
    $props->{current_location} = $legacy_post->{prop_current_location};
    $props->{current_coords}   = $legacy_post->{prop_current_coords};
    $props->{taglist}          = $legacy_post->{prop_taglist};

    $props->{opt_preformatted} = $legacy_post->{prop_opt_preformatted}
        || (
          $legacy_post->{'switched_rte_on'}                                                  ? 1
        : ( $legacy_post->{event_format} && $legacy_post->{event_format} eq "preformatted" ) ? 1
        : 0
        );
    $props->{opt_nocomments} = $legacy_post->{prop_opt_nocomments}
        || ( $legacy_post->{comment_settings}
        && $legacy_post->{comment_settings} eq "nocomments" ? 1 : 0 );
    $props->{opt_noemail} = $legacy_post->{prop_opt_noemail}
        || ( $legacy_post->{comment_settings}
        && $legacy_post->{comment_settings} eq "noemail" ? 1 : 0 );
    $props->{opt_backdated} = $legacy_post->{'prop_opt_backdated'} ? 1 : 0;

    if ( LJ::is_enabled('adult_content') ) {
        $props->{adult_content} = $legacy_post->{prop_adult_content} || '';
        $props->{adult_content} = ""
            unless $props->{adult_content} eq "none"
            || $props->{adult_content} eq "concepts"
            || $props->{adult_content} eq "explicit";

        $props->{adult_content_reason} = $legacy_post->{prop_adult_content_reason} || "";
    }

    # nuke taglists that are just blank
    $props->{taglist} = "" unless $props->{taglist} && $props->{taglist} =~ /\S/;

    # Convert the rich text editor output back to parsable lj tags.
    my $event = $legacy_post->{'event'};
    if ( $legacy_post->{'switched_rte_on'} ) {
        $props->{used_rte} = 1;

        # We want to see if we can hit the fast path for cleaning
        # if they did nothing but add line breaks.
        my $attempt = $event;
        $attempt =~ s!<br />!\n!g;

        if ( $attempt !~ /<\w/ ) {
            $event = $attempt;

            # Make sure they actually typed something, and not just hit
            # enter a lot
            $attempt =~ s!(?:<p>(?:&nbsp;|\s)+</p>|&nbsp;)\s*?!!gm;
            $event = '' unless $attempt =~ /\S/;

            $props->{opt_preformatted} = 0;
        }
        else {
            # Old methods, left in for compatibility during code push
            $event =~ s!<lj-cut class="ljcut">!<lj-cut>!gi;

            $event =~ s!<lj-raw class="ljraw">!<lj-raw>!gi;
        }
    }
    else {
        $props->{used_rte} = 0;
    }

    $canonical->{'event'} = $event;

    ## see if an "other" mood they typed in has an equivalent moodid
    if ( $legacy_post->{'prop_current_mood'} ) {
        if ( my $id = DW::Mood->mood_id( $legacy_post->{'prop_current_mood'} ) ) {
            $props->{current_moodid} = $id;
            delete $props->{current_mood};
        }
    }

    # Crosspost fields are keyed by account id.
    my %crosspost_ids;
    foreach my $name ( keys %$legacy_post ) {
        next unless $name =~ /^prop_xpost_(?:(?:password|chal|resp)_)?(\d+)$/;
        $crosspost_ids{$1} = 1;
    }

    $canonical->{crosspost_entry} = $legacy_post->{prop_xpost_check} ? 1 : 0;
    $canonical->{crosspost}       = {};
    foreach my $acctid ( keys %crosspost_ids ) {
        $canonical->{crosspost}{$acctid} = {
            id       => $legacy_post->{"prop_xpost_$acctid"} ? $acctid : undef,
            password => $legacy_post->{"prop_xpost_password_$acctid"},
            chal     => $legacy_post->{"prop_xpost_chal_$acctid"},
            resp     => $legacy_post->{"prop_xpost_resp_$acctid"},
        };
    }

    return {
        canonical => $canonical,
        post      => $legacy_post,
    };
}

# Build native form fields for a legacy error rerender. This intentionally does
# not decode again: raw subject/body controls and the already-normalized legacy
# request each carry information required for a safe native-schema retry.
sub formdata_from_legacy {
    my ( $canonical, $post ) = @_;

    my $legacy_post = legacy_post_hash($post);
    my $props       = $canonical->{props} || {};
    my @form;
    my $add = sub { push @form, @_ };

    $add->( subject    => $canonical->{subject}, event => $legacy_post->{event} );
    $add->( usejournal => $legacy_post->{usejournal} ) if exists $legacy_post->{usejournal};

    my $editor =
          $props->{used_rte}         ? 'rte0'
        : $props->{opt_preformatted} ? 'html_raw0'
        :                              'html_casual1';
    $add->( editor => $editor );

    my $security = $canonical->{security} || 'public';
    if ( $security eq 'usemask' ) {
        $security = $canonical->{allowmask} == 1 ? 'access' : 'custom';
    }
    $add->( security => $security );
    foreach my $bit ( 1 .. 60 ) {
        $add->( custom_bit => $bit ) if $legacy_post->{"custom_bit_$bit"};
    }

    my @raw_date = map { "date_ymd_$_" } qw(yyyy mm dd);
    if ( grep { exists $legacy_post->{$_} } @raw_date ) {
        $add->( entrytime_date => join( '-', map { $legacy_post->{$_} // '' } @raw_date ) );
    }
    elsif ( defined $canonical->{year} && defined $canonical->{mon} && defined $canonical->{day} ) {
        $add->( entrytime_date => join( '-', @{$canonical}{qw(year mon day)} ) );
    }

    if ( exists $legacy_post->{hour} || exists $legacy_post->{min} ) {
        $add->( entrytime_time => join( ':', map { $legacy_post->{$_} // '' } qw(hour min) ) );
    }
    elsif ( defined $canonical->{hour} && defined $canonical->{min} ) {
        $add->( entrytime_time => join( ':', @{$canonical}{qw(hour min)} ) );
    }
    $add->( trust_datetime       => 1 ) if !exists $canonical->{tz};
    $add->( nojs                 => 1 ) if $legacy_post->{date_diff_nojs};
    $add->( entrytime_outoforder => 1 ) if $props->{opt_backdated};

    $add->( taglist              => $props->{taglist} );
    $add->( prop_picture_keyword => $props->{picture_keyword} );
    $add->( current_mood         => $props->{current_moodid} );
    $add->( current_mood_other   => $props->{current_mood} );
    $add->( current_music        => $props->{current_music} );
    $add->( current_location     => $props->{current_location} );
    $add->( opt_screening        => $props->{opt_screening} );

    my $comment_settings =
          $props->{opt_noemail}    ? 'noemail'
        : $props->{opt_nocomments} ? 'nocomments'
        :                            $legacy_post->{comment_settings};
    $add->( comment_settings => $comment_settings );

    my %adult = ( none => 'none', concepts => 'discretion', explicit => 'restricted' );
    $add->( age_restriction        => $adult{ $props->{adult_content} || '' } || '' );
    $add->( age_restriction_reason => $props->{adult_content_reason} );

    $add->( flags_adminpost => $legacy_post->{flags_adminpost} )
        if exists $legacy_post->{flags_adminpost};

    $add->( crosspost_entry => $canonical->{crosspost_entry} ? 1 : 0 );
    foreach my $acctid ( sort { $a <=> $b } keys %{ $canonical->{crosspost} || {} } ) {
        my $crosspost = $canonical->{crosspost}{$acctid};
        $add->( crosspost => $acctid ) if $crosspost->{id};
        foreach my $field (qw(password chal resp)) {
            next unless defined $crosspost->{$field};
            $add->( "crosspost_${field}_$acctid" => $crosspost->{$field} );
        }
    }

    return Hash::MultiValue->new(@form);
}

1;
