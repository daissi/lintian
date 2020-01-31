# perl/prebuilt/yapp -- lintian check script -*- perl -*-
#
# Copyright © 2019 Felix Lechner
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

package Lintian::perl::prebuilt::yapp;

use warnings;
use strict;

use Path::Tiny;

use Moo;
use namespace::clean;

with 'Lintian::Check';

sub source {
    my ($self) = @_;

    my $processable = $self->processable;

    return if $processable->source eq 'lintian';

    for my $file ($processable->sorted_index) {

        next
          unless $file->name =~ /\.pm$/;

        my $contents = path($file->fs_path)->slurp;

        $self->tag('source-contains-prebuilt-yapp-parser', $file->name)
          if $contents
          =~ /^#\s+This file was generated using Parse::Yapp version [\d.]+/m;
    }

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et