# PianobarPlayer
An application to add web endpoints and a UI over an instance of the pianobar command line Pandora client [https://github.com/PromyLOPh/pianobar].

#Setup
1. Clone the pianobar project, install its dependencies, and build it.
2. Install rvm, ruby, and gems thin, sinatra, liquid, logger.
3. Write out your config.json file in the conf directory with your pandora login, default station, pianobar binary location.
4. Run PianobarPlayer with thin -p PORT -R path-to-config.ru start.
5. Point your browser to http://host:PORT/player, and enjoy the music.
6. File bugs and fork this project.

#Default Pandora Station
Pandora stations are long strings of digits. While your target station might be the 4th entry in your station list, you need to specify a station by its public identifier.
