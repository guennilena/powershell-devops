# USB4 / Thunderbolt Health & Repair

## Overview
This module provides diagnostics and a targeted repair mechanism for
USB4 / Thunderbolt controller issues on Windows systems.

It was developed to handle a real-world issue where USB devices
disconnect under sustained isochronous load (e.g. video conferencing),
while the system itself remains responsive.

## Scope
The script intentionally targets only USB4 / Thunderbolt routing devices
to avoid unintended side effects.

Typical use cases:
- Dell XPS / Precision / Latitude systems
- Thunderbolt / USB4 docking stations
- Windows 11 systems experiencing USB bus drops under load

## What the script does
- Enumerates active USB4 / Thunderbolt routing devices
- Logs device state before and after repair
- Performs a controlled disable/enable cycle
- Captures relevant Windows Event Log entries

## What the script does NOT do
- It does not modify firmware
- It does not touch generic USB peripherals
- It does not apply undocumented registry hacks

## Requirements
- Windows 11
- PowerShell 5.1+ or PowerShell 7+
- Administrative privileges

## Disclaimer
This script is provided as a diagnostic and recovery tool.
It was validated on a Dell XPS system with a Thunderbolt dock,
but may require adaptation for other hardware setups.
