#!/bin/bash 
# set -vx

abort()
{
    echo >&2 '
    ***************
    *** ABORTED ***
    ***************
    '
    echo "An error occurred. Exiting..." >&2
    exit 1
}

summary()
{
  echo_msg "Current Apps & Services in CF_SPACE"
  cf apps
  cf services
}

echo_msg()
{
  echo ""
  echo "************** ${1} **************"
}

build()
{
  echo_msg "Building application"
  ./gradlew build 
}

cf_app_delete()
{
  EXISTS=`cf apps | grep ${1} | wc -l | xargs`
  if [ $EXISTS -ne 0 ]
  then
    echo "Deleting app"
    cf delete -f ${1}
  fi
}

cf_service_delete()
{
  #Were we supplied an App name?
  if [ ! -z "${2}" ]
  then
    EXISTS=`cf services | grep ${1} | grep ${2} | wc -l | xargs`
    if [ $EXISTS -ne 0 ]
    then
      cf unbind-service ${1} ${2}
    fi
  fi

  #Delete the Service Instance
  EXISTS=`cf services | grep ${1} | wc -l | xargs`
  if [ $EXISTS -ne 0 ]
  then
    cf delete-service -f ${1}
  fi
}

clean_cf()
{
  echo_msg "Removing previous deployment (if necessary!)"
  APPS=`cf apps | grep $APPNAME | cut -d" " -f1`
  for app in ${APPS[@]}
  do
    cf delete -f $app
  done
  cf_service_delete $DBSERVICE $APPNAME
  cf_service_delete $DISCOVERY $APPNAME
  echo_msg "Removing Orphaned Routes"
  cf delete-orphaned-routes -f
}

push()
{
  clean_cf
  echo_msg "Pushing to PCF, it will be slow because we are initialising the database as well"
  cf create-service p-mysql 100mb-dev $DBSERVICE
  cf create-service p-service-registry standard $DISCOVERY
  DATE=`date "+%Y%m%d%H%M%S"`
  APPNAME=$APPNAME-$DATE
  cf push $APPNAME -b java_buildpack_offline --no-start --no-manifest --random-route
  echo_msg "Setting environment for SCS"
  cf set-env $APPNAME CF_TARGET $CF_TARGET

  # Sleep for service registry
  max=12
  for ((i=1; i<=$max; ++i )) ; do
    echo "Pausing to allow Service Discovery to Initialise.....$i/$max"
    sleep 5
  done

  # Carry on pushing
  echo_msg "Pushing App: $APPNAME!"
  cf push $APPNAME -b java_buildpack_offline

  # Add unique route for future versioning
  DOMAIN=`cf target | grep "API" | cut -d" " -f5 | sed "s/[^.]*.//"`
  RANDOM_ROUTE=`cf app $APPNAME | grep urls | cut -d":" -f2 | sed "s/-$DATE//" |  cut -d"." -f1 | xargs`
  cf map-route $APPNAME $DOMAIN -n $RANDOM_ROUTE
}

main()
{
  APPNAME=cities
  DBSERVICE=MyDB
  DISCOVERY=ServiceReg

  build 

  # Work out the CF_TARGET
  CF_TARGET=`cf target | grep "API" | cut -d" " -f5| xargs`
  # Disable PWS until we write the small script to check the name of the java buildpack
  PWS=`echo $CF_TARGET | grep "run.pivotal.io" | wc -l`
  if [ $PWS -ne 0 ]
  then
    echo_msg "This won't run on PWS, please use another environment"
    exit 1
  fi

  push
}

check_cli_installed()
{
  #Is the CF CLI installed?
  echo_msg "Targeting the following CF Environment, org and space"
  cf target
  if [ $? -ne 0 ]
  then
    echo_msg "!!!!!! ERROR: You either don't have the CF CLI installed or you are not connected to an Org or Space !!!!!!"
    exit $?
  fi
}

SECONDS=0
trap 'abort' 0
set -e

check_cli_installed
summary
main
summary

trap : 0

echo_msg "Deployment Complete in $SECONDS seconds."
