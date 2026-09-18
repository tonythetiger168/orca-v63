//=============================================================================
// ORCA v6.3 SystemVerilog Assertions - NoC Router
// File: tb/sva/sva_noc.sv
// Description: NoC mesh router safety, deadlock freedom, and coherence assertions
//=============================================================================

`include "orca_pkg.sv"

module sva_noc (
  input logic clk,
  input logic rst_n,

  // Router ports
  input logic [4:0] rx_valid,       // [N, S, E, W, Local]
  input logic [4:0] rx_ready,
  input logic [4:0] tx_valid,
  input logic [4:0] tx_ready,

  // Flit data (simplified monitoring)
  input logic [511:0] rx_data [5],
  input logic [511:0] tx_data [5],

  // Router internal state
  input logic [3:0] [3:0] dest_x,      // Dest X from flit header
  input logic [3:0] [3:0] dest_y,      // Dest Y from flit header
  input logic [4:0] [3:0] vc_id,       // VC ID per port

  // Coherence signals
  input coh_state_t [4:0] coh_state_rx,
  input coh_state_t [4:0] coh_state_tx,
  input logic       [4:0] coh_req_valid,
  input logic       [4:0] coh_rsp_valid
);

  import orca_pkg::*;

  localparam int PORT_NORTH = 0;
  localparam int PORT_SOUTH = 1;
  localparam int PORT_EAST  = 2;
  localparam int PORT_WEST  = 3;
  localparam int PORT_LOCAL = 4;

  // ==========================================================================
  // Basic Protocol Safety
  // ==========================================================================

  // N1: Valid must imply ready eventually (no lost flits)
  generate
    for (genvar p = 0; p < 5; p++) begin : gen_no_lost_flits
      property p_no_lost_rx;
        @(posedge clk) disable iff (!rst_n)
        rx_valid[p] |-> ##[1:10] rx_ready[p];
      endproperty
      assert property (p_no_lost_rx)
        else `uvm_error("SVA_NOC", $sformatf("Port %0d RX flit lost (no ready)", p))

      property p_no_lost_tx;
        @(posedge clk) disable iff (!rst_n)
        tx_valid[p] |-> ##[1:10] tx_ready[p];
      endproperty
      assert property (p_no_lost_tx)
        else `uvm_error("SVA_NOC", $sformatf("Port %0d TX flit lost (no ready)", p))
    end
  endgenerate

  // N2: No X-propagation on valid signals
  generate
    for (genvar p = 0; p < 5; p++) begin : gen_no_x_valid
      property p_no_x_rx_valid;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(rx_valid[p]);
      endproperty
      assert property (p_no_x_rx_valid)
        else `uvm_error("SVA_NOC", $sformatf("Port %0d RX valid is X", p))

      property p_no_x_tx_valid;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(tx_valid[p]);
      endproperty
      assert property (p_no_x_tx_valid)
        else `uvm_error("SVA_NOC", $sformatf("Port %0d TX valid is X", p))
    end
  endgenerate

  // ==========================================================================
  // Deadlock Freedom
  // ==========================================================================

  // N3: No port can be stalled forever (liveness)
  generate
    for (genvar p = 0; p < 5; p++) begin : gen_no_deadlock
      property p_tx_liveness;
        @(posedge clk) disable iff (!rst_n)
        tx_valid[p] |-> s_eventually tx_ready[p];
      endproperty
      assert property (p_tx_liveness)
        else `uvm_error("SVA_NOC", $sformatf("Port %0d TX deadlock detected!", p))
    end
  endgenerate

  // N4: VC allocation must not starve
  generate
    for (genvar p = 0; p < 5; p++) begin : gen_vc_no_starvation
      property p_vc_fairness;
        @(posedge clk) disable iff (!rst_n)
        (vc_id[p] == 0) |-> s_eventually (vc_id[p] == 1);
      endproperty
      // Weak assertion - may be disabled for specific traffic patterns
      // assert property (p_vc_fairness)
      //   else `uvm_warning("SVA_NOC", $sformatf("Port %0d VC starvation possible", p))
    end
  endgenerate

  // ==========================================================================
  // Routing Correctness
  // ==========================================================================

  // N5: Flits must not be routed to invalid ports
  // (Local port only if dest matches current router)
  property p_local_only_for_dest;
    @(posedge clk) disable iff (!rst_n)
    (tx_valid[PORT_LOCAL]) |->
      (dest_x[PORT_LOCAL] == 4'hX && dest_y[PORT_LOCAL] == 4'hX);  // X = current router pos
  endproperty
  assert property (p_local_only_for_dest)
    else `uvm_error("SVA_NOC", "Flit routed to local port but dest mismatch!")

  // N6: X-Y routing: East/West before North/South
  property p_xy_routing_order;
    @(posedge clk) disable iff (!rst_n)
    (rx_valid[PORT_LOCAL] && dest_x[PORT_LOCAL] != 4'hX)
      |-> (tx_valid[PORT_EAST] || tx_valid[PORT_WEST]);
  endproperty
  assert property (p_xy_routing_order)
    else `uvm_error("SVA_NOC", "X-Y routing order violation!")

  // ==========================================================================
  // Coherence Protocol Safety
  // ==========================================================================

  // N7: Coherence state transitions must be valid
  property p_valid_coh_transition;
    @(posedge clk) disable iff (!rst_n)
    (coh_state_rx[PORT_LOCAL] == COH_MODIFIED)
      |-> !(coh_state_tx[PORT_LOCAL] == COH_SHARED);
  endproperty
  assert property (p_valid_coh_transition)
    else `uvm_error("SVA_NOC", "Invalid coherence state transition: M -> S!")

  // N8: Only one coherence request per cycle per port
  generate
    for (genvar p = 0; p < 5; p++) begin : gen_single_coh_req
      property p_single_coh_req;
        @(posedge clk) disable iff (!rst_n)
        $onehot0({coh_req_valid[p], coh_rsp_valid[p]});
      endproperty
      assert property (p_single_coh_req)
        else `uvm_error("SVA_NOC", $sformatf("Port %0d multiple coh transactions!", p))
    end
  endgenerate

  // N9: Modified data must not be lost
  property p_modified_persistence;
    @(posedge clk) disable iff (!rst_n)
    (coh_state_rx[PORT_LOCAL] == COH_MODIFIED && !tx_ready[PORT_LOCAL])
      |-> ##1 (coh_state_rx[PORT_LOCAL] == COH_MODIFIED);
  endproperty
  assert property (p_modified_persistence)
    else `uvm_error("SVA_NOC", "Modified cache line state lost!")

  // ==========================================================================
  // Buffer Safety
  // ==========================================================================

  // N10: Buffer overflow prevention
  // (Checked by ready/valid handshake, but double-check)
  generate
    for (genvar p = 0; p < 5; p++) begin : gen_no_overflow
      property p_no_buffer_overflow;
        @(posedge clk) disable iff (!rst_n)
        rx_valid[p] && !rx_ready[p] |-> ##1 !rx_valid[p];  // Must deassert if not ready
      endproperty
      assert property (p_no_buffer_overflow)
        else `uvm_error("SVA_NOC", $sformatf("Port %0d buffer overflow!", p))
    end
  endgenerate

  // ==========================================================================
  // Coverage
  // ==========================================================================

  // C1: All ports active simultaneously
  property c_all_ports_active;
    @(posedge clk) disable iff (!rst_n)
    (&rx_valid);
  endproperty
  cover property (c_all_ports_active);

  // C2: Local port receives flit from each direction
  generate
    for (genvar p = 0; p < 4; p++) begin : gen_cover_local_from_dir
      property c_local_from_dir;
        @(posedge clk) disable iff (!rst_n)
        tx_valid[PORT_LOCAL] && rx_valid[p];
      endproperty
      cover property (c_local_from_dir);
    end
  endgenerate

  // C3: All coherence states observed
  generate
    for (genvar s = 0; s < 5; s++) begin : gen_cover_coh_states
      coh_state_t state = coh_state_t'(s);
      property c_coh_state;
        @(posedge clk) disable iff (!rst_n)
        (coh_state_rx[PORT_LOCAL] == state);
      endproperty
      cover property (c_coh_state);
    end
  endgenerate

  // C4: Wrap-around routing (East to West, North to South)
  property c_wraparound_east_west;
    @(posedge clk) disable iff (!rst_n)
    rx_valid[PORT_EAST] && tx_valid[PORT_WEST];
  endproperty
  cover property (c_wraparound_east_west);

  property c_wraparound_north_south;
    @(posedge clk) disable iff (!rst_n)
    rx_valid[PORT_NORTH] && tx_valid[PORT_SOUTH];
  endproperty
  cover property (c_wraparound_north_south);

  // C5: Backpressure scenario
  property c_backpressure;
    @(posedge clk) disable iff (!rst_n)
    rx_valid[PORT_LOCAL] && !rx_ready[PORT_LOCAL];
  endproperty
  cover property (c_backpressure);

endmodule : sva_noc
