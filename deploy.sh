
cd `dirname "$0"`

# load common
if [ ! -f ./common.sh ] ; then
	echo 'cannot load common.sh library' >&2
	exit 1
fi
. ./common.sh

onDeploymentSuccess() {
	f=$1
	if [ -f "$HISTORY_DIR/$f/backup" ] ; then
		rm -rf "$HISTORY_DIR/$f/backup"
	fi
	nextid=$(updateHistory "$f")
	echo "$f deployed (version: $nextid)"
}

onDeploymentFailure() {
	f=$1
	rm -f "$HISTORY_DIR/$f/new"
	echo "$f failed"
}

onRecoverySuccess() {
	echo "$1 recovered"
}

onRecoveryFailure() {
	echo "$1 failed to recover"
}


loadConf

DEPLOY_DIR="$JBOSS_HOME/standalone/deployments"
filelist=
for f in *
do
	if [[ "$f" =~ \.war$ ]] ; then
		echo "deploying $f"

		# extract war
		echo -e "\textracting"
		if [ -d tmp ] ; then
			rm -rf tmp
		fi
		mkdir tmp
		unzip -q "$f" -d tmp
		if [ $? != 0 ] ; then
			echo -e "\t${RED}failed to extract the war file{NC}"
			rm -rf tmp
			continue
		fi

		# undeploy war
		war="$DEPLOY_DIR/$f"
		if [ -e "$war" ] ; then
			echo -e "\tundeploying previous version"
			if [ $(undeploy "$f") == 'error' ] ; then
				echo -e "\t${RED}failed to undeploy $f${NC}"
				rm -rf tmp
				continue
			fi
			# backup the original war
			echo -e "\tbacking up"
			backupDeployment "$f" 'clean'
			rm -f "$war."* # remove flag files
		fi
		# otherwise it's a new deployment

		# put away the new war
		if [ ! -d "$HISTORY_DIR/$f" ] ; then
			mkdir "$HISTORY_DIR/$f"
		fi
		mv -f "$f" "$HISTORY_DIR/$f/new"

		# deploy the new war directory
		echo -e "\tdeploying"
		mv -f tmp "$war"
		# override config files
		if [ -d "$CONF_DIR/$f" ] ; then
			cp -rf --backup=none "$CONF_DIR/$f/"* "$war"
		fi
		touch "$war.dodeploy"
		filelist="$filelist $f"
	fi
done

echo
echo 'Waiting for deployment:'"$filelist"
waitForDeployment onDeploymentSuccess onDeploymentFailure $filelist

if [ ! -z "$failedlist" ] ; then
	echo
	echo "Recovery: $failedlist"
	for f in $(recoverWarFiles $failedlist)
	do
		sleep 1
		touch "$DEPLOY_DIR/$f.dodeploy"
	done
	waitForDeployment onRecoverySuccess onRecoveryFailure $failedlist
fi

