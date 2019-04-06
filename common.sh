
RED='\033[0;31m'
GREEN='\033[32;40m'
NC='\033[0m'

loadConf() {
	if [ -f /etc/default/wildfly ] ; then
		. /etc/default/wildfly
	elif [ -f ./local.conf ] ; then
		. ./local.conf
	fi
	if [ ! -d "$JAVA_HOME" ] ; then
		echo -e "${RED}cannot find JAVA_HOME${NC}" >&2
		exit 1
	fi
	if [ ! -d "$JBOSS_HOME" ] ; then
		echo -e "${RED}cannot find JBOSS_HOME${NC}" >&2
		exit 1
	fi
	if [ ! -d "$HISTORY_DIR" ] ; then
		echo -e "${RED}cannot find HISTORY_DIR${NC}" >&2
		exit 1
	fi
	if [ ! -d "$CONF_DIR" ] ; then
		echo -e "${RED}cannot find CONF_DIR${NC}" >&2
		exit 1
	fi

	echo "JAVA_HOME: $JAVA_HOME"
	echo "JBOSS_HOME: $JBOSS_HOME"
	echo "HISTORY_DIR: $HISTORY_DIR"
	echo "CONF_DIR: $CONF_DIR"
	export PATH="$JAVA_HOME/bin:$PATH"
	echo "PATH: $PATH"
	echo
}

waitForDeployment() {
	finishedlist=
	failedlist=
	while [ 1 == 1 ]
	do
		shouldwait='n'
		n=0
		for f in $@
		do
			n=$(($n+1))
			if [ $n -lt 3 ] ; then
				continue # skip $1 $2
			fi
			war="$DEPLOY_DIR/$f"
			if [ -f "$war.deployed" ] ; then
				known='n'
				for ff in $finishedlist
				do
					if [ "$ff" == "$f" ] ; then
						known='y'
						break
					fi
				done
				if [ "$known" == 'n' ] ; then
					$1 $f
					finishedlist="$finishedlist $f"
				fi
			elif [ -f "$war.failed" ] ; then
				known='n'
				for ff in $failedlist
				do
					if [ "$ff" == "$f" ] ; then
						known='y'
						break
					fi
				done
				if [ "$known" == 'n' ] ; then
					$2 $f
					failedlist="$failedlist $f"
				fi
			elif [ ! -f "$war.undeployed" ] ; then
				shouldwait='y'
			fi
		done
		if [ "$shouldwait" == 'y' ] ; then
			sleep 1
		else
			break
		fi
	done
}

deploy() {
	name="$1"
	if [ ! -z "$name" ] ; then
		war="$DEPLOY_DIR/$name"
		if [ -e "$war" ] ; then
			rm -f "$war."* 2> /dev/null # remove flag files
			touch "$war.dodeploy"
			waitForDeployment "$2" "$3" "$name"
			if [ -z "$failedlist" ] ; then
				return 0
			else
				return 1
			fi
		else
			return 2
		fi
	else
		return 3
	fi
}

undeploy() {
	if [ -z "$1" ] ; then
		echo 'error'
	else
		cli="$JBOSS_HOME/bin/jboss-cli.sh"
		r=$($cli --connect --command='undeploy'" $1" 2>&1 | grep -i 'failed')
		if [ -z "$r" ] ; then
			echo 'ok'
		else
			echo 'error'
		fi
	fi
}

recoverWarFiles() {
	for f in $@
	do
		if [ -e "$HISTORY_DIR/$f/backup" ] ; then
			war="$DEPLOY_DIR/$f"
			rm -rf "$war"
			rm -f "$war."* 2> /dev/null # remove flag files
			mv -f "$HISTORY_DIR/$f/backup" "$war"
			echo "$f"
		fi
	done
}

_onRecoverySuccess() {
	echo -e "\t${GREEN}$1 recovered${NC}"
}

_onRecoveryFailure() {
	echo -e "\t${RED}failed to recover $1${NC}"
}

recover() {
	if [ ! -z "$1" ] ; then
		sleep 5
		recoverWarFiles "$1" > /dev/null
		deploy "$1" _onRecoverySuccess _onRecoveryFailure
		return $?
	else
		return 3
	fi
}

backupDeployment() {
	if [ ! -z "$1" ] ; then
		name="$1"
		war="$DEPLOY_DIR/$name"
		hd="$HISTORY_DIR/$name"
		if [ -e "$war" ] ; then
			# prepare directory
			if [ ! -d "$hd" ] ; then
				mkdir "$hd"
			fi
			# clear residual backup
			if [ -e "$hd/backup" ] ; then
				rm -rf "$hd/backup"
			fi
			# do backup
			if [ "$2" == 'clean' ] ; then
				mv -f "$war" "$hd/backup"
			else
				cp -rf "$war" "$hd/backup"
			fi
		fi
	fi
}

updateHistory() {
	name=$1
	hd="$HISTORY_DIR/$name"
	if [ -f "$hd/new" ] ; then
		if [ -f "$hd/lastver" ] ; then
			nextid=$(cat "$hd/lastver")
			nextid=$(($nextid+1))
		else
			nextid=1
		fi
		mv -f "$hd/new" "$hd/$nextid"
		echo "$nextid" | tee "$hd/lastver" "$hd/curver"
	fi
}

listVersions() {
	hd="$HISTORY_DIR/$1"
	if [[ ! -z "$1" && -d "$hd" ]] ; then
		cd "$hd"
		for n in `ls`
		do
			if [[ "$n" =~ [0-9]+ && -f "$n" ]] ; then
				echo "$n"
			fi
		done
		cd - > /dev/null
	fi
}

earliestVersion() {
	listVersions "$1" | sort -g | head -n 1
}

