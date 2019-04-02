
onDeploymentSuccess() {
	f=$1
	war="$DEPLOY_DIR/$f"
	if [ -d "$HISTORY_DIR/$f/lastid" ] ; then
		nextid=`cat "$HISTORY_DIR/$f/lastid"`
		nextid=$(($nextid+1))
	else
		nextid=1
	fi
	mv -f "$HISTORY_DIR/$f/new" "$HISTORY_DIR/$f/$nextid"
	if [ -f "$HISTORY_DIR/$f/backup" ] ; then
		rm -rf "$HISTORY_DIR/$f/backup"
	fi
	echo "$nextid" > "$HISTORY_DIR/$f/lastid"
	echo "$f deployed"
}

onDeploymentFailure() {
	f=$1
	war="$DEPLOY_DIR/$f"
	rm -f "$HISTORY_DIR/$f/new"
	if [ -e "$HISTORY_DIR/$f/backup" ] ; then
		rm -rf "$war"
		rm -f "$war."*
		mv -f "$HISTORY_DIR/$f/backup" "$war"
		touch "$war.dodeploy"
	fi
	echo "$f failed"
}

onRecoverySuccess() {
	echo "$1 recovered"
}

onRecoveryFailure() {
	echo "$1 failed to recover"
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
for f in *
do
	if [[ "$f" =~ \.war$ ]] ; then
		filelist="$filelist $f"
		echo "deploying $f"

		# extract war
		echo -e "\textracting"
		if [ -d tmp ] ; then
			rm -rf tmp
		fi
		mkdir tmp
		cd tmp
		mv -f "../$f" .
		unzip -q "$f"
		if [ ! -d "$HISTORY_DIR/$f" ] ; then
			mkdir "$HISTORY_DIR/$f"
		fi
		mv -f "$f" "$HISTORY_DIR/$f/new"
		cd ..

		# undeploy war
		echo -e "\tundeploying previous version"
		$JBOSS_HOME/bin/jboss-cli.sh --connect --command='undeploy'" $f"
		war="$DEPLOY_DIR/$f"
		if [ -e "$war" ] ; then
			if [ -e "$HISTORY_DIR/$f/backup" ] ; then
				rm -rf "$HISTORY_DIR/$f/backup"
			fi
			mv -f "$war" "$HISTORY_DIR/$f/backup"
			rm -f "$war."*
		fi

		# deploy new war directory
		echo -e "\tdeploying"
		mv -f tmp "$war"
		if [ -d "$CONF_DIR/$f" ] ; then
			# override config
			cp -rf --backup=none "$CONF_DIR/$f/"* "$war"
		fi
		touch "$war.dodeploy"
	fi
done

echo
waitForDeployment onDeploymentSuccess onDeploymentFailure $filelist
echo

if [ ! -z "$failedlist" ] ; then
	waitForDeployment onRecoverySuccess onRecoveryFailure $failedlist
fi

