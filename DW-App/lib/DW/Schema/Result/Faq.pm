use utf8;
package DW::Schema::Result::Faq;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Faq

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

=head1 TABLE: C<faq>

=cut

__PACKAGE__->table("faq");

=head1 ACCESSORS

=head2 faqid

  data_type: 'mediumint'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 question

  data_type: 'text'
  is_nullable: 1

=head2 summary

  data_type: 'text'
  is_nullable: 1

=head2 answer

  data_type: 'text'
  is_nullable: 1

=head2 sortorder

  data_type: 'integer'
  is_nullable: 1

=head2 faqcat

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 lastmodtime

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 lastmoduserid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "faqid",
  {
    data_type => "mediumint",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "question",
  { data_type => "text", is_nullable => 1 },
  "summary",
  { data_type => "text", is_nullable => 1 },
  "answer",
  { data_type => "text", is_nullable => 1 },
  "sortorder",
  { data_type => "integer", is_nullable => 1 },
  "faqcat",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "lastmodtime",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "lastmoduserid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</faqid>

=back

=cut

__PACKAGE__->set_primary_key("faqid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:MCsdbkwFsJNe77wM/BnrYQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
