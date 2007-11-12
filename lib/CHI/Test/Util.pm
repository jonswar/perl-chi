package CHI::Test::Util;
use strict;
use warnings;
use Test::Builder;
use base qw(Exporter);

our @EXPORT = qw(is_between);

sub is_between {
    my ( $value, $min, $max, $desc ) = @_;

    my $tb = Test::Builder->new();
    if ( $value >= $min && $value <= $max ) {
        $tb->ok( 1, $desc );
    }
    else {
        $tb->diag("$value is not between $min and $max");
        $tb->ok( undef, $desc );
    }
}

1;
