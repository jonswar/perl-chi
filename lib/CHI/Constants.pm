package CHI::Constants;
use strict;
use warnings;
use base qw(Exporter);

my @all_constants = do {
    no strict 'refs';
    grep { exists &$_ } keys %{ __PACKAGE__ . '::' };
};
our @EXPORT_OK = (@all_constants);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

use constant CHI_Meta_Namespace => '_CHI_METACACHE';
use constant CHI_Max_Time       => 0xffffffff;

1;

__END__

=pod

=head1 NAME

CHI::Constants -- Internal constants

=head1 DESCRIPTION

These are constants for internal CHI use.

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz, all rights reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
