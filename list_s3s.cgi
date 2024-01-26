#!/usr/local/bin/perl
# Show a list of S3-compatible accounts

require './virtual-server-lib.pl';
&ReadParse();
&can_cloud_providers() || &error($text{'s3s_ecannot'});

&ui_print_header(undef, $text{'s3s_title'}, "", "s3s");

print "<p>",$text{'s3s_desc'},"</p>\n";

my @s3s = &list_s3_accounts();
my @scheds = &list_scheduled_backups();
my @links = ( &ui_link("edit_s3.cgi?new=1", $text{'s3s_add'}) );
if (@s3s) {
	print &ui_links_row(\@links);
	print &ui_columns_start([ $text{'s3s_access'},
				  $text{'s3s_endpoint'},
				  $text{'s3s_usedby'} ]);
	foreach my $s3 (@s3s) {
		my @users;
		foreach my $sched (@scheds) {
			foreach my $dest (&get_scheduled_backup_dests($sched)) {
				my ($mode, $akey) = &parse_backup_url($dest);
				if ($mode == 3 &&
				    ($akey eq $s3->{'access'} ||
				     !$akey && $s3->{'default'})) {
					push(@users, $sched);
					last;
					}
				}
			}
		print &ui_columns_row([
			&ui_link("edit_s3.cgi?id=$s3->{'id'}", $s3->{'access'}),
			&html_escape($s->{'endpoint'} ||
				     $text{'s3s_endpoint_def'}),
			@users ? &text('s3s_users', scalar(@users))
			       : $text{'s3s_nousers'},
			]);
		}
	print &ui_columns_end();
	}
else {
	print "<b>$text{'s3s_none'}</b><p>\n";
	}
print &ui_links_row(\@links);

&ui_print_footer("", $text{'index_return'});
