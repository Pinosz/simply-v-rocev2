# Source snapshot and reproducibility

[Back to README](../README.md)

The supplied source folder was inspected read-only while preparing this documentation. The RTL, fetch scripts, build settings, and original notes were not changed. Historical hardware observations are taken from the project notes and attached figures; this inspection is not a new FPGA build or hardware validation.

## Project scope and version history

The internship integration and hardware traffic demonstration are the scope of this repository. Subsequent transmitter experiments are unfinished and have not been included in the supplied material or in the reported results.

The file modification dates support treating the root files as the newer modular-integration candidate:

| File or document | Recorded modification date |
| --- | --- |
| Wrapper inside the Simply-V unit directory | 21 May 2026 |
| Root RoCE stack and network wrapper | 29 May 2026 |
| Root `custom_top_wrapper.sv` | 30 May 2026 |
| Integration report | 9 June 2026 |
| Updated project summary | 11 June 2026 |

The root wrapper's interface also matches the modular migration described in the report. Modification dates help identify a candidate source version; they do not establish which exact files produced a bitstream. The differences listed below have not been attributed to the unfinished follow-up experiments.

## Code entry points

| Path from the supplied project root | Purpose |
| --- | --- |
| `custom_top_wrapper.sv` | Modular-stack CSR integration wrapper described by the final wiki |
| `rtl/RoCE_stack_wrapper.sv` | RoCE stack, external control injection, internal request/payload generators |
| `rtl/utils/network_wrapper_roce_generic.sv` | Network wrapper and forwarding of external control |
| `rtl/rx_engine/RoCE_udp_rx_acks.sv` | Receive-side ACK handling |
| `SimplyV/Simply-V/hw/xilinx/rtl/cmac_subsystem.sv` | CMAC integration point |
| `SimplyV/Simply-V/config/configs/hpc/config_main_bus.csv` | HPC main-bus configuration |
| `SimplyV/Simply-V/hw/units/custom_rdma_subsystem/` | Packaged-unit wrapper and source-fetch flow |

## Items to reconcile before a reproducible build

1. **Wrapper versions differ.** The root `custom_top_wrapper.sv` targets the modular network wrapper, connects `clk_roce_eng`, and aliases unavailable instantaneous statistics. The copy under `SimplyV/Simply-V/hw/units/custom_rdma_subsystem/` uses an older interface. Select one consistent wrapper/stack revision and make the packaging flow consume it.
2. **Fetched RTL is a separate input.** `fetch_sources.sh` clones a fork's `u250` branch and flattens HDL into `rtl/`. That branch is not proven identical to the root source snapshot. Pin and record the fetched commit and dependencies; resolve duplicate filenames when flattening.
3. **Bus configuration and top-level wiring differ.** The HPC CSV removes legacy packet-data ranges, while the inspected `simplyv.sv` retains `s_data_axi_*` connections. Reconcile this with the intended control-only integration rather than assuming the wiki's final wiring is present everywhere.
4. **An IP configuration link appears exported as text.** `hw/xilinx/ips/common/custom_rdma_subsystem/config.tcl` contains `../tcl/custom_config.tcl` as a plain file in the supplied Windows copy. Confirm and restore the intended link or equivalent packaging behavior in the build environment.
5. **Timing evidence is incomplete for sign-off.** Retain full clock, exception, CDC and timing reports, and review the warning categories visible in the supplied screenshot.

The root Git HEAD file points to `a77169266954bb37b4880c8b6ead40474e3be6d6`. This identifies repository metadata in the copy; it does **not** prove that all inspected working files, dependencies, or hardware bitstreams correspond exactly to that commit.

## Attribution and release contents

The integration builds on Simply-V, Gabriele-bot's RoCEv2 stack, and Alex Forencich's Ethernet components. Retain their existing notices and keep integration changes distinguishable from upstream code. Simply-V includes its own license; the inspected root RoCE folder has no standalone top-level license file. No new blanket license is assigned by this write-up.

Use the curated English documentation for the public project description. Internal scratch notes can contain lab-host and tool-configuration details and earlier, superseded test assumptions; they are not required for the portfolio narrative.

For a reproducible release, record the selected HDL and dependency commits, board and tool versions, wrapper selection, actual build options, complete timing reports, and a hardware-test procedure with explicit expected results.
