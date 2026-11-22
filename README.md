# Ender 3 Klipper configuration

For an Ender 3 with a Creality V4.2.7 board, Sprite direct drive, KevinAkaSam belt-driven Z, and BLTouch. Klipper opens the tracked `~/printer_data/config/ender3/printer.cfg` directly. It includes `macros.cfg`. Git holds the hardware settings, BLTouch Z offset, both sets of heater PID coefficients, and macros. Klipper generates a fresh adaptive bed mesh at the start of each print.

If you installed an earlier release, stage this release separately and switch the Klipper service to the new entry point during cutover. Wait to update the existing Moonraker checkout until the cutover.

## 1. Confirm hardware and prepare GitHub

Use the running config and machine as references. Some items may differ on a modified Ender 3 even when the board model matches.

| Check | Where and what to confirm |
| --- | --- |
| MCU | Run `ls -l /dev/serial/by-id/` on the Pi. Use the existing working device path. Use `/dev/serial/by-path/` if the bridge has no unique ID. Verify the chip marking, firmware protocol and transport against the current setup. Upstream's V4.2.7 example uses STM32F103, a 28 KiB bootloader and USART1 over the board's USB-to-serial bridge. Keep the working firmware. Enter the device path under `[mcu]`. |
| X and Y | Confirm motor directions, endstop states, switches at the configured origins, travel limits with the Sprite installed, and 40 mm rotation distance for stock 20-tooth GT2 X/Y pulleys. Adjust any origin or direction that differs. |
| Belted Z | Confirm motor wiring and direction, motor step angle, microsteps, pulley tooth counts, belt pitch, and collision-free Z limits. For a simple reduction with a moving belt driven by an output pulley, effective Z travel per motor turn is belt pitch × output pulley teeth × motor reduction pulley teeth ÷ driven reduction pulley teeth. Confirm the formula matches your exact belt routing and measure actual travel. This file expects the effective distance in `rotation_distance` with no Z `gear_ratio`. |
| Sprite | Confirm extrusion direction, motor step angle, nozzle diameter, gearbox ratio and calibrated distance. The upstream S1 config uses `42:12` with `26.359` mm. Use that pair only if applicable. A previously calibrated effective distance with no ratio can be represented with `gear_ratio: 1:1`. |
| BLTouch | Trace both signal wires and confirm connector pin order, 5 V and ground, pull-up and polarity. Dedicated probe header signals are normally `^PB0` and `PB1`. If the sensor lead uses the original Z-stop header, verify the actual input, normally `^PA7`. The Z endstop is `probe:z_virtual_endstop`. Verify deploy, stow and trigger with Z safely away from the bed. |
| Probe reach | Measure signed probe XY offsets from the nozzle. Set `home_xy_position` in nozzle coordinates so the probe is over the bed. Set mesh bounds in probe coordinates. For each mesh corner, subtract the probe offsets to obtain the nozzle coordinates and verify those are within actual axis travel. Verify clearance for `z_hop` and `horizontal_move_z`. The mesh move height must exceed the probe Z offset. |
| Heaters and fans | Verify sensor models, wiring, rated temperatures for the actual hotend and bed, and any separate heatsink fan wiring. Confirm that both readings are plausible at room temperature and respond to the correct component before commanding heat. Confirm that the part fan and hotend cooling work. |

Record the confirmed fixed settings in the tracked `printer.cfg` and merge them into `main`. Before installation, also review the existing `printer.cfg` and includes for features you still use, such as filament sensors, input shaping, a display, a separate heater fan or slicer-specific macros. Port needed definitions into the Git repo. The bundled Mainsail config uses Klipper's built-in pause and resume and a cancel macro that turns off heat and part cooling. Remove duplicate definitions when porting macros. Reconfirm the slicer's start and end commands.

[Creality V4.2.7 pin map](https://github.com/Klipper3d/klipper/blob/master/config/generic-creality-v4.2.7.cfg) · [Sprite reference](https://github.com/Klipper3d/klipper/blob/master/config/printer-creality-ender3-s1-2021.cfg) · [KevinAkaSam belt conversion](https://github.com/kevinakasam/BeltDrivenEnder3) · [Rotation distance](https://www.klipper3d.org/Rotation_Distance.html) · [BLTouch checks](https://www.klipper3d.org/BLTouch.html)

Transfer the Z offset and the hotend and bed PID values from the old working configuration if the hardware and probe geometry still match. Look for them at the end of the old `printer.cfg` under `SAVE_CONFIG`. If a heater currently uses `control: watermark`, carry that verified setting over and remove its three PID placeholders until you tune it. Use a verified Z offset before commissioning. Leave all mesh profile sections out of the tracked file.

## 2. Stage and install

Run Pi commands as the account that runs Klipper and Moonraker. Check the service accounts and launch settings with `systemctl show klipper moonraker -p User` and `systemctl cat klipper moonraker`. The scripts expect the standard single-instance service names and data directory. This public repository supports anonymous HTTPS.

```bash
GIT_TERMINAL_PROMPT=0 git ls-remote https://github.com/lazytesting/klipper-chart.git refs/heads/main
git clone https://github.com/lazytesting/klipper-chart.git ~/ender3-bootstrap
~/ender3-bootstrap/scripts/install.sh stage
```

Review the staged `printer.cfg` and macros against your existing config. The installer refuses to apply a checkout with unresolved hardware or calibration placeholders. Before cutover, back up the existing `~/printer_data/config` and `~/printer_data/systemd` off the Pi. Include any custom service files and the targets of external symlinks. Inspect and approve the staged files before applying.

When the printer is idle and cold, set `STAGE` to the printed stage path. The installer archives the old config and service environment before placing the new Git checkout.

```bash
sudo systemctl stop moonraker klipper &&
    ~/ender3-bootstrap/scripts/install.sh apply "$STAGE"
```

While the services are stopped, make the following changes.

1. In the configuration used by the Klipper service, change the positional config-file argument from the old path to the **absolute** path of `~/printer_data/config/ender3/printer.cfg`. On a typical MainsailOS or KIAUH setup, `systemctl cat klipper` shows an `EnvironmentFile` under `~/printer_data/systemd/` with a `KLIPPER_ARGS` or `KLIPPY_ARGS` variable. Edit only the printer config argument and keep the Python, log, and socket paths. If your unit specifies `ExecStart` directly, use a systemd override with the same command and updated config path, then run `sudo systemctl daemon-reload`.
2. Add this section to the existing `moonraker.conf`. If it already defines an Ender 3 updater through an include, replace that definition so there is exactly one. Use the same `origin` as the clone.

   ```ini
   [update_manager ender3]
   type: git_repo
   channel: dev
   path: ~/printer_data/config/ender3
   origin: https://github.com/lazytesting/klipper-chart.git
   primary_branch: main
   is_system_service: False
   ```

3. If the slicer outputs object labels without Klipper polygon definitions, set `enable_object_processing: True` under Moonraker's existing `[file_manager]` section, or create that section if absent. This processes new uploads. Re-upload files sliced before the change. [Moonraker object processing](https://moonraker.readthedocs.io/en/latest/configuration/#file_manager)

Start both services with `sudo systemctl start klipper moonraker`. Check that Klipper reports Ready, the log shows the new config path, and Mainsail lists the `ender3` updater. Before homing or heating, verify cold temperature readings, motor directions, endstop states, BLTouch deploy/stow and trigger, and fan operation. On the first Z home, manually trigger the deployed probe well above the bed and confirm Z stops. [Klipper configuration checks](https://www.klipper3d.org/Config_checks.html) · [BLTouch initial tests](https://www.klipper3d.org/BLTouch.html#initial-tests)

## 3. Adaptive mesh at print start

Enable object labeling in the slicer and ensure the uploaded file has `EXCLUDE_OBJECT_DEFINE` commands with `POLYGON=` **before** the print-start macro runs. The repository enables `[exclude_object]`. In your existing slicer start G-code or print-start macro, call:

```gcode
ADAPTIVE_MESH
```

Place the call after the bed reaches printing temperature and after `G28`, before priming or printing. Replace any saved-profile load or full-bed probing step in that sequence. `ADAPTIVE_MESH` requires object polygons, clears the active mesh, and calls `BED_MESH_CALIBRATE ADAPTIVE=1`. Klipper adds the configured 5 mm margin within the verified mesh bounds. Set the margin in `printer.cfg` to suit your slicer's skirt or brim. The mesh serves the current print without saving a profile.

For the first test, slice and re-upload a small centered object. Verify its polygon occurs before the macro call and check the console for adapted mesh bounds and probe count. If the macro reports missing polygons, fix the slicer labeling or Moonraker processing before retrying. [Klipper adaptive meshes](https://www.klipper3d.org/Bed_Mesh.html#adaptive-meshes) · [Klipper object definitions](https://www.klipper3d.org/Exclude_Object.html#object-definitions)

## 4. Save persistent calibration changes in Git

After a hardware change, use `PROBE_CALIBRATE`, `TESTZ`, and `ACCEPT` for the BLTouch. Use `PID_CALIBRATE HEATER=extruder TARGET=<verified-temperature>` and `PID_CALIBRATE HEATER=heater_bed TARGET=<verified-temperature>` for the heaters that need tuning. Use numeric targets appropriate for the hardware. `SAVE_CONFIG` writes to the tracked `printer.cfg` and restarts Klipper. [Klipper probe calibration](https://www.klipper3d.org/Probe_Calibrate.html)

After saving, review the diff and export it outside the checkout.

```bash
git -C ~/printer_data/config/ender3 diff -- printer.cfg
git -C ~/printer_data/config/ender3 diff -- printer.cfg > ~/ender3-calibration.patch
```

Copy the patch to a workstation with a writable checkout at the same commit. Apply it with `git apply ender3-calibration.patch`, review that it only changes the intended Z offset and PID values, then commit and merge it into `main`. Klipper's generated `#*#` block can be committed as written. Keep hardware values and calibration in this tracked file and keep saved mesh profiles out of the commit.

Once the calibration commit is on GitHub, verify the Pi diff is the saved calibration update, run `git -C ~/printer_data/config/ender3 restore -- printer.cfg` to clear that local diff, then pull the committed version through Mainsail's Update Manager. Confirm the checkout is clean before issuing `RESTART` in Klipper. The Pi's usual Git access remains read-only.

## 5. Update and recover

Merge changes into `main` and use the `ender3` entry in Mainsail's Update Manager while the printer is idle. Review the updated files and issue `RESTART` in Klipper when ready to load them. To undo a bad change, revert it in GitHub and update again. [Moonraker Git updates](https://moonraker.readthedocs.io/en/latest/configuration/#git-repo-configuration)

For SD card recovery, reinstall Klipper, Moonraker, and Mainsail. Restore the host service setup and Moonraker settings from your off-Pi system backup or recreate them using the install steps. GitHub supplies all Klipper settings and committed calibration. Run the installer to stage current `main`. To stage an exact known good revision, pass its full commit SHA to `~/ender3-bootstrap/scripts/recovery.sh` and apply the printed stage using `install.sh apply`. The revision must be in the configured branch history. Repeat the physical checks before printing.

For a cutover rollback, stop both services. Restore the archived config and Klipper launch path from the printed `ender3-before.*` backup, verify the old entry points, and start both services. Keep the displaced configuration available for diagnosis.

## Optional SSH deploy key for a private repository

Use this setup if you make the repository private and want the Pi to fetch with a dedicated read-only key. Run the commands as the Moonraker service user. Clone the bootstrap checkout with the SSH URL and pass that same URL as the first argument after `install.sh stage`. Set Moonraker's `origin` to the same URL.

```bash
install -d -m 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/ender3_deploy -C 'ender3-moonraker' -N ''
cat ~/.ssh/ender3_deploy.pub
```

Use a new dedicated key. If that filename already exists, inspect it before choosing whether to reuse it or create a differently named key. In the repository's **Settings → Deploy keys → Add deploy key**, paste the public key and leave **Allow write access** unchecked. Keep the private key on the Pi. Add this host block near the top of `~/.ssh/config` before broad matching entries, then set the file to mode `600`.

```sshconfig
Host github-ender3
    HostName github.com
    User git
    IdentityFile ~/.ssh/ender3_deploy
    IdentitiesOnly yes
    BatchMode yes
    StrictHostKeyChecking yes
```

If GitHub is new to this account, collect its Ed25519 host key with `ssh-keyscan -t ed25519 github.com > /tmp/ender3-github-hostkey`. Check the output of `ssh-keygen -lf /tmp/ender3-github-hostkey` against GitHub's published Ed25519 fingerprint before appending the file to `~/.ssh/known_hosts`. Then verify access with `git ls-remote git@github-ender3:lazytesting/klipper-chart.git refs/heads/main` as the Moonraker account. The SSH alias in this command must match the clone's `origin` and Moonraker's configured `origin`.

[GitHub deploy keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys#deploy-keys) · [GitHub SSH host fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
