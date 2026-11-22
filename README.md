# Ender 3 Klipper configuration

## What’s specific to this printer

This Ender 3 uses a Creality V4.2.7 board, Sprite direct drive, KevinAkaSam belted Z, and a BLTouch for Z homing and bed meshing. `printer.cfg` holds the hardware settings, BLTouch Z offset, and both heater PID tunes. `macros.cfg` holds the Mainsail and adaptive mesh macros.

Before installation, replace every `REPLACE_…` entry in `printer.cfg` with verified values. Check the MCU device path, motor directions and travel limits, belted Z rotation distance, Sprite gearing, thermistors and temperature limits, and BLTouch wiring, offsets, and reachable mesh bounds. Carry over the Z offset and PID values from your working config if the corresponding hardware is unchanged. For a heater that already uses `control: watermark`, carry that setting over and remove its PID placeholders until you tune it.

## Sync from Mainsail

1. Back up the Pi’s current `~/printer_data/config` and Klipper service configuration off-device. Commit your verified settings to GitHub. With the printer idle and cold, run `sudo systemctl stop klipper moonraker`. Move any existing `ender3` checkout aside, then clone as the Moonraker service user.

   ```bash
   git clone https://github.com/lazytesting/klipper-chart.git ~/printer_data/config/ender3
   ```

2. Use `systemctl cat klipper` to find the service’s launch arguments or environment file. Change the config argument to the **absolute path** of `~/printer_data/config/ender3/printer.cfg`. Keep the existing log and socket arguments. Run `sudo systemctl daemon-reload` if you changed the unit or a drop-in.
3. Add this section once to the existing `moonraker.conf`, or replace the existing `[update_manager ender3]` definition.

   ```ini
   [update_manager ender3]
   type: git_repo
   channel: dev
   path: ~/printer_data/config/ender3
   origin: https://github.com/lazytesting/klipper-chart.git
   primary_branch: main
   is_system_service: False
   ```

4. Run `sudo systemctl start klipper moonraker`. For subsequent changes, merge to `main`, open **Machine → Update Manager** in Mainsail, refresh and update `ender3`, then run `RESTART` in the Klipper console when the printer is idle. [Moonraker Update Manager](https://moonraker.readthedocs.io/en/latest/configuration/#git-repo-configuration)

## Check that it works

- **Startup and sync.** Mainsail should show Klipper as Ready and list `ender3` under Update Manager. Check `~/printer_data/logs/klippy.log` for the new config path if in doubt. `git -C ~/printer_data/config/ender3 status --short` should be empty after a normal update.
- **Before homing.** Verify plausible room-temperature readings for both heaters. With clearance, check X/Y switches with `QUERY_ENDSTOPS` and axis directions with `STEPPER_BUZZ STEPPER=stepper_x` (repeat with `stepper_y` and `stepper_z`). Test BLTouch deploy, stow, and trigger. On the first Z home, manually trigger the deployed pin well above the bed and check that Z stops. [Klipper configuration checks](https://www.klipper3d.org/Config_checks.html) · [BLTouch initial tests](https://www.klipper3d.org/BLTouch.html#initial-tests)
- **Before PID tuning.** Verify hotend cooling and test each heater separately while watching that the corresponding temperature rises. [Klipper heater checks](https://www.klipper3d.org/Config_checks.html#verify-heaters)

## Run the calibrations

- **BLTouch Z offset.** Home with `G28`, run `PROBE_CALIBRATE`, use `TESTZ` to set the nozzle height, and finish with `ACCEPT`. [Klipper probe calibration](https://www.klipper3d.org/Probe_Calibrate.html)
- **Hotend and bed PID.** Run `PID_CALIBRATE HEATER=extruder TARGET=<hotend temperature>` and `PID_CALIBRATE HEATER=heater_bed TARGET=<bed temperature>` separately. Use your usual printing temperatures within the verified heater limits. [Klipper PID tuning](https://www.klipper3d.org/Config_checks.html#calibrate-pid-settings)
- **Adaptive bed mesh.** Enable slicer object labeling. The uploaded G-code must contain `EXCLUDE_OBJECT_DEFINE` with `POLYGON=` before `ADAPTIVE_MESH` runs. If the slicer emits labels only, set `enable_object_processing: True` in Moonraker’s `[file_manager]` section and re-upload the file. Call `ADAPTIVE_MESH` in your print-start sequence after the bed reaches print temperature and after `G28`, before priming. Remove any saved-profile load from that sequence. Test a small centered print and check the console for adapted bounds and probe count. The mesh is used for that print and needs no `SAVE_CONFIG`. [Klipper adaptive meshes](https://www.klipper3d.org/Bed_Mesh.html#adaptive-meshes) · [Moonraker object processing](https://moonraker.readthedocs.io/en/latest/configuration/#file_manager)

After tuning Z offset or PID, run `SAVE_CONFIG` in the console. Klipper restarts and writes the results to the tracked `printer.cfg`. Review the diff, copy it to your writable checkout, and commit the calibration changes to GitHub. Once the commit is on `main`, verify the Pi’s diff contains only the exported calibration, then run `git -C ~/printer_data/config/ender3 restore -- printer.cfg` and update through Mainsail. This keeps the Pi checkout clean and lets GitHub restore the calibration after an SD card failure.
