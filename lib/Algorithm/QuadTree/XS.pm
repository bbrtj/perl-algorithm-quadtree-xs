package Algorithm::QuadTree::XS;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT = qw(
	_AQT_init
	_AQT_deinit
	_AQT_addObject
	_AQT_findObjects
	_AQT_delete
	_AQT_clear
);

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('Algorithm::QuadTree::XS', $VERSION);

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Algorithm::QuadTree::XS - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Algorithm::QuadTree::XS;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Algorithm::QuadTree::XS, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

bartosz, E<lt>bartosz@nonetE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2022 by bartosz

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.34.0 or,
at your option, any later version of Perl 5 you may have available.


=cut

