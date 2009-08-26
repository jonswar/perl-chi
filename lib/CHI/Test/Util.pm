package CHI::Test::Util;
use Date::Parse;
use Test::Builder;
use Test::Log::Dispatch;
use Test::More;
use strict;
use warnings;
use base qw(Exporter);

our @EXPORT_OK =
  qw(activate_test_logger is_between cmp_bool random_string skip_until);

sub activate_test_logger {
    my $log = Test::Log::Dispatch->new( min_level => 'debug' );
    Log::Any->set_adapter( 'Dispatch', dispatcher => $log );
    return $log;
}

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
        $tb->ok( 0, "$desc - bool1 is true, bool2 is false" );
    }
    elsif ( !$bool1 && $bool2 ) {
        $tb->ok( 0, "$desc - bool1 is false, bool2 is true" );
    }
    else {
        $tb->ok( 1, $desc );
    }
}

sub skip_until {
    my ( $until_str, $how_many, $code ) = @_;

    my $until = str2time($until_str);
  SKIP: {
        skip "until $until_str", $how_many if ( time < $until );
        $code->();
    }
}

# Generate random string of printable ASCII characters.
#
sub random_string {
    my ($length) = @_;

    return join( '', map { chr( int( rand(95) + 33 ) ) } ( 1 .. $length ) );
}

1;
