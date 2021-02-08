use utf8;
package DW::Schema::Result::Community;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Community

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

=head1 TABLE: C<community>

=cut

__PACKAGE__->table("community");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 membership

  data_type: 'enum'
  default_value: 'open'
  extra: {list => ["open","closed","moderated"]}
  is_nullable: 0

=head2 postlevel

  data_type: 'enum'
  extra: {list => ["members","select","screened"]}
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "userid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "membership",
  {
    data_type => "enum",
    default_value => "open",
    extra => { list => ["open", "closed", "moderated"] },
    is_nullable => 0,
  },
  "postlevel",
  {
    data_type => "enum",
    extra => { list => ["members", "select", "screened"] },
    is_nullable => 1,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=back

=cut

__PACKAGE__->set_primary_key("userid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:BkxaoQHoehvtWXvfNNd68A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
