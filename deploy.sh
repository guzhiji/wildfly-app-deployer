
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
export PATH="$JAVA_HOME/bin:$PATH"
echo "PATH: $PATH"
echo "HISTORY_DIR: $HISTORY_DIR"
echo "CONF_DIR: $CONF_DIR"
echo

waitForDeployment() {
	finishedlist=
	failedlist=
	while [ 1 == 1 ]
	do
		shouldwait='n'
		for f in $@
		do
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
					echo "$f deployed"
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
					echo "$f failed"
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

DEPLOY_DIR="$JBOSS_HOME/standalone/deployments"
CUR_DIR="$HISTORY_DIR/$(date +%s)"
filelist=
for f in *
do
	if [[ "$f" =~ \.war$ ]] ; then
		filelist="$filelist $f"
		echo "deploying $f"

		# extract war
		echo -e "\textracting"
		mkdir tmp
		cd tmp
		mv "../$f" .
		unzip -q "$f"
		if [ ! -d "$CUR_DIR" ] ; then
			mkdir -p "$CUR_DIR"
		fi
		mv "$f" "$CUR_DIR"
		cd ..

		# undeploy war
		echo -e "\tundeploying previous version"
		$JBOSS_HOME/bin/jboss-cli.sh --connect --command='undeploy'" $f"
		war="$DEPLOY_DIR/$f"
		if [ -e "$war" ] ; then
			rm -rf "$war"
			rm -f "$war."*
		fi

		# deploy new war directory
		echo -e "\tdeploying"
		mv tmp "$war"
		if [ -d "$CONF_DIR/$f" ] ; then
			# override config
			cp -rf --backup=none "$CONF_DIR/$f" "$war"
		fi
		touch "$war.dodeploy"
	fi
done

echo
waitForDeployment $filelist

