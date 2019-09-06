# debian-readme -- lintian check script -*- perl -*-

# Copyright (C) 1998 Richard Braakman
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

package Lintian::debian_readme;
use strict;
use warnings;
use autodie;

use Lintian::Check qw(check_spelling spelling_tag_emitter);
use Lintian::Tags qw(tag);

my $SPELLING_ERROR_IN_README
  = spelling_tag_emitter('spelling-error-in-readme-debian');

sub open_readme {
    my ($pkg_name, $info) = @_;
    my $doc_dir = $info->index_resolved_path("usr/share/doc/${pkg_name}/");
    if ($doc_dir) {
        for my $name (
            qw(README.Debian.gz README.Debian README.debian.gz README.debian)){
            my $path = $doc_dir->child($name);
            next if not $path or not $path->is_open_ok;
            if ($name =~ m/\.gz$/) {
                return $path->open_gz;
            }
            return $path->open;
        }
    }
    return;
}

sub binary {
    my ($pkg_name, undef, $info, undef, $group) = @_;
    my $readme = '';

    my $fd = open_readme($pkg_name, $info);
    return if not defined($fd);
    while (my $line = <$fd>) {
        if ($line =~ m,/usr/doc\b,) {
            tag 'readme-debian-mentions-usr-doc', "line $.";
        }
        $readme .= $line;
    }
    close($fd);

    my @template =(
        'Comments regarding the Package',
        'So far nothing to say',
        '<possible notes regarding this package - if none, delete this file>',
        'Automatically generated by debmake'
    );
    my $regex = join('|', @template);
    if ($readme =~ m/$regex/io) {
        tag 'readme-debian-contains-debmake-template';
    } elsif ($readme =~ m/^\s*-- [^<]*<([^> ]+.\@[^>.]*)>/m) {
        tag 'readme-debian-contains-invalid-email-address', $1;
    }

    check_spelling($readme,$group->info->spelling_exceptions,
        $SPELLING_ERROR_IN_README);

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et
