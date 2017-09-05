#!/bin/sh

set -e

# Prior to running the script, please make sure you have done the following:
#  	1. cf is installed
#  	2. uaac is installed
# This script does the following:
#   1. Creates the following Predix Services: UAA, Asset, ACS, Time Series and Analytics
#   2. Creates a client with the appropriate permissions (scope and authorities)
#   3. Creates users, groups and assigns users to groups

main() {
	# disabling cf trace mode.
	export CF_TRACE=false
	welcome
	loginCf
	checkPrereq
	deployingApp
	createUAA
	getUAAEndpoint
	createClient
	createACS
	createAsset
	createTimeseries
	createAnalyticsFramework
 	updateClient
	createUsers
	createGroups
	assignUsersToGroups
	output
}

loginCf()
{
   cf login -a https://api.system.aws-usw02-pr.ice.predix.io -u student10 -p 'PrediX20!7' -o Predix-Training -s Training2 || sadKitty

}

checkPrereq()
{
  {
	echo ""
    echo "Checking prerequisites ..."
    verifyCommand 'cf -v'
    verifyCommand 'uaac -v'
    echo ""
  }||
  {
    echo sadKitty
  }
}

# Verifies a given command existence
verifyCommand()
{
  x=$($1)
  # echo "x== $x"
  if [[ ${#x} -gt 5 ]];
  then
    echo "OK - $1"
  else
    echoc r "$1 not found!"
    echoc g "Please install: "
    echoc g "\t CF - https://github.com/cloudfoundry/cli"
    echoc g "\t UAAC -https://github.com/cloudfoundry/cf-uaac"
    sadKitty
  fi
}

deployingApp() {
	read -p "Enter a prefix for the services name:" prefix
	cd hello-predix/
	app_name=$prefix-hello-predix
	echo $app_name
	cf push $app_name --random-route || sadKitty
}

createUAA() {
	cd ..
	echo ""
	echo "Creating UAA service..."
	uaaname=$prefix-uaa-training
	cf create-service predix-uaa-training Free $uaaname -c '{"adminClientSecret":"admin_secret"}' || sadKitty
	echo ""
	echo "Binding $app_name app to $uaaname..."
	cf bs $app_name $uaaname || sadKitty
}

getUAAEndpoint() {
	  echo ""
	  echo "Getting UAA endpoint..."
	  {
		 	 env_cf_app=$(cf env $app_name)
			 uaa_uri=`echo $env_cf_app | egrep -o '"uri": "https?://[^ ]+"' | sed s/\"uri\":\ // | sed s/\"//g`

			 if [[ $uaa_uri == *"FAILED"* ]];
			 then
			   echo "Unable to find UAA endpoint for you!"
			   sadKitty
			   exit -1
			 fi

			 echo "UAA endpoint: $uaa_uri"
		} ||
	  {
	    sadKitty
	  }
}

createClient() {
		echo ""
		echo "Creating client..."
		uaac target $uaa_uri --skip-ssl-validation && uaac token client get admin -s admin_secret || sadKitty
		echo ""
		clientname=$prefix-client
		uaac client add $clientname -s secret --authorized_grant_types "authorization_code client_credentials password refresh_token" --autoapprove "openid scim.me" --authorities "clients.read clients.write scim.read scim.write"
}

createACS() {
	echo ""
	echo "Creating ACS service..."
	acsname=$prefix-acs-training
	cf create-service predix-acs-training Free $acsname -c '{"trustedIssuerIds":["'$uaa_uri'/oauth/token"]}' || sadKitty
	echo ""
	cf bs $app_name $acsname || sadKitty

	acs_zone=`cf env $app_name|grep predix-acs-training|grep '"oauth-scope": "'|sed s/\"oauth-scope\":\ // |sed s/\"//g|sed 's/ //g'` || sadKitty
}

createAsset() {
	echo ""
	echo "Creating Asset service..."
	assetname=$prefix-asset
	cf create-service predix-asset Free $assetname -c '{"trustedIssuerIds":["'$uaa_uri'/oauth/token"]}' || sadKitty
	echo ""
	cf bs $app_name $assetname || sadKitty
	asset_zone=`cf env $app_name|grep predix-asset|grep '"oauth-scope": "'|sed s/\"oauth-scope\":\ // |sed s/\"//g|sed 's/ //g'` || sadKitty
	zone=`echo "$asset_zone"|sed -e "s/\predix-asset.zones.//"|sed "s/\.user//"` || sadKitty 
	echo $zone
}

createTimeseries() {
	echo ""
	echo "Creating Timeseries service..."
	timeseriesname=$prefix-timeseries
	cf create-service predix-timeseries Free $timeseriesname -c '{"trustedIssuerIds":["'$uaa_uri'/oauth/token"]}' || sadKitty
	echo ""
	cf bs $app_name $timeseriesname || sadKitty
	timeseries_zone=`cf env $app_name|grep zone-http-header-value|sed 'n;d'|sed s/\"zone-http-header-value\":\ // |sed s/\"//g |sed s/\,//g|sed 's/ //g'` || sadKitty
}

createAnalyticsFramework() {
	echo ""
	echo "Creating Analytics Framework service..."
	analyticsname=$prefix-analytics-framework
	cf create-service predix-analytics-framework Free $analyticsname -c '{"trustedIssuerIds":["'$uaa_uri'/oauth/token"],"runtimeClientId":"'$prefix'-client","runtimeClientSecret":"secret","predixTimeseriesZoneId":"'$timeseries_zone'","predixAssetZoneId":"'$zone'","uiDomainPrefix":"'$prefix'-predixUi", "uiClientId":"'$prefix'-client","uiClientSecret":"secret"}' || sadKitty
	echo ""
	cf bs $app_name $analyticsname
	analytics_zone=`cf env $app_name|grep analytics.zone|sed s/\"zone-oauth-scope\":\ // |sed s/\"//g|sed 's/ //g'` || sadKitty

}

updateClient() {
	echo ""
	echo "Updating client..."
	# uaac target $uaa_uri --skip-ssl-validation && uaac token client get admin -s admin_secret || sadKitty
	echo ""
  uaac client update $clientname --authorities "clients.read clients.write scim.write scim.read acs.policies.read acs.policies.write acs.attributes.read
        acs.attributes.write idps.read idps.write uaa.resource $acs_zone $asset_zone timeseries.zones.$timeseries_zone.query timeseries.zones.$timeseries_zone.user timeseries.zones.$timeseries_zone.ingest $analytics_zone" --scope "$acs_zone openid uaa.none $analytics_zone"
}

createUsers() {
	echo ""
	echo "Creating users..."
	uaac user add app_admin --emails app_admin@gegrctest.com -p app_admin || sadKitty
	uaac user add app_user --emails app_user@gegrctest.com -p app_user || sadKitty
}

createGroups() {
	echo ""
	echo "Creating groups..."
	uaac group add "$acs_zone"
	uaac group add "$asset_zone"
	uaac group add "timeseries.zones.$timeseries_zone.user"
	uaac group add "timeseries.zones.$timeseries_zone.query"
	uaac group add "timeseries.zones.$timeseries_zone.ingest"
	uaac group add "$analytics_zone"
}

assignUsersToGroups() {
	echo ""
	echo "Assigning users to groups..."
	uaac member add "$acs_zone" app_admin
	uaac member add "$asset_zone" app_admin
	uaac member add "timeseries.zones.$timeseries_zone.user" app_admin
	uaac member add "timeseries.zones.$timeseries_zone.query" app_admin
	uaac member add "timeseries.zones.$timeseries_zone.ingest" app_admin
	uaac member add "$analytics_zone" app_admin

	uaac member add "$acs_zone" app_user
	uaac member add "$asset_zone" app_user
	uaac member add "timeseries.zones.$timeseries_zone.user" app_user
	uaac member add "timeseries.zones.$timeseries_zone.query" app_user
	uaac member add "timeseries.zones.$timeseries_zone.ingest" app_user
	uaac member add "$analytics_zone" app_user
}

############################### ASCII ART ###############################
# Predix Training
welcome()
{
	cat <<"EOT"
	_____                 _  _     _______           _         _
  |  __ \               | |(_)   |__   __|         (_)       (_)
  | |__) |_ __  ___   __| | _ __  __| | _ __  __ _  _  _ __   _  _ __    __ _
  |  ___/| '__|/ _ \ / _` || |\ \/ /| || '__|/ _` || || '_ \ | || '_ \  / _` |
  | |    | |  |  __/| (_| || | >  < | || |  | (_| || || | | || || | | || (_| |
  |_|    |_|   \___| \__,_||_|/_/\_\|_||_|   \__,_||_||_| |_||_||_| |_| \__, |
                                                                         __/ |
                                                                        |___/

EOT
}

# sad kitty
sadKitty()
{
    cat <<"EOT"

    /\ ___ /\
   (  o   o  )
    \  >#<  /
    /       \
   /         \       ^
  |           |     //
   \         /    //
    ///  ///   --

EOT
echo ""
exit 1
}

output()
{
	cf env $app_name >> environment.txt
  cat <<EOF >./Analytic_Advance.txt
Hello Predix App Name      :  "$app_name"
UAA Name                   :  "$uaaname"
UAA URI                    :  "$uaa_uri"
UAA Admin Secret           :  admin_secret
Client Name                :  "$clientname"
Client Secret              :  secret
Asset Name                 :  "$assetname"
Timeseries Name            :  "$timeseriesname"
Analytics Name             :  "$analyticsname"
ACS Name                   :  "$acsname"
App Admin User Name        :  app_admin
App Admin User Password    :  app_admin
App User Name              :  app_user
App User Password          :  app_user
EOF
 echo ""
 echo "A AnalyticStandlone.txt file with all your environment details is created"
 echo "Your services are now set up!"
}

main "$@"
