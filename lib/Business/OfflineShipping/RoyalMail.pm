package Business::OfflineShipping::RoyalMail;

use POSIX;
use DBI;

use strict;

our $VERSION = '0.10';

	my $db;
	my $dbuser;
	my $dbpassword;
	my $dbtype;
	my $dbh;


sub ship {
	my ($self, %opts) = @_;
	my ($ship,$shipping,$rates,$currency,$over,$wdiff,$rmweight,$tblmult,$maxlistedweight,$maxlistedrate,$steps,$rmadd);
	my ($country,$mode,$weight,$destination,$postcode,$zone,$max,$dbh,$dancer);

    foreach(keys %opts) {
		$country = $opts{'country'};
		$mode = $opts{'mode'};
		$weight = $opts{'weight'};
        $postcode = $opts{'postcode'};
        $db = $opts{'db'};
        $dbuser = $opts{'dbuser'};
        $dbpassword = $opts{'dbpassword'};
        $dbtype = $opts{'dbtype'};
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

	    $mode =~ s/rm\_//; # legacy format
debug("RM:".__LINE__.": country=$country,mode=$mode,weight=$weight");
	   
	   
	my $type            = setting('rm_type') || 'stamp'; # or 'frank' for franking account
	my $sd_sat_by9      = setting('rm_sd_sat_by9')   || '3.00'; # per item, by 9am saturday
	my $tracked_europe  = setting('rm_tracked_europe') || '5.00';
	my $signed_europe   = setting('rm_signed_europe') || '5.30';
	my $tracked_world   = setting('rm_tracked_world') || '5.40';
	my $signed_world    = setting('rm_signed_world') || '5.30';


	  $country  = 'GB' if ($country eq 'UK');

    my $sth = $dbh->prepare("SELECT rmtable FROM rm_zones WHERE code='$country'");
       $sth->execute() or die $sth->errstr;
	my $table = $sth->fetchrow() || 'rm_domestic';
	   $table = 'rm_bfpo' if ($mode =~ /^bf/);

   unless ($table eq 'rm_bfpo') {
	   $mode    .= $type unless ($mode =~ /surface/);
   }
debug("RM:".__LINE__.": table=$table, mode=$mode, country=$country");

#    $mode = 'parcel0' if (($mode =~ /packet/) and ($weight > '20') and ($table eq 'rm_domestic'));
#	$mode = 'parcel0' if ($mode !~ /^letter|^packet|^parcel|^sd/ and $table eq 'rm_domestic');
#	$mode = 'airpacket' . $type if ($mode !~ /^air|surface/ and ($table eq 'rm_europe' or $table eq 'rm_world'));
	
#
# find max listed weight and rate for table and mode;
#
    $sth = $dbh->prepare("SELECT weight,$mode FROM $table WHERE $mode<>'0' ORDER BY weight DESC LIMIT 1");
	$sth->execute() or die $sth->errstr;
	($maxlistedweight,$maxlistedrate) = $sth->fetchrow_array() or die $sth->errst;
#debug("ShipRM".__LINE__.": maxlistedweight=$maxlistedweight,mlrate=$maxlistedrate");
    if ($weight > $maxlistedweight) {
        $wdiff = $weight - $maxlistedweight;
	   if ($table =~ /domestic/) {
			  $wdiff = ceil($wdiff);
			  $wdiff += '1' if ($wdiff % 2 == 1);
			  $steps = $wdiff / 2;
			  }
	    else {
			  $steps = ceil($wdiff * 10);
			  }
#debug("RM".__LINE__.": wdiff=$wdiff, steps=$steps");  
#
# get overage rate for mode
#
#		  $sth = $dbh->prepare("SELECT $mode FROM $table WHERE weight='00.00'");
#		  $sth->execute();
#		  $over = $sth->fetchrow();
		  $over = $dbh->quick_lookup( $table, { weight => '00.00'}, $mode);
			if ($over != '00.00') {
			   $ship = $maxlistedrate + ($steps * $over);
debug("RM:".__LINE__.": wdiff=$wdiff, over=$over,  ship=$ship");
			}
		}
	else {
	# get rate for listed weight
	$sth = $dbh->prepare("SELECT MIN($mode) AS $mode FROM $table WHERE $mode<>0 AND weight>=$weight");
	$sth->execute() or die $sth->errstr;
	$shipping = $sth->fetchrow() or die $sth->errstr;
	  }

 my $extra = ''; # FIXME ###	
# 
# additional fees
#
	$shipping += $tracked_europe if ($extra =~ /tracked/ && $table =~ /europe/);
	$shipping += $signed_europe if ($extra =~ /signed/ && $table =~ /europe/);
	$shipping += $tracked_world if ($extra =~ /tracked/ && $table =~ /world/);
	$shipping += $signed_world if ($extra =~ /signed/ && $table =~ /world/);
	$shipping += $sd_sat_by9 if ($extra =~ /sd_sat_by9/);


 undef $mode;
debug("RM:".__LINE__.": shipping=$shipping\n-----------------------------------\n\n");
return $shipping;

}

sub track {
#
# ### FIXME ### the royal arses may have broken this ...
#
  my $trackno = shift;
debug("TrackRM:trackno=$trackno");
   my $url = "https://www.royalmail.com/portal/sme/trackintermediate?itemDetailsNotdebuggedIn=true&catId=&trackingNumber=$trackno&mediaId=";
print "RMtrack: url=$url\n";
  my $page = get $url;
debug("TrackRM: page=$page ");
    $page =~ s/\n//g; # serialise
    $page =~ m|(.*Help\</a\>\</div\>\</div\>)(\<div class="tracktrace\-content"\>.*\</div\>)(\<div class="tracktrace\-link\-footer.*)|;
 my $tracktable = $2;
return($tracktable);

}

sub label {
# ### TODO ###
}



sub dbconnect   { 
    my $dsn = "DBI:" . $dbtype . ":$dbh=" . $db;
    my $dbh = DBI->connect( $dsn, $dbuser, $dbpassword, { AutoCommit => 1 }) or die $DBI::errstr;
    my $drh = DBI->install_driver( $dbtype );
#debug("USPS :*: db: db=$db,dbtype=$dbtype,user=$dbuser,pass=$dbpassword, dsn=$dsn");    
    return($dbh);
}

1;

=head1
UserTag royalmail2013 Documentation  <<EOD
Modes are: 
RM1letter (1st class, domestic) no thicker than 25mm
RM2letter (2nd class, domestic) no thicker than 25mm, max 1kg
RMpacket - int packet, max 2kg
RM1packet - 1st class packet, ie a large letter thicker than 25mm
RM2packet - 2nd class packet, ie a large letter thicker than 25mm, max 1kg
RMnext1 (Special Delivery by 1pm, domestic), 
RMnext9 (Special Delivery by 9am, domestic),
RMparcel (domestic), RMair (letter, international), RMpacket (international),
RMpaper (printed paper only, international)
#====================
Domestic deliveries:
Standard parcels: delivery in 3 - 5 days; max 20kg; no proof of delivery.
1st class mail: delivery aimed for next day; no weight limit; no proof of delivery.
"Recorded signed for" 0.68 + 1st class mail rate. Has tracking.
===========
Next day ("special delivery") by 1pm: 10kg weight limit; has proof of delivery and tracking. All
postcodes in England, Wales, Northern Ireland and mainland Scotland except:
    Next working day 5.30pm
  Mainland: AB30-56-Aberdeen, IV21-28, 40, 52-54-Inverness,
  KW1-14-Caithness, PA28-38-Argyll, PH15, 17-26, 31-40-Perthshire,
  PH49-Ballachulish, PH50-Kinlochleven
  Islands: HS1-Stornoway (Lewis), KA27-Arran, KA28-Cumbrae,
  KW15-Kirkwall, KW16-Stormness Town only, PA4141 Gigha, PA 42-49 Islay,
  PA 60-Jura, PA77-Tiree, ZE1-Lerwick (Shetlands), HS3-Harris,
  HS4-Scalpay, HS5 Leverburgh, HS6-N.Uist, HS7-Benbecula, HS8-Erisksay,
  HS8-S, Uist, HS9-Castlebay (Barra), IV41-51, 55-56-Skye
    Two working days 5.30pm
  GY1-Herm only (Channel Islands), GY9-Sark (Channel Islands), HS2-Lewis,
  PA61-Colonsay, PA62-75-Mull, PA78-Coll, ZE2-3-Shetlands
    Three working days 5.30pm
  KW-16-17-Orkney, PH30-Corrour, PH41-Mallaig, PH42-Eigg & Muck,
  PH43-44-Isle of Rum & Canna


Please note that Special Delivery cannot be used when sending an item to an
Admail address
N.B. Deliveries to the Channel Islands and the Isle of Man can be delayed by Customs.
===================
Next day ("special delivery") by 9am: (max 2kg); has proof of delivery and tracking.
  All UK postcodes in England, Wales, Northern Ireland and mainland
 Scotland except those listed below.
  AB30-39, 41-45, 51, 53-56-Aberdeen, AB52-Inverurie, GY1-9-Guernsey
  (including Alderney, Herm and Sark), HS1-Stornoway, HS2-Lewis,
  HS3-Harris, HS4-Scalpay, HS5-Leverburgh, HS6-N.Uist, HS7-Benbecula,
  HS8-Erisksay, HS8-S. Uist, HS9-Castlebay (Barra), IM-All (except IM1)-Isle
  of Man, IV-All (except IV1), KA27-Arran, KA28-Cumbrae, KW-All, PA20-49,
  PA60-Jura, PA61-Colonsay, PA62-75-Mull, PA76-Iona, PA77-Tiree,
  PA78-Coll, PH15-29, 31-40, 45-50-Perthshire, PH30-Corrour, PH41-Mallaig,
  PH42-Eigg and Muck, PH43-Isle of Rum, PH44-Canna, PO30-41-Isle of
  Wight, TR21-25 Isles of Scilly, ZE1-Lerwick, ZE2,3-Shetlands

Please note that Special Delivery cannot be used when sending an item to an
Admail address
N.B. Deliveries to the Channel Islands and the Isle of Man can be delayed by Customs
================
Saturday Guarantee
Available at an additional £2 on items posted on a Friday*
* Available to areas where Special Delivery guarantees Next Day delivery. Guarantee not applicable
  to items sent to Banks, Building Societies, Travel Agents, Jewellers and Post Office outlets.

#####################################################################
International deliveries:

RMair (airmail), max 2kg.
Airsure = airmail = £4.50, to anywhere. max 2kg.
int signed for = airmail + £3.70
#=================
"Int signed for" requires signature on delivery, though this is not routinely available to customers;
does not have delivery confirmation available online; is tracked only within the UK; delivery is to
abroad only.
"Airsure" does not require a signature on delivery; does have delivery confirmation available
online; is tracked world wide; delivery to abroad only.
#======
"Airsure" is available to these countries only:
Europe: Andorra, Austria, Azores, Balearic Islands, Belgium, Canary Islands, Corsica, Denmark,
Faroe Islands, Finland, France, Germany, Iceland, Liechtenstein, Luxembourg, Madeira, Monaco,
Netherlands, Norway, Portugal, Republic of Ireland, Slovak Republic, Spain, Spitzbergen, Sweden and
Switzerland.
World Zone 1: USA
World Zone 2: New Zealand
#========================

The tag is called with these parameters:
[rm mode weight multiplier adder extra cap]
"mode" is RMnext1, RM1letter, RM2letter, RM1packet, RM2packet, RMparcelfor domestic deliveries;
RMair, RMpacket, RMpaper for European or World-wide deliveries.
"weight" is @@TOTAL@@.
"multiplier" is used to add a percentage to the rate.
"adder" is used to add a delivery surcharge, eg 2 for Saturday letters, or 4.20 to add the Airsure
surcharge to standard international airmail.
"extra" is for any extra surcharge, eg packing.
"cap" is a value at which to cap this shipping mode

=head1 SQL SCHEMAS	

Tables are named after the shipmodes.

	rm_zones;
	+---------+-------------+------+-----+---------+-------+
	| Field   | Type        | Null | Key | Default | Extra |
	+---------+-------------+------+-----+---------+-------+
	| code    | char(3)     | NO   | PRI | NULL    |       |
	| rmtable | varchar(64) | YES  | MUL | NULL    |       |
	| region  | varchar(64) | YES  |     | NULL    |       |
	| name    | varchar(64) | YES  |     | NULL    |       |
	+---------+-------------+------+-----+---------+-------+

	rm_domestic;
	+-------------------------+--------------------------------+------+-----+---------+-------+
	| Field                   | Type                           | Null | Key | Default | Extra |
	+-------------------------+--------------------------------+------+-----+---------+-------+
	| weight                  | decimal(4,2) unsigned zerofill | NO   | PRI | 00.00   |       |
	| letter1stamp            | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| letter1frank            | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| letter2stamp            | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| letter2frank            | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| letterlarge1stamp       | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| letterlarge1frank       | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| letterlarge2stamp       | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| letterlarge2frank       | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| parcelsmall1frank       | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| parcelsmall2stamp       | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| parcelsmall2frank       | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| parcelsmall1stamp       | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| sd_by1stamp             | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| sd_by1frank             | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedletter1stamp      | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedletter1frank      | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedletter2frank      | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedletter2stamp      | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedletterlarge2stamp | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedletterlarge2frank | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedletterlarge1frank | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedletterlarge1stamp | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedparcelsmall1stamp | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedparcelsmall1frank | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedparcelsmall2frank | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedparcelsmall2stamp | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedparcelmed2stamp   | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedparcelmed2frank   | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedparcelmed1frank   | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| signedparcelmed1stamp   | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| parcelmed1stamp         | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| parcelmed2stamp         | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| parcelmed2frank         | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| parcelmed1frank         | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| sd_by9                  | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| sd_by9stamp             | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| sd_by9frank             | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| sd_sat_by1stamp         | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| sd_sat_by1frank         | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	+-------------------------+--------------------------------+------+-----+---------+-------+


	rm_europe;
	+----------------+--------------------------------+------+-----+---------+-------+
	| Field          | Type                           | Null | Key | Default | Extra |
	+----------------+--------------------------------+------+-----+---------+-------+
	| weight         | char(6)                        | YES  | MUL | NULL    |       |
	| airletterstamp | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| airletterfrank | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| airparcelstamp | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| airparcelfrank | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| surfaceparcel  | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	+----------------+--------------------------------+------+-----+---------+-------+

	rm_world1;
	+----------------+--------------------------------+------+-----+---------+-------+
	| Field          | Type                           | Null | Key | Default | Extra |
	+----------------+--------------------------------+------+-----+---------+-------+
	| weight         | char(6)                        | YES  | MUL | NULL    |       |
	| airletterstamp | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| airletterfrank | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| airparcelstamp | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| airparcelfrank | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| surfaceletter  | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	+----------------+--------------------------------+------+-----+---------+-------+

	rm_world2;
	+----------------+--------------------------------+------+-----+---------+-------+
	| Field          | Type                           | Null | Key | Default | Extra |
	+----------------+--------------------------------+------+-----+---------+-------+
	| weight         | char(6)                        | YES  | MUL | NULL    |       |
	| airletterstamp | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| airletterfrank | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| airparcelstamp | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| airparcelfrank | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| surfaceletter  | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	+----------------+--------------------------------+------+-----+---------+-------+

	rm_bfpo;
	+---------------+--------------------------------+------+-----+---------+-------+
	| Field         | Type                           | Null | Key | Default | Extra |
	+---------------+--------------------------------+------+-----+---------+-------+
	| weight        | char(6)                        | YES  | MUL | NULL    |       |
	| bfletter      | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| bfletterlarge | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| bfpacket      | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| bfsd500       | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| bfsd1000      | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	| bfsd2500      | decimal(4,2) unsigned zerofill | YES  |     | 00.00   |       |
	+---------------+--------------------------------+------+-----+---------+-------+


=head1 LICENCE AND COPYRIGHT

Copyright Lyn St George

This module is free software and is published under the same terms as Perl itself.

See http://dev.perl.org/licenses/ for more information.

Lyn St George, December 2013, lyn@zolotek.net

=cut

1;

