package Business::OfflineShipping;

use strict;

our $VERSION = '0.10';

sub new {
    my ($class,$shipper) = @_;
   die("OfflineShipping: unspecified shipper") unless $shipper;

    my $subclass = "${class}::$shipper";
    
    eval "use $subclass";
die("unknown shipper $shipper ($@)") if $@;

    my $self = bless {shipper => $shipper}, $subclass;

    return $self;
}

=head1
This is a simple constructor for a new OfflineShipping subclass. For maximal flexibility
all values are passed directly to the subclass and this parent class is minimal.

Given a list of shipping modes to iterate through, usage is something like this:

	foreach $mode (split /\s+/, $shipmodes) {
	# from $mode find $shipper as the subclass to be called, eg 'USPS', 'RoyalMail'
	
	  my $shipment = new OfflineShipping($shipper);
	($rate, $service) = $shipment->ship( 
							  country => $country, 
							  shipmode => $mode, 
							  weight => $shippingweight,
							  postcode => $postcode,
							  db => $db,
							  dbtype => $dbtype,
							  dbuser => $dbuser,
							  dbpassword => $dbpassword,
							  dancer => '0',
							  );
			  }
			  
while each shipping subclass would begin something like this:

sub ship {
	my ($self, %opts) = @_;
		...
    foreach(keys %opts) {
		$country = $opts{'country'};
		$service = $opts{'shipmode'};
		$weight = $opts{'weight'};
        $postcode = $opts{'postcode'};
        $db = $opts{'db'};
        $dbuser = $opts{'dbuser'};
        $dbpassword = $opts{'dbpassword'};
        $dbtype = $opts{'dbtype'};
        $dancer = $opts{'dancer'};
    }

    
It is expected that track() and label() subroutines follow a similar procedure

This is written to be portable and so passes raw database connection values through 
to each submodule. If you use this under Dancer as I do, ignore the db options 
and instead pass "dancer => '1'" and the submodules will use Dancer::Plugin::Database.


=item Shipping table

	  +---------------+--------------+------+-----+---------+-------+
	  | Field         | Type         | Null | Key | Default | Extra |
	  +---------------+--------------+------+-----+---------+-------+
	  | shipmode      | varchar(32)  | NO   | PRI | NULL    |       |
	  | service       | varchar(128) | YES  |     | NULL    |       |
	  | notes         | varchar(255) | YES  |     | NULL    |       |
	  | maxweight     | char(4)      | YES  |     | NULL    |       |
	  | shippingclass | varchar(64)  | YES  |     | NULL    |       |
	  +---------------+--------------+------+-----+---------+-------+

	  
The site.pm, as part of the /checkout route, calls this:

	($cart, $totals, $order_total, $shippinglist) = order();

and has this:  'template xx, {
		  shippinglist => \@$shippinglist,

The checkout page then has the following to display the shipping list:

       <select name="selectedshipmode">
       [% FOREACH ship IN shippinglist %]
       <option value="[% ship.mode %]" [% ship.selected %]> [% ship.service %] : [% ship.frate %] </option>
		[% END %]
	   </select>

The 'frate' above is the rate formatted with the appropriate currency code.


=head1 LICENCE AND COPYRIGHT

Copyright Lyn St George

This module is free software and is published under the same terms as Perl itself.

See http://dev.perl.org/licenses/ for more information.

Lyn St George, December 2013, lyn@zolotek.net

=cut

1;
