use strict;
package LJ::S2;

sub IconsPage {
    my ($u, $remote, $opts) = @_;
    my $get = $opts->{'getargs'};

    my $can_manage = ( $remote && $remote->can_manage( $u ) ) ? 1 : 0;
    my $p = Page($u, $opts);
    $p->{'_type'} = "IconsPage";
    $p->{'view'} = "icons";

    if ($u->should_block_robots) {
        $p->{'head_content'} .= LJ::robot_meta_tags();
    }

    $p->{can_manage} = $can_manage;

    my @allpics = LJ::Userpic->load_user_userpics($u);
    my $defaultpicid = $u ? $u->{'defaultpicid'} : undef;

    my $view_inactive = $can_manage || ( $get->{inactive} && $remote && ( LJ::check_priv( $remote, "supportviewscreened" ) ||
                                           LJ::check_priv( $remote, "supporthelp" ) ) );
    my $default_sortorder = S2::get_property_value($opts->{'ctx'}, 'icons_sort_order') || 'upload';
    my $sortorder = $get->{sortorder} || $default_sortorder;

    @allpics = grep { $_->state eq 'N' || ( $view_inactive && $_->state ne 'X' ) } @allpics;

    my @pics;

    if ( $sortorder eq 'keyword' ) {
        @pics = LJ::Userpic->separate_keywords( \@allpics );
    } else { # Upload Order
        $sortorder = 'upload';
        my @newpics;
        my $default_pic;
        foreach my $pic ( @allpics ) {
            my @keyword = $pic->keywords;
            if ( $pic->is_default ) {
                $default_pic = { keywords => \@keyword, userpic => $pic };
            } else {
                push @newpics, { keywords => \@keyword, userpic => $pic };
            }
        }
        @pics = $default_pic if $default_pic;
        @pics = ( @pics, @newpics );
    }

    my @sort_methods = ( 'upload', 'keyword' );

    $p->{sortorder} = $sortorder;
    $p->{sort_keyseq} = \@sort_methods;
    $p->{sort_urls} = {
        map { $_ => LJ::create_url(undef,
                args => {
                    sortorder => ( $_ eq $default_sortorder ) ? undef : $_,
                },
                viewing_style => 1,
                cur_args => $get,
                keep_args => [ 'sortorder', 'view', 'inactive' ],
            ) } @sort_methods
    };

    my $pagingbar;
    my $start_index = 0;
    my $page_size = S2::get_property_value($opts->{'ctx'}, "num_items_icons")+0 || $LJ::MAX_ICONS_PER_PAGE || 0;

    $page_size = $LJ::MAX_ICONS_PER_PAGE if ( $LJ::MAX_ICONS_PER_PAGE && $page_size > $LJ::MAX_ICONS_PER_PAGE );
    $page_size = 0 if $get->{view} && $get->{view} eq 'all';

    $p->{pages} = ItemRange_fromopts({
        items => \@pics,
        pagesize => $page_size || scalar @pics,
        page => $get->{page} || 1,
        url_of => sub {
            return LJ::create_url(undef,
                args => {
                    page => $_[0],
                },
                keep_args => [ 'sortorder', 'view', 'inactive' ],
                viewing_style => 1,
                cur_args => $get,
            );
        },
        url_all => LJ::create_url( undef,
            args => { view => "all" },
            keep_args => [ "sortorder", "inactive" ],
            viewing_style => 1,
            cur_args => $get,
        ),
    });

    my @pics_out;

    foreach my $pic_hash (@pics) {
        my $pic = $pic_hash->{userpic};
        my $keywords = $pic_hash->{keywords} || [ $pic_hash->{keyword} ];

        my $eh_comment = $pic->comment;
        if ( $eh_comment ) {
            LJ::CleanHTML::clean(\$eh_comment, {
                'wordlength' => 40,
                'addbreaks' => 0,
                'tablecheck' => 1,
                'mode' => 'deny',
            });
        }

        my $eh_description = $pic->description;
        if ( $eh_description ) {
            LJ::CleanHTML::clean(\$eh_description, {
                'wordlength' => 40,
                'addbreaks' => 0,
                'tablecheck' => 1,
                'mode' => 'deny',
            });
        }

        my $kwstr = join( ', ', @{$keywords} );

        push @pics_out, {
            '_type' => 'Icon',
            id => $pic->picid,
            image => Image( $pic->url, $pic->width, $pic->height, $pic->alttext( $kwstr, $pic->is_default ), title => $pic->titletext( $kwstr, $pic->is_default ) ),
            keywords => [ map { LJ::ehtml($_) } sort { lc($a) cmp lc($b) } ( @$keywords ) ],
            comment => $eh_comment,
            description => $eh_description,
            default => ( $pic->is_default ) ? 1 : 0,
            active => $pic->state eq 'I' ? 0 : 1,
            link_url => $pic->url,
        };
    }

    $p->{icons} = \@pics_out;

    return $p;
}

1;
