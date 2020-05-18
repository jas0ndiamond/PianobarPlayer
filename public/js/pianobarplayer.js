'use strict';

var noop = function(){console.log("Executing noop");}; // function doing nothing

var idleStopTimer = null;
var stationUpdateTimer = null;
var currentSongTimer = null;

//debug timer: 30 seconds
//var idleTimerLength = 30 * 1000;

//normal timer: 45 mins
var idleTimerLength = 45 * 30 * 1000;

function startup() {
	//check if the player is started and/or playing

	function makeRequest()
	{
		var $derp = $.ajax
		({
					type:"get",
					url:"/player/song_info",
					dataType : 'json',
					async: true,
					timeout: 8000
		}).error (function(result)
		{
			console.log("Error retrieving current song: " + JSON.stringify(result) );
		}).success (function(songJSON)
		{
			try {

				//TODO: need to call JSON.stringify? =? probably because a JSON object is returned

				var currentSong = JSON.stringify(songJSON);

				console.log("Startup received song: " + currentSong);

				if(songJSON.song.player_stopped == false) {
					showPlayerUI();

					$("#currentSong").empty().text( currentSong );

					getCurrentSong();

					updateStationList();

					updatePlayer();
				}
				else {
					hidePlayerUI();
				}

				//currentSong = null;

				//updatePlayer();

			} catch (err) {
					console.log("Error reading current song: " + err)
			}

		});

		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}

	makeRequest();

}

function showPlayerUI()
{

		$("#playButton").show();
		$("#pauseButton").show();
		$("#likeButton").show();
		$("#banButton").show();
		$("#nextButton").show();

		$("#volupButton").show();
		$("#voldownButton").show();
		$("#volresetButton").show();

		$("#stationlistMenu").show();

		$("debugrow").show();
}

function hidePlayerUI()
{

		$("#playButton").hide();
		$("#pauseButton").hide();
		$("#likeButton").hide();
		$("#banButton").hide();
		$("#nextButton").hide();

		$("#volupButton").hide();
		$("#voldownButton").hide();
		$("#volresetButton").hide();

		$("#stationlistMenu").hide();

		$("debugrow").hide();
}

function getCurrentSong(force)
{
	var forceUpdate = (force != null && force );

	if(forceUpdate) {
		console.log("Retrieving current song forcibly");
	}
	else {
		console.log("Retrieving current song");
	}

	function makeRequest()
	{
		var $derp = $.ajax
		({
					type:"get",
					url:"/player/song_info",
					dataType : 'json',
					async: true,
					timeout: 8000
		}).error (function(result)
		{
			console.log("Error retrieving current song: " + JSON.stringify(result) );
		}).success (function(songJSON)
		{
			var currentSong = null;

			try {

				//TODO: need to call JSON.stringify? =? probably because a JSON object is returned
				currentSong = JSON.stringify(songJSON);
			} catch (err) {
					console.log("Error reading current song: " + err)
			}

			if(currentSong != null ) {

				var isStopped = songJSON["song"]["player_stopped"];
				//play or pause depending on is_playing

				if(!isStopped || forceUpdate ) {
					if( currentSong != $("#currentSong").text() )
					{
						//new song

						//execute new song trigger


						//sessionStorage.setItem( "currentSong",  currentSong);
						$("#currentSong").empty().text( currentSong );

						console.log("New current song: " + currentSong );

						currentSong = null;

						if(!forceUpdate) {
							//song info will lag behind since this is async
							updatePlayer();
						}
					}
					else {
						console.log( "No song update." );
					}

					//schedule the next check
					currentSongTimer = setTimeout(getCurrentSong, 2500);
				}
				else {
					console.log("Skipping next song update. Player is stopped.");
				}
			}
			else {
				console.log("Could not read response from song_info");

				//possible the player is not stopped

				//schedule the next check
				currentSongTimer = setTimeout(getCurrentSong, 2500);
			}

		});

		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}

	makeRequest();
}

function updatePlayer()
{
	console.log("Updating player");

	var songResult = null;

	try
	{
		songResult = $.parseJSON( $("#currentSong").text() );
		//var songResult = $.parseJSON( sessionStorage.getItem( "currentSong" ) );
	}catch(err) {
		console.log("Error parsing current song: " + err)
	}

	if(songResult != null ) {
		var title = songResult.song.title;

		//update the current station div
		$("#currentStation").empty().text(songResult.song.stationName);
		//sessionStorage.setItem( "currentStation",  songResult.song.stationName);


		//show if song liked or not depending on rating 0 for nothing, 1 for like
		if(songResult.song.rating == "1")
		{
			//filled in heart because we love it
			title += " &hearts;";
			$("#likeButton").prop( "disabled", true );
		}
		else
		{
			//blank heart because we may love it once we listen to it
			title += " &#9825;"
			$("#likeButton").prop( "disabled", false );
		}

		//if we're hearing the song, it hasn't been banned yet
		$("#banButton").prop( "disabled", false );

		//update playing vs paused status. the player can be reloaded mid-song
		if(songResult.song.player_stopped == false) {
			if(songResult.song.is_playing == true)
			{
				$("#playButton").hide();
				$("#pauseButton").show();
			}
			else
			{
				$("#playButton").show();
				$("#pauseButton").hide();
			}
		}

		//write the current song html. this should overwrite any placeholder text
		$("#songinfo").empty().append(
			"<b>Now Playing:</b><br><br><b>" + title + "</b><br>" +
			songResult.song.artist + "<br>" +
			"<i>" + songResult.song.album + "</i> on " + songResult.song.stationName + "<br><br>ヽ(͡◕ ͜ʖ ͡◕)ﾉ<br>"
		);

		//status info
		$("#debuginfo").empty().append(
			"<b>pRet</b>: (" + songResult.song.pRet + "): " + songResult.song.pRetStr +
			"<br><b>wRet</b>: (" + songResult.song.wRet + "): " + songResult.song.wRetStr
		);

		//update upcoming list if available
		//var upNextHtml =  "Up Next: <br><br><b>" + title + "</b><br>" +
		//result.song.artist + "<br>" +
		//"<i>" + result.song.album + "</i> on " + result.song.stationName

	}
	else {
		console.log("Skipping player update. Current song was null");
	}

	console.log("Updating player finished");
}

function resetIdleTimer()
{
	//TODO: implement this on the backend

	console.log("Resetting idle timer");
	if(idleStopTimer) {
		clearTimeout(idleStopTimer);
	}

	if( !isStopped() ) {
		//idleStopTimer = setTimeout(idleStop,  60 * 60 * 1000);

		//debug
		idleStopTimer = setTimeout(idleStop,  idleTimerLength);
	}
	else {
		console.log("Skipping idle timer reset. Player is stopped.");
	}
}

function updateStationList(force)
{
	var forceUpdate = (force != null && force );

	if(forceUpdate) {
		console.log("Retrieving station list forcibly");
	}
	else {
		console.log("Retrieving station list");
	}

	function makeRequest()
	{
		var $derp = $.ajax
		({
	        type:"get",
	        url:"/player/getstations",
	        dataType : 'json',
	        async: true,
					timeout: 8000
		}).error (function(result)
	  {
			console.log("Error retrieving station list: " + JSON.stringify(result) );
		}).success (function(stationJSON)
		{
			var stationJSONString = null;

			try {
				stationJSONString = JSON.stringify(stationJSON);
			} catch (err) {
				console.log("Error parsing station list: " + err)
			}

			if(stationJSONString != null) {



				//var isStopped = songJSON["song"]["player_stopped"];
				//TODO: need a safe way of retrieving if the currentsong is playing
				var isStopped = false;


				if(!isStopped || forceUpdate ) {

					if( stationJSONString != $("#stationList").text() )
					{

						console.log("Updating station list: " + stationJSONString );

						$("#stationSelect").empty();

						//TODO: need to rebuild select?
						//rebuild the select
						// $("#stationSelect").select({
						// 	change: function(event, ui) {
						//     	changeStation(this.value)
						// 	}
						// });

						//trust the div holding the current station
						//for each item in the station list
						$.each(stationJSON, function(key, value)
						{
							//0 => 311 Radio

							//station entry
							$("#stationSelect").append("<option value=\"" + key + "\" >" + value + '</option>' );

							//mark the current station as selected
							if(value == $("#currentStation").text() )
							{
								$("#stationSelect").val(key);
							}
						});

						$("#stationList").empty().text( stationJSONString );
					}
					else {
						console.log("No station list update" );
					}

					//schedule next update
					stationUpdateTimer = setTimeout(updateStationList, 12000);
				}
				else {
					console.log("Skipping next station list update. Player is stopped.");
				}

				//$("#stationSelect").selectmenu("refresh");
				//$("stationSelect").select({ style: 'dropdown' });
			}
			else {
				console.log("Skipping player update. Station JSON string was null");

				stationUpdateTimer = setTimeout(updateStationList, 12000);
			}

			//schedule next update
			// if( !isStopped() || forceUpdate ) {
			// 	stationUpdateTimer = setTimeout(updateStationList, 12000);
			// }
			// else {
			// 	console.log("Skipping next station update. Player is stopped.");
			// }
		});
		// Clean XHR object up
		if( $derp != null ){
			$derp.onreadystatechange = $derp.abort = noop;
			$derp = null;
		}
	}
	makeRequest();
}
