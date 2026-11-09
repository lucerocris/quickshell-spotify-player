# quickshell-spotify-player

A full-screen Spotify player for Hyprland, built with Quickshell. It shows the album on a spinning record, a vertical audio visualizer, timed lyrics and your queue. The background colour follows the genre of the song.

Search, playback and the queue use your Spotify account. The official Spotify app plays the audio, hidden on a special workspace. It starts when you first open the player and quits after 10 idle minutes.

## Requirements

- Spotify Premium
- Hyprland using its Lua config syntax (`hl.dsp...`)
- `quickshell`, `cava`, `python3`, `spotify-launcher`, and Qt 6 SVG support

## Install

1. Clone this repo into your Quickshell config folder:

   ```sh
   git clone https://github.com/noni-was-taken/quickshell-spotify-player ~/.config/quickshell/music
   ```

2. Create an app at <https://developer.spotify.com/dashboard>. Add `http://127.0.0.1:8989/login` as the Redirect URI and tick **Web API**.

3. Save the app's Client ID (the Client Secret is not needed):

   ```sh
   mkdir -p ~/.config/music-app
   echo YOUR_CLIENT_ID > ~/.config/music-app/client_id
   ```

4. Log in, then open the link it prints:

   ```sh
   ~/.config/quickshell/music/spot login
   ```

5. Log in to the Spotify app once by running `spotify-launcher`.

6. Add these to your Hyprland config:

   ```lua
   hl.exec_cmd("qs -c music -d")   -- in your autostart
   hl.bind("ALT + S", hl.dsp.exec_cmd("qs -c music ipc call music toggle"), { desc = "music player" })
   ```

## Keys

| Key | Action |
| --- | --- |
| Enter | Search |
| Up / Down, then Enter | Pick and play a result |
| Space | Pause or play |
| Left / Right | Previous or next song |
| Escape | Close search, then close the player |

Closing the player keeps the music playing.

## Customize

Edit the top of `shell.qml`:

- `fontName`: the design uses Euclid Circular A, a commercial font that is not included. Without it, Qt uses a default font.
- `genres`: the colours for each genre.
- `lyricOffset`: shifts the lyrics if they run early or late.
- `quitAfterMinutes`: how long the hidden Spotify app stays open when idle.

## Data sources

- Lyrics: [LRCLIB](https://lrclib.net)
- Genres: [MusicBrainz](https://musicbrainz.org) artist tags, cached in `~/.cache/music-app`

Not affiliated with Spotify.
