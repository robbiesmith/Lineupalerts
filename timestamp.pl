
my $sleep = 1; #first time through run right away

while ( sleep( $sleep ) ) {

	$sleep = 3600;

	my $now_string = localtime;
	
	print "$now_string\n";

}