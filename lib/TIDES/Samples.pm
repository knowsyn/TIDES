
=head1 NAME

TIDES::Samples - Samples base class.

=head1 SYNOPSIS

    TIDES::Samples provides access to the database samples table.

=head1 ABSTRACT

Provide access to the database samples table.

=cut

package TIDES::Samples;

use warnings;
use strict;

=head1 PUBLIC METHODS

=head2 new

  * Purpose: Access database samples
  * Expected parameters: database handle, collection ID, upload ID
  * Function on success: returns Samples object
  * Function on failure: returns undef

=cut

sub new {
    my($type, %params) = @_;
    my $self = {
        dbh        => $params{dbh},
        collection => $params{collection},
        upload     => $params{upload},
    };
    bless $self, $type;
}

=head2 get

  * Purpose: Return ID for a Sample Name. Insert sample if necessary.
  * Expected parameters: sample name
  * Function on success: returns sample ID
  * Function on failure: returns undef

=cut

sub get {
    my $self = shift;
    my $name = shift;
    my $dbh  = $self->{dbh};

    my $sth = $dbh->prepare(q{
        SELECT id FROM samples WHERE name = ? AND collection = ?
    });
    $sth->execute($name, $self->{collection}) or return;
    my($id) = $sth->fetchrow_array;
    return $id if $id;

    $sth = $dbh->prepare(q{
        INSERT INTO samples (name,collection,upload) VALUES (?,?,?)
    });
    $sth->execute($name, $self->{collection}, $self->{upload}) or return;
    return $dbh->last_insert_id(undef, undef, 'samples', undef);
}

=head1 BUGS AND LIMITATIONS

There are no known problems with this module.

=head1 SEE ALSO

L<TIDES>

=head1 AUTHOR

Ken Yamaguchi, C<< <ken at knowledgesynthesis.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2018 Knowledge Synthesis Inc.

This program is released under the following license: gpl

The full text of the license can be found in the LICENSE file included
with this distribution.

=cut

1;

__END__
