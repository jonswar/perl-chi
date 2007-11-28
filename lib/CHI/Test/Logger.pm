package CHI::Test::Logger;
use CHI::Util;
use List::MoreUtils qw(first_index);
use Test::Deep qw(cmp_deeply);
use strict;
use warnings;
use base qw(Class::Accessor);
__PACKAGE__->mk_ro_accessors(qw(msgs));

sub is_debug { 1 }

sub debug {
    my ( $self, $msg ) = @_;
    $self->{msgs} ||= [];
    push( @{ $self->{msgs} }, $msg );
}

sub contains_ok {
    my ( $self, $regex ) = @_;
    my $tb = Test::Builder->new();

    my $found = first_index { /$regex/ } @{ $self->{msgs} };
    if ( $found != -1 ) {
        splice( @{ $self->{msgs} }, $found, 1 );
        $tb->ok( 1, "found message matching $regex" );
    }
    else {
        $tb->ok( 0,
            "could not find message matching $regex; log contains: "
              . dump_one_line( $self->{msgs} ) );
    }
}

sub clear {
    my ($self) = @_;

    $self->{msgs} = [];
}

sub empty_ok {
    my ($self) = @_;

    cmp_deeply( $self->{msgs}, [] );
}

1;
