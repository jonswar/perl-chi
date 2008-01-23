#!perl -w
use strict;
use warnings;
use lib 't/lib';
use CHI::t::Driver::Memory;
CHI::t::Driver::Memory->runtests;
