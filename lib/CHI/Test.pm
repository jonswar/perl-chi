# $Id: $
#
package CHI::Test;

use Log::Any::Test;    # as early as possible
use List::MoreUtils qw(uniq);
use Module::Runtime qw(require_module);
use CHI;
use CHI::Driver::Memory;
use Import::Into;
use strict;
use warnings;

sub import {
    my $class = shift;

    # Test::Deep exports way too much by default
    'Test::Deep'->import::into(
        1, qw(eq_deeply cmp_deeply cmp_set cmp_bag
          cmp_methods subbagof superbagof subsetof
          supersetof superhashof subhashof)
    );

    # Exports all by default
    'Test::More'->import::into(1);

    # Exports all by default
    'Test::Exception'->import::into(1);

    # EXPORT_OK Only
    'CHI::Test::Util'->import::into(
        1, qw(activate_test_logger is_between
          cmp_bool random_string skip_until)
    );
}

sub export_to_level {
    my ( $class, $level, $ignore ) = @_;
    $class->import::into($level);
}

1;
