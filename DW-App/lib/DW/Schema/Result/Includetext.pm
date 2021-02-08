use utf8;
package DW::Schema::Result::Includetext;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Includetext

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

=head1 TABLE: C<includetext>

=cut

__PACKAGE__->table("includetext");

=head1 ACCESSORS

=head2 incname

  data_type: 'varchar'
  is_nullable: 0
  size: 80

=head2 inctext

  data_type: 'mediumtext'
  is_nullable: 1

=head2 updatetime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "incname",
  { data_type => "varchar", is_nullable => 0, size => 80 },
  "inctext",
  { data_type => "mediumtext", is_nullable => 1 },
  "updatetime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</incname>

=back

=cut

__PACKAGE__->set_primary_key("incname");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:rByk1Zmn7IqoNTWUJLu4PA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
