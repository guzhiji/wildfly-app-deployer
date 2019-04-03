
cd `dirname "$0"`

# load common
if [ ! -f ./common.sh ] ; then
	echo 'cannot load common.sh library' >&2
	exit 1
fi
. ./common.sh

onSuccess() {
	echo "$1 done"
}

onFailure() {
	echo "$1 failed"
}

loadConf

DEPLOY_DIR="$JBOSS_HOME/standalone/deployments"
filelist=
for f in $@
do
	if [ -d "$CONF_DIR/$f" ] ; then
		war="$DEPLOY_DIR/$f"
		if [ -d "$war" ] ; then
			echo "$f:"
			echo -e "\tundeploying temporarily"
			$JBOSS_HOME/bin/jboss-cli.sh --connect --command='undeploy'" $f"
			echo -e "\tapplying conf files"
			cp -rf --backup=none "$CONF_DIR/$f/"* "$war"
			echo -e "\tdeploying"
			rm -f "$war."*
			touch "$war.dodeploy"
			filelist="$filelist $f"
		elif [ -f "$war" ] ; then
			echo "$f: not exploded format"
		else
			echo "$f: deployment not found"
		fi
	else
		echo "$f: no conf files found"
	fi
done

echo
waitForDeployment onSuccess onFailure $filelist

