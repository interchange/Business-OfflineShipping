package Business::OfflineShipping::USPS;

use DBI;
use POSIX;

use strict;

our $VERSION = '0.10';

	my ($db, $dbuser, $dbpassword, $dbtype, $dbh, $usps_id, $usps_password);

sub ship {
	my ($self, %opts) = @_;
	my ($sth,$table,$shipping,$delivery,$maxweight,$dancer);
	my ($countrycode,$service,$weight,$destination,$postcode,$zone,$max);
	
    foreach(keys %opts) {
		$countrycode = $opts{'country'};
		$service = $opts{'mode'};
		$weight = $opts{'weight'};
        $postcode = $opts{'postcode'};
        $db = $opts{'db'};
        $dbuser = $opts{'dbuser'};
        $dbpassword = $opts{'dbpassword'};
        $dbtype = $opts{'dbtype'};
        $usps_id = $opts{'shipper_id'};
        $usps_password = $opts{'shipper_password'};
        $dancer = $opts{'dancer'};
    }
	    if ($dancer == '1') {
			use Dancer::Plugin::Database;
			use Dancer ':syntax';
			$dbh = database;
			}
		else {	    
	    	$dbh = dbconnect();
	    }

		return unless length $service;
	
		$countrycode = uc($countrycode);
	    $service = lc($service);

#
# first determine if destination is domestic or not from countrycode, and remap UK to GB
# as they don't believe the UK can be posted to ... skip places such as the Antarctic which 
# USPS really does not post to.
#
    my %destmap = (
			q{US} => q{domestic},
            q{MH} => q{domestic},
			q{AS} => q{domestic},
			q{GU} => q{domestic},
			q{MM} => q{domestic},
			q{MP} => q{domestic},
			q{PW} => q{domestic},
			q{PR} => q{domestic},
			q{VI} => q{domestic},
			q{FM} => q{domestic},
            q{UK} => q{GB},
			q{HM} => q{skip},
			q{ZR} => q{skip},
			q{AQ} => q{skip},
			q{BV} => q{skip},
			q{IO} => q{skip},
			q{TF} => q{skip},
			q{EH} => q{skip},  
			q{PS} => q{skip},
			q{SJ} => q{skip},
			q{YU} => q{skip},
        );
	
      $destination = $destmap{ $countrycode } || $countrycode;

	  return("Error: invalid destination") if $destination eq 'skip';
	  
	  return() if $destination eq 'domestic' && !$postcode;
	  
	
	my %servicemap = (
		  q{usps_fc_pkg} =>  q{USPS First Class Package},
		  q{usps_pm_retail} => q{USPS Priority Mail},
		  q{usps_pm_com_base} => q{USPS Priority Mail},
		  q{usps_pm_com_plus} => q{USPS Priority Mail},
		  q{usps_pme_retail} => q{USPS Priority Mail Express},
		  q{usps_pme_com_base} => q{USPS Priority Mail Express},
		  q{usps_pme_com_plus} => q{USPS Priority Mail Express},
		  q{usps_pmi_retail} => q{USPS Priority Mail International},
		  q{usps_pmi_com_base} => q{USPS Priority Mail International},
		  q{usps_pmi_com_plus} => q{USPS Priority Mail International},
		  q{usps_fcpi_retail} => q{USPS First Class Package International},
		  q{usps_fcpi_com_base} => q{USPS First Class Package International},
		  q{usps_fcpi_com_plus} => q{USPS First Class Package International},
	
		);

		$table = lc($service); 
		$table ||= 'usps_pm_retail' if $destination eq 'domestic';
		$table ||= 'usps_pmi_retail' if $destination ne 'domestic';
		
		$zone = $table;
		$zone =~ /usps_(\w+)_.*/;
		$zone = $1; # for intl lookup
		$max = $zone;
		$zone .= '_zone';
		$max .= '_max';
		$service = $servicemap{ $service } || $service;
		

	if ($destination eq 'domestic') {
	#
	# find zone from tbl
	#
	$sth = $dbh->prepare("SELECT zone FROM usps_zones_dom WHERE code <='$postcode' ORDER BY CODE DESC LIMIT 1");
	$sth->execute() or warn $sth->errstr;
	$zone = $sth->fetchrow_array() or die $sth->errstr;
				}
	else {
	$sth = $dbh->prepare("SELECT $zone,$max FROM usps_zones_intl WHERE code ='$destination'");
	$sth->execute() or warn $sth->errstr;
	($zone,$max) = $sth->fetchrow_array() or die $sth->errstr;
	return('0','') unless length $zone;

	}
	
	#
	# First Class mail tables, both domestic and intl, are in ounces; rest in pounds
	#
	$weight *= '16' if $table =~ /fc/;
	$weight = ceil($weight);
	$weight = sprintf '%02d', $weight;

	$sth = $dbh->prepare("SELECT z$zone FROM $table WHERE weight='$weight'");
	$sth->execute() or warn $sth->errstr;
	$shipping = $sth->fetchrow_array();
	
	$shipping ||= '0';
	$shipping = 'error' unless $shipping > '0';
	 
	return($shipping,$service);

}

sub track {
    my ($tracking, %opt) = @_;
		$tracking ||= '';
	   return unless $tracking;

    my $userid = $opt{userid} || setting('usps_id');
    my $passwd = $opt{passwd} || setting('usps_password');
    my $url = $opt{url} || setting('usps_url') || 'http://Production.ShippingAPIs.com/ShippingAPI.dll';

	my ($response, $error_msg, $xml);
	   my $trackdetail = '';
	   my $tracksummary = '';
	   my $trackerror = '';
	   my $trackinfo = '';

	   $xml = <<EOX;
API=TrackV2&XML=
<TrackRequest USERID="$userid">
  <TrackID ID="$tracking"></TrackID>
</TrackRequest>
EOX

	 my $ua = LWP::UserAgent->new;
	    $ua->timeout(30);
	 my $req = HTTP::Request->new('POST' => $url);
		$req->content_type('text/xml');
		$req->content_length( length($xml) );
		$req->content($xml);
	 my $resp = $ua->request($req);
	 my $respcode = $resp->status_line;

	if ($resp->is_success && $resp->content){
	    $response = $resp->content();
		$error_msg = 'USPS: ';
    } 
    else {
		$error_msg .= 'Error obtaining tracking from USPS';
		return $resp->status_line;
    }
	my $xmlIn = new XML::Simple();
	my $data = $xmlIn->XMLin($response);
#	   $data = $data->{'TrackResponse'}->{'TrackInfo'};
	   $data = $data->{'TrackInfo'}; 
	   $tracksummary = $data->{'TrackSummary'} || '';
	   $trackerror = $data->{'Error'} || '';
	   $trackdetail = $data->{'TrackDetail'} || '';
	  if (length $trackdetail ) {
		if ($data->{'TrackDetail'} =~ /ARRAY/i) {
			for my $i (0 .. 22) {
			$trackdetail .= "$data->{'TrackDetail'}[$i]<br>";
			}
		  }
		else {
			$trackdetail = $data->{'TrackDetail'};
		} 
	  }
		  $trackdetail =~ s|<br><br>||g;
		  $trackinfo = "$tracksummary<p>$trackdetail";

	  return($trackinfo);


}

sub label {
# ### TODO ###

}


sub dbconnect   { 
    my $dsn = "DBI:" . $dbtype . ":database=" . $db;
    my $dbh = DBI->connect( $dsn, $dbuser, $dbpassword, { AutoCommit => 1 }) or die $DBI::errstr;
    my $drh = DBI->install_driver( $dbtype );
    return($dbh);
}

1;

=head1
This uses SQL tables based on the new data from USPS for offline tables. 
Tables are named after the shipmodes.

	usps_zones_dom;
	+-------+------------+------+-----+---------+-------+
	| Field | Type       | Null | Key | Default | Extra |
	+-------+------------+------+-----+---------+-------+
	| code  | varchar(9) | YES  |     | NULL    |       |
	| zone  | varchar(3) | YES  |     | NULL    |       |
	+-------+------------+------+-----+---------+-------+

	usps_zones_intl;
	+-----------+-------------+------+-----+---------+-------+
	| Field     | Type        | Null | Key | Default | Extra |
	+-----------+-------------+------+-----+---------+-------+
	| code      | char(3)     | NO   |     | NULL    |       |
	| name      | varchar(64) | YES  |     | NULL    |       |
	| gxg_zone  | varchar(2)  | YES  |     | NULL    |       |
	| gxg_max   | varchar(2)  | YES  |     | NULL    |       |
	| pmei_zone | varchar(2)  | YES  |     | NULL    |       |
	| pmei_max  | varchar(2)  | YES  |     | NULL    |       |
	| pmi_zone  | varchar(2)  | YES  |     | NULL    |       |
	| pmi_max   | varchar(2)  | YES  |     | NULL    |       |
	| fcmi_zone | varchar(2)  | YES  |     | NULL    |       |
	| fcmi_max  | varchar(3)  | YES  |     | NULL    |       |
	| fcpi_zone | varchar(2)  | YES  |     | NULL    |       |
	| fcpi_max  | varchar(2)  | YES  |     | NULL    |       |
	+-----------+-------------+------+-----+---------+-------+

	usps_fcmi_retail;
	+--------+--------------------------+------+-----+---------+-------+
	| Field  | Type                     | Null | Key | Default | Extra |
	+--------+--------------------------+------+-----+---------+-------+
	| weight | int(2) unsigned zerofill | YES  |     | NULL    |       |
	| z1     | decimal(5,2)             | YES  |     | NULL    |       |
	| z2     | decimal(5,2)             | YES  |     | NULL    |       |
	| z3     | decimal(5,2)             | YES  |     | NULL    |       |
	| z4     | decimal(5,2)             | YES  |     | NULL    |       |
	| z5     | decimal(5,2)             | YES  |     | NULL    |       |
	| z6     | decimal(5,2)             | YES  |     | NULL    |       |
	| z7     | decimal(5,2)             | YES  |     | NULL    |       |
	| z8     | decimal(5,2)             | YES  |     | NULL    |       |
	+--------+--------------------------+------+-----+---------+-------+

	usps_fcpi_retail;
	+--------+--------------------------+------+-----+---------+-------+
	| Field  | Type                     | Null | Key | Default | Extra |
	+--------+--------------------------+------+-----+---------+-------+
	| weight | int(2) unsigned zerofill | YES  |     | NULL    |       |
	| z1     | decimal(5,2)             | YES  |     | NULL    |       |
	| z2     | decimal(5,2)             | YES  |     | NULL    |       |
	| z3     | decimal(5,2)             | YES  |     | NULL    |       |
	| z4     | decimal(5,2)             | YES  |     | NULL    |       |
	| z5     | decimal(5,2)             | YES  |     | NULL    |       |
	| z6     | decimal(5,2)             | YES  |     | NULL    |       |
	| z7     | decimal(5,2)             | YES  |     | NULL    |       |
	| z8     | decimal(5,2)             | YES  |     | NULL    |       |
	| z9     | decimal(5,2)             | YES  |     | NULL    |       |
	+--------+--------------------------+------+-----+---------+-------+


	usps_pmi_retail;
	+--------+--------------------------+------+-----+---------+-------+
	| Field  | Type                     | Null | Key | Default | Extra |
	+--------+--------------------------+------+-----+---------+-------+
	| weight | int(2) unsigned zerofill | YES  |     | NULL    |       |
	| z1     | decimal(5,2)             | YES  |     | NULL    |       |
	| z2     | decimal(5,2)             | YES  |     | NULL    |       |
	| z3     | decimal(5,2)             | YES  |     | NULL    |       |
	| z4     | decimal(5,2)             | YES  |     | NULL    |       |
	| z5     | decimal(5,2)             | YES  |     | NULL    |       |
	| z6     | decimal(5,2)             | YES  |     | NULL    |       |
	| z7     | decimal(5,2)             | YES  |     | NULL    |       |
	| z8     | decimal(5,2)             | YES  |     | NULL    |       |
	| z9     | decimal(5,2)             | YES  |     | NULL    |       |
	| z10    | decimal(5,2)             | YES  |     | NULL    |       |
	| z11    | decimal(5,2)             | YES  |     | NULL    |       |
	| z12    | decimal(5,2)             | YES  |     | NULL    |       |
	| z13    | decimal(5,2)             | YES  |     | NULL    |       |
	| z14    | decimal(5,2)             | YES  |     | NULL    |       |
	| z15    | decimal(5,2)             | YES  |     | NULL    |       |
	| z16    | decimal(5,2)             | YES  |     | NULL    |       |
	| z17    | decimal(5,2)             | YES  |     | NULL    |       |
	+--------+--------------------------+------+-----+---------+-------+

	usps_pmei_retail;
	+--------+--------------------------+------+-----+---------+-------+
	| Field  | Type                     | Null | Key | Default | Extra |
	+--------+--------------------------+------+-----+---------+-------+
	| weight | int(2) unsigned zerofill | YES  |     | NULL    |       |
	| z1     | decimal(5,2)             | YES  |     | NULL    |       |
	| z2     | decimal(5,2)             | YES  |     | NULL    |       |
	| z3     | decimal(5,2)             | YES  |     | NULL    |       |
	| z4     | decimal(5,2)             | YES  |     | NULL    |       |
	| z5     | decimal(5,2)             | YES  |     | NULL    |       |
	| z6     | decimal(5,2)             | YES  |     | NULL    |       |
	| z7     | decimal(5,2)             | YES  |     | NULL    |       |
	| z8     | decimal(5,2)             | YES  |     | NULL    |       |
	| z9     | decimal(5,2)             | YES  |     | NULL    |       |
	| z10    | decimal(5,2)             | YES  |     | NULL    |       |
	| z11    | decimal(5,2)             | YES  |     | NULL    |       |
	| z12    | decimal(5,2)             | YES  |     | NULL    |       |
	| z13    | decimal(5,2)             | YES  |     | NULL    |       |
	| z14    | decimal(5,2)             | YES  |     | NULL    |       |
	| z15    | decimal(5,2)             | YES  |     | NULL    |       |
	| z16    | decimal(5,2)             | YES  |     | NULL    |       |
	| z17    | decimal(5,2)             | YES  |     | NULL    |       |
	+--------+--------------------------+------+-----+---------+-------+


	usps_pme_retail;
	+--------+--------------------------+------+-----+---------+-------+
	| Field  | Type                     | Null | Key | Default | Extra |
	+--------+--------------------------+------+-----+---------+-------+
	| weight | int(2) unsigned zerofill | YES  |     | NULL    |       |
	| z1     | decimal(5,2)             | YES  |     | NULL    |       |
	| z2     | decimal(5,2)             | YES  |     | NULL    |       |
	| z3     | decimal(5,2)             | YES  |     | NULL    |       |
	| z4     | decimal(5,2)             | YES  |     | NULL    |       |
	| z5     | decimal(5,2)             | YES  |     | NULL    |       |
	| z6     | decimal(5,2)             | YES  |     | NULL    |       |
	| z7     | decimal(5,2)             | YES  |     | NULL    |       |
	| z8     | decimal(5,2)             | YES  |     | NULL    |       |
	+--------+--------------------------+------+-----+---------+-------+

	usps_pm_retail;
	+--------+--------------------------+------+-----+---------+-------+
	| Field  | Type                     | Null | Key | Default | Extra |
	+--------+--------------------------+------+-----+---------+-------+
	| weight | int(2) unsigned zerofill | YES  |     | NULL    |       |
	| z1     | decimal(5,2)             | YES  |     | NULL    |       |
	| z2     | decimal(5,2)             | YES  |     | NULL    |       |
	| z3     | decimal(5,2)             | YES  |     | NULL    |       |
	| z4     | decimal(5,2)             | YES  |     | NULL    |       |
	| z5     | decimal(5,2)             | YES  |     | NULL    |       |
	| z6     | decimal(5,2)             | YES  |     | NULL    |       |
	| z7     | decimal(5,2)             | YES  |     | NULL    |       |
	| z8     | decimal(5,2)             | YES  |     | NULL    |       |
	+--------+--------------------------+------+-----+---------+-------+

=head1 LICENCE AND COPYRIGHT

Copyright Lyn St George

This module is free software and is published under the same terms as Perl itself.

See http://dev.perl.org/licenses/ for more information.

Lyn St George, December 2013, lyn@zolotek.net
	

=cut
