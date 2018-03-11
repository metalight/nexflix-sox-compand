#!/bin/bash
# start sox with compand effect when netflix (or other) is playing on the Chromecast or Wii, to route sound through sox.
# beware this script is old, have many potential race conditions, and bad style

touch /root/triggered

# wait up to 30 secs for kodi web interface
TRIES=30
while ((--TRIES)) && ! curl --silent --data-binary '{"jsonrpc": "2.0", "method": "Settings.GetSettingValue", "params": { "setting": "audiooutput.audiodevice"}, "id": 1}' -H 'content-type: application/json;' http://localhost:8080/jsonrpc; do
	sleep 1
done

sleep 3
# give sound to kodi (may not be the first time script is run..)
curl --silent --data-binary '{"jsonrpc": "2.0", "method": "Settings.SetSettingValue", "params": { "setting": "audiooutput.audiodevice", "value": "ALSA:rawjack" }, "id": "libSetSettingValue"}' -H 'content-type: application/json;' http://localhost:8080/jsonrpc

DBUS="DBUS_SESSION_BUS_ADDRESS=unix:path=/dev/shm/user_bus_socket"

silent()
{
	nice arecord -D hw:CODEC -d 1 -f S16_LE -c 2 -r 2000 - 2>/dev/null \
	| sox -D -t wav - -n stat 2>&1 \
	| grep -q 'Maximum amplitude:.*0\.0[0123]';
}

while true; do
	# if input card with the label "CODEC" is N/A, wait
	until aplay -l | grep -q CODEC; do
		sleep 3
	done

	# XioSynth: uses S24_3LE
	# Behringer low-latency USB audio: uses S16_LE
	# wait until there is sound coming in on AUX (here: CODEC)
	# - We're abusing arecord + rate
	#   to limit cpu usage further than recording for 1 whole sec
	while silent || silent; do
		sleep 1
	done

	# park kodi sound on alsa loopback (pi hdmi is a different driver and seems to not always switch live)
	curl --silent --data-binary '{"jsonrpc": "2.0", "method": "Settings.SetSettingValue", "params": { "setting": "audiooutput.audiodevice", "value": "ALSA:@:CARD=Loopback,DEV=0" }, "id": "libSetSettingValue"}' -H 'content-type: application/json;' http://localhost:8080/jsonrpc

	# wait a tiny bit for jackd to register the release, to not upset kodi
	TRIES=5
	while ((--TRIES)) && su - kodi -c "env $DBUS jack_lsp" | grep -q alsa-jack.rawjack; do
		sleep .1
	done
	su - kodi -c "env $DBUS jack_control stop"

	# wait for released hw
	TRIES=30
	while ((--TRIES)) && grep -q 'subdevices_avail: 0' /proc/asound/TP32/pcm0p/info; do
		sleep .1
	done

	# start monitoring kodi in the background, to know when to kill sox
	screen -dmS kodikillsox /root/kodikillsox.sh

	# use sox equalizer to turn down a few low frequencies that resonates with our living room, and use compand to better hear silent parts
	# sox is the lowest latency simple cli solution i could find for this purpose. ladspa, jack plugins or pd not tried
	grep -q 'subdevices_avail: 0' /proc/asound/TP32/pcm0p/info && echo "### Device not available!" || \
		AUDIODEV=hw:TP32 chrt --rr 99 sox -q --buffer 256 -b 16 -r 48000 -c 2 -e s -t alsa hw:CODEC -d compand .001,0.1 40:-70,-60,-30 0 -90 .001 equalizer 37 15 -15

	# when sox is terminated
	sleep 1
	su - kodi -c "env $DBUS jack_control start"

	# give sound back to kodi
	curl --silent --data-binary '{"jsonrpc": "2.0", "method": "Settings.SetSettingValue", "params": { "setting": "audiooutput.audiodevice", "value": "ALSA:rawjack" }, "id": "libSetSettingValue"}' -H 'content-type: application/json;' http://localhost:8080/jsonrpc

	sleep 1
done

