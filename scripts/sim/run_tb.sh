#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [-g] [-w waves.wcfg] <tb_top>"
  echo "  -g              Open XSIM GUI"
  echo "  -w waves.wcfg   Load a saved wave layout (optional)"
  exit 1
}

GUI=0
WCFG=""
while getopts ":gw:" opt; do
  case "$opt" in
  g) GUI=1 ;;
  w) WCFG="$OPTARG" ;;
  *) usage ;;
  esac
done
shift $((OPTIND - 1))

TB_TOP="${1:-}"
[[ -z "$TB_TOP" ]] && usage

# Clean + build dirs
rm -rf xsim.dir *.wdb *.log *.jou
mkdir -p build/sim

# Compile design + TB (adjust globs if needed)
xvlog -sv $(find src/rtl -type f \( -name '*.sv' -o -name '*.v' \)) \
  $(find tb -type f \( -name '*.sv' -o -name '*.v' \))

# Elaborate with debug info so waves work
xelab "$TB_TOP" -s sim_snapshot -timescale 1ps/1ps -debug typical

if ((GUI)); then
  # GUI mode: optionally preload a .wcfg layout
  if [[ -n "$WCFG" && -f "$WCFG" ]]; then
    xsim sim_snapshot -gui -view "$WCFG"
  else
    # Open GUI and auto-log everything so the wave window populates
    # (No 'quit' so the GUI stays open)
    cat >build/sim/gui_waves.tcl <<'EOF'
log_wave -r /*
# comment out the next line if you want to press Run yourself
run -all
EOF
    xsim sim_snapshot -gui -tclbatch build/sim/gui_waves.tcl
  fi
else
  # Headless: log everything and run to completion
  cat >build/sim/headless.tcl <<'EOF'
log_wave -r /*
run -all
quit
EOF
  xsim sim_snapshot -tclbatch build/sim/headless.tcl
fi
