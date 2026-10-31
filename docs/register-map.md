# CSR register map

[Back to README](../README.md)

This map follows the **root** `custom_top_wrapper.sv` inspected for this write-up. Registers are 32-bit aligned; narrower fields occupy the low bits. Add each offset to the RDMA CSR base for the selected bitstream and PCIe mapping.

## Control and transfer metadata

| Offset | Register | Fields and behavior |
| --- | --- | --- |
| `0x000` | `CTRL` | R/W; bit 0 transfer enable, bit 1 QP-command enable |
| `0x004` | `TXMETA_LOC_QPN` | R/W; local QPN `[23:0]` |
| `0x008` | `TXMETA_DMA_LENGTH` | R/W; generated transfer length in bytes `[31:0]`; this name does not imply an implemented memory DMA |
| `0x00C` | `TXMETA_N_TRANSFERS` | R/W; requested transfer count `[31:0]` |
| `0x010` | `TXMETA_FREQUENCY` | R/W; pacing field `[3:0]`, zero-extended toward the stack |
| `0x014` | `TXMETA_FLAGS` | R/W; bit 0 selects WRITE (`0`) or SEND (`1`); bit 1 selects immediate mode |
| `0x018` | `TXMETA_ISSUE` | Write bit 0 as `1` to produce a transfer-start pulse; no read decode is implemented |

The internal generator for instance `i` expects local QPN **`256 + i`**. Use that value consistently in QP configuration and transfer metadata.

## Queue Pair configuration

| Offset | Register | Fields and behavior |
| --- | --- | --- |
| `0x020` | `QP_REQ_TYPE` | R/W; `[2:0]`; `0x1` OPEN, `0x4` CLOSE |
| `0x024` | `QP_R_KEY` | R/W; `[31:0]` |
| `0x028` | `QP_REM_QPN` | R/W; remote QPN `[23:0]` |
| `0x02C` | `QP_LOC_QPN` | R/W; local QPN `[23:0]` |
| `0x030` | `QP_REM_PSN` | R/W; remote PSN `[23:0]` |
| `0x034` | `QP_LOC_PSN` | R/W; local PSN `[23:0]` |
| `0x038` | `QP_REM_IP` | R/W; remote IPv4 address `[31:0]` |
| `0x03C` | `QP_REM_ADDR_LO` | R/W; remote address `[31:0]` |
| `0x040` | `QP_REM_ADDR_HI` | R/W; remote address `[63:32]` |
| `0x044` | `QP_ISSUE` | Write bit 0 as `1` to issue the selected QP operation; no read decode is implemented |

`QP_R_KEY`, both PSNs, and the high remote-address word reset to zero. A reproducible test should set them explicitly rather than depend on state left by an earlier run. A configured remote address is a packet-header value, not evidence of a write reaching memory.

## Network configuration

| Offset | Register | Fields and behavior |
| --- | --- | --- |
| `0x050` | `NET_LOCAL_MAC_LO` | R/W; local MAC low 32 bits |
| `0x054` | `NET_LOCAL_MAC_HI` | R/W; local MAC high 16 bits |
| `0x058` | `NET_LOCAL_IP` | R/W; local IPv4 address `[31:0]` |
| `0x05C` | `NET_UDP_PORT` | R/W; `[15:0]`; reset `4791` / `0x12B7` |
| `0x060` | `NET_CONFIG` | R/W; PMTU `[2:0]`, priority tag `[5:3]`, flow-control pause bit 6; write bit 7 to pulse ARP-cache clear |

PMTU resets to encoded value `2`; consult the selected stack revision for the encoding. `NET_CONFIG[7]` is a pulse command, not persistent configuration.

## Status and telemetry

| Offset | Register | Behavior in the root integration wrapper |
| --- | --- | --- |
| `0x100` | `STAT_TEST` | Read-only; tied to zero; bus-read probe rather than a success flag |
| `0x104` | `STAT_LATENCY_INST` | Read-only; aliases the available average-latency signal |
| `0x108` | `STAT_LATENCY_AVG` | Read-only; average-latency signal |
| `0x10C` | `STAT_TRANSFER_INST` | Read-only; aliases the available average-transfer-time signal |
| `0x110` | `STAT_TRANSFER_AVG` | Read-only; average-transfer-time signal |

The original instantaneous-register names are retained for compatibility; they are not independent instantaneous measurements in this wrapper. Completion-related telemetry depends on received ACKs. It remained zero in the documented two-FPGA test, where a responder was absent. Reads without an explicit decode, including the two issue-register offsets, return `0xDEADBEEF`.

See the [build and hardware-test guide](build-and-test.md) for address discovery and the interpretation of CMAC counters.
