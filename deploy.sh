
cd `dirname "$0"`

# load common
if [ ! -f ./common.sh ] ; then
	echo 'cannot load common.sh library' >&2
	exit 1
fi
. ./common.sh

# event handlers

onDeploymentSuccess() {
	nextid=$(updateHistory "$1")
	echo -e "\t${GREEN}$1 deployed (version: $nextid)${NC}"
	if [ -e "$HISTORY_DIR/$1/backup" ] ; then
		echo -e "\tcleaning up"
		rm -rf "$HISTORY_DIR/$1/backup"
	fi
}

onDeploymentFailure() {
	rm -f "$HISTORY_DIR/$1/new"
	echo -e "\t${RED}failed to deploy $1${NC}"
	echo -e "\trecovering"
	recover "$1"
}

# configuration

loadConf
DEPLOY_DIR="$JBOSS_HOME/standalone/deployments"

# main

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
			echo -e "\t${RED}failed to extract the war file${NC}"
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
		# do deploy
		deploy "$f" onDeploymentSuccess onDeploymentFailure
	fi
done
