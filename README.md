Lintian - Static Debian package analysis tool
=============================================

Lintian is a static analysis tool for finding many bugs, policy
violations and other issues in Debian based packages.  It can process
binary Debian packages (.deb), micro/installer packages (.udeb),
Debian source packages (.dsc) and (to a limited degree) the "changes"
files.


Running Lintian
===============

Running Lintian is as simple as invoking

    $ lintian path/to/pkg_version_arch.changes

Alternatively, you can pass Lintian binary/udeb or dsc files directly
instead of the .changes file.  Lintian is designed to work directly
from the source tree (simply use "frontend/lintian" itself).

For information about command options, please run lintian (or
lintian-info) with "--help". Alternatively, you can also read the
manpages lintian(1) and lintian-info(1).

Advice / Tips and Tricks
------------------------

If there is a tag you are not familiar with, you can use "--info" or
lintian-info to get more information:

    $ lintian-info -t no-version-field

If you want to enable all tags, simply use the "Evil and pedantic"
mnemonic:

    $ lintian -EvIL +pedantic path/to/pkg_version_arch.changes

You may want to drop the "-v", which may make Lintian more verbose
than you would like.  Also, keep in mind that "-E" enables
"experimental" tags and "-L +pedantic" enables some very pedantic
tags.

Lintian is not always right!  Static analysis involves a trade-off
between "accuracy" and CPU/memory usage.  Furthermore, in some cases,
certain packages trigger a corner case where the Debian Policy gives
more leeway than Lintian does.

If you have installed Lintian via the "lintian" Debian package, you
can find the Lintian User's Manual in:

    $ sensible-browser /usr/share/doc/lintian/lintian.html/index.html
    # or in txt format
    $ less /usr/share/doc/lintian/lintian.txt.gz

Alternatively, Debian provides an on-line version of the manual on
the [Lintian web site][online-manual].

[online-manual]: https://lintian.debian.org/manual/index.html

Compiling Lintian
=================

Lintian is written in pure Perl and therefore does not require any
"building" at all.  Consequently, Lintian currently does not have a
build system.  Instead it relies on its Debian build system
(implemented in debian/rules) and debhelper.  Thus, on Debian-based
systems, installing the build dependencies (see debian/control) and
running:

    $ dpkg-buildpackage

will provide you with a "lintian" Debian package.

So far there has been little work in providing a stand-alone build
system as Lintian requires a fair share of "Debian specific" tools and
libraries, including the "Dpkg" and "AptPkg" Perl modules.

We are willing to accept and maintain a stand-alone build system for
Lintian.  Where not intrusive, we may also be willing to accept
alternative dependencies for "Debian specific" libraries/tools.

Developing/Patching Lintian
===========================

If you are interested in working developing patches for Lintian or
just writing your own Lintian checks, please download the Lintian
source and consider reading the doc/README.developers from the source
tree:

    $ perldoc doc/README.developers

We also have some short tutorials in our API docs.  You can compile
the API documentation via:

    $ debian/rules api-doc
    $ sensible-browser doc/api.html/index.html

From there, you might want to start with "Lintian::Tutorial".  If you
prefer to use perldoc (or want to improve the tutorials), you can find
the source files for the tutorial in doc/tutorial.

There is also an online copy on the [Lintian web site][online-api-docs].
Note that the online copy does not necessarily reflect the API of the
current development version of Lintian.  Instead, it is the API of
Lintian when it was last updated on the Lintian web site.

[online-api-docs]: https://lintian.debian.org/library-api/index.html

Feedback
========

Please file bugs against the "lintian" package in the Debian Bug
Tracker.  We recommend using reportbug(1) for filing bugs, but
in its absence you send a [mail to the BTS][bts-report-bug].

Any comments, critics, or suggestions about Lintian or related topics
are highly appreciated by the authors! Please contact
<lintian-maint@debian.org>.  Thanks!

Please note that all data submitted to the Debian Bug Tracker and the
address <lintian-maint@debian.org> will be available to the general
public.  Should you be aware of a severe non-disclosed security issue
in Lintian, then please contact the
[Debian Security Team][report-security-issue] instead.

[bts-report-bug]: https://www.debian.org/Bugs/Reporting

[report-security-issue]: https://www.debian.org/security/faq#contact
