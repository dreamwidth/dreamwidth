use utf8;
package DW::Schema::Result::User;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::User

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<user>

=cut

__PACKAGE__->table("user");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 user

  data_type: 'char'
  is_nullable: 1
  size: 25

=head2 caps

  data_type: 'smallint'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 clusterid

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 dversion

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 email

  data_type: 'char'
  is_nullable: 1
  size: 50

=head2 password

  data_type: 'char'
  is_nullable: 1
  size: 30

=head2 status

  data_type: 'char'
  default_value: 'N'
  is_nullable: 0
  size: 1

=head2 statusvis

  data_type: 'char'
  default_value: 'V'
  is_nullable: 0
  size: 1

=head2 statusvisdate

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 name

  data_type: 'char'
  is_nullable: 0
  size: 80

=head2 bdate

  data_type: 'date'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 themeid

  data_type: 'integer'
  default_value: 1
  is_nullable: 0

=head2 moodthemeid

  data_type: 'integer'
  default_value: 1
  extra: {unsigned => 1}
  is_nullable: 0

=head2 opt_forcemoodtheme

  data_type: 'enum'
  default_value: 'N'
  extra: {list => ["Y","N"]}
  is_nullable: 0

=head2 allow_infoshow

  data_type: 'char'
  default_value: 'Y'
  is_nullable: 0
  size: 1

=head2 allow_contactshow

  data_type: 'char'
  default_value: 'Y'
  is_nullable: 0
  size: 1

=head2 allow_getljnews

  data_type: 'char'
  default_value: 'N'
  is_nullable: 0
  size: 1

=head2 opt_showtalklinks

  data_type: 'char'
  default_value: 'Y'
  is_nullable: 0
  size: 1

=head2 opt_whocanreply

  data_type: 'enum'
  default_value: 'all'
  extra: {list => ["all","reg","friends"]}
  is_nullable: 0

=head2 opt_gettalkemail

  data_type: 'char'
  default_value: 'Y'
  is_nullable: 0
  size: 1

=head2 opt_htmlemail

  data_type: 'enum'
  default_value: 'Y'
  extra: {list => ["Y","N"]}
  is_nullable: 0

=head2 opt_mangleemail

  data_type: 'char'
  default_value: 'N'
  is_nullable: 0
  size: 1

=head2 useoverrides

  data_type: 'char'
  default_value: 'N'
  is_nullable: 0
  size: 1

=head2 defaultpicid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 has_bio

  data_type: 'enum'
  default_value: 'N'
  extra: {list => ["Y","N"]}
  is_nullable: 0

=head2 is_system

  data_type: 'enum'
  default_value: 'N'
  extra: {list => ["Y","N"]}
  is_nullable: 0

=head2 journaltype

  data_type: 'char'
  default_value: 'P'
  is_nullable: 0
  size: 1

=head2 lang

  data_type: 'char'
  default_value: 'EN'
  is_nullable: 0
  size: 2

=head2 oldenc

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "userid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "user",
  { data_type => "char", is_nullable => 1, size => 25 },
  "caps",
  {
    data_type => "smallint",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "clusterid",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "dversion",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "email",
  { data_type => "char", is_nullable => 1, size => 50 },
  "password",
  { data_type => "char", is_nullable => 1, size => 30 },
  "status",
  { data_type => "char", default_value => "N", is_nullable => 0, size => 1 },
  "statusvis",
  { data_type => "char", default_value => "V", is_nullable => 0, size => 1 },
  "statusvisdate",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "name",
  { data_type => "char", is_nullable => 0, size => 80 },
  "bdate",
  { data_type => "date", datetime_undef_if_invalid => 1, is_nullable => 1 },
  "themeid",
  { data_type => "integer", default_value => 1, is_nullable => 0 },
  "moodthemeid",
  {
    data_type => "integer",
    default_value => 1,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "opt_forcemoodtheme",
  {
    data_type => "enum",
    default_value => "N",
    extra => { list => ["Y", "N"] },
    is_nullable => 0,
  },
  "allow_infoshow",
  { data_type => "char", default_value => "Y", is_nullable => 0, size => 1 },
  "allow_contactshow",
  { data_type => "char", default_value => "Y", is_nullable => 0, size => 1 },
  "allow_getljnews",
  { data_type => "char", default_value => "N", is_nullable => 0, size => 1 },
  "opt_showtalklinks",
  { data_type => "char", default_value => "Y", is_nullable => 0, size => 1 },
  "opt_whocanreply",
  {
    data_type => "enum",
    default_value => "all",
    extra => { list => ["all", "reg", "friends"] },
    is_nullable => 0,
  },
  "opt_gettalkemail",
  { data_type => "char", default_value => "Y", is_nullable => 0, size => 1 },
  "opt_htmlemail",
  {
    data_type => "enum",
    default_value => "Y",
    extra => { list => ["Y", "N"] },
    is_nullable => 0,
  },
  "opt_mangleemail",
  { data_type => "char", default_value => "N", is_nullable => 0, size => 1 },
  "useoverrides",
  { data_type => "char", default_value => "N", is_nullable => 0, size => 1 },
  "defaultpicid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "has_bio",
  {
    data_type => "enum",
    default_value => "N",
    extra => { list => ["Y", "N"] },
    is_nullable => 0,
  },
  "is_system",
  {
    data_type => "enum",
    default_value => "N",
    extra => { list => ["Y", "N"] },
    is_nullable => 0,
  },
  "journaltype",
  { data_type => "char", default_value => "P", is_nullable => 0, size => 1 },
  "lang",
  { data_type => "char", default_value => "EN", is_nullable => 0, size => 2 },
  "oldenc",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=back

=cut

__PACKAGE__->set_primary_key("userid");

=head1 UNIQUE CONSTRAINTS

=head2 C<user>

=over 4

=item * L</user>

=back

=cut

__PACKAGE__->add_unique_constraint("user", ["user"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:KaHFrPFmxwMA7Og5BWhEIA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
