#!/bin/bash

#example startup script to launch player in fullscreen mode

#optionally kickoff player here

#launch firefox browser and enter fullscreen
/usr/bin/firefox https://localhost:7777/player &
sleep 2

#hit F11 key to enter fullscreen
#xdotool search --sync --onlyvisible --class "Firefox" windowactivate key F11

