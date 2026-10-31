// =============================================================================
// Module: custom_top_wrapper  (custom_rdma_subsystem IP)
// Author: Domenico Coppola
//
// Custom Simply-V unit packaging the RoCE/RDMA wrapper that replaces the
// xlnx_axis_fifo inside cmac_subsystem. The CPU drives the RoCE stack via
// AXI4-Lite memory-mapped registers; the wrapper exposes AXIS @ 512 bit
// toward the CMAC.
//
// Sources for the underlying RoCE stack are pulled by fetch_sources.sh into
// the local rtl/ directory; this file (custom_top_wrapper.sv) is the Vivado
// IP top and instantiates network_wrapper_roce_generic from there.
//
// See the project-level docs (docs/wrapper_implementation_report.md) for the
// register map and the bring-up sequence from software.
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "simplyv_axi.svh"

module custom_top_wrapper #(

    //////////////////////////////////////
    //  Add here IP-related parameters  //
    //////////////////////////////////////

    // AXI/MEM macros parameters (must be aligned with platform configuration)
    parameter int unsigned LOCAL_DATA_WIDTH  = 32,
    parameter int unsigned LOCAL_ADDR_WIDTH  = 32,

    // RoCE stack parameters
    parameter int unsigned MAC_DATA_WIDTH    = 512,
    parameter int unsigned STACK_DATA_WIDTH  = 512,
    parameter int unsigned FIFO_REGS         = 4,
    parameter [7:0]        ENABLE_PFC        = 8'h0,
    parameter int unsigned DEBUG             = 0
) (

    ///////////////////////////////////
    //  Add here IP-related signals  //
    ///////////////////////////////////

    // Clock and reset (matches cmac_output_clock_322MHz inside cmac_subsystem)
    input  logic clk_i,
    input  logic rst_ni,

    // ----- AXI4-Lite slave (CSR) from CMAC XBAR ---------------------------
    `DEFINE_AXILITE_SLAVE_PORTS(s_csr, LOCAL_DATA_WIDTH, LOCAL_ADDR_WIDTH),

    // ----- AXIS TX toward CMAC --------------------------------------------
    output wire [MAC_DATA_WIDTH-1   : 0] m_axis_tdata,
    output wire [MAC_DATA_WIDTH/8-1 : 0] m_axis_tkeep,
    output wire                          m_axis_tvalid,
    input  wire                          m_axis_tready,
    output wire                          m_axis_tlast,
    output wire                          m_axis_tuser,

    // ----- AXIS RX from CMAC ----------------------------------------------
    input  wire [MAC_DATA_WIDTH-1   : 0] s_axis_tdata,
    input  wire [MAC_DATA_WIDTH/8-1 : 0] s_axis_tkeep,
    input  wire                          s_axis_tvalid,
    output wire                          s_axis_tready,
    input  wire                          s_axis_tlast,
    input  wire                          s_axis_tuser
);

    // -------------------------------------------------------------------------
    // Register offsets (in byte address space).
    // See docs/wrapper_implementation_report.md for the full register map.
    // -------------------------------------------------------------------------
    localparam logic [11:0] OFFSET_CTRL                = 12'h000;
    localparam logic [11:0] OFFSET_TXMETA_LOC_QPN      = 12'h004;
    localparam logic [11:0] OFFSET_TXMETA_DMA_LENGTH   = 12'h008;
    localparam logic [11:0] OFFSET_TXMETA_N_TRANSFERS  = 12'h00C;
    localparam logic [11:0] OFFSET_TXMETA_FREQUENCY    = 12'h010;
    localparam logic [11:0] OFFSET_TXMETA_FLAGS        = 12'h014;
    localparam logic [11:0] OFFSET_TXMETA_ISSUE        = 12'h018;

    localparam logic [11:0] OFFSET_QP_REQ_TYPE         = 12'h020;
    localparam logic [11:0] OFFSET_QP_R_KEY            = 12'h024;
    localparam logic [11:0] OFFSET_QP_REM_QPN          = 12'h028;
    localparam logic [11:0] OFFSET_QP_LOC_QPN          = 12'h02C;
    localparam logic [11:0] OFFSET_QP_REM_PSN          = 12'h030;
    localparam logic [11:0] OFFSET_QP_LOC_PSN          = 12'h034;
    localparam logic [11:0] OFFSET_QP_REM_IP           = 12'h038;
    localparam logic [11:0] OFFSET_QP_REM_ADDR_LO      = 12'h03C;
    localparam logic [11:0] OFFSET_QP_REM_ADDR_HI      = 12'h040;
    localparam logic [11:0] OFFSET_QP_ISSUE            = 12'h044;

    localparam logic [11:0] OFFSET_NET_LOCAL_MAC_LO    = 12'h050;
    localparam logic [11:0] OFFSET_NET_LOCAL_MAC_HI    = 12'h054;
    localparam logic [11:0] OFFSET_NET_LOCAL_IP        = 12'h058;
    localparam logic [11:0] OFFSET_NET_UDP_PORT        = 12'h05C;
    localparam logic [11:0] OFFSET_NET_CONFIG          = 12'h060;

    localparam logic [11:0] OFFSET_STAT_TEST           = 12'h100;
    localparam logic [11:0] OFFSET_STAT_LATENCY_INST   = 12'h104;
    localparam logic [11:0] OFFSET_STAT_LATENCY_AVG    = 12'h108;
    localparam logic [11:0] OFFSET_STAT_TRANSFER_INST  = 12'h10C;
    localparam logic [11:0] OFFSET_STAT_TRANSFER_AVG   = 12'h110;

    // -------------------------------------------------------------------------
    // Register storage.
    // -------------------------------------------------------------------------
    logic        reg_ctrl_txmeta_enable;
    logic        reg_ctrl_qp_init_enable;

    logic [23:0] reg_txmeta_loc_qpn;
    logic [31:0] reg_txmeta_dma_length;
    logic [31:0] reg_txmeta_n_transfers;
    logic [3 :0] reg_txmeta_frequency;
    logic        reg_txmeta_tx_type;
    logic        reg_txmeta_is_immediate;

    logic [2 :0] reg_qp_req_type;
    logic [31:0] reg_qp_r_key;
    logic [23:0] reg_qp_rem_qpn;
    logic [23:0] reg_qp_loc_qpn;
    logic [23:0] reg_qp_rem_psn;
    logic [23:0] reg_qp_loc_psn;
    logic [31:0] reg_qp_rem_ip;
    logic [31:0] reg_qp_rem_addr_lo;
    logic [31:0] reg_qp_rem_addr_hi;

    logic [31:0] reg_net_mac_lo;
    logic [15:0] reg_net_mac_hi;
    logic [31:0] reg_net_local_ip;
    logic [15:0] reg_net_udp_port;
    logic [2 :0] reg_net_pmtu;
    logic [2 :0] reg_net_priority_tag;
    logic        reg_net_flow_ctrl_pause;

    logic        pulse_txmeta_issue;
    logic        pulse_qp_init_issue;
    logic        pulse_clear_arp_cache;

    // -------------------------------------------------------------------------
    // AXI4-Lite write channel FSM.
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        W_IDLE = 2'd0,
        W_DATA = 2'd1,
        W_RESP = 2'd2
    } w_state_e;

    w_state_e w_state, w_state_next;

    logic [LOCAL_ADDR_WIDTH-1:0] w_addr_reg;

    assign s_csr_axilite_awready = (w_state == W_IDLE);
    assign s_csr_axilite_wready  = (w_state == W_DATA);
    assign s_csr_axilite_bvalid  = (w_state == W_RESP);
    assign s_csr_axilite_bresp   = 2'b00;  // OKAY

    always_comb begin
        w_state_next = w_state;
        case (w_state)
            W_IDLE: if (s_csr_axilite_awvalid && s_csr_axilite_awready) w_state_next = W_DATA;
            W_DATA: if (s_csr_axilite_wvalid  && s_csr_axilite_wready ) w_state_next = W_RESP;
            W_RESP: if (s_csr_axilite_bvalid  && s_csr_axilite_bready ) w_state_next = W_IDLE;
            default: w_state_next = W_IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            w_state    <= W_IDLE;
            w_addr_reg <= '0;
        end else begin
            w_state <= w_state_next;
            if (w_state == W_IDLE && s_csr_axilite_awvalid && s_csr_axilite_awready) begin
                w_addr_reg <= s_csr_axilite_awaddr;
            end
        end
    end

    wire        write_strobe = (w_state == W_DATA) && s_csr_axilite_wvalid && s_csr_axilite_wready;
    wire [31:0] write_data   = s_csr_axilite_wdata;
    wire [11:0] write_off    = w_addr_reg[11:0];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            reg_ctrl_txmeta_enable  <= 1'b0;
            reg_ctrl_qp_init_enable <= 1'b0;
            reg_txmeta_loc_qpn      <= '0;
            reg_txmeta_dma_length   <= '0;
            reg_txmeta_n_transfers  <= '0;
            reg_txmeta_frequency    <= '0;
            reg_txmeta_tx_type      <= 1'b0;
            reg_txmeta_is_immediate <= 1'b0;
            reg_qp_req_type         <= '0;
            reg_qp_r_key            <= '0;
            reg_qp_rem_qpn          <= '0;
            reg_qp_loc_qpn          <= '0;
            reg_qp_rem_psn          <= '0;
            reg_qp_loc_psn          <= '0;
            reg_qp_rem_ip           <= '0;
            reg_qp_rem_addr_lo      <= '0;
            reg_qp_rem_addr_hi      <= '0;
            reg_net_mac_lo          <= '0;
            reg_net_mac_hi          <= '0;
            reg_net_local_ip        <= '0;
            reg_net_udp_port        <= 16'h12B7;
            reg_net_pmtu            <= 3'd2;
            reg_net_priority_tag    <= '0;
            reg_net_flow_ctrl_pause <= 1'b0;
            pulse_txmeta_issue      <= 1'b0;
            pulse_qp_init_issue     <= 1'b0;
            pulse_clear_arp_cache   <= 1'b0;
        end else begin
            pulse_txmeta_issue    <= 1'b0;
            pulse_qp_init_issue   <= 1'b0;
            pulse_clear_arp_cache <= 1'b0;

            if (write_strobe) begin
                unique case (write_off)
                    OFFSET_CTRL: begin
                        reg_ctrl_txmeta_enable  <= write_data[0];
                        reg_ctrl_qp_init_enable <= write_data[1];
                    end
                    OFFSET_TXMETA_LOC_QPN:     reg_txmeta_loc_qpn      <= write_data[23:0];
                    OFFSET_TXMETA_DMA_LENGTH:  reg_txmeta_dma_length   <= write_data;
                    OFFSET_TXMETA_N_TRANSFERS: reg_txmeta_n_transfers  <= write_data;
                    OFFSET_TXMETA_FREQUENCY:   reg_txmeta_frequency    <= write_data[3:0];
                    OFFSET_TXMETA_FLAGS: begin
                        reg_txmeta_tx_type      <= write_data[0];
                        reg_txmeta_is_immediate <= write_data[1];
                    end
                    OFFSET_TXMETA_ISSUE:       pulse_txmeta_issue  <= write_data[0];

                    OFFSET_QP_REQ_TYPE:        reg_qp_req_type     <= write_data[2:0];
                    OFFSET_QP_R_KEY:           reg_qp_r_key        <= write_data;
                    OFFSET_QP_REM_QPN:         reg_qp_rem_qpn      <= write_data[23:0];
                    OFFSET_QP_LOC_QPN:         reg_qp_loc_qpn      <= write_data[23:0];
                    OFFSET_QP_REM_PSN:         reg_qp_rem_psn      <= write_data[23:0];
                    OFFSET_QP_LOC_PSN:         reg_qp_loc_psn      <= write_data[23:0];
                    OFFSET_QP_REM_IP:          reg_qp_rem_ip       <= write_data;
                    OFFSET_QP_REM_ADDR_LO:     reg_qp_rem_addr_lo  <= write_data;
                    OFFSET_QP_REM_ADDR_HI:     reg_qp_rem_addr_hi  <= write_data;
                    OFFSET_QP_ISSUE:           pulse_qp_init_issue <= write_data[0];

                    OFFSET_NET_LOCAL_MAC_LO:   reg_net_mac_lo      <= write_data;
                    OFFSET_NET_LOCAL_MAC_HI:   reg_net_mac_hi      <= write_data[15:0];
                    OFFSET_NET_LOCAL_IP:       reg_net_local_ip    <= write_data;
                    OFFSET_NET_UDP_PORT:       reg_net_udp_port    <= write_data[15:0];
                    OFFSET_NET_CONFIG: begin
                        reg_net_pmtu            <= write_data[2:0];
                        reg_net_priority_tag    <= write_data[5:3];
                        reg_net_flow_ctrl_pause <= write_data[6];
                        pulse_clear_arp_cache   <= write_data[7];
                    end

                    default: /* ignore writes to unmapped offsets */;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // AXI4-Lite read channel FSM.
    // -------------------------------------------------------------------------
    typedef enum logic [0:0] {
        R_IDLE = 1'b0,
        R_RESP = 1'b1
    } r_state_e;

    r_state_e r_state, r_state_next;

    logic [31:0] r_data_reg;

    assign s_csr_axilite_arready = (r_state == R_IDLE);
    assign s_csr_axilite_rvalid  = (r_state == R_RESP);
    assign s_csr_axilite_rdata   = r_data_reg;
    assign s_csr_axilite_rresp   = 2'b00;

    always_comb begin
        r_state_next = r_state;
        case (r_state)
            R_IDLE: if (s_csr_axilite_arvalid && s_csr_axilite_arready) r_state_next = R_RESP;
            R_RESP: if (s_csr_axilite_rvalid  && s_csr_axilite_rready ) r_state_next = R_IDLE;
            default: r_state_next = R_IDLE;
        endcase
    end

    wire        stat_test_w;
    wire [31:0] latency_avg_w, latency_moving_avg_w, latency_inst_w;
    wire [31:0] transfer_time_avg_w, transfer_time_moving_avg_w, transfer_time_inst_w;

    function automatic logic [31:0] read_decode(input logic [LOCAL_ADDR_WIDTH-1:0] addr);
        unique case (addr[11:0])
            OFFSET_CTRL:               read_decode = {30'd0, reg_ctrl_qp_init_enable, reg_ctrl_txmeta_enable};
            OFFSET_TXMETA_LOC_QPN:     read_decode = {8'd0,  reg_txmeta_loc_qpn};
            OFFSET_TXMETA_DMA_LENGTH:  read_decode = reg_txmeta_dma_length;
            OFFSET_TXMETA_N_TRANSFERS: read_decode = reg_txmeta_n_transfers;
            OFFSET_TXMETA_FREQUENCY:   read_decode = {28'd0, reg_txmeta_frequency};
            OFFSET_TXMETA_FLAGS:       read_decode = {30'd0, reg_txmeta_is_immediate, reg_txmeta_tx_type};
            OFFSET_QP_REQ_TYPE:        read_decode = {29'd0, reg_qp_req_type};
            OFFSET_QP_R_KEY:           read_decode = reg_qp_r_key;
            OFFSET_QP_REM_QPN:         read_decode = {8'd0,  reg_qp_rem_qpn};
            OFFSET_QP_LOC_QPN:         read_decode = {8'd0,  reg_qp_loc_qpn};
            OFFSET_QP_REM_PSN:         read_decode = {8'd0,  reg_qp_rem_psn};
            OFFSET_QP_LOC_PSN:         read_decode = {8'd0,  reg_qp_loc_psn};
            OFFSET_QP_REM_IP:          read_decode = reg_qp_rem_ip;
            OFFSET_QP_REM_ADDR_LO:     read_decode = reg_qp_rem_addr_lo;
            OFFSET_QP_REM_ADDR_HI:     read_decode = reg_qp_rem_addr_hi;
            OFFSET_NET_LOCAL_MAC_LO:   read_decode = reg_net_mac_lo;
            OFFSET_NET_LOCAL_MAC_HI:   read_decode = {16'd0, reg_net_mac_hi};
            OFFSET_NET_LOCAL_IP:       read_decode = reg_net_local_ip;
            OFFSET_NET_UDP_PORT:       read_decode = {16'd0, reg_net_udp_port};
            OFFSET_NET_CONFIG:         read_decode = {24'd0, 1'b0, reg_net_flow_ctrl_pause, reg_net_priority_tag, reg_net_pmtu};
            OFFSET_STAT_TEST:          read_decode = {31'd0, stat_test_w};
            OFFSET_STAT_LATENCY_INST:  read_decode = latency_inst_w;
            OFFSET_STAT_LATENCY_AVG:   read_decode = latency_avg_w;
            OFFSET_STAT_TRANSFER_INST: read_decode = transfer_time_inst_w;
            OFFSET_STAT_TRANSFER_AVG:  read_decode = transfer_time_avg_w;
            default:                   read_decode = 32'hDEAD_BEEF;
        endcase
    endfunction

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_state    <= R_IDLE;
            r_data_reg <= '0;
        end else begin
            r_state <= r_state_next;
            if (r_state == R_IDLE && s_csr_axilite_arvalid && s_csr_axilite_arready) begin
                r_data_reg <= read_decode(s_csr_axilite_araddr);
            end
        end
    end

    // -------------------------------------------------------------------------
    // network_wrapper_roce_generic instance (sources fetched into rtl/).
    // -------------------------------------------------------------------------
    wire active_high_rst = ~rst_ni;

    network_wrapper_roce_generic #(
        .MAC_DATA_WIDTH   ( MAC_DATA_WIDTH   ),
        .STACK_DATA_WIDTH ( STACK_DATA_WIDTH ),
        .FIFO_REGS        ( FIFO_REGS        ),
        .ENABLE_PFC       ( ENABLE_PFC       ),
        .DEBUG            ( DEBUG            )
    ) network_wrapper_u (
        .clk_mac   ( clk_i           ),
        .rst_mac   ( active_high_rst ),
        .clk_stack ( clk_i           ),
        .rst_stack ( active_high_rst ),

        .flow_ctrl_pause ( reg_net_flow_ctrl_pause ),

        .m_network_tx_axis_tdata  ( m_axis_tdata  ),
        .m_network_tx_axis_tkeep  ( m_axis_tkeep  ),
        .m_network_tx_axis_tvalid ( m_axis_tvalid ),
        .m_network_tx_axis_tready ( m_axis_tready ),
        .m_network_tx_axis_tlast  ( m_axis_tlast  ),
        .m_network_tx_axis_tuser  ( m_axis_tuser  ),

        .s_network_rx_axis_tdata  ( s_axis_tdata  ),
        .s_network_rx_axis_tkeep  ( s_axis_tkeep  ),
        .s_network_rx_axis_tvalid ( s_axis_tvalid ),
        .s_network_rx_axis_tready ( s_axis_tready ),
        .s_network_rx_axis_tlast  ( s_axis_tlast  ),
        .s_network_rx_axis_tuser  ( s_axis_tuser  ),

        .pfc_pause_req ( 8'h00 ),
        .pfc_pause_ack ( /* unused */ ),

        .m_qp_context_spy       ( 1'b0  ),
        .m_qp_local_qpn_spy     ( 24'd0 ),
        .s_qp_spy_context_valid ( /* unused */ ),
        .s_qp_spy_state         ( /* unused */ ),
        .s_qp_spy_rem_qpn       ( /* unused */ ),
        .s_qp_spy_loc_qpn       ( /* unused */ ),
        .s_qp_spy_rem_psn       ( /* unused */ ),
        .s_qp_spy_rem_acked_psn ( /* unused */ ),
        .s_qp_spy_loc_psn       ( /* unused */ ),
        .s_qp_spy_r_key         ( /* unused */ ),
        .s_qp_spy_rem_addr      ( /* unused */ ),
        .s_qp_spy_rem_ip_addr   ( /* unused */ ),
        .s_qp_spy_syndrome      ( /* unused */ ),

        .ctrl_local_mac_address ( {reg_net_mac_hi, reg_net_mac_lo} ),
        .ctrl_local_ip          ( reg_net_local_ip                 ),
        .ctrl_clear_arp_cache   ( pulse_clear_arp_cache            ),
        .ctrl_pmtu              ( reg_net_pmtu                     ),
        .ctrl_RoCE_udp_port     ( reg_net_udp_port                 ),
        .ctrl_priority_tag      ( reg_net_priority_tag             ),

        .stat_test                ( stat_test_w                ),
        .cfg_latency_avg_po2      ( 4'd8  ),
        .cfg_throughput_avg_po2   ( 5'd8  ),
        .monitor_loc_qpn          ( reg_qp_loc_qpn ),
        .transfer_time_avg        ( transfer_time_avg_w        ),
        .transfer_time_moving_avg ( transfer_time_moving_avg_w ),
        .transfer_time_inst       ( transfer_time_inst_w       ),
        .latency_avg              ( latency_avg_w              ),
        .latency_moving_avg       ( latency_moving_avg_w       ),
        .latency_inst             ( latency_inst_w             ),

        .ext_txmeta_enable         ( reg_ctrl_txmeta_enable           ),
        .ext_txmeta_valid          ( reg_ctrl_txmeta_enable           ),
        .ext_txmeta_start_transfer ( pulse_txmeta_issue               ),
        .ext_txmeta_loc_qpn        ( reg_txmeta_loc_qpn               ),
        .ext_txmeta_is_immediate   ( reg_txmeta_is_immediate          ),
        .ext_txmeta_tx_type        ( reg_txmeta_tx_type               ),
        .ext_txmeta_dma_transfer   ( reg_txmeta_dma_length            ),
        .ext_txmeta_n_transfers    ( reg_txmeta_n_transfers           ),
        .ext_txmeta_frequency      ( {28'd0, reg_txmeta_frequency}    ),

        .ext_qp_init_enable        ( reg_ctrl_qp_init_enable                  ),
        .ext_qp_init_valid         ( pulse_qp_init_issue                      ),
        .ext_qp_init_req_type      ( reg_qp_req_type                          ),
        .ext_qp_init_r_key         ( reg_qp_r_key                             ),
        .ext_qp_init_rem_qpn       ( reg_qp_rem_qpn                           ),
        .ext_qp_init_loc_qpn       ( reg_qp_loc_qpn                           ),
        .ext_qp_init_rem_psn       ( reg_qp_rem_psn                           ),
        .ext_qp_init_loc_psn       ( reg_qp_loc_psn                           ),
        .ext_qp_init_rem_ip_addr   ( reg_qp_rem_ip                            ),
        .ext_qp_init_rem_addr      ( {reg_qp_rem_addr_hi, reg_qp_rem_addr_lo} )
    );

endmodule : custom_top_wrapper

`resetall
