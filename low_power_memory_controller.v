`timescale 1ns/1ps

// Configurable, single-request-per-cycle, banked memory controller.
// Verilog-2001. Address is a WORD address, not a byte address.
// BANKS and WORDS_PER_BANK should be powers of two for efficient hardware.
module low_power_memory_controller #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 10,
    parameter BANKS          = 4,
    parameter WORDS_PER_BANK = 256,
    parameter STRB_WIDTH     = DATA_WIDTH / 8
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     req_valid,
    input  wire                     req_write,
    input  wire [ADDR_WIDTH-1:0]    req_addr,
    input  wire [DATA_WIDTH-1:0]    req_wdata,
    input  wire [STRB_WIDTH-1:0]    req_wstrb,
    output reg                      rsp_valid,
    output reg  [DATA_WIDTH-1:0]    rsp_rdata,
    output reg  [BANKS-1:0]         bank_active,
    output wire                     busy,
    output reg                      error
);

    localparam TOTAL_WORDS = BANKS * WORDS_PER_BANK;

    // Flattened storage keeps the example portable across Verilog tools.
    // Synthesis may infer distributed/register memory unless an SRAM macro
    // or target-specific memory inference template is used.
    reg [DATA_WIDTH-1:0] mem [0:TOTAL_WORDS-1];

    integer bank_index;
    integer word_index;
    integer flat_index;
    integer byte_index;

    // This controller accepts one request on each rising edge when req_valid
    // is high. A one-cycle response pulse follows the accepted request.
    assign busy = 1'b0; // No multi-cycle operation in this simple interface.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_valid  <= 1'b0;
            rsp_rdata  <= {DATA_WIDTH{1'b0}};
            bank_active <= {BANKS{1'b0}};
            error      <= 1'b0;
        end else begin
            rsp_valid   <= 1'b0;
            bank_active <= {BANKS{1'b0}};
            error       <= 1'b0;

            if (req_valid) begin
                if (req_addr >= TOTAL_WORDS) begin
                    rsp_valid <= 1'b1;
                    error     <= 1'b1;
                    // Keep rsp_rdata unchanged on an invalid request.
                end else begin
                    bank_index = req_addr / WORDS_PER_BANK;
                    word_index = req_addr % WORDS_PER_BANK;
                    flat_index = req_addr;
                    bank_active[bank_index] <= 1'b1;
                    rsp_valid <= 1'b1;

                    if (req_write) begin
                        // Byte write enables: only selected byte lanes update.
                        for (byte_index = 0; byte_index < STRB_WIDTH; byte_index = byte_index + 1) begin
                            if (req_wstrb[byte_index]) begin
                                mem[flat_index][byte_index*8 +: 8] <=
                                    req_wdata[byte_index*8 +: 8];
                            end
                        end
                    end else begin
                        // Read data changes only for a valid read request.
                        rsp_rdata <= mem[flat_index];
                    end
                end
            end
        end
    end

endmodule
