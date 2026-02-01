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

function Help() {
cat <<EOD
Usage: $0 -n <name> -d [<description>] -f <folder_name> -r [<rcon_password>] -w
Set up Minecraft servers using systemd.

  -n, --name                  Unit name
  -d, --description           Unit description (OPTIONAL)
  -f, --folder                Folder name following '${base_working_dir}' containing your server files
  -r, --rcon-password         Rcon password, default is random (OPTIONAL)
  -w, --whitelist             Flag representing use of server whitelist (OPTIONAL)
  -o, --output-final-unit     Print the contents of the created systemd unit
  -h, --help                  Display this help and exit

Code and revisions <https://github.com/nitrate92/mcctl>
EOD
}

# DEFAULTS
base_working_dir="/opt/minecraft"
server_port="25565"
rcon_client="${base_working_dir}/common/mcrcon-0.7.2-linux-x86-64/mcrcon"
rcon_port="25575"
whitelist_enable="false"

VALID_ARGS=$(getopt -o n:p:d:f:r:P:woh --long name:,server-port:,description:,folder:,rcon-password:,rcon-port:,whitelist,output-final-unit,help -- "$@")
if [[ $? -ne 0 ]]; then
    Help
    exit 0
fi

eval set -- "$VALID_ARGS"
while [ : ]; do
  case "$1" in
    -n | --name)
        name=$2
        shift 2
        ;;
    -p | --server-port)
        server_port=$2
        shift 2
        ;;
    -d | --description)
        desc=$2
        shift 2
        ;;
    -f | --folder)
        folder=$2
        shift 2
        ;;
    -r | --rcon-password)
        rcon_password=$2
        shift 2
        ;;
    -P | --rcon-port)
        rcon_port=$2
        shift 2
        ;;
    -w | --whitelist)
        whitelist="true"
        shift
        ;;
    -o | --output-final-unit)
        output_final_unit="true"
        shift
        ;;
    -h | --help)
        Help
        exit 0
        shift
        ;;
    --) shift;
        break
        ;;
  esac
done

# Make sure we can do this thing, these must come in order of importance
if [[ $(ps --no-headers -o comm 1) != "systemd" ]]; then
    echo "Error: Could not determine if systemd is present on this system."
    exit 1
elif [[ ! -e $rcon_client ]]; then
    echo "Error: Rcon client not found at '${rcon_client}'."
    exit 1
elif [[ $name && $folder ]]; then
    echo "mcctl engaged!"

    # Add self to /usr/sbin for convenience
    sbin="/usr/sbin/$(basename "$0" | cut -d "." -f 1)"
    if [ ! -L $sbin ]; then
        printf "Allowing use from /usr/sbin: '%s'\n" "$sbin"
        ln -s "$(realpath "$0")" "$sbin"
    fi

    # Are services already running?
    active_instance=$(systemctl list-units --type=service --state=running,active | grep -o "minecraft-.*\.service" | awk '{print $1}')
    active_instance_sole_name=$(echo $active_instance | cut -d "-" -f 2 | cut -d "." -f 1)

    # If we don't specify anything, just randomly generate one.
    if [[ ! $rcon_password ]]; then
        rcon_password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13; echo)
    fi

    # Make sure our base directory belongs to "minecraft" for security reasons
    if ! id "minecraft" >/dev/null 2>&1; then
        echo "Creating user 'minecraft'."
        useradd minecraft
        passwd minecraft
    fi

    # stat can do this too, but this is consistent across more platforms
    if [[ $(ls -ld "$base_working_dir" | awk '{print $3":"$4}') != "minecraft:minecraft" ]]; then
        echo "User and group 'minecraft' is taking ownership of '$base_working_dir'"
        chown -R minecraft:minecraft "$base_working_dir"
    fi

    # Conveniently pull any one value from server.properties
    function GetServerProperty() {
        # $1 = property (i.e. server-port)
        # $2 = particular server folder
        grep "$1" "$base_working_dir/$2/server.properties" | cut -d "=" -f 2
    }

    # Check for existence of systemd service, create it if nonexistent.
    service_file=/etc/systemd/system/minecraft-"$name".service
    if [[ ! -e $service_file ]]; then
        printf "Do I have to follow you all day?\nTouching '%s'\n" "$service_file"
        touch "$service_file"
    fi

    # Which server instance are we working with?
    working_dir="${base_working_dir}/${folder}"

    # Which script should we pick to run the server? We'll try to determine this automatically.
    # TODO: MAKE CONFIGURABLE
    run_script=$(find "$working_dir" -regextype sed -iregex ".*\(start|server|run\)*\.sh" | head -1)

    # Write out our systemd unit. This will run our Minecraft instance as the 'minecraft' user!
    echo "Writing '${service_file}'..."
    cat >"$service_file" <<EOF
[Unit]
Description=${desc}
After=network-online.target

[Service]
Type=Simple
SuccessExitStatus=0 1
ExecStart=bash ${run_script}
ExecStop=bash -c '${rcon_client} -p ${rcon_password} -P ${rcon_port} stop'
WorkingDirectory=${working_dir}
Restart=on-failure
User=minecraft
Group=minecraft

[Install]
WantedBy=network-online.target
EOF

    if [[ $output_final_unit = "true" ]]; then
        printf "\n$(cat "$service_file")\n\n"
    fi

    # Agree to the EULA
    if [[ -e "$working_dir/eula.txt" ]]; then
        echo "Agreeing to Mojang's EULA..."
        sed -i -r "s/^eula=.*/eula=true/g;" "$working_dir/eula.txt"
    fi

    # Set up server.properties
    if [[ -e "$working_dir/server.properties" ]]; then
        echo "Configuring server..."
        cp "$working_dir/server.properties" "$working_dir/server.properties.bak"
        # TODO: Handle existence of config without existence of the properties we want to modify
        sed -i -r "s/^enable-rcon=.*/enable-rcon=true/g; s/^enforce-whitelist=.*/enforce-whitelist=${whitelist_enable}/g; s/^rcon\.password=.*/rcon\.password=${rcon_password}/g; s/^rcon\.port=.*/rcon\.port=${rcon_port}/g; s/^white-list=.*/white-list=${whitelist_enable}/g;" "$working_dir/server.properties"
    else
        echo "Error: '$working_dir/server.properties' was not found."
        exit 1
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
    elif [[ $(GetServerProperty "server-port" "$active_instance_sole_name") = "$server_port" ]]; then
        echo "Port '$server_port' is conflicting with another running instance of Minecraft '$active_instance'. It is being disabled and stopped in favor of '$name_fmt'."
        systemctl disable "minecraft-$active_instance" && systemctl stop "minecraft-$active_instance"
    elif [[ $(netstat -putln | grep ":$server_port" | awk '{print $7}') ]]; then
        printf "Error: Port '%s' is conflicting with running process(es):\n\t$(netstat -putln | grep ":$server_port" | awk '{print $7}')\nPlease stop the conflicting processes, or change 'server-port'.\n" "$server_port"
        exit 1
    else
        systemctl enable "$name_fmt" && systemctl start "$name_fmt"
    fi

    exit 0
else
    Help
fi
