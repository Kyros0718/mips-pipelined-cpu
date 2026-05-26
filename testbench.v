`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:         Penn State
// Engineer:        Ky-Anh Nguyen
//
// Create Date:     May 07 2026
// Design Name:     CMPEN 331 Extra Credit - Pipelined CPU Testbench
// Module Name:     testbench
// Project Name:    CMPEN 331 Extra Credit
// Target Devices:  XC7Z010-CLG400-1
// Description:
//   Testbench for the 5-stage pipelined CPU with hazard handling and forwarding.
//   Runs the full 35-instruction program (PC starts at 0).
//
// Program Overview:
//   0x00-0x08: Setup: lui $1, ori $4, jal sum
//   0x6c:      sum subroutine: accumulates 4 data values via lw loop
//              Each lw-add pair triggers a load-use stall (wpcir=0)
//              Expected sum: 0xa3 + 0x27 + 0x79 + 0x115 = 0x258
//   0x84:      jr $31: return to caller (0x10)
//   0x10:      sw $2, 0($4): stores result 0x258 into memory[24] (address 0x60)
//   0x64:      j finish: infinite loop after program completes
//
// Expected Final State:
//   memory[24] = 0x00000258 (sw result)
//   $2         = 0x00000258 (sll $2, $8, 0 in delay slot of jr)
//////////////////////////////////////////////////////////////////////////////////

//==============================================================================
// TESTBENCH MODULE
//==============================================================================

module testbench();

    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    // SIGNAL DECLARATIONS
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    reg clk;
    wire [31:0] wdi;

    //--------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    //--------------------------------------------------------------------------
    Datapath dut (
        .clk (clk),
        .wdi (wdi)
    );

    //--------------------------------------------------------------------------
    // Clock Generation - 10ns period (5ns high, 5ns low)
    //--------------------------------------------------------------------------
    initial begin
        clk = 0;
    end

    always begin
        #5 clk = ~clk;
    end

    //--------------------------------------------------------------------------
    // Simulation Control: 100 cycles
    // Program needs ~80+ cycles to complete (35 instructions + 4 stalls +
    // loop iterations + pipeline fill). 1000ns gives comfortable margin.
    //--------------------------------------------------------------------------
    initial begin
        #1000 $finish;
    end

endmodule
