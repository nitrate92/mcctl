# mcctl
Minecraft server control via systemd and [mcrcon](https://github.com/Tiiffi/mcrcon). I am only testing this on Debian 13.<br>
mcctl's goal is to automate the process of creating and managing systemd units for individual Minecraft server instances.

```
usage: mcctl -n <name> -d [<description>] -f <folder_name> -r [<rcon_password>] -w
  -n      String representing the unit name
  -d      String representing the unit description (OPTIONAL)
  -f      String representing the folder name following 'base_working_dir' containing your server files
  -r      String representing an rcon password (OPTIONAL)
  -w      Flag representing use of server whitelist (OPTIONAL)
  -h      Display the help menu
```

# Recommended setup
All server instances may live in their own folders under `/opt/minecraft`

```
halen@fog-7050:/opt/minecraft$ ls -la
total 488236
drwxr-xr-x 13 minecraft minecraft      4096 Oct 19 21:00  .
drwxr-xr-x  5 root      root           4096 Oct 29 16:33  ..
drwxr-xr-x 15 minecraft minecraft      4096 Oct 31 22:03  allthepoops10
drwxr-xr-x 14 minecraft minecraft      4096 Jun 20 19:44  atm10
drwxr-xr-x 15 minecraft minecraft      4096 Jan 25  2025  atm9sky
-rw-r--r--  1 minecraft minecraft 499893476 Mar 18  2025  atm9sky.tar.gz
drwxr-xr-x 14 minecraft minecraft      4096 Sep  1 11:26  bettermc
drwxr-xr-x 15 minecraft minecraft      4096 Jun 15  2024  bettermcOldv24
drwxr-xr-x  3 minecraft minecraft      4096 Oct 29 16:34  common
drwxr-xr-x 11 minecraft minecraft      4096 Nov 29  2024 'fart shit butt ass'
drwxr-xr-x 13 minecraft minecraft      4096 Jan  5  2025 'fart shit butt ass 2'
drwxr-xr-x 11 minecraft minecraft      4096 Apr 29  2025 'not dementia'
drwxr-xr-x 11 minecraft minecraft      4096 Aug 25  2024  twilight
drwxr-xr-x 15 minecraft minecraft      4096 Jul 15 23:00  Valhelsia-6-6.2.2-SERVER
```

Your folders should include the shell script that runs the server. 

i.e.
``
run.sh
start.sh
serverstart.sh
``

mcctl is written to automatically pick up scripts following naming formats including "run", "start", and "server" for convenience.

# How?
Pass a friendly name for your unit, i.e. `blah`, as well as a folder for it to reside in with all your other Minecraft instances.<br>
Upon creation of an instance, mcctl will check for port conflicts with any other running instances and any other system processes.<br>
It will also automatically create, start, and enable a `.service` file with the appropriate configuration.

i.e.
```
[Unit]
Description=
After=network-online.target

[Service]
Type=Simple
SuccessExitStatus=0 1
ExecStart=bash /opt/minecraft/blah/run.sh
ExecStop=bash -c '/opt/minecraft/common/mcrcon-0.7.2-linux-x86-64/mcrcon -p DeditatedWAM69 -P 25575 stop'
WorkingDirectory=/opt/minecraft/blah
Restart=on-failure
User=minecraft
Group=minecraft

[Install]
WantedBy=network-online.target
```

# Why?
If you like doing stuff the CLI way, this is how I do it.

# Issues and Feature Requests
Feel free to open issues for bugs and feature requests. In its current state, this project could definitely use more configuration options. Please keep in mind that this is nothing more than something I build upon in my free time.
