use utf8;
package DW::Schema::Result::CaptchaCache;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::CaptchaCache

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

=head1 TABLE: C<captcha_cache>

=cut

__PACKAGE__->table("captcha_cache");

=head1 ACCESSORS

=head2 captcha_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 question

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 answer

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 issuetime

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "captcha_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "question",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "answer",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "issuetime",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</captcha_id>

=back

=cut

__PACKAGE__->set_primary_key("captcha_id");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:C/qYRFe5zHBGTKNkweZ8Sw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
