#!/bin/bash

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "Please run as root."
    exit
fi

# Make sure root still knows who we are
if [[ $(/usr/bin/id -u) = 0 ]]; then
    USER=$SUDO_USER
    HOME=$(eval echo ~"$USER")
fi

# You can change these to suit your needs
base_working_dir="${HOME}/minecraft"
rcon_client="${base_working_dir}/common/mcrcon-0.7.2-linux-x86-64/mcrcon"

function Help() {
    echo "usage: $0 -n <name> -d <description> -f <folder_name> -r [<rcon_password>]"
    echo "  -n      String representing the unit name"
    echo "  -d      String representing the unit description"
    echo "  -f      String representing the folder name following '${base_working_dir}' containing your server files"
    echo "  -r      String representing an rcon password (OPTIONAL)"
    echo "  -h      Display this help menu"
}

while getopts ":n:d:f:r:h" option; do
    case $option in
    n)
        name=$OPTARG
        ;;
    d)
        desc=$OPTARG
        ;;
    f)
        folder=$OPTARG
        ;;
    r)
        rcon_password=$OPTARG
        ;;
    h)
        Help
        exit
        ;;
    \?)
        echo "Error: Invalid option"
        exit
        ;;
    esac
done

# Ensure required arguments have been passed
if [[ $name && $desc && $folder ]]; then
    active_instance=$(systemctl list-units --type=service --state=running,active | grep -o "minecraft-.*\.service")

    echo "mcctl engaged!"

    # Add self to /usr/sbin for convenience
    sbin="/usr/sbin/$0"
    if [[ ! -e $sbin ]]; then
        printf "Allowing use from /usr/sbin: '%s'\n" "$sbin"
        ln -s "$(dirname -- "$(readlink -f -- "$0")")" "$sbin"
    fi

    # Which server instance are we working with?
    working_dir="${base_working_dir}/${folder}"
    run_script=$(find "$working_dir" -regextype sed -iregex ".*\(start|server|run\)*\.sh" | head -1)

    function GetServerProperty() {
        # $1 = property (i.e. server-port)
        echo grep "$1" "$base_working_dir/$2/server.properties" | cut -d "=" -f 2
    }

    # Default rcon password
    if [[ ! $rcon_password ]]; then
        rcon_password="DeditatedWAM69"
    fi

    # Check for existence of systemd service
    service_file=/etc/systemd/system/minecraft-"$name".service
    if [[ ! -e $service_file ]]; then
        printf "Do I have to follow you all day?\nTouching '%s'\n" "$service_file"
        touch "$service_file"
    fi

    echo "Writing ${service_file}..."
    cat >"$service_file" <<EOF
[Unit]
Description=${desc}
After=network-online.target

[Service]
Type=Simple
SuccessExitStatus=0 1
ExecStart=bash ${run_script}
ExecStop=bash -c '../common/mcrcon-0.7.2-linux-x86-64/mcrcon -p ${rcon_password} stop'
WorkingDirectory=${working_dir}
Restart=on-failure
User=${USER}
Group=$(/usr/bin/id -g "${USER}")

[Install]
WantedBy=network-online.target
EOF

    # Make sure the server config exists before we try playing with it
    if [[ -e "$working_dir/server.properties" ]]; then
        cp "$working_dir/server.properties" "$working_dir/server.properties.bak"
        sed -i -r "s/^enable-rcon=.*/enable-rcon=true/g ; s/^enforce-whitelist=.*/enforce-whitelist=true/g; s/^rcon\.password=.*/rcon\.password=${rcon_password}/g ; s/^white-list=.*/white-list=true/g;" "$working_dir/server.properties"
    fi

    # Let's get this over with
    systemctl daemon-reload
    # If we're updating an existing service that's running, just restart it. If not, enable the service, then start it.
    if [[ $active_instance = "minecraft-$name.service" ]]; then
        systemctl restart "minecraft-$name.service"
    else
        # Disable and shut down another server if it conflicts with the port used by this instance
        if [[ $(GetServerProperty "server-port" "$($active_instance | cut -d "." -f 1)") = $(GetServerProperty "server-port" "$name") ]]; then
            systemctl disable "minecraft-$active_instance" && systemctl stop "minecraft-$active_instance"
        fi
        systemctl enable "minecraft-$name.service" && systemctl start "minecraft-$name.service"
    fi

    exit 0
elif [[ ! -e $rcon_client ]]; then
    echo "Error: Rcon client not found at '${rcon_client}'"
else
    Help
fi