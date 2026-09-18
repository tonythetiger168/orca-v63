// ORCA v6.3 ZEN++ - v6.3.1
`include "orca_pkg.sv"


// GPIO pad ring: 32 pads, 方向/上拉/驅動配置
module gpio_pad
  import orca_pkg::*; (
  input  logic [31:0] gpio_o,
  output logic [31:0] gpio_i,
  input  logic [31:0] gpio_oe,
  input  logic [31:0] gpio_pu,
  input  logic [31:0] gpio_ds,
  inout  logic [31:0] pad
);
  for (genvar i = 0; i < 32; i++) begin : g_pad
    assign pad[i]    = gpio_oe[i] ? gpio_o[i] : (gpio_pu[i] ? 1'b1 : 1'bz);
    assign gpio_i[i] = pad[i];
  end
endmodule : gpio_pad
