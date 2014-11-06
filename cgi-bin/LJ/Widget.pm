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

package LJ::Widget;

use strict;
use Carp;
use LJ::ModuleLoader;
use LJ::Auth;

# FIXME: don't really need all widgets now
LJ::ModuleLoader->require_subclasses( "LJ::Widget" );
LJ::ModuleLoader->require_subclasses( "DW::Widget" );

our $currentId = 1;

# can pass in "id" opt to use instead of incrementing $currentId.
# useful for when a widget will be created more than once but we want to keep its ID the same.
sub new {
    my $class = shift;
    my %opts = @_;

    my $id = $opts{id} ? $opts{id} : $currentId++;
    return bless {id => $id}, $class;
}

sub need_res {
    return ();
}

sub need_res_opts {
    return ();
}

sub render_body {
    return "";
}

sub start_form {
    my $class = shift;
    my %opts = @_;

    croak "Cannot call start_form on parent widget class" if $class eq "LJ::Widget";

    my $eopts = "";
    my $ehtml = $opts{noescape} ? 0 : 1;
    foreach my $attr (grep { ! /^(noescape)$/ && ! /^(authas)$/ } keys %opts) {
        $eopts .= " $attr=\"" . ($ehtml ? LJ::ehtml($opts{$attr}) : $opts{$_}) . "\"";
    }

    my $ret = "<form method='POST'$eopts>";
    $ret .= LJ::form_auth();

    if ($class->authas) {
        my $u = $opts{authas} || $BMLCodeBlock::GET{authas} || $BMLCodeBlock::POST{authas};
        $u = LJ::load_user($u) unless LJ::isu($u);
        my $authas = LJ::isu($u) ? $u->user : undef;

        if ($authas && !$LJ::REQ_GLOBAL{widget_authas_form}) {
            $ret .= $class->html_hidden({ name => "authas", value => $authas, id => "_widget_authas" });
            $LJ::REQ_GLOBAL{widget_authas_form} = 1;
        }
    }

    return $ret;
};

sub end_form {
    my $class = shift;

    croak "Cannot call end_form on parent widget class" if $class eq "LJ::Widget";

    my $ret = "</form>";
    return $ret;
}

# should this widget be rendered?
# -- not a page logic decision
sub should_render {
    my $class = shift;
    return $class->is_disabled ? 0 : 1;
}

# returns the dom id of this widget element
sub widget_ele_id {
    my $class = shift;

    my $widget_id = ref $class ? $class->{id} : $currentId++;
    return "LJWidget_$widget_id";
}

# render a widget, including its content wrapper
sub render {
    my ($class, @opts) = @_;

    my $subclass = $class->subclass;
    my $css_subclass = lc($subclass);
    # figure out where "Odd number of elements in hash assignment" warning is coming from
    if ( scalar( @opts ) % 2 == 1 ) {
        carp "Odd number of \@opts passed from $subclass";
    }
    my %opt_hash = @opts;

    my $widget_ele_id = $class->widget_ele_id;

    return "" unless $class->should_render;

    my $ret = "<div class='appwidget appwidget-$css_subclass' id='$widget_ele_id'>\n";

    my $rv = eval {
        my $widget = $class;

        my $opts = { $widget->need_res_opts };

        # include any resources that this widget declares
        if (defined $opt_hash{stylesheet_override}) {
            LJ::need_res($opt_hash{stylesheet_override}) if $opt_hash{stylesheet_override};

            # include non-CSS files (we used stylesheet_override above)
            foreach my $file ($widget->need_res) {
                if ($file =~ m!^[^/]+\.(js|css)$!i) {
                    next if $1 eq 'css';
                    LJ::need_res( $opts, "js/widgets/$subclass/$file" );
                    next;
                }
                LJ::need_res( $opts, $file ) unless $file =~ /\.css$/i;
            }
        } else {
            foreach my $file ($widget->need_res) {
                if ($file =~ m!^[^/]+\.(js|css)$!i) {
                    my $prefix = $1 eq 'js' ? "js" : "stc";
                    LJ::need_res( $opts, "$prefix/widgets/$subclass/$file" );
                    next;
                }
                LJ::need_res( $opts, $file );
            }
        }
        LJ::need_res($opt_hash{stylesheet}) if $opt_hash{stylesheet};

        return $widget->render_body(@opts);
    };

    if ( defined $rv && $rv =~ /\w/ ) {
        $ret .= $rv;
    } elsif ( $@ ) {
        $ret .= "<strong>[Error: $@]</strong";
#        $class->handle_error;
    }

    $ret .= "</div><!-- end .appwidget-$css_subclass -->\n";

    return $ret;
}

sub post_fields_by_widget {
    my $class = shift;
    my %opts = @_;

    my $post = $opts{post};
    my $widgets = $opts{widgets};
    my $errors = $opts{errors};

    my %per_widget = map { /^(?:LJ::Widget::)?(.+)$/; $1 => {} } @$widgets;
    my $eff_submit = undef;

    # per_widget is populated above for widgets which
    # are declared to be able to post to this page... if
    # it's not in the hashref then it's not whitelisted
    my $allowed = sub {
        my $wclass = shift;
        return 1 if $per_widget{$wclass};

        push @$errors, "Submit from disallowed class: $wclass";
        return 0;
    };

    foreach my $key (keys %$post) {
        next unless $key;

        # FIXME: this is currently unused, but might be useful
        if ($key =~ /^Widget_Submit_(.+)$/) {
            die "Multiple effective submits?  class=$1"
                if $eff_submit;

            # is this class whitelisted?
            next unless $allowed->($1);

            $eff_submit = $1;
            next;
        }

        my ($subclass, $field) = $key =~ /^Widget(?:\[([\w]+)\])?_(.+)$/;
        next unless $subclass && $field;

        $subclass =~ s/_/::/g;

        # whitelisted widget class?
        next unless $allowed->($subclass);

        $per_widget{$subclass}->{$field} = $post->{$key};
    }

    # now let's remove empty hashref placeholders from %per_widget
    while (my ($k, $v) = each %per_widget) {
        delete $per_widget{$k} unless %$v;
    }

    return \%per_widget;
}

sub post_fields_of_widget {
    my $class = shift;
    my $widget = shift;
    my $post = shift() || \%BMLCodeBlock::POST;

    my $errors = [];
    my $per_widget = LJ::Widget->post_fields_by_widget( post => $post, widgets => [ $widget ], errors => $errors );
    return $per_widget->{$widget} || {};
}

sub post_fields {
    my $class = shift;
    my $post = shift() || \%BMLCodeBlock::POST;

    my @widgets = ( $class->subclass );
    my $errors = [];
    my $per_widget = LJ::Widget->post_fields_by_widget( post => $post, widgets => \@widgets, errors => $errors );
    return $per_widget->{$class->subclass} || {};
}

sub get_args {
    my $class = shift;
    return \%BMLCodeBlock::GET;
}

sub get_effective_remote {
    my $class = shift;

    if ($class->authas) {
        return LJ::get_effective_remote();
    }

    return LJ::get_remote();
}

# call to have a widget process a form submission. this checks for formauth unless
# an ajax auth token was already verified
# returns hash returned from the last processed widget
# pushes any errors onto @BMLCodeBlock::errors
sub handle_post {
    my $class   = shift;
    my $post    = shift;
    my @widgets;
    # support for per-widget handle_post() options
    my %widget_opts = ();
    while (@_) {
        my $w = shift;
        if (@_ && ref $_[0]) {
            $widget_opts{$w} = shift(@_);
        }
        push @widgets, $w;
    }
    # no errors, return empty list
    return () unless LJ::did_post() && @widgets;

    # is this widget disabled?
    return () if $class->is_disabled;

    # require form auth for widget submissions
    my $errorsref = \@BMLCodeBlock::errors;

    unless (LJ::check_form_auth($post->{lj_form_auth}) || $LJ::WIDGET_NO_AUTH_CHECK) {
        push @$errorsref, LJ::Lang::ml('error.invalidform');
    }

    my $per_widget = $class->post_fields_by_widget( post => $post, widgets => \@widgets, errors => $errorsref );

    my %res;

    while (my ($class, $fields) = each %$per_widget) {
        eval { %res = "LJ::Widget::$class"->handle_post($fields, %{$widget_opts{$class} or {}}) } or
            "LJ::Widget::$class"->handle_error($@ => $errorsref);
    }

    return %res;
}

# handles post vars for a widget, passes result of handle_post to render
sub handle_post_and_render {
    my ($class, $post, $widgetclass, %opts) = @_;

    my %post_result = LJ::Widget->handle_post($post, $widgetclass);
    my $subclass = LJ::Widget::subclass($widgetclass);

    $opts{$_} = $post_result{$_} foreach keys %post_result;
    return "LJ::Widget::$subclass"->render(%opts);
}

*error = \&handle_error;
sub handle_error {
    my ($class, $errstr, $errref) = @_;
    $errstr ||= $@;
    $errref ||= \@BMLCodeBlock::errors;
    return 0 unless $errstr;

    $errstr =~ s/\s+at\s+.+line \d+.*$//ig unless $LJ::IS_DEV_SERVER || $LJ::DEBUG{"full_widget_error"};
    push @$errref, $errstr;
    return 1;
}

sub error_list {
    my ($class, @errors) = @_;

    if (@errors) {
        $class->error($_) foreach @errors;
    }
    return @BMLCodeBlock::errors;
}

sub is_disabled {
    my $class = shift;

    my $subclass = $class->subclass;
    return 0 unless $subclass;
    return $LJ::WIDGET_DISABLED{$subclass} ? 1 : 0;
}

# returns the widget subclass name
sub subclass {
    my $class = shift;
    $class = ref $class if ref $class;
    return $class unless $class =~ /::/;
    return ($class =~ /(?:LJ|DW)::Widget::([\w:]+)$/)[0];
}

# wrapper around BML... for now
sub decl_params {
    my $class = shift;
    return BML::decl_params(@_);
}

sub form_auth {
    my $class = shift;
    return LJ::form_auth(@_);
}

# override in subclasses with a string of JS to extend the widget subclass with
sub js { '' }

# override to return a true value if this widget accept AJAX posts
sub ajax { 0 }

# override if this widget can perform an AJAX request via GET instead of post
sub can_fake_ajax_post { 0 }

# override in subclasses that support authas authentication
sub authas { 0 }

# instance method to return javascript for this widget
# "page_js_obj" opt:
#     The JS object that is defined by the page the widget is in.
#     Used to create a variable "<page_js_obj>.<widgetclass>" which holds
#     this widget's JS object.  Then the page can call functions that are
#     on specific widgets.
sub wrapped_js {
    my $self = shift;
    my %opts = @_;

    croak "wrapped_js is an instance method" unless ref $self;

    my $widgetid = $self->widget_ele_id or return '';
    my $widgetclass = $self->subclass;
    my $js = $self->js or return '';

    my $authtoken = LJ::Auth->ajax_auth_token(LJ::get_remote(), "/_widget");
    $authtoken = LJ::ejs($authtoken);

    LJ::need_res(qw(js/ljwidget.js));

    my $widgetvar = "LJWidget.widgets[\"$widgetid\"]";
    my $widget_js_obj = $opts{page_js_obj} ? "$opts{page_js_obj}.$widgetclass = $widgetvar;" : "";

    return qq {
        <script>
            $widgetvar = new LJWidget("$widgetid", "$widgetclass", "$authtoken");
            $widget_js_obj
            OBJ.extend($widgetvar, {$js});
            LiveJournal.register_hook("page_load", function () { $widgetvar.initWidget() });
        </script>
    };
}

# allows given form fields to be passed into the widget's handle_post, even if they don't have the widget prefix on them
# this is needed for recaptcha modules in widgets
sub use_specific_form_fields {
    my $class = shift;
    my %opts = @_;

    my $post = $opts{post};
    my $widget = $opts{widget};
    my %given_fields = map { $_ => 1 } @{$opts{fields}};

    foreach my $field (%$post) {
        $post->{"Widget[$widget]_$field"} = $post->{$field} if $given_fields{$field};
    }

    return;
}

package LJ::Error::WidgetError;

use strict;
use base qw(LJ::Error);

sub fields { qw(errstr) }

sub new {
    my $class = shift;
    my ($errstr, %opts) = @_;

    my $self = { errstr => $errstr };

    return bless $self, $class;
}

sub as_html {
    my $self = shift;

    return $self->{errstr};
}

##################################################
# htmlcontrols-like utility methods

package LJ::Widget;
use strict;

# most of these are flat wrappers, but swapping in a valid 'name'
sub _html_star {
    my $class = shift;
    my $func  = shift;
    my %opts = @_;

    croak "Cannot call htmlcontrols-like utility method on parent widget class" if $class eq "LJ::Widget";

    my $prefix = $class->input_prefix;
    $opts{name} = "${prefix}_$opts{name}";
    return $func->(\%opts);
}

sub _html_star_list {
    my $class  = shift;
    my $func   = shift;
    my @params = @_;

    croak "Cannot call htmlcontrols-like utility method on parent widget class" if $class eq "LJ::Widget";

    # If there's only one (non-ref) element in @params, then there
    # is no name for the field and nothing should be changed.
    unless (@params == 1 && !ref $params[0]) {
        my $prefix = $class->input_prefix;

        my $is_name = 1; # if true, the next element we'll check is a name (not a value)
        foreach my $el (@params) {
            if (ref $el) {
                $el->{name} = "${prefix}_$el->{name}" if $el->{name};
                $is_name = 1;
                next;
            }
            if ($is_name) {
                $el = "${prefix}_$el";
                $is_name = 0;
            } else {
                $is_name = 1;
            }
        }
    }

    return $func->(@params);
}

sub html_text {
    my $class = shift;
    return $class->_html_star(\&LJ::html_text, @_);
}

sub html_check {
    my $class = shift;
    return $class->_html_star(\&LJ::html_check, @_);
}

sub html_textarea {
    my $class = shift;
    return $class->_html_star(\&LJ::html_textarea, @_);
}

sub html_color {
    my $class = shift;
    return $class->_html_star(\&LJ::html_color, @_);
}

sub input_prefix {
    my $class = shift;
    my $subclass = $class->subclass;
    $subclass =~ s/::/_/g;
    return 'Widget[' . $subclass . ']';
}

sub html_select {
    my $class = shift;

    croak "Cannot call htmlcontrols-like utility method on parent widget class" if $class eq "LJ::Widget";

    my $prefix = $class->input_prefix;

    # old calling method, exact wrapper around html_select
    if (ref $_[0]) {
        my $opts = shift;
        $opts->{name} = "${prefix}_$opts->{name}";
        return LJ::html_select($opts, @_);
    }

    # newer calling method, no hashref w/ list as list => [ ... ]
    my %opts = @_;
    my $list = delete $opts{list};
    $opts{name} = "${prefix}_$opts{name}";
    return LJ::html_select(\%opts, @$list);
}

sub html_datetime {
    my $class = shift;
    return $class->_html_star(\&LJ::html_datetime, @_);
}

sub html_hidden {
    my $class = shift;

    return $class->_html_star_list(\&LJ::html_hidden, @_);
}

sub html_submit {
    my $class = shift;

    return $class->_html_star_list(\&LJ::html_submit, @_);
}

##################################################
# Utility methods for getting/setting ML strings
# in the 'widget' ML domain
# -- these are usually living in a db table somewhere
#    and input by an admin who wants translateable text

sub ml_key {
    my $class = shift;
    my $key = shift;

    croak "invalid key: $key"
        unless $key;

    my $ml_class = lc $class->subclass;
    return "widget.$ml_class.$key";
}

sub ml_remove_text {
    my $class = shift;
    my $ml_key = shift;

    my $ml_dmid     = $class->ml_dmid;
    my $root_lncode = $class->ml_root_lncode;
    return LJ::Lang::remove_text($ml_dmid, $ml_key, $root_lncode);
}

sub ml_set_text {
    my $class = shift;
    my ($ml_key, $text) = @_;

    # create new translation system entry
    my $ml_dmid     = $class->ml_dmid;
    my $root_lncode = $class->ml_root_lncode;

    # call web_set_text, though there shouldn't be any
    # commits going on since this is the 'widget' dmid
    return LJ::Lang::web_set_text
        ($ml_dmid, $root_lncode, $ml_key, $text,
         { changeseverity => 1, childrenlatest => 1 });
}

sub ml_dmid {
    my $class = shift;

    my $dom = LJ::Lang::get_dom("widget");
    return $dom->{dmid};
}

sub ml_root_lncode {
    my $class = shift;

    my $ml_dom = LJ::Lang::get_dom("widget");
    my $root_lang = LJ::Lang::get_root_lang($ml_dom);
    return $root_lang->{lncode};
}

# override LJ::Lang::is_missing_string to return true
# if the string equals the class name (the fallthrough
# for LJ::Widget->ml)
sub ml_is_missing_string {
    my $class = shift;
    my $string = shift;

    $class =~ /.+::(\w+)$/;
    return $string eq $1 || LJ::Lang::is_missing_string($string);
}

# this function should be used when getting any widget ML string
# -- it's really just a wrapper around LJ::Lang::ml or BML::ml,
#    but it does nice things like falling back to global definition
# -- also allows getting of strings from the 'widget' ML domain
#    for text which was dynamically defined by an admin
sub ml {
    my ($class, $code, $vars) = @_;

    # can pass in a string and check 3 places in order:
    # 1) widget.foo.text => general .widget.foo.text (overridden by current page)
    # 2) widget.foo.text => general widget.foo.text  (defined in en(_LJ).dat)
    # 3) widget.foo.text => widget  widget.foo.text  (user-defined by a tool)

    # whether passed with or without a ".", eat that immediately
    $code =~ s/^\.//;

    # 1) try with a ., for current page override in 'general' domain
    # 2) try without a ., for global version in 'general' domain
    foreach my $curr_code (".$code", $code) {
        my $string = LJ::Lang::ml($curr_code, $vars);
        return "" if $string eq "_none";
        return $string unless LJ::Lang::is_missing_string($string);
    }

    # 3) now try with "widget" domain for user-entered translation string
    my $dmid = $class->ml_dmid;
    my $lncode = LJ::Lang::get_effective_lang();
    my $string = LJ::Lang::get_text($lncode, $code, $dmid, $vars);
    return "" if $string eq "_none";
    return $string unless LJ::Lang::is_missing_string($string);

    # return the class name if we didn't find anything
    $class =~ /.+::(\w+)$/;
    return $1;
}

1;
__END__

=head1 NAME

LJ::Widget - parent class for areas of contained information and code (widgets)
to be used on one or more BML pages

=head1 SYNOPSIS

    LJ::Widget::WidgetName->render;
    LJ::Widget::AnotherWidget->render( options );

    LJ::Widget->handle_post(\%POST, qw( WidgetName AnotherWidget ));

    my $widget = LJ::Widget::AjaxWidget->new;
    $headextra .= $widget->wrapped_js( options );
    $widget->render;

=head1 DESCRIPTION

This is the parent class for widgets.  A widget is a part of a BML page that can
be relatively self-contained and is sometimes used on multiple pages.  Using a
widget instead of putting the code directly in a BML page allows more
flexibility in terms of re-using code and readability.  It is much easier to
read and understand a BML page with calls to a couple of widgets than a BML page
with large blocks of unrelated code.

Widgets can do POST actions to themselves or to other widgets, but the goal is
to keep the function of each widget relatively simple.

POST form elements in a widget are given widget-specific prefixes in their
names.  These are then removed when the different POST values are being checked
in C<handle_post>.

AJAX POSTs go to the endpoint "widget.bml", and they perform form auths
differently than non-AJAX POSTs do.

Strings within widgets can and should be English-stripped.  Usually, these
strings are defined within en.dat or en_LJ.dat with the string name of
"widget.$widgetname.$stringname".  However, these strings can also be defined in
BML pages, which will override what's defined in en(_LJ).dat.

Strings in the "widget" ML domain get there when a user inputs text that should
be translatable in a widget web form on the site.  

In almost all cases, methods are called on subclasses of this parent class, and
not on the parent class itself.  It is explicitly noted when a method should be
called on the parent class instead of on a subclass.

Also, methods that can be and are often subclassed are noted as such.  Most
other methods can be subclassed, but it's probably not particularly useful to do
so.

=head1 CONSTRUCTOR

=over 4

=item C<new>

This is only needed when you want to create a widget without actually rendering
it yet.  It is usually called with no options, but you can pass an C<id> to give
the widget a defined ID (number) instead of an auto-generated one (useful if
you're using AJAX and widgets get re-rendered and you don't want IDs to change).

=back

=head1 METHODS

=over 4

=item C<render>

Renders a widget's display.  It wraps the output of C<render_body> with a div
and includes the files defined in C<need_res>.  It will return an empty string
if C<should_render> returns false.  Options passed to it will be passed on to
C<render_body>.

=item C<render_body>

This is called when C<render> is called.  It returns the HTML/BML that should be
printed when a widget is rendered.  Can be subclassed.

=item C<should_render>

Returns if this widget should render or not.  It cannot be passed any
parameters.  It is called automatically when C<render> is called, and by default
it will return false if the widget is disabled via C<is_disabled>.  Can be
subclassed.

=item C<handle_post>

Code that's run when a widget that POSTs is submitted.  This should be called
on the parent class instead of on the specific widget, and the widget(s) you
want to be handled should be passed as parameters.  The parent class method
calls the subclass methods appropriately.  Returns the hash returned from the
last processed widget.  Can be subclassed.

=item C<handle_post_and_render>

This is called on the parent class, and it handles the POST for a single given
widget and returns the results of that POST to C<render>.

=item C<need_res>

Returns a list of paths to static files that should be included on the page that
the widget is called on (i.e. CSS and JS).  Can be subclassed.

=item C<need_res_opts>

Returns a hash of opts that can be passed to need_res -- for example, ( group => 'jquery' ). Can be subclassed.

=item C<post_fields_by_widget>

Returns a hashref of the POST fields for each widget that was handled via
C<handle_post> when a POST action occurs.  Generally only used as a helper
method.  Should be called on the parent class.

=item C<post_fields_of_widget>

Returns the POST fields for a specific given widget handled via C<handle_post>.
Should be called on the parent class.

=item C<post_fields>

Same as C<post_fields_of_widget>, but returns the POST fields for the widget
it's called on.

=item C<use_specific_form_fields>

Given the POST values and a list of specific fields, this will allow those
fields to be passed into the widget's C<handle_post> even if they don't have
the necessary widget prefix on them.  This is currently used for widgets that
have a reCAPTCHA module, since you can't modify the name of the fields for it.

=item C<get_args>

Returns the GET args of the page the widget is on.

=item C<get_effective_remote>

If the widget is an C<authas> widget, it returns the currently authenticated
user (remote or a journal remote manages).  Otherwise, it returns remote.

=item C<handle_error>

Pushes an error onto a given arrayref of errors (or @BMLCodeBlock::errors) for
display.

=item C<error_list>

Returns a list of errors for a widget, using C<handle_error> to build up the
list in @BMLCodeBlock::errors.

=item C<is_disabled>

Returns if a widget is disabled or not based on a config hash value.

=item C<subclass>

Given a widget package name, returns the name of the widget subclass.
Example: giving "LJ::Widget::WidgetName" would return "WidgetName".

=item C<widget_ele_id>

Returns the HTML id attribute for this widget.

=item C<decl_params>

Wrapper around BML::decl_params().

=item C<form_auth>

Wrapper around LJ::form_auth().

=back

=head2 AJAX-Related Methods

=over 4

=item C<js>

Returns a string of JavaScript for a widget so it does not have to be included
as a separate file.  Can be subclassed.

=item C<wrapped_js>

Returns the JavaScript that's in C<js>.  Also sets up JavaScript so that AJAX
widgets can be used.  If a C<page_js_obj> parameter is passed in, its value is
used to create a JavaScript variable that holds the widget JavaScript object in
it.

=back

=head2 Flags for Widgets

=over 4

=item C<ajax>

Returns if the widget can accept AJAX POSTs or not.  Can be subclassed.

=item C<can_fake_ajax_post>

Returns if a widget can perform AJAX requests via GET instead of POST or not.
Can be subclassed.

=item C<authas>

Returns if a widget supports authas authentication or not (in GET or POST).  Can
be subclassed.

=back

=head2 Form Utility Methods

=over 4

=item C<start_form>

Returns HTML for the start of a form (including form auth) that POSTs to a
widget.  Can be passed options similar to that of htmlcontrols methods.

=item C<end_form>

Returns HTML for the end of a form that POSTs to a widget.

=item C<html_text>

Widget-specific HTML text field.  Must be used in place of LJ::html_text() if
C<handle_post> is being used.

=item C<html_check>

Widget-specific HTML text checkbox/radio button.  Must be used in place of
LJ::html_check() if C<handle_post> is being used.

=item C<html_textarea>

Widget-specific HTML text area.  Must be used in place of LJ::html_textarea() if
C<handle_post> is being used.

=item C<html_color>

Widget-specific HTML color field.  Must be used in place of LJ::html_color() if
C<handle_post> is being used.

=item C<html_select>

Widget-specific HTML selection box.  Must be used in place of LJ::html_select()
if C<handle_post> is being used.

=item C<html_datetime>

Widget-specific HTML datetime field.  Must be used in place of
LJ::html_datetime() if C<handle_post> is being used.

=item C<html_hidden>

Widget-specific HTML hidden field.  Must be used in place of LJ::html_hidden()
if C<handle_post> is being used.

=item C<html_submit>

Widget-specific HTML submit button.  Must be used in place of LJ::html_submit()
if C<handle_post> is being used.

=item C<input_prefix>

The prefix that's added on to form element names to make them widget-specific.

=back

=head2 Translation String Methods

=over 4

=item C<ml_key>

The full ML key for a widget string, given the part of the key that's specific
to the string.

=item C<ml_remove_text>

Removes a translation string from the widget ML domain.

=item C<ml_set_text>

Adds a translation string to the widget ML domain.

=item C<ml_dmid>

Domain ID for the widget ML domain.

=item C<ml_root_lncode>

Root language for the widget ML domain.

=item C<ml_is_missing_string>

Returns if a widget string is missing or not.

=item C<ml>

Returns the translation string for a given ML key.  Can be a general string
defined by the page or in en(_LJ).dat, or a string in the widget domain that was
defined by a user via a tool.

=back

=head1 EXAMPLES

See these widgets for some basic examples of different types of widgets:

    cgi-bin/LJ/Widget/ExampleRenderWidget.pm
    cgi-bin/LJ/Widget/ExamplePostWidget.pm
    cgi-bin/LJ/Widget/ExampleAjaxWidget.pm
