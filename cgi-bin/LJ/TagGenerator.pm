#!/usr/bin/perl

package LJ::TagGenerator;
use Carp;

my %_tag_groups = (
                   ":common" => [qw(a b body br code col colgroup dd del div dl dt em
                                  font form frame frameset h1 h2 h3 h4 h5 h6 head hr
                                  html i img input li nobr ol option p pre table td th 
                                  tr Tr TR tt title u ul)],
                   ":html4" => [qw(a abbr acronym address applet area b base basefont
                                 bdo big blockquote body br button caption center cite
                                 code col colgroup dd del dfn dir div dl dt em fieldset
                                 font form frame frameset h1 h2 h3 h4 h5 h6 head hr html
                                 i iframe img input ins isindex kbd label legend li link
                                 map menu meta noframes noscript object ol optgroup option
                                 p param pre q s samp script select small span strike
                                 strong style sub sup table tbody td textarea tfoot th 
                                 thead title tr Tr TR tt u ul var)],
                  );
                                 
sub import {
    shift;  # ditch the class name
    my %args = @_;
    my $tags = $args{tags} || $_tag_groups{":common"};
    ref $tags and UNIVERSAL::isa($tags, "ARRAY")
      or croak "Invalid tags argument";
    my $prefix = $args{prefix} || "";
    my $suffix = $args{suffix} || "";
    my $uppercase = $args{uppercase} || 1;
    my $package = (caller)[0];
    while (my $tag = shift @$tags) {
        if (exists $_tag_groups{$tag}) {
            push @$tags, @{$_tag_groups{$tag}};
            next;
        }
        if ($uppercase) {
            $tag = uc $tag;
        }
        # print "aliasing __$tag to ${package}::$prefix$tag$suffix\n";
        *{"${package}::$prefix$tag$suffix"} = \&{"__$tag"};
    }
}
        
sub AUTOLOAD {
    $AUTOLOAD =~ /::__([^:]*)$/ or croak "No such method $AUTOLOAD";
    my $tagname = lc $1;
    my $sub = "sub $AUTOLOAD " . q{
      {
          my $result = '<__TAGNAME__';
          if (ref($_[0]) && ref($_[0]) eq 'HASH') {
              my $attrs = shift;
              while (my ($key, $value) = each %$attrs) {
	          $key =~ s/^\-//;
	          $key =~ s/_/-/g;
	          $result .= (defined $value ? qq( $key="$value") : qq( $key));
              }
          }
          if (@_) {
              $result .= ">" . join("", @_) . "</__TAGNAME__>";
          } else {
              $result .= " />";
          }
          return $result;
      }
    };
    $sub =~ s/__TAGNAME__/$tagname/g;
    eval $sub;
    goto &$AUTOLOAD;
}

1;
