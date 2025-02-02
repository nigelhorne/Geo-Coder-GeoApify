package Geo::Coder::GeoApify;

use strict;
use warnings;

use Carp;
use Encode;
use JSON::MaybeXS;
use HTTP::Request;
use LWP::UserAgent;
use LWP::Protocol::https;
use URI;

=head1 NAME

Geo::Coder::GeoApify - Provides a Geo-Coding functionality using L<https://www.geoapify.com/maps-api/>

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use Geo::Coder::GeoApify;

    my $geo_coder = Geo::Coder::GeoApify->new(apiKey => $ENV{'GEOAPIFY_KEY'});
    my $location = $geo_coder->geocode(location => '10 Downing St., London, UK');

=head1 DESCRIPTION

Geo::Coder::GeoApify provides an interface to https://www.geoapify.com/maps-api/,
a free Geo-Coding database covering many countries.

=head1 METHODS

=head2 new

    $geo_coder = Geo::Coder::GeoApify->new(apiKey => $ENV{'GEOAPIFY_KEY'});

=cut

sub new
{
	my $class = shift;

	# Handle hash or hashref arguments
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	# Ensure the correct instantiation method is used
	unless (defined $class) {
		carp(__PACKAGE__, ' Use ->new() not ::new() to instantiate');
		return;
	}

	# If $class is an object, clone it with new arguments
	return bless { %{$class}, %args }, ref($class) if ref($class);

	# Validate that the apiKey is provided and is a scalar
	my $apiKey = $args{'apiKey'};
	unless (defined $apiKey && !ref($apiKey)) {
		carp(__PACKAGE__, defined $apiKey ? ' apiKey must be a scalar' : ' apiKey not given');
		return;
	}

	# Set up user agent (ua) if not provided
	my $ua = $args{'ua'} // LWP::UserAgent->new(agent => __PACKAGE__ . "/$VERSION");
	$ua->default_header(accept_encoding => 'gzip,deflate');
	$ua->env_proxy(1);

	# Disable SSL verification if the host is not defined (not recommended in production)
	$ua->ssl_opts(verify_hostname => 0) unless defined $args{'host'};

	# Set host, defaulting to 'api.geoapify.com/v1/geocode'
	my $host = $args{'host'} // 'api.geoapify.com/v1/geocode';

	# Return the blessed object
	return bless { ua => $ua, host => $host, apiKey => $apiKey }, $class;
}

=head2 geocode

    $location = $geo_coder->geocode(location => $location);

    print 'Latitude: ', $location->{'features'}[0]{'geometry'}{'coordinates'}[1], "\n";
    print 'Longitude: ', $location->{'features'}[0]{'geometry'}{'coordinates'}[0], "\n";

    @locations = $geo_coder->geocode('Portland, USA');
    print 'There are Portlands in ', join (', ', map { $_->{'state'} } @locations), "\n";

=cut

sub geocode
{
	my $self = shift;
	my %params;

	# Handle different types of input
	if(ref $_[0] eq 'HASH') {
		%params = %{$_[0]};
	} elsif(ref $_[0]) {
		Carp::croak('Usage: geocode(location => $location)');
		return;	# Required for t/carp.t test case
	} elsif((@_ % 2) == 0) {
		%params = @_;
	} else {
		$params{location} = shift;
	}

	# Ensure location is provided
	my $location = $params{location}
		or Carp::croak('Usage: geocode(location => $location)');

	# Fail when the input is just a set of numbers
	if($params{'location'} !~ /\D/) {
		Carp::croak('Usage: ', __PACKAGE__, ": invalid input to geocode(), $params{location}");
		return;
	}

	# Encode location if it's in UTF-8
	$location = Encode::encode_utf8($location) if Encode::is_utf8($location);

	# Create URI for the API request
	my $uri = URI->new("https://$self->{host}/search");

	# Handle potential confusion between England and New England
	$location =~ s/(.+),\s*England$/$1, United Kingdom/i;

	# Replace spaces with plus signs for URL encoding
	$location =~ s/\s/+/g;

	# Set query parameters
	$uri->query_form('text' => $location, 'apiKey' => $self->{'apiKey'});
	my $url = $uri->as_string();

	# Send the request and handle response
	my $res = $self->{ua}->get($url);

	if($res->is_error()) {
		Carp::carp("API returned error on $url: ", $res->status_line());
		return {};
	}

	# Decode the JSON response
	my $json = JSON::MaybeXS->new->utf8();
	my $rc;
	eval {
		$rc = $json->decode($res->decoded_content());
	};
	if($@ || !defined $rc) {
		Carp::carp("$url: Failed to decode JSON - ", $@ || $res->content());
		return {};
	}

	return $rc;
}

=head2 ua

Accessor method to get and set UserAgent object used internally. You
can call I<env_proxy> for example, to get the proxy information from
environment variables:

    $geo_coder->ua()->env_proxy(1);

You can also set your own User-Agent object:

    use LWP::UserAgent::Throttled;

    my $ua = LWP::UserAgent::Throttled->new();
    $ua->throttle({ 'api.geoapify.com' => 5 });
    $ua->env_proxy(1);
    $geo_coder = Geo::Coder::GeoApify->new({ ua => $ua, apiKey => $ENV{'GEOAPIFY_KEY'} });

=cut

sub ua
{
	my $self = shift;

	# Update 'ua' if an argument is provided
	$self->{ua} = shift if @_;

	# Return the 'ua' value
	return $self->{ua};
}

=head2 reverse_geocode

    my $address = $geo_coder->reverse_geocode(lat => 37.778907, lon => -122.39732);
    print 'City: ', $address->{features}[0]->{'properties'}{'city'}, "\n";

Similar to geocode except it expects a latitude,longitude pair.

=cut

sub reverse_geocode
{
	my $self = shift;
	my %params;

	# Handle input: accept either hash or hashref
	if(ref $_[0] eq 'HASH') {
		%params = %{$_[0]};
	} elsif(ref $_[0]) {
		Carp::croak('Usage: reverse_geocode(lat => $lat, lon => $lon)');
		return;	# Required for t/carp.t test case
	} elsif((@_ % 2) == 0) {
		%params = @_;
	}

	# Validate latitude and longitude
	my $lat = $params{lat} or Carp::carp('Missing latitude (lat)');
	my $lon = $params{lon} or Carp::carp('Missing longitude (lon)');

	return {} unless $lat && $lon;	# Return early if lat or lon is missing

	# Build URI for the API request
	my $uri = URI->new("https://$self->{host}/reverse");
	$uri->query_form(
		'lat'	=> $lat,
		'lon'	=> $lon,
		'apiKey' => $self->{'apiKey'}
	);
	my $url = $uri->as_string();

	# Send request to the API
	my $res = $self->{ua}->get($url);

	# Handle API errors
	if($res->is_error) {
		Carp::carp("API returned error on $url: ", $res->status_line());
		return {};
	}

	# Decode the JSON response
	my $json = JSON::MaybeXS->new->utf8();
	my $rc;
	eval {
		$rc = $json->decode($res->decoded_content());
	};

	# Handle JSON decoding errors
	if($@ || !defined $rc) {
		Carp::carp("$url: Failed to decode JSON - ", $@ || $res->content());
		return {};
	}

	return $rc;
}

=head1 AUTHOR

Nigel Horne, C<< <njh at bandsman.co.uk> >>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Lots of thanks to the folks at geoapify.com

=head1 SEE ALSO

L<Geo::Coder::GooglePlaces>, L<HTML::GoogleMaps::V3>

=head1 LICENSE AND COPYRIGHT

Copyright 2024 Nigel Horne.

This program is released under the following licence: GPL2

=cut

1;
