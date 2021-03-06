package SReview::Web::Controller::Review;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::Collection 'c';

use feature "switch";

use SReview::Talk;
use SReview::Access qw/admin_for/;

sub view {
	my $c = shift;

	my $id = $c->stash("id");
	my $talk;
        eval {
                if(defined($id)) {
                        $talk = SReview::Talk->new(talkid => $id);
                } else {
                        $talk = SReview::Talk->by_nonce($c->stash('nonce'));
                }
        };
        if($@) {
                $c->stash(error => $@);
                $c->render(variant => 'error');
                return;
        }
        my $nonce = $talk->nonce;
	my $variant;
	if(admin_for($c, $talk) || $talk->state eq 'preview') {
		$variant = undef;
	} elsif($talk->state < 'preview') {
		$variant = 'preparing';
	} elsif($talk->state < 'done') {
		$variant = 'transcode';
	} else {
		$variant = 'done';
	}
		
	$c->stash(talk => $talk);
	$c->stash(stylesheets => ['/review.css']);
	$c->render(variant => $variant);
}

sub update {
        my $c = shift;
	my $id = $c->stash("id");
	my $talk;

        $c->stash(stylesheets => ['/review.css']);
	if(defined($id)) {
		$talk = SReview::Talk->new(talkid => $id);
	} else {
                eval {
		        $talk = SReview::Talk->by_nonce($c->stash('nonce'));
                };
                if($@) {
                        $c->stash(error => $@);
                        $c->render(variant => 'error');
                        return;
                }
	}
        $c->stash(talk => $talk);
        if(!admin_for($c, $talk) && $talk->state ne 'preview') {
                $c->stash(error => 'This talk is not currently available for review. Please try again later!');
                $c->render(variant => 'error');
                return;
        }
        $talk->add_correction(serial => 0);
        if($c->param('serial') ne $talk->corrections->{serial}) {
                $c->stash(error => 'This talk was updated (probably by someone else) since you last loaded it. Please reload the page, and try again.');
                $c->render(variant => 'error');
                return;
        }

        if($c->param("complete_reset") == 1) {
                $talk->reset_corrections();
                $c->render(variant => 'reset');
        }
        if($c->param("video_state") eq "ok") {
                $talk->state_done("preview");
                $c->render(variant => 'done');
                return;
        }
        if($c->param("audio_channel") ne "3") {
                $talk->add_correction("audio_channel", $c->param("audio_channel"));
        } else {
                if($c->param("no_audio_options") eq "no_publish") {
                        $talk->set_state("broken");
                        $c->render(variant => 'broken');
                        return;
                }
        }
        my $corrections = {};
        if($c->param("start_time") ne "start_time_ok") {
                $talk->add_correction("offset_start", $c->param("start_time_corrval"));
                $corrections->{start} = $c->param("start_time_corrval");
        }
        if($c->param("end_time") ne "end_time_ok") {
                $talk->add_correction("offset_end", $c->param("end_time_corrval"));
                $corrections->{end} = $c->param("end_time_corrval");
        }
        if($c->param("av_sync") eq "av_not_ok_audio") {
                $talk->add_correction("offset_audio", $c->param("av_seconds"));
                $corrections->{audio_offset} = $c->param("av_seconds");
        } elsif($c->param("av_sync" eq "av_not_ok_video")) {
                $talk->add_correction("offset_audio", "-" . $c->param("av_seconds"));
                $corrections->{audio_offset} = "-" . $c->param("av_seconds");
        }
        if(length($c->param("comment_text")) > 0) {
                $talk->add_correction("comment", $c->param("comment_text"));
                $talk->set_state("broken");
                $c->stash(other_msg => $c->param("comment_text"));
                $c->render(variant => "other");
        }
        $talk->done_correcting;
        $talk->set_state("waiting_for_files");
        $talk->state_done("waiting_for_files");
        $c->stash(corrections => $corrections);
        $c->render(variant => 'newreview');
}

sub data {
        my $c = shift;
        my $talk = SReview::Talk->by_nonce($c->stash('nonce'));

        my $data = $talk->corrected_times;

        $c->render(json => $data);
}

1;
