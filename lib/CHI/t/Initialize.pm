package CHI::t::Initialize;
use strict;
use warnings;
use CHI::Test;
use CHI::Util qw(dump_one_line);
use base qw(CHI::Test::Class);

sub is_good {
    my (@params) = @_;

    my $cache = CHI->new(@params);
    isa_ok(
        $cache,
        'CHI::Driver',
        sprintf( "got a good cache with params '%s'",
            dump_one_line( \@params ) )
    );
}

sub is_bad {
    my (@params) = @_;

    dies_ok( sub { my $cache = CHI->new(@params) },
        sprintf( "died with params '%s'", dump_one_line( \@params ) ) );
}

sub test_driver_options : Test(7) {
    my $cache;
    is_good( driver       => 'Memory',              global => 1 );
    is_good( driver       => 'File' );
    is_good( driver_class => 'CHI::Driver::Memory', global => 1 );
    is_good( driver_class => 'CHI::Driver::File' );
    is_bad( driver_class => 'Memory' );
    is_bad( driver       => 'CHI::Driver::File' );
    is_bad( driver       => 'DoesNotExist' );
}

1;
