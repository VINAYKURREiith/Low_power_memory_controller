`timescale 1ns/1ps

module tb_low_power_memory_controller;
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 10;
    parameter BANKS = 4;
    parameter WORDS_PER_BANK = 16; // Smaller simulation memory: 64 words.
    parameter STRB_WIDTH = DATA_WIDTH / 8;

    reg clk;
    reg rst_n;
    reg req_valid;
    reg req_write;
    reg [ADDR_WIDTH-1:0] req_addr;
    reg [DATA_WIDTH-1:0] req_wdata;
    reg [STRB_WIDTH-1:0] req_wstrb;

    wire rsp_valid;
    wire [DATA_WIDTH-1:0] rsp_rdata;
    wire [BANKS-1:0] bank_active;
    wire busy;
    wire error;

    integer passed;
    integer failed;

    low_power_memory_controller #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .BANKS(BANKS),
        .WORDS_PER_BANK(WORDS_PER_BANK),
        .STRB_WIDTH(STRB_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .req_valid(req_valid), .req_write(req_write),
        .req_addr(req_addr), .req_wdata(req_wdata), .req_wstrb(req_wstrb),
        .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata),
        .bank_active(bank_active), .busy(busy), .error(error)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task send_write;
        input [ADDR_WIDTH-1:0] address;
        input [DATA_WIDTH-1:0] data;
        input [STRB_WIDTH-1:0] strobe;
        begin
            @(negedge clk);
            req_valid = 1'b1;
            req_write = 1'b1;
            req_addr = address;
            req_wdata = data;
            req_wstrb = strobe;
            @(posedge clk); #1;
            if (rsp_valid && !error) begin
                $display("[PASS] WRITE addr=%0d data=%h strb=%b", address, data, strobe);
                passed = passed + 1;
            end else begin
                $display("[FAIL] WRITE addr=%0d rsp_valid=%b error=%b", address, rsp_valid, error);
                failed = failed + 1;
            end
            @(negedge clk);
            req_valid = 1'b0;
            req_write = 1'b0;
        end
    endtask

    task send_read_check;
        input [ADDR_WIDTH-1:0] address;
        input [DATA_WIDTH-1:0] expected;
        begin
            @(negedge clk);
            req_valid = 1'b1;
            req_write = 1'b0;
            req_addr = address;
            req_wdata = {DATA_WIDTH{1'b0}};
            req_wstrb = {STRB_WIDTH{1'b0}};
            @(posedge clk); #1;
            if (rsp_valid && !error && rsp_rdata === expected) begin
                $display("[PASS] READ  addr=%0d data=%h", address, rsp_rdata);
                passed = passed + 1;
            end else begin
                $display("[FAIL] READ  addr=%0d expected=%h got=%h valid=%b error=%b",
                         address, expected, rsp_rdata, rsp_valid, error);
                failed = failed + 1;
            end
            @(negedge clk);
            req_valid = 1'b0;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        req_valid = 1'b0;
        req_write = 1'b0;
        req_addr = {ADDR_WIDTH{1'b0}};
        req_wdata = {DATA_WIDTH{1'b0}};
        req_wstrb = {STRB_WIDTH{1'b0}};
        passed = 0;
        failed = 0;

        $dumpfile("low_power_memory_controller.vcd");
        $dumpvars(0, tb_low_power_memory_controller);
        $display("============================================");
        $display(" Low-Power Multi-Bank Memory Controller TB");
        $display(" Banks=%0d, Words/bank=%0d, Data width=%0d", BANKS, WORDS_PER_BANK, DATA_WIDTH);
        $display("============================================");

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // One write/read pair in each of the four banks.
        send_write(0,  32'h1234_ABCD, 4'b1111);
        send_read_check(0, 32'h1234_ABCD);
        send_write(16, 32'hA5A5_5A5A, 4'b1111);
        send_read_check(16, 32'hA5A5_5A5A);
        send_write(32, 32'hDEAD_BEEF, 4'b1111);
        send_read_check(32, 32'hDEAD_BEEF);
        send_write(48, 32'h55AA_00FF, 4'b1111);
        send_read_check(48, 32'h55AA_00FF);

        // Partial-byte write: update only the low 16 bits.
        send_write(0, 32'h0000_CCDD, 4'b0011);
        send_read_check(0, 32'h1234_CCDD);

        // Idle behavior: response and bank activity should deassert.
        @(negedge clk);
        req_valid = 1'b0;
        @(posedge clk); #1;
        if (!rsp_valid && bank_active == {BANKS{1'b0}}) begin
            $display("[PASS] IDLE: no response and no active bank");
            passed = passed + 1;
        end else begin
            $display("[FAIL] IDLE: rsp_valid=%b bank_active=%b", rsp_valid, bank_active);
            failed = failed + 1;
        end

        // Invalid address (64 is outside 0..63).
        @(negedge clk);
        req_valid = 1'b1;
        req_write = 1'b0;
        req_addr = 64;
        @(posedge clk); #1;
        if (rsp_valid && error) begin
            $display("[PASS] INVALID ADDRESS: error asserted");
            passed = passed + 1;
        end else begin
            $display("[FAIL] INVALID ADDRESS: rsp_valid=%b error=%b", rsp_valid, error);
            failed = failed + 1;
        end

        @(negedge clk);
        req_valid = 1'b0;
        repeat (2) @(negedge clk);

        $display("--------------------------------------------");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);
        $display("--------------------------------------------");
        if (failed == 0) $display("ALL TESTS PASSED");
        else $display("TESTS FAILED");
        $finish;
    end
endmodule
