
onSuccess() {
	echo "$1 done"
}

onFailure() {
	echo "$1 failed"
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

cd `dirname "$0"`

if [ -f /etc/default/wildfly ] ; then
	. /etc/default/wildfly
elif [ -f ./local.conf ] ; then
	. ./local.conf
fi
if [ ! -d "$JAVA_HOME" ] ; then
	echo 'cannot find JAVA_HOME' >&2
	exit 1
fi
if [ ! -d "$JBOSS_HOME" ] ; then
	echo 'cannot find JBOSS_HOME' >&2
	exit 1
fi
if [ ! -d "$HISTORY_DIR" ] ; then
	echo 'cannot find HISTORY_DIR' >&2
	exit 1
fi
if [ ! -d "$CONF_DIR" ] ; then
	echo 'cannot find CONF_DIR' >&2
	exit 1
fi

echo "JAVA_HOME: $JAVA_HOME"
echo "JBOSS_HOME: $JBOSS_HOME"
echo "HISTORY_DIR: $HISTORY_DIR"
echo "CONF_DIR: $CONF_DIR"
export PATH="$JAVA_HOME/bin:$PATH"
echo "PATH: $PATH"
echo

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

