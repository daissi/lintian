# debian/upstream/metadata -- lintian check script -*- perl -*-

# Copyright © 2016 Petter Reinholdtsen
# Copyright © 2020 Chris Lamb <lamby@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, you can find it on the World Wide
# Web at http://www.gnu.org/copyleft/gpl.html, or write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA.

package Lintian::debian::upstream::metadata;

use v5.20;
use warnings;
use utf8;

use List::Util qw(none);

use YAML::XS;
$YAML::XS::LoadBlessed = 0;

use constant EMPTY => q{};

use Moo;
use namespace::clean;

with 'Lintian::Check';

sub source {
    my ($self) = @_;

    my $file
      = $self->processable->patched->resolve_path('debian/upstream/metadata');

    if ($self->processable->native) {
        $self->tag('upstream-metadata-in-native-source')
          if defined $file;
        return;
    }

    unless (defined $file) {
        $self->tag('upstream-metadata-file-is-missing');
        return;
    }

    $self->tag('upstream-metadata-exists');

    unless ($file->is_open_ok) {
        $self->tag('upstream-metadata-is-not-a-file');
        return;
    }

    # Need 0.69 for $LoadBlessed (#861958)
    return
      if $YAML::XS::VERSION < 0.69;

    my $yaml;
    eval { $yaml = YAML::XS::LoadFile($file->unpacked_path); };

    if ($@ || !defined $yaml) {
        my $message = $@;
        my ($reason, $document, $line, $column)= (
            $message =~ /
                \AYAML::XS::Load\sError:\sThe\sproblem:\n
                \n\s++(.+)\n
                \n
                was\sfound\sat\sdocument:\s(\d+),\sline:\s(\d+),\scolumn:\s(\d+)\n/x
        );

        $message
          = "$reason (at document $document, line $line, column $column)"
          if ( length $reason
            && length $document
            && length $line
            && length $document);

        $self->tag('upstream-metadata-yaml-invalid', $message);

        return;
    }

    unless (ref $yaml eq 'HASH') {
        $self->tag('upstream-metadata-not-yaml-mapping', $file->name);
        return;
    }

    $self->tag('upstream-metadata-field-present', $_) for keys %{$yaml};

    $self->tag('upstream-metadata-missing-repository')
      if none { defined $yaml->{$_} } qw(Repository Repository-Browse);
    $self->tag('upstream-metadata-missing-bug-tracking')
      if none { defined $yaml->{$_} } qw(Bug-Database Bug-Submit);

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et
