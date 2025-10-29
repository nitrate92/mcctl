# mcctl
Minecraft server control via systemd. I am only testing this on Debian 13.

```
usage: mcctl -n <name> -d <description> -f <folder_name> -r [<rcon_password>]"
  -n      String representing the unit name"
  -d      String representing the unit description"
  -f      String representing the folder name following '${base_working_dir}' containing your server files"
  -r      String representing an rcon password (OPTIONAL)"
  -h      Display the help menu"
```

# Why?
If you like doing stuff the CLI way, this is it.
