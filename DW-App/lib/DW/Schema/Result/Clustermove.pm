use utf8;
package DW::Schema::Result::Clustermove;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Clustermove

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

=head1 TABLE: C<clustermove>

=cut

__PACKAGE__->table("clustermove");

=head1 ACCESSORS

=head2 cmid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 sclust

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 dclust

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 timestart

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 timedone

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 sdeleted

  data_type: 'enum'
  extra: {list => [1,0]}
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "cmid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "sclust",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "dclust",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "timestart",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "timedone",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "sdeleted",
  { data_type => "enum", extra => { list => [1, 0] }, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</cmid>

=back

=cut

__PACKAGE__->set_primary_key("cmid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:033qfQKLj3pTysEGzUJRhA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
