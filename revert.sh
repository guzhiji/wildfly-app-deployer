
cd `dirname "$0"`

# load common
if [ ! -f ./common.sh ] ; then
	echo 'cannot load common.sh library' >&2
	exit 1
fi
. ./common.sh

onRecoverySuccess() {
	echo -e "\t${GREEN}$1 recovered${NC}"
}

onRecoveryFailure() {
	echo -e "\t${RED}failed to recover $1${NC}"
}

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
	recoverWarFiles "$1"
	touch "$DEPLOY_DIR/$1.dodeploy"
	waitForDeployment onRecoverySuccess onRecoveryFailure "$1"
}

revert() {
	name="$1"
	ver="$2"
	hard="$3"
	war="$DEPLOY_DIR/$name"
	if [[ -e "$war" && "$ver" =~ [0-9]+ && -f "$HISTORY_DIR/$name/$ver" ]] ; then
		echo "reverting $name to $ver"
		curver=$(cat "$HISTORY_DIR/$name/curver")
		echo -e "\tundeploying the current version: $curver"
		if [ $(undeploy "$name") == 'ok' ] ; then
			# extract
			echo -e "\textracting version $ver"
			mkdir tmp
			unzip -q "$HISTORY_DIR/$name/$ver" -d tmp
			# backup
			echo -e "\tbacking up version $curver"
			backupDeployment "$name" 'clean'
			rm -f "$war."* # remove flag files
			# deploy
			echo -e "\tdeploying version $ver"
			mv -f tmp "$war"
			# override config files
			if [ -d "$CONF_DIR/$name" ] ; then
				cp -rf --backup=none "$CONF_DIR/$name/"* "$war"
			fi
			touch "$war.dodeploy"
			waitForDeployment onSuccess onFailure "$name"
			if [ -z "$failedlist" ] ; then
				# update current version
				echo "$ver" > "$HISTORY_DIR/$name/curver"
			fi
			# TODO clean history if hard is true
		else
			echo -e "\t${RED}failed to undeploy${NC}"
		fi
	fi
}

loadConf

DEPLOY_DIR="$JBOSS_HOME/standalone/deployments"

name=$1

if [[ -z "$name" || ! -e "$DEPLOY_DIR/$name" ]] ; then
	echo -e "${RED}a valid deployment name is required${NC}" >&2
	exit 1
fi

if [ ! -f "$HISTORY_DIR/$name/lastver" ] ; then
	echo -e "${RED}no history information available for $name${NC}" >&2
	exit 1
fi

if [ -z "$2" ] ; then
	curver=$(cat "$HISTORY_DIR/$name/curver")
	curver=$(($curver-1))
	if [ $curver -lt 1 ] ; then
		echo -e "${RED}no earlier version available${NC}"
		exit 1
	fi
	revert "$name" $curver
else
	case "$2" in
		list)
			cd "$HISTORY_DIR/$name"
			ls | while read n
			do
				if [[ "$n" =~ [0-9]+ && -f "$n" ]] ; then
					echo "$n"
				fi
			done
			;;
		ver*)
			echo 'Last Version: '$(cat "$HISTORY_DIR/$name/lastver")
			echo 'Current Version: '$(cat "$HISTORY_DIR/$name/curver")
			;;
		hard)
			curver=$(cat "$HISTORY_DIR/$name/curver")
			curver=$(($curver-1))
			if [ $curver -lt 1 ] ; then
				echo -e "${RED}no earlier version available${NC}"
				exit 1
			fi
			revert "$name" $curver 'hard'
			;;
		*)
			revert "$name" "$2" "$3"
			;;
	esac
fi
