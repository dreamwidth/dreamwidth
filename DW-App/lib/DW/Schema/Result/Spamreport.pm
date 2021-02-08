use utf8;
package DW::Schema::Result::Spamreport;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Spamreport

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

=head1 TABLE: C<spamreports>

=cut

__PACKAGE__->table("spamreports");

=head1 ACCESSORS

=head2 srid

  data_type: 'mediumint'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 reporttime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 posttime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 state

  data_type: 'enum'
  default_value: 'open'
  extra: {list => ["open","closed"]}
  is_nullable: 0

=head2 ip

  data_type: 'varchar'
  is_nullable: 1
  size: 45

=head2 journalid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 posterid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 report_type

  data_type: 'enum'
  default_value: 'comment'
  extra: {list => ["entry","comment","message"]}
  is_nullable: 0

=head2 subject

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 body

  data_type: 'blob'
  is_nullable: 0

=head2 client

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "srid",
  {
    data_type => "mediumint",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "reporttime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "posttime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "state",
  {
    data_type => "enum",
    default_value => "open",
    extra => { list => ["open", "closed"] },
    is_nullable => 0,
  },
  "ip",
  { data_type => "varchar", is_nullable => 1, size => 45 },
  "journalid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "posterid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "report_type",
  {
    data_type => "enum",
    default_value => "comment",
    extra => { list => ["entry", "comment", "message"] },
    is_nullable => 0,
  },
  "subject",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "body",
  { data_type => "blob", is_nullable => 0 },
  "client",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</srid>

=back

=cut

__PACKAGE__->set_primary_key("srid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:YQsw1Rv22fc3JQS10IiAIw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
