# Generated from Makefile.PL using makefilepl2cpanfile

requires 'perl', '5.6.2';

requires 'CHI';
requires 'Encode';
requires 'ExtUtils::MakeMaker', '6.64';
requires 'HTTP::Request';
requires 'JSON::MaybeXS';
requires 'LWP::Protocol::https';
requires 'LWP::UserAgent';
requires 'Params::Get', '0.04';
requires 'Params::Validate::Strict';
requires 'Time::HiRes';
requires 'URI';

on 'develop' => sub {
	requires 'Devel::Cover';
	requires 'Perl::Critic';
	requires 'Test::Pod';
	requires 'Test::Pod::Coverage';
};
