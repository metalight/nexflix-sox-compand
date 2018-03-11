#!/bin/bash
# 1. pause kodi, if playing
# 2. wait until kodi is playing again
# 3. kill sox

curlopt='-s -H Content-Type: application/json --data-binary'
jsonopt='"id": '$RANDOM', "jsonrpc": "2.0"'
url='http://localhost:8080/jsonrpc'

getid()
{
	curl $curlopt '{'"$jsonopt"', "method": "Player.GetActivePlayers"}' \
		$url \
		| awk -F'[:,]' '{print $7}'
}


playing()
{
	plid="$(getid)"
	if [ -n "$plid" ]; then
		curl $curlopt '{'"$jsonopt"',
			"method": "Player.GetProperties",
			"params": { "playerid": '$plid',
				"properties": ["speed"] }
		}' $url \
		| grep speed | grep -vq speed..0 && return 0
	fi
	return 1
}

pause()
{
	curl $curlopt '{'"$jsonopt"',
		"method": "Player.PlayPause", "params": {
			"playerid": '$plid' }
	}' $url
}

if playing; then
	pause
fi

until playing; do
	sleep 1
done

killall sox
