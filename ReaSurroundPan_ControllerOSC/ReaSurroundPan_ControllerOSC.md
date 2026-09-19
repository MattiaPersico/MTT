# ReaSurroundPan_ControllerOSC — Notes

## What it is

A script that listens for OSC messages from an external hardware controller (a device with X, Y, and Touch axes) and uses them to control ReaSurroundPan on selected tracks. When the controller sends a touch message, values are applied directly to the pan parameters; when not touched, values are sent back to the controller via OSC, enabling bidirectional sync between the hardware knob/screen and REAPER.

## Ruled out
