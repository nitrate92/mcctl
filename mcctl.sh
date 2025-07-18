#!/bin/bash

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "Please run with root privileges."
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
    echo "usage: $0 -n <name> -d <description> -f <folder_name> -r [<rcon_password>] -w"
    echo "  -n      String representing the unit name"
    echo "  -d      String representing the unit description"
    echo "  -f      String representing the folder name following '${base_working_dir}' containing your server files"
    echo "  -r      String representing an rcon password (OPTIONAL)"
    echo "  -w      Flag representing use of server whitelist (OPTIONAL)"
    echo "  -h      Display this help menu"
}

while getopts ":n:d:f:r:w:h" option; do
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
    w)
        whitelist_enable="true"
        ;;
    h)
        Help
        exit 0
        ;;
    \?)
        echo "Error: Invalid option"
        exit 1
        ;;
    esac
done

# Ensure required arguments have been passed and we have a way to use rcon
if [[ $USER = "root" ]]; then
    echo "Error: I will not let you run a server using the root account! Please switch to a standard user account and run this with 'sudo'."
    exit 1
elif [[ $(ps --no-headers -o comm 1) != "systemd" ]]; then
    echo "Error: Could not determine if systemd is on this system."
    exit 1
elif [[ ! -e $rcon_client ]]; then
    echo "Error: Rcon client not found at '${rcon_client}'."
    exit 1
elif [[ $name && $desc && $folder ]]; then
    echo "mcctl engaged!"

    # Add self to /usr/sbin for convenience
    sbin="/usr/sbin/$(basename "$0" | cut -d "." -f 1)"
    if [[ ! -e $sbin ]]; then
        printf "Allowing use from /usr/sbin: '%s'\n" "$sbin"
        ln -s "$(realpath "$0")" "$sbin"
    fi

    # Are services already running?
    active_instance=$(systemctl list-units --type=service --state=running,active | grep -o "minecraft-.*\.service")

    # Default rcon password
    if [[ ! $rcon_password ]]; then
        rcon_password="DeditatedWAM69"
    fi

    # Default whitelist
    if [[ ! $whitelist_enable ]]; then
        whitelist_enable="false"
    fi

    # Which server instance are we working with?
    working_dir="${base_working_dir}/${folder}"
    # Which script should we pick to run the server? We'll try to determine this automatically.
    run_script=$(find "$working_dir" -regextype sed -iregex ".*\(start|server|run\)*\.sh" | head -1)

    # Conveniently pull any one value from server.properties
    function GetServerProperty() {
        # $1 = property (i.e. server-port)
        grep "$1" "$base_working_dir/$2/server.properties" | cut -d "=" -f 2
    }

    # Check for existence of systemd service, create it if nonexistent.
    service_file=/etc/systemd/system/minecraft-"$name".service
    if [[ ! -e $service_file ]]; then
        printf "Do I have to follow you all day?\nTouching '%s'\n" "$service_file"
        touch "$service_file"
    fi

    # Write out our systemd unit. This will run our Minecraft instance as the current user!
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
        sed -i -r "s/^enable-rcon=.*/enable-rcon=true/g ; s/^enforce-whitelist=.*/enforce-whitelist=${whitelist_enable}/g; s/^rcon\.password=.*/rcon\.password=${rcon_password}/g ; s/^white-list=.*/white-list=${whitelist_enable}/g;" "$working_dir/server.properties"
    fi

    # Let's get this over with
    name_fmt="minecraft-$name.service"
    server_port=$(GetServerProperty "server-port" "$name")
    systemctl daemon-reload

    # The order these conditions happen in is very important. We want to check if the running instance
    # is the same one we're working on. If not, compare the port numbers between the running instance
    # and the one we're working on. If they are the same, see if any processes are using our instance's
    # port. Finally, if all is good, enable and start the newly created instance.
    if [[ $active_instance = "$name_fmt" ]]; then
        systemctl restart "$name_fmt"
    elif [[ $(GetServerProperty "server-port" "$($active_instance | cut -d "." -f 1)") = "$server_port" ]]; then
        echo "Port '$server_port' is conflicting with another running instance of Minecraft '$active_instance'. It is being disabled and stopped in favor of '$name_fmt'."
        systemctl disable "minecraft-$active_instance" && systemctl stop "minecraft-$active_instance"
    elif [[ $(netstat -putln | grep ":$server_port" | awk '{print $7}') ]]; then
        printf "Error: Port '%s' is conflicting with running process(es):\n$(netstat -putln | grep ":$server_port" | awk '{print $7}')\nPlease stop the conflicting processes, or change 'server-port'.\n" "$server_port"
        exit 1
    else
        systemctl enable "$name_fmt" && systemctl start "$name_fmt"
    fi

    exit 0
else
    Help
fi