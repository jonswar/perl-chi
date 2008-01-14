package CHI::Test::Util;
use strict;
use warnings;
use Test::Builder;
use base qw(Exporter);

our @EXPORT_OK = qw(is_between cmp_bool);

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

sub cmp_bool {
    my ( $bool1, $bool2, $desc ) = @_;

    my $tb = Test::Builder->new();
    if ( $bool1 && !$bool2 ) {
        $tb->diag("bool1 is true, bool2 is false");
    }
    elsif ( !$bool1 && $bool2 ) {
        $tb->diag("bool1 is false, bool2 is true");
    }
    else {
        $tb->ok( 1, $desc );
    }
}

1;
