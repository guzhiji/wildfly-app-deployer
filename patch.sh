
cd `dirname "$0"`

# load common
if [ ! -f ./common.sh ] ; then
	echo 'cannot load common.sh library' >&2
	exit 1
fi
. ./common.sh

onSuccess() {
	if [ -e "$HISTORY_DIR/$1/backup" ] ; then
		rm -rf "$HISTORY_DIR/$1/backup"
	fi
	nextid=$(updateHistory "$1")
	echo "$1 deployed (version: $nextid)"
}

onFailure() {
	rm -f "$HISTORY_DIR/$1/new"
	echo "$1 failed"
}

loadConf

DEPLOY_DIR="$JBOSS_HOME/standalone/deployments"
CUR_DIR="$PWD"
applist=
for f in *
do
	# validate the current file
	name=
	patchType=
	if [[ "$f" =~ \.war$ ]] ; then
		name="$f"
		patchType='.war'
	elif [[ "$f" =~ \.zip$ ]] ; then
		name=$(echo "$f" | sed s'/\.zip$/\.war/')
		patchType='.zip'
	elif [[ "$f" =~ \.tar$ ]] ; then
		name=$(echo "$f" | sed s'/\.tar$/\.war/')
		patchType='.tar'
	elif [[ "$f" =~ \.tar\.gz$ ]] ; then
		name=$(echo "$f" | sed s'/\.tar\.gz$/\.war/')
		patchType='.tar.gz'
	elif [[ "$f" =~ \.tar\.bz2$ ]] ; then
		name=$(echo "$f" | sed s'/\.tar\.bz2$/\.war/')
		patchType='.tar.bz2'
	elif [[ "$f" =~ \.tar\.xz$ ]] ; then
		name=$(echo "$f" | sed s'/\.tar\.xz$/\.war/')
		patchType='.tar.xz'
	fi
	if [ -z "$name" ] ; then
		continue
	fi
	war="$DEPLOY_DIR/$name"
	if [ ! -d "$war" ] ; then
		continue
	fi
	echo "patching $name"
	# extract the patch file into tmp
	echo -e "\textracting patch file ($patchType)"
	if [ -d tmp ] ; then
		rm -rf tmp
	fi
	mkdir tmp
	case "$patchType" in
		.war|.zip) unzip -q "$f" -d tmp ;;
		.tar) tar -xf "$f" -C tmp ;;
		.tar.gz) tar -xzf "$f" -C tmp ;;
		.tar.bz2) tar -xjf "$f" -C tmp ;;
		.tar.xz) tar -xJf "$f" -C tmp ;;
	esac
	if [ $? != 0 ] ; then
		echo -e "\tfailed to extract patch file"
		rm -rf tmp
		continue
	fi
	# find the base directory of the extracted patch
	cd tmp
	dirfound='n'
	for d in *
	do
		if [[ "$d" == 'WEB-INF' && -d "$d" ]] ; then
			dirfound='y'
			break
		elif [ -d "$d/WEB-INF" ] ; then
			dirfound='y'
			cd "$d"
			break
		fi
	done
	if [ "$dirfound" == 'n' ] ; then
		echo -e "\tthe patch file $f does not contain WEB-INF"
		cd "$CUR_DIR"
		rm -rf tmp
		continue
	fi
	# temporarily undeploy the war
	echo -e "\tundeploying previous version"
	if [ $(undeploy "$name") == 'error' ] ; then
		echo -e "\t${RED}failed to undeploy $name${NC}"
		cd "$CUR_DIR"
		rm -rf tmp
		continue
	fi
	rm -f "$war."*
	# backup the original app
	echo -e "\tbacking up"
	backupDeployment "$name"
	# apply the patch
	echo -e "\tapplying the patch"
	cp -rf --backup=none ./* "$war"
	# override config files
	if [ -d "$CONF_DIR/$name" ] ; then
		cp -rf --backup=none "$CONF_DIR/$name/"* "$war"
	fi
	# archive the patched app
	echo -e "\tarchiving the patched version"
	cd "$war"
	jar -cf "$HISTORY_DIR/$name/new" .
	cd - > /dev/null
	# re-deploy
	touch "$war.dodeploy"
	applist="$applist $name"
	# clean up
	echo -e "\tcleaning up"
	cd "$CUR_DIR"
	rm -rf tmp
done

echo
echo 'Waiting for deployment:'"$applist"
waitForDeployment onSuccess onFailure $applist

if [ ! -z "$failedlist" ] ; then
	echo
	echo "Recovery: $failedlist"
	for f in $(recoverWarFiles $failedlist)
	do
		touch "$DEPLOY_DIR/$f.dodeploy"
	done
	waitForDeployment onSuccess onFailure $failedlist
fi