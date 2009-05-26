# $Id: $
#
package CHI::Test;
use List::MoreUtils qw(uniq);

BEGIN {

    # If PERL_LOCAL_LIB is set, run tests with libs restricted to PERL_LOCAL_LIB
    # OS X specific for now
    #
    if ( my $local_lib = $ENV{PERL_LOCAL_LIB} ) {
        @INC = uniq( grep { !m{^(/Library|/Network/Library)} } @INC );
        push( @INC,
            map { $_, "$_/darwin-thread-multi-2level" } $ENV{PERL_LOCAL_LIB} );
    }
}
use CHI;
use CHI::Driver::Memory;
use CHI::Test::Logger;
use CHI::Util qw(require_dynamic);
use strict;
use warnings;

sub import {
    my $class = shift;
    $class->export_to_level( 1, undef, @_ );
}

sub packages_to_import {
    return (
        qw(
          Test::Deep
          Test::More
          Test::Exception
          CHI::Test::Util
          )
    );
}

sub export_to_level {
    my ( $class, $level, $ignore ) = @_;

    foreach my $package ( $class->packages_to_import() ) {
        require_dynamic($package);
        my @export;
        if ( $package eq 'Test::Deep' ) {

            # Test::Deep exports way too much by default
            @export =
              qw(eq_deeply cmp_deeply cmp_set cmp_bag cmp_methods subbagof superbagof subsetof supersetof superhashof subhashof);
        }
        else {

            # Otherwise, grab everything from @EXPORT
            no strict 'refs';
            @export = @{"$package\::EXPORT"};
        }
        $package->export_to_level( $level + 1, undef, @export );
    }
}

1;
