package Business::OfflineShipping::UPS;

use DBI;
use POSIX;

use strict;

our $VERSION = '0.10';

	my ($db, $dbuser, $dbpassword, $dbtype);

sub ship {
	my ($self, %opts) = @_;
	my ($dbh,$sth,$table,$shipping,$delivery,$maxweight,$dancer);
	my ($countrycode,$mode,$weight,$destination,$postcode,$zone,$max,$service);
	
    foreach(keys %opts) {
		$countrycode = $opts{'country'};
		$mode = $opts{'mode'};
		$weight = $opts{'weight'};
        $postcode = $opts{'postcode'};
        $db = $opts{'db'};
        $dbuser = $opts{'dbuser'};
        $dbpassword = $opts{'dbpassword'};
        $dbtype = $opts{'dbtype'};
    }
	    if ($dancer == '1') {
			use Dancer::Plugin::Database;
			use Dancer ':syntax';
			$dbh = database;
			}
		else {	    
	    	$dbh = dbconnect();
	    }

#debug("UPS; country=$countrycode, mode=$mode,w=$weight, postcode=$postcode");

		return unless length $mode;
	
		$countrycode = uc($countrycode);
	    $mode = lc($mode);

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
#debug("UPS".__LINE__.": dest=$destination; postcode=$postcode, service=$mode, weight=$weight\n");
	  return("Need zip code") if $destination eq 'domestic' && !$postcode;

	  return("Error: invalid destination") if $destination eq 'skip';
	
	my %servicemap = (
		  q{ups_1day} =>  q{UPS Next Day},
		  q{ups_1day_am} => q{UPS Next Day Early}, 
		  q{ups_1day_saver} => q{UPS Next Day Saver},
		  q{ups_2day} => q{UPS 2 Day},
		  q{ups_2day_am} => q{UPS 2 Day Early},
		  q{ups_3day} => q{UPS 3 Day Air },
		  q{ups_ground} => q{UPS Ground},
		  q{ups_express} => q{UPS World Wide Express},
		  q{ups_express_saver} => q{UPS World Wide Express Saver},
		  q{ups_expedited} => q{UPS World Wide Expedited},
		  q{ups_standard_ca} => q{UPS Standard},
		  q{ups_standard_mx} => q{UPS Standard},
	
		);

		$table = lc($mode); 
		
		$service = $servicemap{ $mode } || $mode;
		
		$mode =~ s/ups_//g;
	
#debug("UPS".__LINE__.": dbh=$dbh; mode=$mode service=$service, weight=$weight, dest=$destination, table=$table\n");

	if ($destination eq 'domestic') {
	# find zone from tbl
	$sth = $dbh->prepare("SELECT $mode FROM ups_zones_dom WHERE zip <='$postcode' ORDER BY zip DESC LIMIT 1");
	$sth->execute() or warn $sth->errstr;
	$zone = $sth->fetchrow_array() or die $sth->errstr;
	$zone =~ s/^0*//g;
#debug("UPS: zone=$zone, weight=$weight, tbl=$table");	

				}
	else {
	$sth = $dbh->prepare("SELECT $zone,$max FROM ups_zones_intl WHERE code ='$destination'");
#debug("UPS: intl zone=$zone,max=$max,dest=$destination");
	$sth->execute() or warn $sth->errstr;
	($zone,$max) = $sth->fetchrow_array() or die $sth->errstr;
#debug("UPS: intl zone=$zone,max=$max");

	}
	
	$weight = ceil($weight);
#debug("UPS,weight=$weight, zone=$zone, tbl=$table");

	$sth = $dbh->prepare("SELECT z$zone FROM $table WHERE weight='$weight'");
	$sth->execute() or warn $sth->errstr;
	$shipping = $sth->fetchrow_array();
	
	$shipping ||= '0';
	$shipping = 'error' unless $shipping > '0';

		return($shipping,$service) if $shipping eq 'error';

	my $type = 'air';
	   $type = 'ground' if $mode eq 'ground';
	
	$sth = $dbh->prepare("SELECT rate FROM ups_fuel_surcharge WHERE code='$type'");
	$sth->execute() or warn $sth->errstr;
	my $surcharge = $sth->fetchrow_array() || '.1';
	   $shipping += $shipping * $surcharge;
	   $shipping = sprintf '%.2f', $shipping;
	
#debug("UPS".__LINE__.": baseshipping in USD=$shipping =========\n");	

		return($shipping,$service);

}

sub track {
    my ($tracking, %opt) = @_;

	my $tracking_number = shift;
    my $lwp = LWP::UserAgent->new();
    my $result = $lwp->get("http://wwwapps.ups.com/tracking/tracking.cgi?tracknum=$tracking_number");

	my ($page, $updated, $latest, $current, $out);
       $page = $result->content();
	   $page =~ s/\n//g;

	   $page =~ m|<li>(Updated.*Time)\W*<\/li>|i;
	   $updated = $1;
	   $updated = "<div>" . $updated . "</div>";
#debug("UPStrack".__LINE__.": updated=$updated");

	   $page =~ m|.*Delivered Begin.*(<label>.*<\/dd><\/dl>).*Delivered End.*|i;
	   $latest = $1;
	   $latest = "<div>" . $latest . "<p></div>";
#debug("UPStrack".__LINE__.": latest=$latest");

	   $page =~ m|START\: Standard.*\>Shipment Progress.*(<table.*<tr.*<\/table>).*END\: Standard|i;
	   $current = $1;
	   $current =~ s/class="dataTable"//i;
	   $current =~ s/cellpadding="0"/cellpadding='3'/gi;

       $out = "<div>" . $updated . "<p>" . $latest . "<p>" . $current . "</div>";
#debug("UPStrack".__LINE__.": out=$out");
	   return($out);
}

sub label {
# TODO 

}


sub dbconnect   { 
    my $dsn = "DBI:" . $dbtype . ":database=" . $db;
    my $dbh = DBI->connect( $dsn, $dbuser, $dbpassword, { AutoCommit => 1 }) or die $DBI::errstr;
    my $drh = DBI->install_driver( $dbtype );
    return($dbh);
}

1;

=head1
This uses SQL tables based on data from UPS for offline tables. 
Tables are named after the shipmodes.

	ups_1day;
	+--------+--------------+------+-----+---------+-------+
	| Field  | Type         | Null | Key | Default | Extra |
	+--------+--------------+------+-----+---------+-------+
	| weight | varchar(3)   | YES  |     | NULL    |       |
	| z102   | decimal(5,2) | YES  |     | NULL    |       |
	| z103   | decimal(5,2) | YES  |     | NULL    |       |
	| z104   | decimal(5,2) | YES  |     | NULL    |       |
	| z105   | decimal(5,2) | YES  |     | NULL    |       |
	| z106   | decimal(5,2) | YES  |     | NULL    |       |
	| z107   | decimal(5,2) | YES  |     | NULL    |       |
	| z108   | decimal(5,2) | YES  |     | NULL    |       |
	| z124   | decimal(5,2) | YES  |     | NULL    |       |
	| z125   | decimal(5,2) | YES  |     | NULL    |       |
	| z126   | decimal(5,2) | YES  |     | NULL    |       |
	+--------+--------------+------+-----+---------+-------+

	ups_1day_saver;
	+--------+--------------+------+-----+---------+-------+
	| Field  | Type         | Null | Key | Default | Extra |
	+--------+--------------+------+-----+---------+-------+
	| weight | varchar(3)   | YES  |     | NULL    |       |
	| z132   | decimal(5,2) | YES  |     | NULL    |       |
	| z133   | decimal(5,2) | YES  |     | NULL    |       |
	| z134   | decimal(5,2) | YES  |     | NULL    |       |
	| z135   | decimal(5,2) | YES  |     | NULL    |       |
	| z136   | decimal(5,2) | YES  |     | NULL    |       |
	| z137   | decimal(5,2) | YES  |     | NULL    |       |
	| z138   | decimal(5,2) | YES  |     | NULL    |       |
	+--------+--------------+------+-----+---------+-------+

	ups_2day;
	+--------+--------------+------+-----+---------+-------+
	| Field  | Type         | Null | Key | Default | Extra |
	+--------+--------------+------+-----+---------+-------+
	| weight | varchar(3)   | YES  |     | NULL    |       |
	| z202   | decimal(5,2) | YES  |     | NULL    |       |
	| z203   | decimal(5,2) | YES  |     | NULL    |       |
	| z204   | decimal(5,2) | YES  |     | NULL    |       |
	| z205   | decimal(5,2) | YES  |     | NULL    |       |
	| z206   | decimal(5,2) | YES  |     | NULL    |       |
	| z207   | decimal(5,2) | YES  |     | NULL    |       |
	| z208   | decimal(5,2) | YES  |     | NULL    |       |
	| z224   | decimal(5,2) | YES  |     | NULL    |       |
	| z225   | decimal(5,2) | YES  |     | NULL    |       |
	| z226   | decimal(5,2) | YES  |     | NULL    |       |
	+--------+--------------+------+-----+---------+-------+

	ups_2day_am;
	+--------+--------------+------+-----+---------+-------+
	| Field  | Type         | Null | Key | Default | Extra |
	+--------+--------------+------+-----+---------+-------+
	| weight | varchar(3)   | YES  |     | NULL    |       |
	| z242   | decimal(5,2) | YES  |     | NULL    |       |
	| z243   | decimal(5,2) | YES  |     | NULL    |       |
	| z244   | decimal(5,2) | YES  |     | NULL    |       |
	| z245   | decimal(5,2) | YES  |     | NULL    |       |
	| z246   | decimal(5,2) | YES  |     | NULL    |       |
	| z247   | decimal(5,2) | YES  |     | NULL    |       |
	| z248   | decimal(5,2) | YES  |     | NULL    |       |
	+--------+--------------+------+-----+---------+-------+

	ups_3day;
	+--------+--------------+------+-----+---------+-------+
	| Field  | Type         | Null | Key | Default | Extra |
	+--------+--------------+------+-----+---------+-------+
	| weight | varchar(3)   | YES  |     | NULL    |       |
	| z302   | decimal(5,2) | YES  |     | NULL    |       |
	| z303   | decimal(5,2) | YES  |     | NULL    |       |
	| z304   | decimal(5,2) | YES  |     | NULL    |       |
	| z305   | decimal(5,2) | YES  |     | NULL    |       |
	| z306   | decimal(5,2) | YES  |     | NULL    |       |
	| z307   | decimal(5,2) | YES  |     | NULL    |       |
	| z308   | decimal(5,2) | YES  |     | NULL    |       |
	+--------+--------------+------+-----+---------+-------+


	ups_ground;
	+--------+--------------+------+-----+---------+-------+
	| Field  | Type         | Null | Key | Default | Extra |
	+--------+--------------+------+-----+---------+-------+
	| weight | varchar(3)   | YES  |     | NULL    |       |
	| z2     | decimal(5,2) | YES  |     | NULL    |       |
	| z3     | decimal(5,2) | YES  |     | NULL    |       |
	| z4     | decimal(5,2) | YES  |     | NULL    |       |
	| z5     | decimal(5,2) | YES  |     | NULL    |       |
	| z6     | decimal(5,2) | YES  |     | NULL    |       |
	| z7     | decimal(5,2) | YES  |     | NULL    |       |
	| z8     | decimal(5,2) | YES  |     | NULL    |       |
	| z44    | decimal(5,2) | YES  |     | NULL    |       |
	| z45    | decimal(5,2) | YES  |     | NULL    |       |
	| z46    | decimal(5,2) | YES  |     | NULL    |       |
	+--------+--------------+------+-----+---------+-------+

	ups_zones_dom;
	+------------+------------+------+-----+---------+-------+
	| Field      | Type       | Null | Key | Default | Extra |
	+------------+------------+------+-----+---------+-------+
	| zip        | varchar(8) | NO   | PRI | NULL    |       |
	| ground     | char(3)    | YES  |     | NULL    |       |
	| 3day       | char(3)    | YES  |     | NULL    |       |
	| 2day       | char(3)    | YES  |     | NULL    |       |
	| 2day_am    | char(3)    | YES  |     | NULL    |       |
	| 1day_saver | char(3)    | YES  |     | NULL    |       |
	| 1day       | char(3)    | YES  |     | NULL    |       |
	+------------+------------+------+-----+---------+-------+


	ups_fuel_surcharge;
	+-------+------------+------+-----+---------+-------+
	| Field | Type       | Null | Key | Default | Extra |
	+-------+------------+------+-----+---------+-------+
	| code  | varchar(7) | YES  |     | NULL    |       |
	| rate  | char(3)    | YES  |     | NULL    |       |
	+-------+------------+------+-----+---------+-------+



=head1 LICENCE AND COPYRIGHT

Copyright Lyn St George

This module is free software and is published under the same terms as Perl itself.

See http://dev.perl.org/licenses/ for more information.

Lyn St George, December 2013, lyn@zolotek.net

=cut
