use utf8;
package DW::Schema::Result::Talkleft;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Talkleft

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

=head1 TABLE: C<talkleft>

=cut

__PACKAGE__->table("talkleft");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 posttime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 journalid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 nodetype

  data_type: 'char'
  is_nullable: 0
  size: 1

=head2 nodeid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 jtalkid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 publicitem

  data_type: 'enum'
  default_value: 1
  extra: {list => [1,0]}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "posttime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "journalid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "nodetype",
  { data_type => "char", is_nullable => 0, size => 1 },
  "nodeid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "jtalkid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "publicitem",
  {
    data_type => "enum",
    default_value => 1,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:eSYnug5Q1y89XydTvqYMZQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
