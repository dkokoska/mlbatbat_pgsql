#! /usr/bin/perl

# Postgres SQL and other modifications made by Brian Huey, 2016
# This script is made freely available for non-commerical use by Mike Fast
# August 2007
# http://fastballs.wordpress.com/
# Attribution is appreciated but not required.
#
# This script uses portions of Joseph Adler's code from hack_28_parser.pl
# as published by O'Reilly Media in the book Baseball Hacks, copyright 2006
# ISBN 0-596-00942-9, available at http://www.oreilly.com/catalog/baseballhks/
# used under the terms set forth in the book on Page xvi, as follows:
# "In general, you may use the code in this book in your programs and documentation.
# You do not need to contact us for permission unless you're reproducing a significant
# portion of the code.  For example, writing a program that uses several chunks of code
# from this book does not require permission."
#
# Code lines 26-85, 121-122, 207-217, 230-231, and 294-301 are largely by Joseph Adler
# and the rest of the code is largely or completely by Mike Fast

# Database connection statement
use DBI;
my $server_pw = $ENV{'DB_PW'}
$dbh = DBI->connect("DBI:Pg:database=baseball_test;host=localhost", 'power_user', $server_pw )
or die $DBI::errstr;

# Set base directory for XML game data download URL
$year = '2015';
$basedir = "./games/year_$year";

# Define XML objects
use XML::Simple;
$boxparser= new XML::Simple(ForceArray => 1, KeepRoot => 1, KeyAttr => 'boxscore');
$inningparser= new XML::Simple(ForceArray => 1, KeepRoot => 1, KeyAttr => 'inning');
$hitsparser= new XML::Simple(ForceArray => 1, KeepRoot => 1, KeyAttr => 'hitchart');
$playerparser= new XML::Simple(ForceArray => 1, KeepRoot => 1, KeyAttr => 'game');
$gameparser= new XML::Simple(ForceArray => 1, KeepRoot => 1, KeyAttr => 'game');

sub extract_date($) {
    my($in) = @_;
    my $gmyr = substr($in,0,4);
    my $gmmn = substr($in,5,2);
    my $gmdy = substr($in,8,2);
    my $gamedate = '\'' . $gmyr . '-' . $gmmn . '-' . $gmdy . '\'';
    return $gamedate;
}

sub extract_info($) {
    # This subroutine parses game information from the boxscore.xml file
    my ($box) = @_;
    my $home = $box->{boxscore}->[0]->{home_team_code};
    my $away = $box->{boxscore}->[0]->{away_team_code};
    my $game_id = "'" . $box->{boxscore}->[0]->{game_id} . "'";
    my $gamedate = extract_date($box->{boxscore}->[0]->{game_id});
    my $gameinfo = "'" . $box->{boxscore}->[0]->{game_info}->[0] . "'";
    my $away_team_runs = $box->{boxscore}->[0]->{linescore}->[0]->{away_team_runs};
    my $home_team_runs = $box->{boxscore}->[0]->{linescore}->[0]->{home_team_runs};
    my $status_ind = $box->{boxscore}->[0]->{status_ind};
    return ($home, $away, $game_id, $gamedate, $gameinfo, $away_team_runs, $home_team_runs, $status_ind);
}

# Get the list of months from the base year directory
opendir MDIR, $basedir;
@monthdirs = readdir MDIR;
closedir MDIR;

foreach $mondir (@monthdirs) {
    if ($mondir =~ /month/) {
        opendir DDIR, "$basedir/$mondir";
        my @daydirs = readdir DDIR;
        closedir DDIR;
        foreach $daydir (@daydirs) {
            if ($daydir =~ /day/) {
                opendir GDIR, "$basedir/$mondir/$daydir";
                my @gamedirs = readdir GDIR;
                closedir GDIR;
                foreach $gamedir (@gamedirs) {
                    if ($gamedir =~ /gid_/ and (-e "$basedir/$mondir/$daydir/$gamedir/inning/inning_hit.xml")) {
                        $fulldir = "$basedir/$mondir/$daydir/$gamedir";
                        $box = $boxparser->XMLin("$fulldir/boxscore.xml");
                        my ($home, $away, $game_id, $gamedate, $gameinfo, $away_team_runs, $home_team_runs, $status_ind) = extract_info($box);
                        # Game number = 1, unless the 2nd game of a doubleheader when game number = 2
                        $game_number = substr($game_id, -2, 1);
                    if ($gameinfo =~ /<br\/><b>Weather<\/b>: (\d+) degrees,.*<br\/><b>Wind<\/b>: (\d+) mph, ([\w\s]+).<br\/>/) {
                        $temperature = $1;
                        $wind = $2;
                        $wind_dir = "'" . $3 . "'";
                    } else {
        		        $gameinfo =~ /<br\/><b>Weather<\/b>: (\d+) degrees,.*<br\/><b>Wind<\/b>: (\bIndoors|0 mph)/;
                        # Domed stadiums may list wind speed as "Indoors"
                        $temperature = $1;
                        $wind = 0;
                        $wind_dir = "'Indoors'";
                    }
                $home = $dbh->quote($home);
                $away = $dbh->quote($away);
                $game = $gameparser->XMLin("$fulldir/game.xml");
                $game_time = $game->{game}->[0]->{local_game_time};
                $game_time = $dbh->quote($game_time);
    	        $status_ind = $dbh->quote($status_ind);
                # Input the game info into the database
                $no_duplicate_query = 'SELECT game_id FROM games WHERE (date = ' . $gamedate
                . ' AND home = ' . $home . ' AND away = ' . $away . ' AND game = ' . $game_number
                . ' AND game_id = ' . $game_id . ')';
                $sth= $dbh->prepare($no_duplicate_query) or die $DBI::errstr;
                $sth->execute();
                my $numRows = $sth->rows;
                $sth->finish();
                if ($numRows) {
                    # don't insert duplicate game entry into games table
                } else {
                    $game_query = 'INSERT INTO games (date, home, away, game, wind, wind_dir, temp,
                    runs_home, runs_away, local_time, game_id, completion) VALUES (' . $gamedate . ', '. $home . ', ' . $away
                    . ', ' . $game_number . ', ' . $wind . ', ' . $wind_dir . ', ' . $temperature . ', '
                    . $home_team_runs . ', ' . $away_team_runs . ', ' . $game_time . ',' . $game_id . ',' . $status_ind . ')';
                    $sth= $dbh->prepare($game_query) or die $DBI::errstr;
                    $sth->execute();
                    $sth->finish();
                }
                # Check for new players in the players.xml file and input them into the database
                $players = $playerparser->XMLin("$fulldir/players.xml");
                foreach $team (@{$players->{game}->[0]->{team}}) {
                    foreach $player (@{$team->{player}}) {
                        $id = $player->{id};
                        $first = $dbh->quote($player->{first});
                        $last = $dbh->quote($player->{last});
                        $throws = $dbh->quote($player->{rl});
                        $no_duplicate_query = 'SELECT eliasid FROM players WHERE eliasid = ' . $id;
                        $sth= $dbh->prepare($no_duplicate_query) or die $DBI::errstr;
                        $sth->execute();
                        my $numRows = $sth->rows;
                        $sth->finish();
                        if ($numRows) {
                            # don't insert duplicate player entry into players table
                        } else {
                            $player_query = 'INSERT INTO players (eliasid, first, last, throws) '
                            . 'VALUES (' . $id . ', '. $first . ', ' . $last . ', ' . $throws . ')';
                            $sth= $dbh->prepare($player_query) or die $DBI::errstr;
                            $sth->execute();
                            $sth->finish();
                        }
                    }
                }
                # Check if game info has been input before inputting umpire, at bat, and pitch info
                $game_id_query = 'SELECT game_id FROM games WHERE (date = ' . $gamedate
                . ' AND home = ' . $home . ' AND away = ' . $away . ' AND game = ' . $game_number . ')';
                $sth= $dbh->prepare($game_id_query) or die $DBI::errstr;
                $sth->execute();
                my $numRows = $sth->rows;
                if (1==$numRows) {
                    $select_game_id = $sth->fetchrow_array();
                    print "\nParsing game number $select_game_id ($gamedir).\n";
                } else {
                    die "duplicate game entry $select_game_id in database or game not found.\n";
                }
                $sth->finish();

                # Find the home plate umpire and input him into the database
                foreach $umpire (@{$players->{game}->[0]->{umpires}->[0]->{umpire}}) {
                    $umpire_name = $umpire->{name};
                    ($umpire_first, $umpire_last) = split(/\s/, $umpire_name);
                    $umpire_first = $dbh->quote($umpire_first);
                    $umpire_last = $dbh->quote($umpire_last);
                    $position = $umpire->{position};
                    if ('home' eq $position) {
                        $no_duplicate_query = 'SELECT ump_id FROM umpires WHERE first = ' . $umpire_first
                        . ' AND last = ' . $umpire_last;
                        $sth= $dbh->prepare($no_duplicate_query) or die $DBI::errstr;
                        $sth->execute();
                    my $numRows = $sth->rows;
                    if ($numRows) {
                        # don't insert duplicate umpire entry into umpires table
                        # get umpire id
                        $select_ump_id = $sth->fetchrow_array();
                        $sth->finish();
                    } else {
                        $sth->finish();
                        $umpire_query = 'INSERT INTO umpires (first, last) '
                        . 'VALUES (' . $umpire_first . ', ' . $umpire_last . ')';
                        $sth= $dbh->prepare($umpire_query) or die $DBI::errstr;
                        $sth->execute();
                        $sth->finish();
                        # get umpire id
                        $umpire_id_query = 'SELECT ump_id FROM umpires WHERE first = ' . $umpire_first
                        . ' AND last = ' . $umpire_last;
                        $sth= $dbh->prepare($umpire_id_query) or die $DBI::errstr;
                        $sth->execute();
                        my $numRows = $sth->rows;
                        if (1==$numRows) {
                            $select_ump_id = $sth->fetchrow_array();
                            $sth->finish();
                        } else {
                            die "numrows=$numRows, duplicate umpire entry $umpire_first $umpire_last in database or umpire not found.\n";
                        }
                    }
                    } else {
                    # ignore base umpires
                    }
                }
                # update game record with umpire id
                $umpire_update_query = 'UPDATE games SET umpire = ' . $select_ump_id. ' WHERE game_id = ' . "'" . $select_game_id . "'";
                $sth= $dbh->prepare($umpire_update_query) or die $DBI::errstr;
                $sth->execute();

                # Parse the at bats and pitches from each inning_?.xml file
                opendir IDIR, "$fulldir/inning";
                my @inningfiles = readdir IDIR;
                closedir IDIR;
                my @innings = ();
                foreach $inningfn (@inningfiles) {
                    if ($inningfn =~ /inning_(\d+)\.xml/) {
                        $inning_num = $1;
                        # Pre-process the inning_?.xml file
                        $inning = $inningparser->XMLin(
                            "$fulldir/inning/$inningfn");
                        @innings[$inning_num] = $inning;

                    # Parse the at-bat and pitch data for the top and bottom halves of each inning
                    foreach $atbat (@{$inning->{inning}->[0]->{top}->[0]->{atbat}}) {
                        $half = 1;
                        parse_at_bats_and_pitches($atbat, $dbh, $select_game_id, $inning_num, $half);
                        parse_runner($atbat, $dbh, $select_game_id, $inning_num, $half);
                        parse_po($atbat, $dbh, $select_game_id, $inning_num, $half);
                    }
            		foreach $action (@{$inning->{inning}->[0]->{top}->[0]->{action}}) {
            		    $half = 1;
            		    parse_action($action, $dbh, $select_game_id, $inning_num, $half);
            		}
                    foreach $atbat (@{$inning->{inning}->[0]->{bottom}->[0]->{atbat}}) {
                        $half = 2;
                        parse_at_bats_and_pitches($atbat, $dbh, $select_game_id, $inning_num, $half);
                        parse_runner($atbat, $dbh, $select_game_id, $inning_num, $half);
                        parse_po($atbat, $dbh, $select_game_id, $inning_num, $half);
                    }
                    foreach $action (@{$inning->{inning}->[0]->{bottom}->[0]->{action}}) {
                        $half = 2;
                        parse_action($action, $dbh, $select_game_id, $inning_num, $half);
                    }
                    }
                }

                $hits = $hitsparser->XMLin("$fulldir/inning/inning_hit.xml");
                # When a ball in play and an error are recorded on the same play,
                # the error may be the first play listed in inning_hit.xml or the second play.
                # Currently the first play is recorded in the database, and
                # the second play is not recorded in the database but is saved to a text file
                # for later manual review.  Some cases of batting around in one inning may
                # also be saved to the text file.
                # This section of code could be improved by automating the manual review process.
                open (HITRECORD, ">> hit_record.txt") || die "sorry, system can't open hitrecord";
                foreach $hip (@{$hits->{hitchart}->[0]->{hip}}) {
                    $hit_des = $hip->{des};
                    $hit_x = $hip->{x};
                    $hit_y = $hip->{y};
                    $hit_type = $dbh->quote($hip->{type});
                    $hit_batter = $hip->{batter};
                    $hit_pitcher = $hip->{pitcher};
                    $hit_inning = $hip->{inning};
                    # find the at bat that matches the ball in play
                    $find_ab_id_query = 'SELECT ab_id, hit_x, event FROM atbats WHERE (game_id = ' . "'" . $select_game_id . "'"
                    . ' AND inning = ' . $hit_inning . ' AND batter = ' . $hit_batter . ' AND pitcher = '
                    . $hit_pitcher . ')';
                    $sth= $dbh->prepare($find_ab_id_query) or die $DBI::errstr;
                    $sth->execute();
                    my $numRows = $sth->rows;
                    # for one matching at bat, check if hit data already entered in database
                    if (1==$numRows) {
                        ($select_ab_id, $select_hit_x, $select_event) = $sth->fetchrow_array();
                        # update atbats table with hit info for each matching at_bat
                        if (0<$select_hit_x) {
                            # already entered into database
                            print HITRECORD "game $select_game_id:1.1 This hit $hit_batter - $hit_pitcher - $hit_inning already recorded in database.\n";
                        } else {
                            update_hit_info($hit_x, $hit_y, $hit_type, $select_ab_id);
                        }
                    }
                    elsif (2==$numRows) {
                        # if the batter has batted twice in the inning against the same pitcher
                        ($select_ab_id, $select_hit_x, $select_event) = $sth->fetchrow_array();
                        # if the first ball in play is already recorded, don't update it
                        if ($hit_x==$select_hit_x && $select_event eq $hit_des) {
                            print HITRECORD "game $select_game_id:2.1 This hit $hit_batter - $hit_pitcher - $hit_inning already recorded in database.\n";
                        } elsif (0<$select_hit_x) {
                            # select the info for the second ball in play from the database
                            ($select_ab_id, $select_hit_x, $select_event) = $sth->fetchrow_array();
                            # if the second ball in play is already recorded, don't update it
                            if ($hit_x==$select_hit_x && $select_event eq $hit_des) {
                                print HITRECORD "game $select_game_id:2.2 This hit $hit_batter - $hit_pitcher - $hit_inning already recorded in database.\n";
                            } else {
                                # if the second ball in play hasn't been recorded, update the db
                                update_hit_info($hit_x, $hit_y, $hit_type, $select_ab_id);
                            }
                        } else {
                            # if the first ball in play hasn't been recorded, update the db
                            update_hit_info($hit_x, $hit_y, $hit_type, $select_ab_id);
                        }
                    } else {
                        die "numrows=$numRows, no matching at bat found for hit $hit_batter - $hit_pitcher - $hit_inning.\n";
                    }
                }
                close HITRECORD;
            }
        }
    }
    }
    }
}
# This is a debug section if you want to look at contents of the XML file
# in an easier-to-read format
#           use Data::Dumper;
#           open (OUTFILE, "> debug_parser_innings.txt") || die "sorry, system can't open outfile";
#           print OUTFILE Dumper($hits);
#           print OUTFILE Dumper($players);
#           print OUTFILE Dumper($names);
#           print OUTFILE Dumper($box);
#           print OUTFILE Dumper(@innings);
#           close OUTFILE;

sub update_hit_info($hit_x, $hit_y, $hit_type, $select_ab_id) {
    # update at bat record with hit info
    $hit_query = 'UPDATE atbats SET hit_x = ' . $hit_x . ', hit_y = ' . $hit_y
    . ', hit_type = ' . $hit_type . ' WHERE ab_id = ' . "'" . $select_ab_id . "'";
    $sth= $dbh->prepare($hit_query) or die $DBI::errstr;
    $sth->execute();
    $sth->finish();
}

sub parse_po($atbat, $dbh, $select_game_id, $inning_num, $half) {
    foreach $po (@{$atbat->{po}}) {
        $des = $dbh->quote($po->{des});
        $event_num = $po->{event_num};
        if (not $event_num) {
            $event_num = $atbat->{num};
        }
        $run_id = "'" . $select_game_id . '-' . $event_num . "'";
        $po_query = 'INSERT INTO runners (run_id, game_id, inning, half, event_num, event) '
        . 'VALUES (' . $run_id . ',' . "'" . $select_game_id . "'" . ', ' . $inning_num . ', '
        . $half . ', ' . $event_num . ', ' . $des . ')';
        $sth = $dbh->prepare($po_query) or die $DBI::errstr;
        $sth->execute();
        $sth->finish();
    }
}

sub parse_runner($atbat, $dbh, $select_game_id, $inning_num, $half) {
    foreach $runner (@{$atbat->{runner}}) {
        $runner_id = $runner->{id};
        $start = $dbh->quote($runner->{start});
        $end = $dbh->quote($runner->{end});
        $event = $dbh->quote($runner->{event});
        $event_num = $runner->{event_num};
        if (not $event_num) {
            $event_num = $atbat->{num};
        }
        $run_id = "'" . $select_game_id . '-' . $runner_id . '-' . $event_num . "'";
        $rn_query = 'INSERT INTO runners (run_id, game_id, inning, half, event_num, runner_id, start_b, end_b, event) '
        . 'VALUES (' . $run_id . ',' .  "'" . $select_game_id . "'" . ', ' . $inning_num . ', ' . $half
        . ', ' . $event_num . ', ' . $runner_id . ', ' . $start . ', ' . $end . ', ' . $event . ')';
        $sth = $dbh->prepare($rn_query) or die $DBI::errstr;
        $sth->execute();
        $sth->finish();
    }
}

sub parse_action($action, $dbh, $select_game_id, $inning_num, $half) {
    $event_num = $action->{event_num};
    $des = $dbh->quote($action->{des});
    $ball = $action->{b};
    $strike = $action->{s};
    $out = $action->{o};
    $pitch_num = $action->{pitch};
    $event = $dbh->quote($action->{event});
    if (not $event_num) {
        $event_num = $pitch_num;
    }
    $ac_id = "'" . $select_game_id . '-' . $event_num . "'";
    $ac_query = 'INSERT INTO actions (ac_id, game_id, inning, half, event_num, des, ball, strike, outs, pitch_num, event) '
    . 'VALUES (' . $ac_id . ',' .  "'" . $select_game_id . "'" . ', ' . $inning_num . ', ' . $half
    . ', ' . $event_num . ', ' . $des . ', ' . $ball . ', ' . $strike . ', ' . $out . ', ' . $pitch_num . ', '
    . $event . ')';
    $sth = $dbh->prepare($ac_query) or die $DBI::errstr;
    $sth->execute();
    $sth->finish();
}

sub parse_at_bats_and_pitches($atbat, $dbh, $select_game_id, $inning_num, $half) {
    $event = $dbh->quote($atbat->{event});
    $num = $atbat->{num};
    $ball = $atbat->{b};
    $strike = $atbat->{s};
    $out = $atbat->{o};
    $pitcher_id = $atbat->{pitcher};
    $batter_id = $atbat->{batter};
    $stand = $dbh->quote($atbat->{stand});
    $des = $dbh->quote($atbat->{des});
    $ab_id = "'" . $select_game_id . '-' . $num . "'";
    $ab_query = 'INSERT INTO atbats (ab_id, game_id, inning, num, ball, strike, outs,'
    . ' batter, pitcher, stand, des, event, half) '
    . 'VALUES (' . $ab_id . ',' . "'" . $select_game_id . "'" . ', ' . $inning_num . ', ' . $num
    . ', ' . $ball . ', ' . $strike . ', ' . $out . ', ' . $batter_id . ', ' . $pitcher_id . ', ' . $stand . ', ' . $des . ', '
    . $event . ', ' . $half . ')';
    $sth= $dbh->prepare($ab_query) or die $DBI::errstr;
    $sth->execute();
    $sth->finish();
    print " ab#$num";
    $ball_count = 0;
    $strike_count = 0;
    foreach $pitch (@{$atbat->{pitch}}) {
        # these fields are common to pitch-f/x and non-pfx data
        $pitch_des = $dbh->quote($pitch->{des});
        $id = $pitch->{id};
        $pitch_id = "'" . $select_game_id . '-' . $id . "'";
        $result_type = $dbh->quote($pitch->{type});
        $pitch_x = $pitch->{x};
        $pitch_y = $pitch->{y};
        $start_speed = $pitch->{start_speed};
        $on_1b = $dbh->quote($pitch->{on_1b});
        $on_2b = $dbh->quote($pitch->{on_2b});
        $on_3b = $dbh->quote($pitch->{on_3b});
        $event_num = $pitch->{event_num};
        if (not $event_num) {
    	   $event_num = $id;
        }
        # determine if the data for this pitch includes pitch-f/x fields
        $pitchfx = 0;
        if (0 < $start_speed) {
            $pitchfx = 1;
            $end_speed = $pitch->{end_speed};
            $sz_top = $pitch->{sz_top};
            $sz_bot = $pitch->{sz_bot};
            $pfx_x = $pitch->{pfx_x};
            $pfx_z = $pitch->{pfx_z};
            $px = $pitch->{px};
            $pz = $pitch->{pz};
            $x0 = $pitch->{x0};
            $y0 = $pitch->{y0};
            $z0 = $pitch->{z0};
            $vx0 = $pitch->{vx0};
            $vy0 = $pitch->{vy0};
            $vz0 = $pitch->{vz0};
            $ax = $pitch->{ax};
            $ay = $pitch->{ay};
            $az = $pitch->{az};
            $break_y = $pitch->{break_y};
            $break_angle = $pitch->{break_angle};
            $break_length = $pitch->{break_length};
            $sv_id = $dbh->quote($pitch->{sv_id});
            $pitch_type = $dbh->quote($pitch->{pitch_type});
            $type_confidence = $pitch->{type_confidence};
            $nasty = $pitch->{nasty};
            $cc = $dbh->quote($pitch->{cc});
        	# New fields
        	$spin_dir = $pitch->{spin_dir};
        	$spin_rate = $pitch->{spin_rate};
        	$zone = $pitch->{zone};
        }
        # insert a new record in the database for this pitch
        if ($pitchfx) {
            $pitch_query = 'INSERT INTO pitches (pitch_id, ab_id, des, type, id, x, y, start_speed,'
            . ' end_speed, sz_top, sz_bot, pfx_x, pfx_z, px, pz, x0, y0, z0, vx0, vy0,'
            . ' vz0, ax, ay, az, break_y, break_angle, break_length, sv_id, pitch_type,'
            . ' type_confidence, on_1b, on_2b, on_3b, nasty, cc, ball_count, strike_count, spin_dir, spin_rate, zone, event_num) '
            . 'VALUES (' . join(', ', ($pitch_id, $ab_id, $pitch_des, $result_type, $id,
            $pitch_x, $pitch_y, $start_speed, $end_speed, $sz_top, $sz_bot, $pfx_x, $pfx_z,
            $px, $pz, $x0, $y0, $z0, $vx0, $vy0, $vz0, $ax, $ay, $az, $break_y, $break_angle,
            $break_length, $sv_id, $pitch_type, $type_confidence, $on_1b, $on_2b, $on_3b, $nasty, $cc, $ball_count, $strike_count,
    	    $spin_dir, $spin_rate, $zone, $event_num)) . ')';
        } else {
            $pitch_query = 'INSERT INTO pitches (pitch_id, ab_id, des, type, id, x, y, on_1b, on_2b, on_3b, event_num)'
            . ' VALUES (' . join(', ', ($pitch_id, $ab_id, $pitch_des, $result_type, $id,
            $pitch_x, $pitch_y, $on_1b, $on_2b, $on_3b, $event_num)) . ')';
        }
        $sth= $dbh->prepare($pitch_query) or die $DBI::errstr;
        $sth->execute();
        if ("'B'" eq $result_type) {
    	    $ball_count++;
        }
        if ("'S'" eq $result_type) {
            if (2 == $strike_count && ("'Foul'" eq $pitch_des || "'Foul (Runner Going)'" eq $pitch_des)) {
            # don't increment
            }
            else {
                $strike_count++
            }
        }
    }
}