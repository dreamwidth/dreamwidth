use utf8;
package DW::Schema::Result::Sitekeyword;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Sitekeyword

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

=head1 TABLE: C<sitekeywords>

=cut

__PACKAGE__->table("sitekeywords");

=head1 ACCESSORS

=head2 kwid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 keyword

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=cut

__PACKAGE__->add_columns(
  "kwid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "keyword",
  { data_type => "varchar", is_nullable => 0, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</kwid>

=back

=cut

__PACKAGE__->set_primary_key("kwid");

=head1 UNIQUE CONSTRAINTS

=head2 C<keyword>

=over 4

=item * L</keyword>

=back

=cut

__PACKAGE__->add_unique_constraint("keyword", ["keyword"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:oilUPlrCtCAuv6X9a4AAnA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
