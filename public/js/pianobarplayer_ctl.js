'use strict';

var noop = function(){console.log("Executing noop");}; // function doing nothing

function play()
{
	resetIdleTimer();

	function makeRequest()
	{
		var $derp = $.ajax
		({
					type:"get",
					url:"/player/play",
					dataType : 'json',
					async: true
		}).error (function(result)
		{
			console.log("Error on play: " + JSON.stringify(result) );
		}).success (function() {

			$("#playButton").hide();
			$("#pauseButton").show();

			updatePlayer();
		});
		// Clean XHR object up
		if( $derp != null ){
				$derp.onreadystatechange = $derp.abort = noop;
				$derp = null;
		}
	}
	makeRequest();
}

function pause()
{
	$("#pauseButton").hide();

	resetIdleTimer();

	function makeRequest()
	{
		var $derp = $.ajax
		({
					type:"get",
					url:"/player/pause",
					dataType : 'json',
					async: true
		}).error (function(result)
		{
			console.log("Error on pause: " + JSON.stringify(result) );
			$("#pauseButton").show();
		}).success (function() {

			$("#playButton").show();

			//probably don't need to update Player- not likely to change on pause
		});

		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}

	makeRequest();
}

function next()
{
	$("#nextButton").prop( "disabled", true );

	resetIdleTimer();

	$("#songinfo").empty().append("<b>Seeking...└[ ◔ _ ◔ ]┘</b>");

	function makeRequest()
	{
		var $derp = $.ajax
		({
					type:"get",
					url:"/player/next",
					dataType : 'json',
					async: true
		}).error (function(result)
		{
			//sometimes we get this: {"readyState":4,"responseText":"","status":200,"statusText":"OK"}
			console.log("Error seeking next song: " + JSON.stringify(result) );
			$("#nextButton").prop( "disabled", false );
		}).success (function() {

			$("#nextButton").prop( "disabled", false );
			updatePlayer();
		});

		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}

	makeRequest();
}

function upcoming()
{
	//TODO: implement this info since it's available
	//player/upcoming
}

function ban()
{
	resetIdleTimer();

	function makeRequest()
	{
		$("#banButton").prop( "disabled", true );
		$("#banButton").text("Banning...");

		var $derp = $.ajax
		({
					type:"get",
					url:"/player/ban",
					dataType : 'json',
					async: true
		}).error (function(result)
		{
			console.log("Error banning song: " + JSON.stringify(result) );

			$("#banButton").text(":(");
			//$("#banButton").prop( "disabled", false );
		}).success (function() {

			$("#banButton").text(":(");
			//$("#banButton").prop( "disabled", false );

			updatePlayer();
		});

		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}

	makeRequest();
}

function like()
{
	resetIdleTimer();

	//ruby/bash will update the now playing file

	function makeRequest()
	{
		$("#likeButton").prop( "disabled", true );
		$("#likeButton").text("Liking...");

		var $derp = $.ajax
		({
					type:"get",
					url:"/player/like",
					dataType : 'json',
					async: true
		}).error (function(result)
		{
			//TODO: Error liking song: {"readyState":4,"responseText":"","status":200,"statusText":"OK"}

			console.log("Error liking song: " + JSON.stringify(result) );

			$("#likeButton").text(":)");
			//$("#likeButton").prop( "disabled", true );

		}).success (function() {

			$("#likeButton").text(":)");
			//$("#likeButton").prop( "disabled", false );

			//update player to show song is liked
			updatePlayer();
		});

		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}

	makeRequest();
}

function isStopped()
{
	if( $("#currentSong").text() ) {
		var currentSong = $.parseJSON( $("#currentSong").text() );

		if(currentSong.song.player_stopped == false) {
			return false;
		}
	}

	return true;
}

function start()
{
	//check if we're already started first

	if( !isStopped() ) {
			console.log("Ignoring Start request for currently running player");
			return;
	}

	console.log("Starting player...");

	showPlayerUI();

	//TODO: hide start button


	$("#songinfo").empty().append("<b>Player is starting...  ( ◔ ◡ ◔ )</b>");

	//forcible updates since player could be started for the first time, or previously stopped
	getCurrentSong(true);

	updateStationList(true);

	function makeRequest()
	{
		var $derp = $.ajax
		({
					type:"get",
					url:"/player/start",
					dataType : 'json',
					async: true
		}).error (function(result)
		{
			console.log("Error starting pianobarplayer: " + JSON.stringify(result) );
		}).success (function() {
			updatePlayer();
		});

		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}

	makeRequest();

	//TODO: restart timers?
}

function idleStop() {
	console.log("Idle timer has expired. Stopping player.");
	stop();
}

function stop()
{

	if( isStopped() ) {
			console.log("Ignoring Stop request for currently stopped player");
			return;
	}

	console.log("Stopping player...");

	hidePlayerUI();

	//stop the song and station checks
	clearTimeout(currentSongTimer);
	clearTimeout(stationUpdateTimer);
	clearTimeout(idleStopTimer);

	function makeRequest()
	{
		var $derp = $.ajax
		({
					type:"get",
					url:"/player/stop",
					dataType : 'json',
					async: true
		}).error (function(result)
		{
			console.log("Error stopping pianobarplayer: " + JSON.stringify(result) );
		}).success (function() {

			updatePlayer();
		});

		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}

	makeRequest();

	$("#currentSong").empty();
	$("#stationList").empty();
	$("#currentStation").empty();
	$("#stationlistMenu").empty();
	$("#songinfo").empty().append("<b>Player is stopped ( ■ _ ■ )</b>");
}

function quit()
{
	//stop the song and station checks
	clearTimeout(currentSongTimer);
	clearTimeout(stationUpdateTimer);
	clearTimeout(idleStopTimer);

	//clear song and stations
	$("#currentSong").empty();
	$("#stationList").empty();
	$("#currentStation").empty();
	$("#stationlistMenu").empty();

	$("#songinfo").empty().append('<b>Player has quit. Thanks for listening. ┌(° ͜ʖ͡°)┘</b><br>Refresh the page to reload the player<br><a href="javascript:window.location.reload();">Refresh</a>');
	$("#playerControl").empty();

	function makeRequest()
	{
		var $derp = $.ajax
		({
					type:"get",
					url:"/player/quit",
					dataType : 'json',
					async: true
		}).error (function(result)
		{
			console.log("Error quitting: " + JSON.stringify(result) );
		}).success (function() {

			//$("#player").empty().html(makeRequest("/player/quit"));

		});

		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}

	makeRequest();
}

function volup()
{
	resetIdleTimer();

	console.log("Volume increased");

	function makeRequest()
	{
		var $derp = $.ajax
		({
					type:"get",
					url:"/player/volup",
					dataType : 'json',
					async: true
		}).error (function(result)
		{
			console.log("Error increasing volume: " + JSON.stringify(result) );
		});

		//do not need to update the player for volume. currently there's no volume readout

		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}

	makeRequest();
}

function volreset()
{
	resetIdleTimer();

	console.log("Volume reset");

	function makeRequest()
	{
		var $derp = $.ajax
		({
					type:"get",
					url:"/player/volreset",
					dataType : 'json',
					async: true
		}).error (function(result)
		{
			console.log("Error resetting volume: " + JSON.stringify(result) );
		});

		//do not need to update the player for volume. currently there's no volume readout

		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}

	makeRequest();
}

function voldown()
{
	resetIdleTimer();

	console.log("Volume decreased");

	function makeRequest()
	{
		var $derp = $.ajax
		({
					type:"get",
					url:"/player/voldown",
					dataType : 'json',
					async: true
		}).error (function(result)
		{
			console.log("Error decreasing volume: " + JSON.stringify(result) );
		});

		//do not need to update the player for volume. currently there's no volume readout


		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}

	makeRequest();
}

function changeStation(stationNumber)
{
	resetIdleTimer();

	$("#songinfo").empty().append("<b>Seeking...⎝ º ᗜ º ⎠</b>");

	function makeRequest(station)
	{
		var $derp = $.ajax
		({
					type:"get",
					url:"/player/playstation?station=" + station,
					dataType : 'json',
					async: true
		}).error (function(result)
		{
			console.log("Error updating station: " + JSON.stringify(result) );
		}).success (function() {

			//get the current station from the next song
			updatePlayer();

			//this will update the selected entry
			updateStationList();
		});

		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}

	//TODO: don't change station if the selected value is the current value

	makeRequest(stationNumber);
}
