#!/bin/bash
# file: bashbot.sh 
# do not edit, this file will be overwritten on update

# bashbot, the Telegram bot written in bash.
# Written by Drew (@topkecleon) and Daniil Gentili (@danogentili), KayM (@gnadelwartz).
# Also contributed: JuanPotato, BigNerd95, TiagoDanin, iicc1.
# https://github.com/topkecleon/telegram-bot-bash

# Depends on JSON.sh (http://github.com/dominictarr/JSON.sh) (MIT/Apache),
# This file is public domain in the USA and all free countries.
# Elsewhere, consider it to be WTFPLv2. (wtfpl.net/txt/copying)
#
#### $$VERSION$$ v0.91-0-g31808a9
#
# Exit Codes:
# - 0 sucess (hopefully)
# - 1 can't change to dir
# - 2 can't write to tmp, count or token 
# - 3 user / command / file not found
# - 4 unkown command
# - 5 cannot connect to telegram bot
# shellcheck disable=SC2140

# are we runnig in a terminal?
if [ -t 1 ] && [ "$TERM" != "" ];  then
    CLEAR='clear'
    RED='\e[31m'
    GREEN='\e[32m'
    ORANGE='\e[35m'
    NC='\e[0m'
fi

# get location and name of bashbot.sh
SCRIPT="$0"
REALME="${BASH_SOURCE[0]}"
SCRIPTDIR="$(dirname "${REALME}")"
RUNDIR="$(dirname "$0")"

MODULEDIR="${SCRIPTDIR}/modules"


if [ "${SCRIPT}" != "${REALME}" ] || [ "$1" = "source" ]; then
	SOURCE="yes"
else
	SCRIPT="./$(basename "${SCRIPT}")"
	MODULEDIR="./$(basename "${MODULEDIR}")"
fi

if [ "$BASHBOT_HOME" != "" ]; then
	SCRIPTDIR="$BASHBOT_HOME"
	[ "${BASHBOT_ETC}" = "" ] && BASHBOT_ETC="$BASHBOT_HOME"
	[ "${BASHBOT_VAR}" = "" ] && BASHBOT_VAR="$BASHBOT_HOME"
fi

ADDONDIR="${BASHBOT_ETC:-./addons}"

RUNUSER="${USER}" # USER is overwritten by bashbot array

if [ "${SOURCE}" != "yes" ] && [ "$BASHBOT_HOME" = "" ] && ! cd "${RUNDIR}" ; then
	echo -e "${RED}ERROR: Can't change to ${RUNDIR} ...${NC}"
	exit 1
else
	RUNDIR="."
fi

if [ ! -w "." ]; then
	echo -e "${ORANGE}WARNING: ${RUNDIR} is not writeable!${NC}"
	ls -ld .
fi


TOKENFILE="${BASHBOT_ETC:-.}/token"
if [ ! -f "${TOKENFILE}" ]; then
   if [ "${CLEAR}" = "" ] && [ "$1" != "init" ]; then
	echo "Running headless, run ${SCRIPT} init first!"
	exit 2 
   else
	${CLEAR}
	echo -e "${RED}TOKEN MISSING.${NC}"
	echo -e "${ORANGE}PLEASE WRITE YOUR TOKEN HERE OR PRESS CTRL+C TO ABORT${NC}"
	read -r token
	printf '%s\n' "${token}" > "${TOKENFILE}"
   fi
fi

BOTADMIN="${BASHBOT_ETC:-.}/botadmin"
if [ ! -f "${BOTADMIN}" ]; then
   if [ "${CLEAR}" = "" ]; then
	echo "Running headless, set botadmin to AUTO MODE!"
	printf '%s\n' '?' > "${BOTADMIN}"
   else
	${CLEAR}
	echo -e "${RED}BOTADMIN MISSING.${NC}"
	echo -e "${ORANGE}PLEASE WRITE YOUR TELEGRAM ID HERE OR ENTER '?'${NC}"
	echo -e "${ORANGE}TO MAKE FIRST USER TYPING '/start' TO BOTADMIN${NC}"
	read -r admin
	[ "${admin}" = "" ] && admin='?'
	printf '%s\n' "${admin}" > "${BOTADMIN}"
   fi
fi

BOTACL="${BASHBOT_ETC:-.}/botacl"
if [ ! -f "${BOTACL}" ]; then
	echo -e "${ORANGE}Create empty ${BOTACL} file.${NC}"
	printf '\n' >"${BOTACL}"
fi

DATADIR="${BASHBOT_VAR:-.}/data-bot-bash"
if [ ! -d "${DATADIR}" ]; then
	mkdir "${DATADIR}"
elif [ ! -w "${DATADIR}" ]; then
	echo -e "${RED}ERROR: Can't write to ${DATADIR}!.${NC}"
	ls -ld "${DATADIR}"
	exit 2
fi

COUNTFILE="${BASHBOT_VAR:-.}/count"
if [ ! -f "${COUNTFILE}" ]; then
	printf '\n' >"${COUNTFILE}"
elif [ ! -w "${COUNTFILE}" ]; then
	echo -e "${RED}ERROR: Can't write to ${COUNTFILE}!.${NC}"
	ls -l "${COUNTFILE}"
	exit 2
fi

BOTTOKEN="$(< "${TOKENFILE}")"
URL="${BASHBOT_URL:-https://api.telegram.org/bot}${BOTTOKEN}"

ME_URL=$URL'/getMe'

UPD_URL=$URL'/getUpdates?offset='
GETFILE_URL=$URL'/getFile'

declare -rx SCRIPT SCRIPTDIR MODULEDIR RUNDIR ADDONDIR TOKENFILE BOTADMIN BOTACL DATADIR COUNTFILE
declare -rx BOTTOKEN URL ME_URL UPD_URL GETFILE_URL

declare -ax CMD
declare -Ax UPD BOTSENT USER MESSAGE URLS CONTACT LOCATION CHAT FORWARD REPLYTO VENUE iQUERY
export res CAPTION


COMMANDS="${BASHBOT_ETC:-.}/commands.sh"
if [ "${SOURCE}" != "yes" ]; then
	if [ ! -f "${COMMANDS}" ] || [ ! -r "${COMMANDS}" ]; then
		echo -e "${RED}ERROR: ${COMMANDS} does not exist or is not readable!.${NC}"
		ls -l "${COMMANDS}"
		exit 3
	fi
	# shellcheck source=./commands.sh
	source "${COMMANDS}" "source"
fi

###############
# load modules
for modules in ${MODULEDIR:-.}/*.sh ; do
	# shellcheck source=./modules/aliases.sh
	[ -r "${modules}" ] && source "${modules}" "source"
done

#################
# BASHBOT INTERNAL functions
# $1 URL, $2 filename in DATADIR
# outputs final filename
download() {
	local empty="no.file" file="${2:-${empty}}"
	if [[ "$file" = *"/"* ]] || [[ "$file" = "."* ]]; then file="${empty}"; fi
	while [ -f "${DATADIR:-.}/${file}" ] ; do file="$RAMDOM-${file}"; done
	getJson "$1" >"${DATADIR:-.}/${file}" || return
	printf '%s\n' "${DATADIR:-.}/${file}"
}

# $1 postfix, e.g. chatid
# $2 prefix, back- or startbot-
procname(){
	printf '%s\n' "$2${ME}_$1"
}

# $1 sting to search for proramm incl. parameters
# retruns a list of PIDs of all current bot proceeses matching $1
proclist() {
	# shellcheck disable=SC2009
	ps -fu "${UID}" | grep -F "$1" | grep -v ' grep'| grep -F "${ME}" | sed 's/\s\+/\t/g' | cut -f 2
}

# $1 sting to search for proramm to kill
killallproc() {
	local procid; procid="$(proclist "$1")"
	if [ "${procid}" != "" ] ; then
		# shellcheck disable=SC2046
		kill $(proclist "$1")
		sleep 1
		procid="$(proclist "$1")"
		# shellcheck disable=SC2046
		[ "${procid}" != "" ] && kill $(proclist -9 "$1")
	fi
}


# returns true if command exist
_exists()
{
	[ "$(LC_ALL=C type -t "$1")" = "file" ]
}

# execute function if exists
_exec_if_function() {
	[ "$(LC_ALL=C type -t "${1}")" != "function" ] || "$@"
}
# returns true if function exist
_is_function()
{
	[ "$(LC_ALL=C type -t "$1")" = "function" ]
}

declare -xr DELETE_URL=$URL'/deleteMessage'
delete_message() {
	sendJson "${1}" '"message_id": '"${2}"'' "${DELETE_URL}"
}

get_file() {
	[ "$1" = "" ] && return
	sendJson ""  '"file_id": "'"${1}"'"' "${GETFILE_URL}"
	printf '%s\n' "${URL}"/"$(JsonGetString <<< "${res}" '"result","file_path"')"
}

# curl is preffered, but may not availible on ebedded systems
TIMEOUT="${BASHBOT_TIMEOUT}"
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || TIMEOUT="20"

if [ "${BASHBOT_WGET}" = "" ] && _exists curl ; then
  # simple curl or wget call, output to stdout
  getJson(){
	# shellcheck disable=SC2086
	curl -sL ${BASHBOT_CURL_ARGS} -m "${TIMEOUT}" "$1"
  }
  # usage: sendJson "chat" "JSON" "URL"
  sendJson(){
	local chat="";
	[ "${1}" != "" ] && chat='"chat_id":'"${1}"','
	# shellcheck disable=SC2086
	res="$(curl -s ${BASHBOT_CURL_ARGS} -m "${TIMEOUT}" -d '{'"${chat} $2"'}' -X POST "${3}" \
		-H "Content-Type: application/json" | "${JSONSHFILE}" -s -b -n )"
	BOTSENT[OK]="$(JsonGetLine '"ok"' <<< "$res")"
	BOTSENT[ID]="$(JsonGetValue '"result","message_id"' <<< "$res")"
  }
  #$1 Chat, $2 what , $3 file, $4 URL, $5 caption
  sendUpload() {
	[ "$#" -lt 4  ] && return
	if [ "$5" != "" ]; then
	# shellcheck disable=SC2086
		res="$(curl -s ${BASHBOT_CURL_ARGS} "$4" -F "chat_id=$1" -F "$2=@$3;${3##*/}" -F "caption=$5" | "${JSONSHFILE}" -s -b -n )"
	else
	# shellcheck disable=SC2086
		res="$(curl -s ${BASHBOT_CURL_ARGS} "$4" -F "chat_id=$1" -F "$2=@$3;${3##*/}" | "${JSONSHFILE}" -s -b -n )"
	fi
	BOTSENT[OK]="$(JsonGetLine '"ok"' <<< "$res")"
  }
else
  # simple curl or wget call outputs result to stdout
  getJson(){
	# shellcheck disable=SC2086
	wget -t 2 -T "${TIMEOUT}" ${BASHBOT_WGET_ARGS} -qO - "$1"
  }
  # usage: sendJson "chat" "JSON" "URL"
  sendJson(){
	local chat="";
	[ "${1}" != "" ] && chat='"chat_id":'"${1}"','
	# shellcheck disable=SC2086
	res="$(wget -t 2 -T "${TIMEOUT}" ${BASHBOT_WGET_ARGS} -qO - --post-data='{'"${chat} $2"'}' \
		--header='Content-Type:application/json' "${3}" | "${JSONSHFILE}" -s -b -n )"
	BOTSENT[OK]="$(JsonGetLine '"ok"' <<< "$res")"
	BOTSENT[ID]="$(JsonGetValue '"result","message_id"' <<< "$res")"
  }
  sendUpload() {
	sendJson "$1" '"text":"Sorry, wget does not support file upload"' "${MSG_URL}"
	BOTSENT[OK]="false"
  }
fi 

# convert common telegram entities to JSON
# title caption description markup inlinekeyboard
title2Json(){
	local title caption desc markup keyboard
	[ "$1" != "" ] && title=',"title":"'$1'"'
	[ "$2" != "" ] && caption=',"caption":"'$2'"'
	[ "$3" != "" ] && desc=',"description":"'$3'"'
	[ "$4" != "" ] && markup=',"parse_mode":"'$4'"'
	[ "$5" != "" ] && keyboard=',"reply_markup":"'$5'"'
	echo "${title}${caption}${desc}${markup}${keyboard}"
}

# get bot name
getBotName() {
	getJson "$ME_URL"  | "${JSONSHFILE}" -s -b -n | JsonGetString '"result","username"'
}

# pure bash implementaion, done by KayM (@gnadelwartz)
# see https://stackoverflow.com/a/55666449/9381171
JsonDecode() {
        local out="$1" remain="" U=""
	local regexp='(.*)\\u[dD]([0-9a-fA-F]{3})\\u[dD]([0-9a-fA-F]{3})(.*)'
        while [[ "${out}" =~ $regexp ]] ; do
		U=$(( ( (0xd${BASH_REMATCH[2]} & 0x3ff) <<10 ) | ( 0xd${BASH_REMATCH[3]} & 0x3ff ) + 0x10000 ))
                remain="$(printf '\\U%8.8x' "${U}")${BASH_REMATCH[4]}${remain}"
                out="${BASH_REMATCH[1]}"
        done
        echo -e "${out}${remain}"
}

JsonGetString() {
	sed -n -e '0,/\['"$1"'\]/ s/\['"$1"'\][ \t]"\(.*\)"$/\1/p'
}
JsonGetLine() {
	sed -n -e '0,/\['"$1"'\]/ s/\['"$1"'\][ \t]//p'
}
JsonGetValue() {
	sed -n -e '0,/\['"$1"'\]/ s/\['"$1"'\][ \t]\([0-9.,]*\).*/\1/p'
}
# read JSON.sh style data and asssign to an ARRAY
# $1 ARRAY name, must be declared with "declare -A ARRAY" before calling
Json2Array() {
	# shellcheck source=./commands.sh
	[ "$1" = "" ] || source <( printf "$1"'=( %s )' "$(sed -E -e 's/\t/=/g' -e 's/=(true|false)/="\1"/')" )
}
# output ARRAY as JSON.sh style data
# $1 ARRAY name, must be declared with "declare -A ARRAY" before calling
Array2Json() {
	local key
	declare -n ARRAY="$1"
	for key in "${!ARRAY[@]}"
       	do
		printf '["%s"]\t"%s"\n' "${key//,/\",\"}" "${ARRAY[${key}]//\"/\\\"}"
       	done
}

################
# processing of updates starts here
process_updates() {
	local max num debug="$1"
	max="$(sed <<< "${UPDATE}" '/\["result",[0-9]*\]/!d' | tail -1 | sed 's/\["result",//g;s/\].*//g')"
	Json2Array 'UPD' <<<"${UPDATE}"
	for ((num=0; num<=max; num++)); do
		process_client "$num" "${debug}"
	done
}
process_client() {
	local num="$1" debug="$2" 
	CMD=( ); iQUERY=( )
	iQUERY[ID]="${UPD["result",${num},"inline_query","id"]}"
	[[ "${debug}" = *"debug"* ]] && cat <<< "$UPDATE" >>"MESSAGE.log"
	if [ "${iQUERY[ID]}" = "" ]; then
		process_message "${num}" "${debug}"
	else
		process_inline "${num}" "${debug}"
	fi
	#####
	# process inline and message events
	# first classic commnad dispatcher
	# shellcheck source=./commands.sh
	source "${COMMANDS}" "${debug}" &

	# then all registered addons
	if [ "${iQUERY[ID]}" = "" ]; then
		event_message "${debug}"
	else
		event_inline "${debug}"
	fi

	# last count users
	tmpcount="COUNT${CHAT[ID]}"
	grep -q "$tmpcount" <"${COUNTFILE}" &>/dev/null || cat <<< "$tmpcount" >>"${COUNTFILE}"
}

declare -Ax BASBOT_EVENT_INLINE BASBOT_EVENT_MESSAGE BASHBOT_EVENT_CMD BASBOT_EVENT_REPLY BASBOT_EVENT_FORWARD 
declare -Ax BASBOT_EVENT_CONTACT BASBOT_EVENT_LOCATION BASBOT_EVENT_FILE BASHBOT_EVENT_TEXT BASHBOT_EVENT_TIMER

start_timer(){
	# send alarm every ~60 s
	while :; do
		sleep 59.5
    		kill -ALRM $$
	done;
}

EVENT_TIMER="0"
event_timer() {
	local event timer debug="$1"
	(( EVENT_TIMER++ ))
	# shellcheck disable=SC2153
	for event in "${!BASHBOT_EVENT_TIMER[@]}"
	do
		timer="${event##*,}"
		[[ ! "$timer" =~ ^-*[1-9][0-9]*$ ]] && continue
		if [ "$(( EVENT_TIMER % timer ))" = "0" ]; then
			_exec_if_function "${BASHBOT_EVENT_TIMER[${event}]}" "timer" "${debug}"
			[ "$(( EVENT_TIMER % timer ))" -lt "0" ] && \
				unset BASHBOT_EVENT_TIMER["${event}"]
		fi
	done
}

event_inline() {
	local event debug="$1"
	# shellcheck disable=SC2153
	for event in "${!BASHBOT_EVENT_INLINE[@]}"
	do
		_exec_if_function "${BASHBOT_EVENT_INLINE[${event}]}" "inline" "${debug}"
	done
}
event_message() {
echo "${MESSAGE[0]}"
	local event debug="$1"
	# ${MESSAEG[*]} event_message
	# shellcheck disable=SC2153
	for event in "${!BASHBOT_EVENT_MESSAGE[@]}"
	do
		 _exec_if_function "${BASHBOT_EVENT_MESSAGE[${event}]}" "messsage" "${debug}"
	done
	
	# ${TEXT[*]} event_text
	if [ "${MESSAGE[0]}" != "" ]; then
		# shellcheck disable=SC2153
		for event in "${!BASHBOT_EVENT_TEXT[@]}"
		do
			_exec_if_function "${BASHBOT_EVENT_TEXT[${event}]}" "text" "${debug}"
		done

		# ${CMD[*]} event_cmd
		if [ "${CMD[0]}" != "" ]; then
			# shellcheck disable=SC2153
			for event in "${!BASHBOT_EVENT_CMD[@]}"
			do
				_exec_if_function "${BASHBOT_EVENT_CMD[${event}]}" "command" "${debug}"
			done
		fi
	fi
	# ${REPLYTO[*]} event_replyto
	if [ "${REPLYTO[UID]}" != "" ]; then
		# shellcheck disable=SC2153
		for event in "${!BASHBOT_EVENT_REPLYTO[@]}"
		do
			_exec_if_function "${BASHBOT_EVENT_REPLYTO[${event}]}" "replyto" "${debug}"
		done
	fi

	# ${FORWARD[*]} event_forward
	if [ "${FORWARD[UID]}" != "" ]; then
		# shellcheck disable=SC2153
		for event in "${!BASHBOT_EVENT_FORWARD[@]}"
		do
			 _exec_if_function && "${BASHBOT_EVENT_FORWARD[${event}]}" "forward" "${debug}"
		done
	fi

	# ${CONTACT[*]} event_contact
	if [ "${CONTACT[FIRST_NAME]}" != "" ]; then
		# shellcheck disable=SC2153
		for event in "${!BASHBOT_EVENT_CONTACT[@]}"
		do
			_exec_if_function "${BASHBOT_EVENT_CONTACT[${event}]}" "contact" "${debug}"
		done
	fi

	# ${VENUE[*]} event_location
	# ${LOCALTION[*]} event_location
	if [ "${LOCATION[LONGITUDE]}" != "" ] || [ "${VENUE[TITLE]}" != "" ]; then
		# shellcheck disable=SC2153
		for event in "${!BASHBOT_EVENT_LOCATION[@]}"
		do
			_exec_if_function "${BASHBOT_EVENT_LOCATION[${event}]}" "location" "${debug}"
		done
	fi

	# ${URLS[*]} event_file
	# NOTE: compare again #URLS -1 blanks!
	if [[ "${URLS[*]}" != "     " ]]; then
		# shellcheck disable=SC2153
		for event in "${!BASHBOT_EVENT_FILE[@]}"
		do
			_exec_if_function "${BASHBOT_EVENT_FILE[${event}]}" "file" "${debug}"
		done
	fi

}
process_inline() {
	local num="${1}"
	iQUERY[0]="$(JsonDecode "${UPD["result",${num},"inline_query","query"]}")"
	iQUERY[USER_ID]="${UPD["result",${num},"inline_query","from","id"]}"
	iQUERY[FIRST_NAME]="$(JsonDecode "${UPD["result",${num},"inline_query","from","first_name"]}")"
	iQUERY[LAST_NAME]="$(JsonDecode "${UPD["result",${num},"inline_query","from","last_name"]}")"
	iQUERY[USERNAME]="$(JsonDecode "${UPD["result",${num},"inline_query","from","username"]}")"
}
process_message() {
	local num="$1"
	# Message
	MESSAGE[0]="$(JsonDecode "${UPD["result",${num},"message","text"]}" | sed 's#\\/#/#g')"
	MESSAGE[ID]="${UPD["result",${num},"message","message_id"]}"

	# Chat
	CHAT[ID]="${UPD["result",${num},"message","chat","id"]}"
	CHAT[LAST_NAME]="$(JsonDecode "${UPD["result",${num},"message","chat","last_name"]}")"
	CHAT[FIRST_NAME]="$(JsonDecode "${UPD["result",${num},"message","chat","first_name"]}")"
	CHAT[USERNAME]="$(JsonDecode "${UPD["result",${num},"message","chat","username"]}")"
	CHAT[TITLE]="$(JsonDecode "${UPD["result",${num},"message","chat","title"]}")"
	CHAT[TYPE]="$(JsonDecode "${UPD["result",${num},"message","chat","type"]}")"
	CHAT[ALL_ADMIN]="${UPD["result",${num},"message","chat","all_members_are_administrators"]}"
	CHAT[ALL_MEMBERS_ARE_ADMINISTRATORS]="${CHAT[ALL_ADMIN]}" # backward compatibility

	# User
	USER[ID]="${UPD["result",${num},"message","from","id"]}"
	USER[FIRST_NAME]="$(JsonDecode "${UPD["result",${num},"message","from","first_name"]}")"
	USER[LAST_NAME]="$(JsonDecode "${UPD["result",${num},"message","from","last_name"]}")"
	USER[USERNAME]="$(JsonDecode "${UPD["result",${num},"message","from","username"]}")"

	# in reply to message from
	REPLYTO=( )
	REPLYTO[UID]="${UPD["result",${num},"message","reply_to_message","from","id"]}"
	if [ "${REPLYTO[UID]}" != "" ]; then
	   REPLYTO[0]="$(JsonDecode "${UPD["result",${num},"message","reply_to_message","text"]}")"
	   REPLYTO[ID]="${UPD["result",${num},"message","reply_to_message","message_id"]}"
	   REPLYTO[FIRST_NAME]="$(JsonDecode "${UPD["result",${num},"message","reply_to_message","from","first_name"]}")"
	   REPLYTO[LAST_NAME]="$(JsonDecode "${UPD["result",${num},"message","reply_to_message","from","last_name"]}")"
	   REPLYTO[USERNAME]="$(JsonDecode "${UPD["result",${num},"message","reply_to_message","from","username"]}")"
	fi

	# forwarded message from
	FORWARD=( )
	FORWARD[UID]="${UPD["result",${num},"message","forward_from","id"]}"
	if [ "${FORWARD[UID]}" != "" ]; then
	   FORWARD[ID]="${MESSAGE[ID]}" # same as message ID
	   FORWARD[FIRST_NAME]="$(JsonDecode "${UPD["result",${num},"message","forward_from","first_name"]}")"
	   FORWARD[LAST_NAME]="$(JsonDecode "${UPD["result",${num},"message","forward_from","last_name"]}")"
	   FORWARD[USERNAME]="$(JsonDecode "${UPD["result",${num},"message","forward_from","username"]}")"
	fi

	# Audio
	URLS[AUDIO]="$(get_file "${UPD["result",${num},"message","audio","file_id"]}")"
	# Document
	URLS[DOCUMENT]="$(get_file "${UPD["result",${num},"message","document","file_id"]}")"
	# Photo
	URLS[PHOTO]="$(get_file "${UPD["result",${num},"message","photo",0,"file_id"]}")"
	# Sticker
	URLS[STICKER]="$(get_file "${UPD["result",${num},"message","sticker","file_id"]}")"
	# Video
	URLS[VIDEO]="$(get_file "${UPD["result",${num},"message","video","file_id"]}")"
	# Voice
	URLS[VOICE]="$(get_file "${UPD["result",${num},"message","voice","file_id"]}")"

	# Contact
	CONTACT=( )
	CONTACT[FIRST_NAME]="$(JsonDecode "${UPD["result",${num},"message","contact","first_name"]}")"
	if [ "${CONTACT[FIRST_NAME]}" != "" ]; then
		CONTACT[USER_ID]="$(JsonDecode  "${UPD["result",${num},"message","contact","user_id"]}")"
		CONTACT[LAST_NAME]="$(JsonDecode "${UPD["result",${num},"message","contact","last_name"]}")"
		CONTACT[NUMBER]="${UPD["result",${num},"message","contact","phone_number"]}"
		CONTACT[VCARD]="$(JsonGetString '"result",'"${num}"',"message","contact","vcard"' <<<"${UPDATE}")"
	fi

	# vunue
	VENUE=( )
	VENUE[TITLE]="$(JsonDecode "${UPD["result",${num},"message","venue","title"]}")"
	if [ "${VENUE[TITLE]}" != "" ]; then
		VENUE[ADDRESS]="$(JsonDecode "${UPD["result",${num},"message","venue","address"]}")"
		VENUE[LONGITUDE]="${UPD["result",${num},"message","venue","location","longitude"]}"
		VENUE[LATITUDE]="${UPD["result",${num},"message","venue","location","latitude"]}"
		VENUE[FOURSQUARE]="${UPD["result",${num},"message","venue","foursquare_id"]}"
	fi

	# Caption
	CAPTION="$(JsonDecode "${UPD["result",${num},"message","caption"]}")"

	# Location
	LOCATION[LONGITUDE]="${UPD["result",${num},"message","location","longitude"]}"
	LOCATION[LATITUDE]="${UPD["result",${num},"message","location","latitude"]}"

	# split message in command and args
	CMD=( )
	if [[ "${MESSAGE[0]}" = "/"* ]]; then
		set -f; unset IFS
		# shellcheck disable=SC2206
		CMD=( ${MESSAGE[0]} )
		CMD[0]="${CMD[0]%%@*}"
		set +f
	fi 
}

#########################
# main get updates loop, should never terminate
start_bot() {
	local DEBUG="$1"
	local OFFSET=0
	local mysleep="100" # ms
	local addsleep="100"
	local maxsleep="$(( ${BASHBOT_SLEEP:-5000} + 100 ))"
	[[ "${DEBUG}" = *"debug" ]] && exec &>>"DEBUG.log"
	[ "${DEBUG}" != "" ] && date && echo "Start BASHBOT in Mode \"${DEBUG}\""
	[[ "${DEBUG}" = "xdebug"* ]] && set -x 
	#cleaup old pipes and empty logfiles
	find "${DATADIR}" -type p -delete
	find "${DATADIR}" -size 0 -name "*.log" -delete
	# load addons on startup
	for addons in ${ADDONDIR:-.}/*.sh ; do
		# shellcheck source=./modules/aliases.sh
		[ -r "${addons}" ] && source "${addons}" "startbot" "${DEBUG}"
	done
	# start timer events
	if _is_function start_timer ; then
		# shellcheck disable=SC2064
		trap "event_timer $DEBUG" ALRM
		start_timer &
		# shellcheck disable=SC2064
		trap "kill -9 $!; exit" EXIT INT HUP TERM QUIT 
	fi
	while true; do
		UPDATE="$(getJson "$UPD_URL$OFFSET" | "${JSONSHFILE}" -s -b -n)"

		# Offset
		OFFSET="$(grep <<< "${UPDATE}" '\["result",[0-9]*,"update_id"\]' | tail -1 | cut -f 2)"
		((OFFSET++))

		if [ "$OFFSET" != "1" ]; then
			mysleep="100"
			process_updates "${DEBUG}"
		fi
		# adaptive sleep in ms rounded to next lower second
		[ "${mysleep}" -gt "999" ] && sleep "${mysleep%???}"
		# bash aritmetic
		((mysleep+= addsleep , mysleep= mysleep>maxsleep ?maxsleep:mysleep))
	done
}

# initialize bot environment, user and permissions
bot_init() {
	local DEBUG="$1"
	# upgrade from old version
	local OLDTMP="${BASHBOT_VAR:-.}/tmp-bot-bash"
	[ -d "${OLDTMP}" ] && { mv -n "${OLDTMP}/"* "${DATADIR}"; rmdir "${OLDTMP}"; }
	[ -f "modules/inline.sh" ] && rm -f "modules/inline.sh"
	# load addons on startup
	for addons in ${ADDONDIR:-.}/*.sh ; do
		# shellcheck source=./modules/aliases.sh
		[ -r "${addons}" ] && source "${addons}" "init" "${DEBUG}"
	done
	#setup bashbot
	[[ "${UID}" -eq "0" ]] && RUNUSER="nobody"
	echo -n "Enter User to run basbot [$RUNUSER]: "
	read -r TOUSER
	[ "$TOUSER" = "" ] && TOUSER="$RUNUSER"
	if ! id "$TOUSER" &>/dev/null; then
		echo -e "${RED}User \"$TOUSER\" not found!${NC}"
		exit 3
	else
		# shellcheck disable=SC2009
		oldbot="$(ps -fu "$TOUSER" | grep startbot | grep -v -e 'grep' -e '\-startbot' )"
		[ "${oldbot}" != "" ] && \
			echo -e "${ORANGE}Warning: At least one not upgraded TMUX bot is running! You must stop it with kill command:${NC}\\n${oldbot}"
		echo "Adjusting user \"${TOUSER}\" files and permissions ..."
		[ -w "bashbot.rc" ] && sed -i '/^[# ]*runas=/ s/runas=.*$/runas="'$TOUSER'"/' "bashbot.rc"
		chown -R "$TOUSER" . ./*
		chmod 711 .
		chmod -R a-w ./*
		chmod -R u+w "${COUNTFILE}" "${DATADIR}" "${BOTADMIN}" ./*.log 2>/dev/null
		chmod -R o-r,o-w "${COUNTFILE}" "${DATADIR}" "${TOKENFILE}" "${BOTADMIN}" "${BOTACL}" 2>/dev/null
		# jsshDB must writeable by owner
		find . -name '*.jssh' -exec chmod u+w \{\} +
		ls -la
	fi
}

if ! _is_function send_message ; then
	echo -e "${RED}ERROR: send_message is not availible, did you deactivate ${MODULEDIR}/sendMessage.sh?${NC}"
	exit 1
fi

JSONSHFILE="${BASHBOT_JSONSH:-${RUNDIR}/JSON.sh/JSON.sh}"
[[ "${JSONSHFILE}" != *"/JSON.sh" ]] && echo -e "${RED}ERROR: \"${JSONSHFILE}\" ends not with \"JSONS.sh\".${NC}" && exit 3

if [ ! -f "${JSONSHFILE}" ]; then
	echo "Seems to be first run, Downloading ${JSONSHFILE}..."
	[[ "${JSONSHFILE}" = "${RUNDIR}/JSON.sh/JSON.sh" ]] && mkdir "JSON.sh" 2>/dev/null && chmod +w "JSON.sh"
	getJson "https://cdn.jsdelivr.net/gh/dominictarr/JSON.sh/JSON.sh" >"${JSONSHFILE}"
	chmod +x "${JSONSHFILE}" 
fi

if [ "${SOURCE}" != "yes" ] && [ "$1" != "init" ] &&  [ "$1" != "help" ] && [ "$1" != "" ]; then
  ME="$(getBotName)"
  if [ "$ME" = "" ]; then
	echo -e "${RED}ERROR: Can't connect to Telegram Bot! May be your TOKEN is invalid ...${NC}"
	exit 1
  fi
fi

# source the script with source as param to use functions in other scripts
# do not execute if read from other scripts

if [ "${SOURCE}" != "yes" ]; then

  ##############
  # internal options only for use from bashbot and developers
  case "$1" in
	"outproc") # forward output from interactive and jobs to chat
		[ "$3" = "" ] && echo "No file to read from" && exit 3
		[ "$2" = "" ] && echo "No chat to send to" && exit 3
		while read -r line ;do
			[ "$line" != "" ] && send_message "$2" "$line"
		done 
		rm -f -r "${DATADIR:-.}/$3"
		[ -s "${DATADIR:-.}/$3.log" ] || rm -f "${DATADIR:-.}/$3.log"
		exit
		;;
	"startbot" )
		start_bot "$2"
		exit
		;;
	"init") # adjust users and permissions
		bot_init "$2"
		exit
		;;
  esac


  ###############
  # "official" arguments as shown to users
  SESSION="${ME:-unknown}-startbot"
  BOTPID="$(proclist "${SESSION}")"

  case "$1" in
	"count")
		echo "A total of $(wc -l <"${COUNTFILE}") users used me."
		exit
		;;
	"broadcast")
		NUMCOUNT="$(wc -l <"${COUNTFILE}")"
		echo "Sending the broadcast $* to $NUMCOUNT users."
		[ "$NUMCOUNT" -gt "300" ] && sleep="sleep 0.5"
		shift
		while read -r f; do send_markdown_message "${f//COUNT}" "$*"; $sleep; done <"${COUNTFILE}"
		;;
	"status")
		if [ "${BOTPID}" != "" ]; then
			echo -e "${GREEN}Bot is running.${NC}"
			exit
		else
			echo -e "${ORANGE}Bot not running.${NC}"
			exit 5
		fi
		;;
		 
	"start")
		# shellcheck disable=SC2086
		[ "${BOTPID}" != "" ] && kill ${BOTPID}
		nohup "$SCRIPT" "startbot" "$2" "${SESSION}" &>/dev/null &
		echo "Session Name: ${SESSION}"
		if [ "$(proclist "${SESSION}")" != "" ]; then
		 	echo -e "${GREEN}Bot started successfully.${NC}"
		else
			echo -e "${RED}An error occurred while starting the bot.${NC}"
			exit 5
		fi
		;;
	"kill"|"stop")
		if [ "${BOTPID}" != "" ]; then
			# shellcheck disable=SC2086
			if kill ${BOTPID}; then
				echo -e "${GREEN}OK. Bot stopped successfully.${NC}"
			else
				echo -e "${RED}An error occured while stopping bot.${NC}"
				exit 5
			fi
		fi
		exit
		;;
	"resumeb"* | "killb"* | "suspendb"*)
  		_is_function job_control || { echo -e "${RED}Module background is not availible!${NC}"; exit 3; }
		job_control "$1"
		;;
	"help")
		less "README.txt"
		exit
		;;
	*)
		echo -e "${RED}${REALME}: BAD REQUEST${NC}"
		echo -e "${RED}Available arguments: start, stop, kill, status, count, broadcast, help, suspendback, resumeback, killback${NC}"
		exit 4
		;;
  esac

  # warn if root
  if [[ "${UID}" -eq "0" ]] ; then
	echo -e "\\n${ORANGE}WARNING: ${SCRIPT} was started as ROOT (UID 0)!${NC}"
	echo -e "${ORANGE}You are at HIGH RISK when running a Telegram BOT with root privilegs!${NC}"
  fi
fi # end source
