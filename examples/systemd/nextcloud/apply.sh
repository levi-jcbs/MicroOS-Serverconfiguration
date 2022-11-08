#!/bin/bash

echo "> APPLICATION"

read -p "ID der Application:           " XX
read -p "Name der Application:         " APPLICATION_NAME

echo ""
echo "> DATABASE"

read -p "Password der Datenbank:       " DATABASE_PASSWORD
read -p "Root-Password der Datenbank:  " DATABASE_ROOT_PASSWORD

echo ""
echo "> NEXTCLOUD"

read -p "Domain oder IP der Nextcloud: " NEXTCLOUD_ADDRESS
read -p "Protokoll (http/https):       " NEXTCLOUD_PROTOCOL

echo ""
read -sn1 -p "> ÄNDERUNGEN ANWENDEN? (ja/nein)" doit
echo ""

if [ "$doit" == "j" ]; then
    read -p "apply.sh löschen (ja/nein)    " remove_apply_sh
    
    # replace application name and id file names
    rename "XX_APPLICATION_NAME" "${XX}_${APPLICATION_NAME}" *.{service,timer};
    rename "XX" "${XX}" *.{service,timer};
    
    # replace application name and id in file content
    sed -i -e "s/XX_APPLICATION_NAME/${XX}_${APPLICATION_NAME}/g" *.{service,timer}
    sed -i -e "s/XX/${XX}/g" *.{service,timer}

    # replace app-specific options in file content
    sed -i -e "s/DATABASE_PASSWORD/${DATABASE_PASSWORD}/g" *.{service,timer}
    sed -i -e "s/DATABASE_ROOT_PASSWORD/${DATABASE_ROOT_PASSWORD}/g" *.{service,timer}

    sed -i -e "s/NEXTCLOUD_ADDRESS/${NEXTCLOUD_ADDRESS}/g" *.{service,timer}
    sed -i -e "s/NEXTCLOUD_PROTOCOL/${NEXTCLOUD_PROTOCOL}/g" *.{service,timer}

    if [ "$remove_apply_sh" == "ja" ]; then
	rm apply.sh
    fi
fi
