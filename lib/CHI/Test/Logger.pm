package CHI::Test::Logger;
use strict;
use warnings;
use CHI::Util qw(dump_one_line);
use List::MoreUtils qw(first_index);
use Test::Deep qw(cmp_deeply);
use base qw(Class::Accessor);
__PACKAGE__->mk_ro_accessors(qw(msgs));

foreach my $level (qw(fatal error warn info debug)) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$level" } = sub {
        my ( $self, $msg ) = @_;
        $self->{msgs} ||= [];
        push( @{ $self->{msgs} }, $msg );
    };
    *{ __PACKAGE__ . "::is_$level" } = sub { 1 };
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
