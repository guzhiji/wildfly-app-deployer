
cd `dirname "$0"`

# load common
if [ ! -f ./common.sh ] ; then
	echo 'cannot load common.sh library' >&2
	exit 1
fi
. ./common.sh

# event handlers

onSuccess() {
	echo -e "\t${GREEN}$1 deployed${NC}"
	if [ -e "$HISTORY_DIR/$1/backup" ] ; then
		echo -e "\tcleaning up"
		rm -rf "$HISTORY_DIR/$1/backup"
	fi
}

onFailure() {
	echo -e "\t${RED}failed to deploy $1${NC}"
	echo
	echo "Recovery: $1"
	recover "$1"
}

# functions

removeNewer() {
	hd="$HISTORY_DIR/$1"
	if [[ ! -z "$1" && -f "$hd/curver" ]] ; then
		curver=$(cat "$hd/curver")
		for n in $(listVersions "$1")
		do
			if [ $n -gt $curver ] ; then
				echo -e "\tremoving version $n"
				rm -f "$hd/$n"
			fi
		done
	fi
}

keepVersions() {
	hd="$HISTORY_DIR/$1"
	if [[ ! -z "$1" && -f "$hd/curver" ]] ; then
		if [[ ! "$2" =~ [1-9][0-9]* ]] ; then
			echo -e "${RED}please specify a number of versions to keep${NC}"
			exit 1
		elif [ $2 -lt 3 ] ; then
			echo -e "${RED}at least 3 versions to keep${NC}"
			exit 1
		fi
		curver=$(cat "$hd/curver")
		v=$(($curver-$2+1))
		echo "keep $2 versions from the current one (version: $curver)"
		for n in $(listVersions "$1")
		do
			if [ $n -lt $v ] ; then
				echo -e "\tremoving version $n"
				rm -f "$hd/$n"
			fi
		done
	fi
}

revert() {
	name="$1"
	ver="$2"
	hard="$3"
	war="$DEPLOY_DIR/$name"
	if [[ ! -z "$name" && -e "$war" ]] ; then
		hd="$HISTORY_DIR/$name"
		curver=$(cat "$hd/curver")
		if [[ ! "$ver" =~ [0-9]+ ]] ; then
			echo -e "${RED}a valid version number required${NC}" >&2
			exit 1
		elif [ ! -f "$hd/$ver" ] ; then
			echo -e "${RED}version $ver does not exist${NC}" >&2
			exit 1
		elif [ $ver == $curver ] ; then
			echo -e "${RED}version $ver already deployed${NC}" >&2
			exit 1
		else
			echo "reverting $name to version $ver"
			# undeploy
			echo -e "\tundeploying the current version: $curver"
			if [ $(undeploy "$name") == 'error' ] ; then
				echo -e "\t${RED}failed to undeploy $name${NC}"
			else
				# extract
				echo -e "\textracting version $ver"
				mkdir tmp
				unzip -q "$hd/$ver" -d tmp
				# backup
				echo -e "\tbacking up version $curver"
				backupDeployment "$name" 'clean'
				# deploy
				echo -e "\tdeploying version $ver"
				mv -f tmp "$war"
				# override config files
				if [ -d "$CONF_DIR/$name" ] ; then
					cp -rf --backup=none "$CONF_DIR/$name/"* "$war"
				fi
				deploy "$name" onSuccess onFailure
				if [ $? == 0 ] ; then
					# update current version
					echo "$ver" > "$hd/curver"
					# remove newer versions
					if [ "$hard" == 'hard' ] ; then
						removeNewer "$name"
					fi
				fi
			fi
		fi
	fi
}

checkEarlierVersion() {
	name="$1"
	ver="$2"
	if [ $ver -lt $(earliestVersion "$name") ] ; then
		echo -e "${RED}no earlier version available${NC}" >&2
		exit 1
	fi
}

# configuration

loadConf
DEPLOY_DIR="$JBOSS_HOME/standalone/deployments"


name="$1"
if [[ -z "$name" || ! -e "$DEPLOY_DIR/$name" ]] ; then
	echo -e "${RED}a valid deployment name is required${NC}" >&2
	exit 1
fi
if [ ! -f "$HISTORY_DIR/$name/curver" ] ; then
	echo -e "${RED}no history information available for $name${NC}" >&2
	exit 1
fi

if [ -z "$2" ] ; then
	# soft revert to previous version
	# revert.sh name
	curver=$(cat "$HISTORY_DIR/$name/curver")
	ver=$(($curver-1))
	checkEarlierVersion "$name" $ver
	revert "$name" $ver
else
	case "$2" in
		list)
			# list all versions
			# revert.sh name list
			listVersions "$name" | sort -g
			;;
		ver|version)
			# show the latest version and current version
			# revert.sh name ver
			echo 'latest version: '$(latestVersion "$name")
			echo 'current version: '$(cat "$HISTORY_DIR/$name/curver")
			;;
		keep)
			# keep recent n versions
			# revert.sh name keep n
			keepVersions "$name" "$3"
			;;
		newest|last|latest)
			# revert to the newest version
			# revert.sh name newest
			ver=$(latestVersion "$name")
			echo "latest version: $ver"
			revert "$name" $ver
			;;
		hard)
			# hard revert to previous version
			# revert.sh name hard
			curver=$(cat "$HISTORY_DIR/$name/curver")
			ver=$(($curver-1))
			checkEarlierVersion "$name" $ver
			revert "$name" $ver 'hard'
			;;
		*)
			# revert to a specified version
			# revert.sh name ver [hard]
			revert "$name" "$2" "$3"
			;;
	esac
fi
