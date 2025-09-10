# Ports
- `{verilog} clk` => System Clock (free running)
- `{verilog} rst` => Active-high Sync Reset
## Start Side (Phy to DUT)
- `{verilog} start_valid` => **request**: "I have a start for this `start_id` now" (Hold until Handshake)
- `{verilog} start_ready` => **permission**: "DUT can accept that start this cycle" (Comb. out of DUT)
- `{verilog} start_id[ID_W-1:0]` => ID for this start request,valid cycle where `{verilog} start_valid` is 1
## End Side (Parser to DUT)
- `{verilog} end_valid` => **request**: "I have an end for this `end_id` now" (Hold until Handshake)
- `{verilog} end_ready` => **permission:** "DUT can accept the end this cycle" (Comb. out of DUT)
- `{verilog} end_id[ID_W-1:0]` => ID for this end request. Valid when `{verilog} end_valid` is 1

**Handshake rule (applies to both start & end):** a transfer “**fires**” in a cycle iff `{verilog} valid && ready` are **both 1**.
# Result side (DUT to UART)
- `{verilog} out_valid` => "There's a completed measurment this cycle" (Pulse after end fires)
- `{verilog} out_ready` => consumer's (UART) permission: "I can take a result this cycle"
- `{verilog} out_id[ID_W-1:0]` => ID of completed event
- `{verilog} out_start_ts[TS_W-1:0]` => Timestamp captured at start of counting for that ID
- `{verilog} out_end_ts[TS_W-1:0]` => Timestamp captured at start of counting for that ID
- `{verilog} out_delta[TS_w-1:0]` => `out_end_ts - out_start_ts` % 2^TS_W
# Internal Signals
## Counter
- `cnt_q[TS_W-1:0]` => Free running timestamp counter (increments every clk)
## Scoreboard Memories (functional Version w/ Arrays)
- `{verilog} start_ts_mem[DEPTH]` => per-ID stored start timestamp (written on start, read on end)
- `{verilog} valid_mem[DEPTH]` => per-ID **in-use flag**
	- `0` -> This ID is inactive (no existing start)
	- `1` -> This ID is **active** (start happened, awaiting end)
## Lookups (Comb Reads of Scoreboard)
- `{verilog} assign valid_at_start = valid_mem[start_id]` => "Is this `start_id` already active?"
	- blocks double starts
- `{verilog} assign valid_at_end = valid_mem[start_id]` => "Was there a start for this `{verilog}end_id`?"
	- Blocks an end without a start
## Collision Detection (Hazards)
- `{verilog}hazard_same_id = start_valid && end_valid && (start_id == end_id)` => Both sides are trying to operate on the **same ID in the same cycle**
## Ready Logic (Minimal Version)
- `{verilog}end_ready = valid_at_end && out_ready` => Only finish an ID if it is active AND the consumer can accept a result
- `{verilog}end_may_fire = end_valid && end_ready` => Check if the end will actually handshake this cycle
- `{verilog}start_ready = (!valid_at_start) && !(hazard_same_id && end_may_fire)` => Accept a start iff the ID is not already active AND  the end is not about to fire for the ID
## Handshake Events
- `{verilog}start_fire = start_valid && start_ready` => Trigger to write start timestamp and mark the ID active
- `{verilog}end_fire = end_valid && end_ready` => Trigger to read start timestamp, capture end timestamp, clear the ID from RAM, and pipeline a result
