use utf8;
package DW::Schema::Result::Supportlog;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Supportlog

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

=head1 TABLE: C<supportlog>

=cut

__PACKAGE__->table("supportlog");

=head1 ACCESSORS

=head2 splid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 spid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 timelogged

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 type

  data_type: 'enum'
  extra: {list => ["req","answer","comment","internal","screened"]}
  is_nullable: 0

=head2 faqid

  data_type: 'mediumint'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 userid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 message

  data_type: 'text'
  is_nullable: 1

=head2 tier

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "splid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "spid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "timelogged",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "type",
  {
    data_type => "enum",
    extra => { list => ["req", "answer", "comment", "internal", "screened"] },
    is_nullable => 0,
  },
  "faqid",
  {
    data_type => "mediumint",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "userid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "message",
  { data_type => "text", is_nullable => 1 },
  "tier",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</splid>

=back

=cut

__PACKAGE__->set_primary_key("splid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:k8m4y9CdCLCM9NRWb1I5Jg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
