# Observe reroll network traffic

Follow-up: [reseed transport investigation](NETWORK_RESEED_PATH.md) recovered
an in-memory local-recipient branch and verified its identity condition in the
live solo session. This strengthens the path-specific findings without proving
absence of all server effects.

This external Windows network-layer collector does not attach to the game's
process, install hooks, change game memory, decrypt TLS, or modify networking.
No addon update is required. Windows Packet Monitor needs an Administrator
PowerShell session; Codex's current shell is not elevated.

## Run the experiment

1. Keep the game running alone on your ship, with the combined reroller loaded.
   Select a planet. Choose two mission requirements in the dialog, but do not
   start searching yet. Avoid unrelated downloads or browsing during the test.
2. Open **PowerShell as Administrator** and run:

   ```powershell
   & '<repo>\scripts\capture_network.ps1'
   ```

3. Press Enter at the ready prompt and return to the game. Leave it idle for
   the 30-second baseline. At the high beep, start your search. At the low beep,
   60 seconds later, cancel searching and leave the map idle for 30 seconds.
   A successful match may stop searching earlier; the mod log records how many
   calls actually occurred. A run with zero calls cannot test the hypothesis.
4. The script stops capture and prints its output folder under
   `MissionReroller/artifacts/network/`. Send the agent that folder path.

If another Packet Monitor session or filters are present, the script refuses
to take them over. It never removes existing filters. Unrecognized localized
filter output also stops the script; preserve the output for diagnosis.
If interrupted, `finally` attempts to stop its own capture. If the PowerShell
process is forcibly terminated, inspect `pktmon status` and stop the capture
you started using `pktmon stop`. Do not stop another user's capture.

## What is collected

- Packet Monitor ETL and converted pcapng segments from all NICs, containing
  the first 128 bytes per packet. This includes headers and sometimes a small
  payload prefix from **other applications**, not just the game.
- Periodic TCP/UDP socket tables with process IDs; the game PID/start time.
- New reroller log lines with UTC observation intervals. These times are when
  the collector reads each line, not exact timestamps of native execution.
- Phase boundaries, DNS-cache snapshots, adapter inventory and Packet Monitor
  diagnostics. DNS snapshots are optional if Windows cannot expose them.

Files remain local and are under ignored `artifacts/`, outside release ZIPs.
Multi-file logging preserves earlier segments instead of overwriting them.
Packet Monitor documentation: [capture options](https://learn.microsoft.com/windows-server/administration/windows-commands/pktmon-start).

## Analyze

```powershell
python -B `
  '<repo>\scripts\analyze_network.py' `
  '<capture-directory>'
```

The standard-library-only analyzer writes `report.md`, `flows.csv`, and
`reroll-windows.json`. It parses Ethernet/raw IPv4/IPv6 TCP/UDP headers and
reports unsupported/truncated packets. It uses sampled socket tuples to mark
game *candidates*, not definitive packet-level ownership. All endpoint owners
remain unclassified. A shared cloud IP or DNS hint does not establish an
official service. TCP payload byte counts exclude TCP/IP headers; all counts
are observations, potentially duplicated by NIC capture/offload.

If a run fails before conversion, retain its ETL and diagnostics. Convert each
segment explicitly using `pktmon etl2pcap <file.etl> --out <file.pcapng>`.
Do not analyze both a combined capture and its duplicate segments together.

## What this can establish

We can check whether traffic associated with sampled game sockets appears
during and around logged reseeds, and compare it with idle windows. Traffic on
an existing connection matters too; counting new connections alone is inadequate.

This cannot prove the absence of official-server requests. Short-lived sockets,
shared UDP ports, Steam/proxy traffic, unsupported packets, missing adapters,
packet loss and encrypted multiplexed connections limit inference. Baseline
traffic can continue while rerolling. A packet near a call does not prove that
call caused it, and a quiet capture is only a bounded observation.

The report therefore always labels the official-server question inconclusive.
After inspecting capture quality, repeated controlled comparisons and endpoint
evidence, we can state narrower supported findings. Determining exact requests
would require additional tracing of the game's native dispatch path; this
collector does not invent HTTP contents or claim TLS decryption.
