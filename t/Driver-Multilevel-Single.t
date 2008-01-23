#!perl -w
use strict;
use warnings;
use lib 't/lib';
use CHI::t::Driver::Multilevel::Single;
CHI::t::Driver::Multilevel::Single->runtests;
