# Troubleshooting log

Problems I ran into while building and moving services in the lab. Each entry: symptom, cause, fix, and what I took from it.

## 1. Docker host could not reach the NAS or Jellyfin

**Symptom.** After moving the media stack to the CI runner laptop, an NFS mount of the NAS hung. Ping to every address on the home network failed, including the gateway, while internet access and inbound SSH worked.

**Cause.** The laptop's own hardening. An `nftables` table drops every outgoing connection to private address ranges, so CI jobs cannot touch the home network. `iptables -S` and `ufw status` showed nothing, because the rules live in a separate `inet` table. `nft list ruleset` showed it at once.

**Fix.** Kept the isolation and added two narrow accept rules ahead of the drop: one TCP port to the NAS for NFSv4, one to Jellyfin. The rules were added to the script that generates the table, not to the live table, because a timer reloads the table every minute.

**Lesson.** Check `nft list ruleset`, not only `iptables` and `ufw`. A rule set that heals itself has to be changed at its source.

## 2. VPN port forwarding hook answered 403

**Symptom.** Gluetun received a forwarded port from the VPN provider, but its hook that sets the port in qBittorrent failed with `403 Forbidden`.

**Cause.** Two things. qBittorrent requires a login even from localhost by default. And in qBittorrent 5.3 the setting that turns that off is read from the `[WebUI]` section of the config file, while most guides still place it under `[Preferences]`, where it is silently ignored.

**Fix.** Stopped the container, set `LocalHostAuth=false` under `[WebUI]`, started it again. Verified by reading the preferences back through the API: listening port equal to the forwarded port, bound to the VPN interface.

**Lesson.** When a setting has no effect, check where the running version actually stores it. Verify through the API, not by trusting the file.

## 3. SSH: `Permission denied (publickey)` with the right key

**Symptom.** Key-based login to the laptop failed, although the key had been installed weeks earlier.

**Cause.** Wrong username. `known_hosts` on the workstation showed the host had been reached before, on the same day the key was created, so the key was fine and the account name had to be the variable.

**Fix.** Found the real account name in my own earlier notes. No guessing: repeated failed logins against a hardened host only risk a lockout.

**Lesson.** `Permission denied (publickey)` does not say which half is wrong. Use what the client already knows (`known_hosts`, `ssh -v`) to narrow it down before changing anything on the server.

## 4. Library import skipped films that clearly existed

**Symptom.** Radarr imported 110 of about 125 films. A trilogy that played fine in Jellyfin was missing.

**Cause.** Radarr expects one film per folder. The trilogy sat in one parent folder, and eight other films were loose files directly in the library root. Jellyfin tolerates both. A first search for the folder also missed it because the glob was case sensitive.

**Fix.** A small Python script against the Radarr API: look each film up by its database id, assert that title and year match, create a `Title (Year)` folder, move the video with its sidecar files using `mv -n`, then trigger a rescan and print which films now have a file. Nothing is overwritten or deleted except folders that are empty afterwards.

**Lesson.** Assert before moving files. Search case-insensitively. Report the result from the application's point of view, not from the file system's.

## 5. Series lookups timed out during import

**Symptom.** Sonarr's library import page spun for over an hour.

**Cause.** Not local. DNS answered in milliseconds and the container had a working route. Timing the metadata service directly with `curl` showed most requests getting no response within 60 seconds while a few returned in about one second.

**Fix.** Stopped retrying and scheduled the import for later, with a script that retries per folder and shows the matches before saving.

**Lesson.** Measure each layer separately (DNS, route, remote service) before changing local configuration. Sometimes the correct fix is to wait.

## 6. Disk failure and a partly lost library

**Symptom.** After replacing a failed disk, some shows had folders but no episodes, and one file was a few megabytes instead of several gigabytes.

**Fix.** Scripted audit of the whole library: video files per folder, files far below expected size, and duplicate episodes by season and episode number across about a thousand files. Folders were only removed after confirming they held no video.

**Lesson.** A folder listing is not an inventory. Count the files that matter and check their sizes.
