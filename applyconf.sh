
cd `dirname "$0"`

# load common
if [ ! -f ./common.sh ] ; then
	echo 'cannot load common.sh library' >&2
	exit 1
fi
. ./common.sh

# event handlers

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
	echo -e "\t${RED}$1 failed${NC}"
	echo -e "\trecovering"
	recoverWarFiles "$1" > /dev/null
	touch "$DEPLOY_DIR/$1.dodeploy"
	waitForDeployment onRecoverySuccess onRecoveryFailure "$1"
}

# configuration

loadConf
DEPLOY_DIR="$JBOSS_HOME/standalone/deployments"

for f in $@
do
	war="$DEPLOY_DIR/$f"
	if [ -d "$war" ] ; then
		if [ -d "$CONF_DIR/$f" ] ; then
			echo "$f:"
			# temporarily undeploy the war
			echo -e "\tundeploying temporarily"
			if [ $(undeploy "$f") == 'ok' ] ; then
				rm -f "$war."*
				# backup the original war
				echo -e "\tbacking up"
				backupDeployment "$f"
				# apply configuration files
				echo -e "\tapplying configuration files"
				cp -rf --backup=none "$CONF_DIR/$f/"* "$war"
				# re-deploy
				echo -e "\tdeploying"
				touch "$war.dodeploy"
				waitForDeployment onSuccess onFailure "$f"
			else
				echo -e "\t${RED}failed to undeploy $f${NC}"
			fi
		else
			echo -e "${RED}$f: no configuration files found${NC}"
		fi
	elif [ -f "$war" ] ; then
		echo -e "${RED}$f: not exploded format${NC}"
	else
		echo -e "${RED}$f: deployment not found${NC}"
	fi
done
