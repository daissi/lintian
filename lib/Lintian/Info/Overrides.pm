# -*- perl -*- Lintian::Info::Overrides -- access to override data
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

package Lintian::Info::Overrides;

use strict;
use warnings;
use autodie;

use Path::Tiny;

use Lintian::Architecture qw(:all);
use Lintian::Tag::Override;
use Lintian::Util qw($PKGNAME_REGEX strip);

use Moo::Role;
use namespace::clean;

=head1 NAME

Lintian::Info::Overrides - access to override data

=head1 SYNOPSIS

    use Lintian::Processable;
    my $processable = Lintian::Processable::Binary->new;

=head1 DESCRIPTION

Lintian::Info::Overrides provides an interface to package data for overrides.

=head1 INSTANCE METHODS

=over 4

=item overrides(OVERRIDE-FILE)

Read OVERRIDE-FILE and add the overrides found there which match the
metadata of the current file (package and type).  The overrides are added
to the overrides hash in the info hash entry for the current file.

file_start() must be called before this method.  This method throws an
exception if there is no current file and calls fail() if the override
file cannot be opened.

=cut

sub overrides {
    my ($self, $TAGS) = @_;

    my @tags;

    my $profile = $TAGS->{profile};
    unless (defined $TAGS->{current}) {
        die 'no current file when adding overrides';
    }

    my $package = $self->pkg_name;
    my $architecture = $self->pkg_arch;
    my $type = $self->pkg_type;

    my $procstruct = $TAGS->{info}{$self->pkg_path};

    my $comments = [];
    my $last_over;

    my $overrides_path
      = path($self->info->groupdir)->child('override')->stringify;

    return
      unless -f $overrides_path;

    open(my $fh, '<:encoding(UTF-8)', $overrides_path);

    local $_;

  OVERRIDE:
    while (<$fh>) {
        strip;
        if ($_ eq '') {
            # Throw away comments, as they are not attached to a tag
            # also throw away the option of "carrying over" the last
            # comment
            $comments = [];
            $last_over = undef;
            next;
        }
        if (/^#/o){
            s/^# ?//o;
            push @$comments, $_;
            next;
        }
        s/\s+/ /go;
        my $override = $_;
        # The override looks like the following:
        # [[pkg-name] [arch-list] [pkg-type]:] <tag> [extra]
        # - Note we do a strict package name check here because
        #   parsing overrides is a bit ambiguous (see #699628)
        if (
            $override =~ m/\A (?:                   # start optional part
                  (?:\Q$package\E)?                 # optionally starts with package name -> $1
                  (?: \s*+ \[([^\]]+?)\])?          # optionally followed by an [arch-list] (like in B-D) -> $2
                  (?:\s*+ ([a-z]+) \s*+ )?          # optionally followed by the type -> $3
                :\s++)?                             # end optional part
                ([\-\+\.a-zA-Z_0-9]+ (?:\s.+)?)     # <tag-name> [extra] -> $4
                   \Z/xsm
        ) {
            # Valid - so far at least
            my ($archlist, $opkg_type, $tagdata)= ($1, $2, $3, $4);
            my ($rawtag, $extra) = split(m/ /o, $tagdata, 2);
            my $tag;
            my $tagover;
            my $data;
            if ($opkg_type and $opkg_type ne $type) {
                push(
                    @tags,
                    [
                        'malformed-override',
                        join(q{ },
                            "Override of $rawtag for package type $opkg_type",
                            "(expecting $type) at line $.")]);
                next;
            }
            if ($architecture eq 'all' && $archlist) {
                push(
                    @tags,
                    [
                        'malformed-override',
                        join(q{ },
                            'Architecture list for arch:all package',
                            "at line $. (for tag $rawtag)")]);
                next;
            }
            if ($archlist) {
                # parse and figure
                my (@archs) = split(m/\s++/o, $archlist);
                my $negated = 0;
                my $found = 0;
                foreach my $a (@archs){
                    $negated++ if $a =~ s/^!//o;
                    if (is_arch_wildcard($a)) {
                        $found = 1
                          if wildcard_includes_arch($a, $architecture);
                    } elsif (is_arch($a)) {
                        $found = 1 if $a eq $architecture;
                    } else {
                        push(
                            @tags,
                            [
                                'malformed-override',
                                join(q{ },
                                    "Unknown architecture \"$a\"",
                                    "at line $. (for tag $rawtag)")]);
                        next OVERRIDE;
                    }
                }
                if ($negated > 0 && scalar @archs != $negated){
                    # missing a ! somewhere
                    push(
                        @tags,
                        [
                            'malformed-override',
                            join(q{ },
                                'Inconsistent architecture negation',
                                "at line $. (for tag $rawtag)")]);
                    next;
                }
                # missing wildcard checks and sanity checking archs $arch
                if ($negated) {
                    $found = $found ? 0 : 1;
                }
                next unless $found;
            }

            if ($last_over && $last_over->tag eq $rawtag && !scalar @$comments)
            {
                # There are no new comments, no "empty line" in between and
                # this tag is the same as the last, so we "carry over" the
                # comment from the previous override (if any).
                #
                # Since L::T::Override is (supposed to be) immutable, the new
                # override can share the reference with the previous one.
                $comments = $last_over->comments;
            }
            $extra = '' unless defined $extra;
            $data = {
                'extra' => $extra,
                'comments' => $comments,
            };
            $comments = [];
            $tagover = Lintian::Tag::Override->new($rawtag, $data);
            # tag will be changed here if renamed reread
            $tag = $tagover->{'tag'};

            unless($tag eq $rawtag) {
                push(@tags, ['renamed-tag',"$rawtag => $tag at line $."]);
            }

            # treat here ignored overrides
            if ($profile && !$profile->is_overridable($tag)) {
                $TAGS->{ignored_overrides}{$tag}++;
                next;
            }
            $procstruct->{'overrides-data'}{$tag}{$extra} = $tagover;
            $procstruct->{overrides}{$tag}{$extra} = 0;
            $last_over = $tagover;
        } else {
            # We know this to be a bad override; check if it might be
            # an override for a different package.
            if ($override !~ m/^\Q$package\E[\s:\[]/) {
                # So, we got an override that does not start with the
                # package name - cases include:
                #  1 <tag> ...
                #  2 <tag> something: ...
                #  3 <wrong-pkg> [archlist] <type>: <tag> ...
                #  4 <wrong-pkg>: <tag> ...
                #  5 <wrong-pkg> <type>: <tag> ...
                #
                # Case 2 and 5 are hard to distinguish from one another.

                # First, remove the archlist if present (simplifies
                # the next step)
                $override =~ s/([^:\[]+)?\[[^\]]+\]([^:]*):/$1 $2:/;
                $override =~ s/\s\s++/ /g;

                if ($override
                    =~ m/^($PKGNAME_REGEX)?(?: (?:binary|changes|source|udeb))? ?:/o
                ) {
                    my $opkg = $1;
                    # Looks like a wrong package name - technically,
                    # $opkg could be a tag if the tag information is
                    # present, but it is very unlikely.
                    push(
                        @tags,
                        [
                            'malformed-override',
                            join(q{ },
                                'Possibly wrong package in override',
                                "at line $. (got $opkg, expected $package)")]);
                    next;
                }
            }
            # Nope, package name appears to match (or not present
            # at all), not sure what the problem is so we just throw a
            # generic parse error.

            push(@tags, ['malformed-override', "Cannot parse line $.: $_"]);
        }
    }
    close($fh);

    return @tags;
}

1;

=back

=head1 AUTHOR

Originally written by Felix Lechner <felix.lechner@lease-up.com> for
Lintian.

=head1 SEE ALSO

lintian(1), L<Lintian::Collect>, L<Lintian::Collect::Binary>,
L<Lintian::Collect::Source>

=cut

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et
