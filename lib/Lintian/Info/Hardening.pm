# -*- perl -*- Lintian::Info::Hardening
#
# Copyright © 2019 Felix Lechner
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.

package Lintian::Info::Hardening;

use strict;
use warnings;
use autodie;

use Path::Tiny;

use Lintian::Util qw(rstrip);

use constant EMPTY => q{};

use Moo::Role;
use namespace::clean;

=head1 NAME

Lintian::Info::Hardening - access to collected hardening data

=head1 SYNOPSIS

    use Lintian::Processable;
    my $processable = Lintian::Processable::Binary->new;

=head1 DESCRIPTION

Lintian::Info::Hardening provides an interface to collected hardening data.

=head1 INSTANCE METHODS

=over 4

=item hardening_info

Returns a hashref mapping a FILE to its hardening issues.

NB: This is generally only useful for checks/binaries to emit the
hardening-no-* tags.

Needs-Info requirements for using I<hardening_info>: hardening-info

=cut

sub hardening_info {
    my ($self) = @_;

    return $self->{hardening_info}
      if exists $self->{hardening_info};

    my $hardf = path($self->groupdir)->child('hardening-info')->stringify;

    my %hardening_info;

    if (-e $hardf) {
        open(my $idx, '<', $hardf);
        while (my $line = <$idx>) {
            chomp($line);

            if ($line =~ m,^([^:]+):(?:\./)?(.*)$,) {
                my ($tag, $file) = ($1, $2);

                push(@{$hardening_info{$file}}, $tag);
            }
        }
        close($idx);
    }

    $self->{hardening_info} = \%hardening_info;

    return $self->{hardening_info};
}

=back

=head1 AUTHOR

Originally written by Felix Lechner <felix.lechner@lease-up.com> for
Lintian.

=head1 SEE ALSO

lintian(1), L<Lintian::Collect>, L<Lintian::Collect::Binary>,
L<Lintian::Collect::Source>

=cut

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et