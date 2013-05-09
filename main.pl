use LWP;
use XML::Simple;
use URI::Escape;
use POSIX qw(strftime);
use JSON qw( decode_json );
use Data::Dumper;


# Create a user agent object
#  use LWP::UserAgent;
    my $ua = LWP::UserAgent->new;

	#Create the xml parser
	my $xml = new XML::Simple;

my $sleep = 1;
my @sentmessages;

while ( sleep($sleep ) ) {
	$sleep = 3600;
	$sleep = 10;

	my $now_string = localtime;
	
	print "$now_string\n";
	
	my $hourString = strftime "%H", localtime;
	# CLEAN OUT THE LIST OF SENT MESSAGES EVERY DAY AT 1 AM
	if ( $hourString eq "01" ) {
		@sentmessages = ();
	}

	@phoneList = ();
	%userTeamlistHash = ();

	my $usersURL = "http://qam.espn.go.com/alerts/users/smithrp/flbLineupAlerts";
	my $usersReq = HTTP::Request->new(GET => $usersURL);
	my $res = $ua->request($usersReq);

  	if ($res->is_success) {
		my $decoded_json = decode_json( $res->content );
		my $usersJson = $decoded_json->{"users"};
		for my $userItem (@$usersJson) {
			my $leagueList = $userItem->{"leagues"};
			$userTeamlistHash{ "$userItem->{phone}" } = $leagueList;
			push (@phoneList, "$userItem->{phone}");
		}
	}
#		print Dumper %userTeamlistHash;
	
	for my $phoneNumber (@phoneList) {
## NOW USING CE - NOT phonenumbers.txt
#	open PHONEFILE, "phonenumbers.txt" or die $!;
##	
#	while (my $phoneNumber = <PHONEFILE>) {
#	#	my $phoneNumber = "9176966439"; # Rob Android
#	#	my $phoneNumber = "9172792970"; # Dave
#	#	my $phoneNumber = "3473023696"; # Rob Phone 7
#	#	my $phoneNumber = "3474131043"; # Neil
#	# 9176960820 # Hickey
#	# 8609067679 # Sujal
#	# 9176961116 # Welch
#	# 8603357142 # Mullen
#	#	if ( $ARGV[0] ) {
#	#		$phoneNumber = $ARGV[0];
#	#	}
#
##5163173842

		# Find the SWID from the phone number
		my $swid;
	
		my $swidURL = "http://m.espn.go.com/alerts/util/getSWIDbyMDN?mdn=1${phoneNumber}";
		my $swidReq = HTTP::Request->new(GET => $swidURL);
		my $res = $ua->request($swidReq);
	
	  	if ($res->is_success) {
			$swid = $res->content;
		}
		if ( $swid eq "null" ) {
			print "swid is null for $phoneNumber\n";
			print $swidURL;
		}
	
		# Fine the username from the swid
		my $username;
	
		my $usernameURL = "http://m.espn.go.com/alerts/util/userInfoXMLbySwid?key=Adsf84Jf290fA4fK&swid=${swid}";
		my $usernameReq = HTTP::Request->new(GET => $usernameURL);
		my $res = $ua->request($usernameReq);
	
	  	if ($res->is_success) {
			my $userData = $xml->XMLin($res->content);
			$username = $userData->{username};
		}
	
	    $ua->default_header('Cookie' => "SWID=${swid}");
	
		#Get the teams for this user
		my $req = HTTP::Request->new(GET => "http://games.espn.go.com/flb/wireless/xml/espnapp/userEntries?");
		my $res = $ua->request($req);
	
		my $sleep = 1; #first time through run right away
	
		if ($res->is_success) {
			my $data = $xml->XMLin($res->content, ForceArray => [ 'userEntry' ] );
			foreach my $userEntry (@{$data->{userEntry}}) {
				my $leagueId = $userEntry->{leagueId};
				my $leagueName = $userEntry->{leagueName};
				my $teamId = $userEntry->{teamId};
				my @leagueList = @{$userTeamlistHash{$phoneNumber}};
				my $leagueInList = 0;
				for my $league (@leagueList) {
					if ($league == $leagueId) {
						$leagueInList = 1;
					}
					if ($league == "all") {
						$leagueInList = 1;
					}
				}
				if (not $leagueInList) {
					next; #this league is not in the user's list - skip it
				}
				
				#Get the roster for each team
				my $rosterURL = "http://games.espn.go.com/flb/wireless/xml/espnapp/roster?includeCacheableData=true&userName=${username}&leagueId=${leagueId}&teamId=${teamId}";
				my $rosterReq = HTTP::Request->new(GET => $rosterURL);
			    my $rosterRes = $ua->request($rosterReq);
	
			    if ($rosterRes->is_success) {
					my $rosterData = $xml->XMLin($rosterRes->content);
					my $roster = $rosterData->{team}->{roster};
					my $teamName = $rosterData->{team}->{teamName};
					foreach my $rosterGroup (@{$roster->{rosterGroup}}) {
						my $groupName = $rosterGroup->{rosterGroupName};
						my $isPitchers = 0;
						if ( $groupName eq "PITCHERS") {
							$isPitchers = 1;
						}
						# Determine if each player is inactive
						my $players = $rosterGroup->{players};
						foreach my $player (@{$players->{player}}) {
							my $message;
							if ( $isPitchers ) {
								if( $player->{probableStarter} eq "true" ) {
									if( $player->{slot} eq "BE" || $player->{slot} eq "DL" ) {
										$message = uri_escape("ESPN Lineup - $player->{playerName} is starting and is on the Bench on team ${teamName} in league ${leagueName}\n");
									}
								}
							} else {
								if( $player->{probableStarter} eq "false" && $player->{playerStatus} eq "3" ) {
									if( $player->{slot} ne "BE" && $player->{slot} ne "DL" ) {
										$message = uri_escape("ESPN Lineup - $player->{playerName} is not starting and is in your lineup on team ${teamName} in league ${leagueName}\n");
									}
								}
							}
							# Send a text message to the user if a roster problem was identified
							if( $message ) {
								if ( $message ~~ @sentmessages ) {
									# no need to send a text - already did send this message
								} else {
									my $sendTextURL = "http://m.espn.go.com/alerts/util/sendSMS?phoneNumber=${phoneNumber}&message=${message}\n";
									my $sendTextReq = HTTP::Request->new(GET => $sendTextURL);
								    my $sendTextRes = $ua->request($sendTextReq);
								    print "$username: ";
									print uri_unescape(${message});
									push (@sentmessages, $message);
								}
							}
						}
					}
			    }
			}
		} else {
		      print $res->status_line, "\n";
		}
	}
}

  
