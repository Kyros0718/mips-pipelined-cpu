`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:         Penn State
// Engineer:        Ky-Anh Nguyen
// 
// Create Date:     May 07 2026
// Design Name:     CMPEN 331 Extra Credit - Pipelined CPU
// Module Name:     Datapath
// Project Name:    CMPEN 331 Extra Credit
// Target Devices:  XC7Z010-CLG400-1
// Description: 
//              Implementation of a 5-stage pipelined CPU including:
//                  - Instruction Fetch (IF)
//                  - Instruction Decode (ID)
//                  - Execution (EXE)
//                  - Memory Access (MEM)
//                  - Write Back (WB)
//
//                  - Hazard handling
//                  - Forwarding support
// 
//              Project Requirements:
//                  - Based on the Lab 5 honor-option pipelined CPU design
//                  - Supports synthesis, implementation, and bitstream generation
//                  - Top-level ports include clk and wdi[31:0]
//             
// Instructions Implemented (PC starts at 0):
//   0x00: lui  $1,  0          0x1c: addi $5, $0, 3
//   0x04: ori  $4,  $1, 80     0x20: addi $5, $5, -1   (loop2)
//   0x08: jal  sum             0x24: ori  $8, $5, 0xffff
//   0x0c: addi $5,  $0, 4      0x28: xori $8, $8, 0x5555
//   0x10: sw   $2,  0($4)      0x2c: addi $9, $0, -1
//   0x14: lw   $9,  0($4)      0x30: andi $10,$9, 0xffff
//   0x18: sub  $8,  $9, $4     0x34: or   $6, $10, $9
//   ... (see IM module for full 35-instruction listing)
//
// Assumptions:
//   - All 32 Regfile registers initialized to 0
//   - Data memory initialized with 4 test values at addresses 0x50-0x5c
//   - Load-use stall logic (wpcir) handles lw-dependent hazards
//   - Forwarding resolves all other RAW data hazards
//   - Delayed branches: one delay slot always executes after branch/jump
//////////////////////////////////////////////////////////////////////////////////

//==============================================================================
// TOP-LEVEL DATAPATH MODULE
//==============================================================================
// This module connects all the pipeline stages together.
//
// Input:  clk - clock signal
// Output: wdi[31:0] - final writeback data from the WB stage
//
// Module Function:
// 1. Fetch, decode, execute, access memory, and write back instructions
// 2. Pass control/data signals through pipeline registers
// 3. Provide final WB-stage output for synthesis and bitstream generation
//==============================================================================

module Datapath(
    input clk,
    output [31:0] wdi
);
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    // WIRE DECLARATIONS
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    //--------------------------------------------------
    // Internal wires connect pipeline stages and modules
    // Naming convention:
    //      d* = ID stage signals
    //      e* = EXE stage signals
    //      m* = MEM stage signals
    //      w* = WB stage signals
    //--------------------------------------------------


    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    // IF Stage Wires
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    //--------------------------------------------------
    wire [31:0] pc;     // current program counter
    wire [31:0] pc4;    // PC + 4
    wire [31:0] ins;    // instruction from IM
    wire [31:0] npc;    // next PC (output of NPC mux)
    //--------------------------------------------------


    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    // IF/ID Pipeline Register Wires
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    //--------------------------------------------------
    wire [31:0] dpc4;   // PC+4 latched into ID stage
    wire [31:0] inst;   // instruction latched into ID stage
    //--------------------------------------------------


    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    // Instruction Field Wires
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    //--------------------------------------------------
    wire [5:0]  op;
    wire [5:0]  func;
    wire [4:0]  rs;
    wire [4:0]  rt;
    wire [4:0]  rd;
    wire [15:0] imm;
    wire [25:0] addr;   // 26-bit jump target field

    assign op   = inst[31:26];
    assign rs   = inst[25:21];
    assign rt   = inst[20:16];
    assign rd   = inst[15:11];
    assign func = inst[5:0];
    assign imm  = inst[15:0];
    assign addr = inst[25:0];
    //--------------------------------------------------


    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    // CU Output Wires
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    //--------------------------------------------------
    wire        wreg, m2reg, wmem, aluimm, regrt;
    wire        jal, sext, shift, wpcir;
    wire [3:0]  aluc;
    wire [1:0]  pcsrc;
    wire [1:0]  fwda, fwdb;
    //--------------------------------------------------


    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    // ID Stage Wires
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    //--------------------------------------------------
    wire [31:0] jpc;        // jump target address (JShift)
    wire [31:0] ioffset;    // sign-extended + <<2 branch offset (ImmShift)
    wire [31:0] bpc;        // branch target: dpc4 + ioffset
    wire [4:0]  drn;        // destination register (Mux2_5b)
    wire [31:0] dimm;       // extended immediate (Ext)
    wire [31:0] qa, qb;     // raw register file outputs
    wire [31:0] da, db;     // forwarded rs, rt values
    wire        rsrtequ;    // 1 if da == db (EqCheck)
    //--------------------------------------------------


    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    // ID/EXE Pipeline Register Wires
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    //--------------------------------------------------
    wire        ewreg, em2reg, ewmem, ejal, ealuimm, eshift;
    wire [3:0]  ealuc;
    wire [31:0] epc4;
    wire [31:0] ea, eb;     // forwarded rs, rt latched into EXE
    wire [31:0] eimm;
    wire [4:0]  ern0;       // destination register before f-component
    //--------------------------------------------------


    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    // EXE Stage Wires
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    //--------------------------------------------------
    wire [31:0] epc8;       // PC+8 (return address for jal)
    wire [31:0] sa;         // zero-extended shamt: {27'b0, eimm[10:6]}
    wire [31:0] alu_a;      // ALU operand a (ea or sa)
    wire [31:0] alu_b;      // ALU operand b (eb or eimm)
    wire [31:0] r;          // raw ALU result
    wire [31:0] ealu;       // final EXE result (r or epc8 for jal)
    wire [4:0]  ern;        // destination register after f-component
    
    // sa: zero-extended shift amount from instruction field eimm[10:6]
    assign sa = {27'b0, eimm[10:6]};
    //--------------------------------------------------


    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    // EXE/MEM Pipeline Register Wires
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    //--------------------------------------------------
    wire        mwreg, mm2reg, mwmem;
    wire [31:0] malu;       // ALU result / return address in MEM
    wire [31:0] mb;         // store data (rt value) for sw
    wire [4:0]  mrn;        // destination register in MEM
    //--------------------------------------------------


    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    // MEM Stage Wires
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    //--------------------------------------------------
    wire [31:0] mmo;        // memory memory output (DataMem do)
    //--------------------------------------------------


    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    // MEM/WB Pipeline Register Wires
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    //--------------------------------------------------
    wire        wwreg, wm2reg;
    wire [31:0] wmo;        // writeback memory output (from MEMWB)
    wire [31:0] walu;       // ALU result in WB
    wire [4:0]  wrn;        // destination register in WB
    //--------------------------------------------------
    

    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    // WB Stage Wires
    //◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇◇
    //--------------------------------------------------
    // wdi is declared as output port — no internal wire needed
    //--------------------------------------------------




    //◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
    // STAGE 1: INSTRUCTION FETCH (IF)
    //◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
    //--------------------------------------------------

    // Program Counter: holds fetch address, holds on stall
    PC pc_reg (
        .clk(clk), .wpcir(wpcir),
        .npc(npc),
        .pc(pc)
    );

    // PC + 4: sequential next address
    Add32 pc_add4 (
        .a(pc), .b(32'd4),
        .y(pc4)
    );

    // Instruction Memory: combinational read
    IM im (
        .a(pc),
        .do(ins)
    );

    // IF/ID Register: latches pc4 and instruction, holds on stall
    IFID ifid (
        .clk(clk), .wpcir(wpcir),
        .pc4(pc4), .ins(ins),
        .dpc4(dpc4), .inst(inst)
    );

    //--------------------------------------------------




    //◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
    // STAGE 2: INSTRUCTION DECODE (ID)
    //◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
    //--------------------------------------------------

    // Control Unit: generates all control signals, forwarding selects, stall
    CU cu (
        .op(op), .func(func), .rs(rs), .rt(rt),
        .ewreg(ewreg), .em2reg(em2reg), .ern(ern),
        .mwreg(mwreg), .mm2reg(mm2reg), .mrn(mrn),
        .rsrtequ(rsrtequ),
        .wreg(wreg), .m2reg(m2reg), .wmem(wmem),
        .aluc(aluc), .aluimm(aluimm), .regrt(regrt),
        .jal(jal), .sext(sext), .shift(shift),
        .pcsrc(pcsrc), .wpcir(wpcir),
        .fwda(fwda), .fwdb(fwdb)
    );

    // Register File: reads combinationally, writes on negedge clk
    Regfile regfile (
        .clk(clk),
        .rna(rs), .rnb(rt),
        .we(wwreg), .d(wdi), .wn(wrn),
        .qa(qa), .qb(qb)
    );

    // Destination Register Mux: regrt=0 → rd (R-type), regrt=1 → rt (I-type)
    Mux2_5b drn_mux (
        .rd(rd), .rt(rt), .regrt(regrt),
        .drn(drn)
    );

    // Immediate Extender: sign or zero extends based on sext
    Ext ext (
        .imm(imm), .sext(sext),
        .dimm(dimm)
    );

    // Jump Address Shift: 26-bit addr << 2 → jpc
    JShift jshift (
        .addr(addr),
        .jpc(jpc)
    );

    // Branch Offset Shift: sign_extend(imm) << 2 → ioffset
    ImmShift immshift (
        .imm(imm),
        .ioffset(ioffset)
    );

    // Branch Target: dpc4 + ioffset → bpc
    Add32 bpc_add (
        .a(dpc4), .b(ioffset),
        .y(bpc)
    );

    // Forwarding Mux A (rs): 00=qa, 01=ealu(EXE), 10=malu(MEM), 11=mmo(load)
    Mux4_32b fwda_mux (
        .d0(qa), .d1(ealu), .d2(malu), .d3(mmo),
        .sel(fwda),
        .y(da)
    );

    // Forwarding Mux B (rt): 00=qb, 01=ealu(EXE), 10=malu(MEM), 11=mmo(load)
    Mux4_32b fwdb_mux (
        .d0(qb), .d1(ealu), .d2(malu), .d3(mmo),
        .sel(fwdb),
        .y(db)
    );

    // Equality Check: da == db → rsrtequ (for beq/bne branch resolution)
    EqCheck eqcheck (
        .da(da), .db(db),
        .rsrtequ(rsrtequ)
    );

    // NPC Mux: 00=pc4(seq), 01=bpc(branch), 10=da(jr), 11=jpc(j/jal)
    Mux4_32b npc_mux (
        .d0(pc4), .d1(bpc), .d2(da), .d3(jpc),
        .sel(pcsrc),
        .y(npc)
    );

    // ID/EXE Register: latches all ID signals on posedge clk
    IDEXE idexe (
        .clk(clk),
        .wreg(wreg), .m2reg(m2reg), .wmem(wmem), .jal(jal),
        .aluc(aluc), .aluimm(aluimm), .shift(shift),
        .dpc4(dpc4), .da(da), .db(db), .dimm(dimm), .drn(drn),
        .ewreg(ewreg), .em2reg(em2reg), .ewmem(ewmem), .ejal(ejal),
        .ealuc(ealuc), .ealuimm(ealuimm), .eshift(eshift),
        .epc4(epc4), .ea(ea), .eb(eb), .eimm(eimm), .ern0(ern0)
    );

    //--------------------------------------------------




    //◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
    // STAGE 3: EXECUTION (EXE)
    //◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
    //--------------------------------------------------

    // PC+8: return address stored by jal into $31
    Add32 epc8_add (
        .a(epc4), .b(32'd4),
        .y(epc8)
    );

    // Shift Amount Mux: eshift=1 → sa (shamt); eshift=0 → ea (rs)
    Mux2_32b shamt_mux (
        .d0(ea), .d1(sa),
        .sel(eshift),
        .y(alu_a)
    );

    // Immediate Mux: ealuimm=1 → eimm (immediate); ealuimm=0 → eb (rt)
    Mux2_32b imm_mux (
        .d0(eb), .d1(eimm),
        .sel(ealuimm),
        .y(alu_b)
    );

    // ALU: performs arithmetic, logic, and shift operations
    ALU alu (
        .a(alu_a), .b(alu_b), .aluc(ealuc),
        .r(r)
    );

    // JAL Result Mux: ejal=1 → ealu=epc8; ejal=0 → ealu=r (ALU result)
    Mux2_32b jal_mux (
        .d0(r), .d1(epc8),
        .sel(ejal),
        .y(ealu)
    );

    // F Module: ejal=1 → ern=31; ejal=0 → ern=ern0
    F f_module (
        .ern0(ern0), .ejal(ejal),
        .ern(ern)
    );

    // EXE/MEM Register: latches EXE results on posedge clk
    EXEMEM exemem (
        .clk(clk),
        .ewreg(ewreg), .em2reg(em2reg), .ewmem(ewmem),
        .ealu(ealu), .eb(eb), .ern(ern),
        .mwreg(mwreg), .mm2reg(mm2reg), .mwmem(mwmem),
        .malu(malu), .mb(mb), .mrn(mrn)
    );

    //--------------------------------------------------




    //◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
    // STAGE 4: MEMORY ACCESS (MEM)
    //◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
    //--------------------------------------------------

    // Data Memory: combinational read, negedge write
    DataMem datamem (
        .clk(clk), .a(malu), .di(mb), .we(mwmem),
        .do(mmo)
    );

    // MEM/WB Register: latches MEM results on posedge clk
    MEMWB memwb (
        .clk(clk),
        .mwreg(mwreg), .mm2reg(mm2reg),
        .mmo(mmo), .malu(malu), .mrn(mrn),
        .wwreg(wwreg), .wm2reg(wm2reg),
        .wmo(wmo), .walu(walu), .wrn(wrn)
    );

    //--------------------------------------------------




    //◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
    // STAGE 5: WRITE BACK (WB)
    //◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
    //--------------------------------------------------

    // WB Mux: wm2reg=1 → wdi=wmo (memory load); wm2reg=0 → wdi=walu (ALU)
    Mux2_32b wb_mux (
        .d0(walu), .d1(wmo),
        .sel(wm2reg),
        .y(wdi)
    );

    // wdi is the top-level output port — drives regfile write port directly

    //--------------------------------------------------

endmodule




//◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈
// HELPER MODULES - Generic reusable modules
//◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈


//◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈
// Mux4_32b - 4-to-1 Multiplexer
//◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈
//--------------------------------------------------
// Selects one of four 32-bit inputs based on a 2-bit select signal.
// Used for forwarding (fwda, fwdb) and next PC selection (pcsrc).
//
// Inputs:
//   d0   - input 0
//   d1   - input 1
//   d2   - input 2
//   d3   - input 3
//   sel  - 2-bit select signal
//
// Outputs:
//   y    - selected output (32 bits)
//--------------------------------------------------

module Mux4_32b(
    input [31:0] d0,
    input [31:0] d1,
    input [31:0] d2,
    input [31:0] d3,
    input [1:0] sel,
    output reg [31:0] y
);
    always @(*) begin
        case(sel)
            2'b00: y = d0;
            2'b01: y = d1;
            2'b10: y = d2;
            2'b11: y = d3;
            default: y = d0;
        endcase
    end

endmodule



//◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈
// Mux2_32b - 2-to-1 Multiplexer
//◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈
//--------------------------------------------------
// Selects one of two 32-bit inputs based on a 1-bit select signal.
// Used for ALU operand select, shift amount select,
// JAL result override, and writeback select.
//
// Inputs:
//   d0  - input 0 (selected when sel = 0)
//   d1  - input 1 (selected when sel = 1)
//   sel - 1-bit select signal
//
// Outputs:
//   y   - selected output (32 bits)
//--------------------------------------------------

module Mux2_32b(
    input [31:0] d0,
    input [31:0] d1,
    input sel,
    output reg [31:0] y
);
    always @(*) begin
        if (sel) y = d1;
        else     y = d0;
    end

endmodule



//◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈
// Add32 - 32-bit Adder
//◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈◈
//--------------------------------------------------
// Adds two 32-bit values combinationally.
//
// Inputs:
//   a   - first operand (32 bits)
//   b   - second operand (32 bits)
//
// Outputs:
//   y   - sum (32 bits)
//--------------------------------------------------

module Add32(
    input [31:0] a,
    input [31:0] b,
    output reg [31:0] y
);
    always @(*) begin
        y = a + b;
    end

endmodule




//==============================================================================
// STAGE 1: INSTRUCTION FETCH (IF) MODULES
//==============================================================================

//------------------------------------------------------------------------------
// PC - Program Counter
//------------------------------------------------------------------------------
// Holds the address of the current instruction being fetched.
// Starts at address 0 for full test program.
//
// Inputs:
//   clk     - clock signal (update PC on positive edge)
//   wpcir   - write enable (1=update PC, 0=stall/hold)
//   npc     - next PC value selected by NPC mux (32 bits)
//
// Outputs:
//   pc      - current program counter value (32 bits)
//------------------------------------------------------------------------------

module PC(
    input clk,
    input wpcir,
    input [31:0] npc,
    output reg [31:0] pc
);
    // Initialize PC
    initial begin
        pc = 32'd0;
    end
    
    // Update PC (Positive Clock Edge)
    always @(posedge clk) begin
        if (wpcir) pc <= npc;
    end
    
endmodule



//------------------------------------------------------------------------------
// IM - Instruction Memory
//------------------------------------------------------------------------------
// Stores the program instructions. Read-only memory.
//
// Inputs:
//   a   - program counter / address to read from (32 bits)
//
// Outputs:
//   do  - instruction at the given address (32 bits)
//------------------------------------------------------------------------------

module IM(
    input [31:0] a,
    output reg [31:0] do
);
    // Instruction Memory Array
    reg [31:0] memory [0:63];  // 64 instruction words; each is 32 bits
        
    // Initialize Instructions
    integer i;
    initial begin
        // Clear instruction memory
        for (i = 0; i < 64; i = i + 1) begin
            memory[i] = 32'h00000000;
        end
    
        // I-type: opcode(6) | rs(5) | rt(5) | immediate (16)
        // R-type: opcode(6) | rs(5) | rt(5) | rd(5) | shamt(5) | funct(6)
                                   
        memory[0]  = 32'h3c010000; // (00) main:   lui  $1, 0
        memory[1]  = 32'h34240050; // (04)         ori  $4, $1, 80
        memory[2]  = 32'h0c00001b; // (08) call:   jal  sum
        memory[3]  = 32'h20050004; // (0c) dslot1: addi $5, $0, 4
        memory[4]  = 32'hac820000; // (10) return: sw   $2, 0($4)
        memory[5]  = 32'h8c890000; // (14)         lw   $9, 0($4)
        memory[6]  = 32'h01244022; // (18)         sub  $8, $9, $4
        memory[7]  = 32'h20050003; // (1c)         addi $5, $0, 3
        memory[8]  = 32'h20a5ffff; // (20) loop2:  addi $5, $5, -1
        memory[9]  = 32'h34a8ffff; // (24)         ori  $8, $5, 0xffff
        memory[10] = 32'h39085555; // (28)         xori $8, $8, 0x5555
        memory[11] = 32'h2009ffff; // (2c)         addi $9, $0, -1
        memory[12] = 32'h312affff; // (30)         andi $10,$9,0xffff
        memory[13] = 32'h01493025; // (34)         or   $6, $10, $9
        memory[14] = 32'h01494026; // (38)         xor  $8, $10, $9
        memory[15] = 32'h01463824; // (3c)         and  $7, $10, $6
        memory[16] = 32'h10a00003; // (40)         beq  $5, $0, shift
        memory[17] = 32'h00000000; // (44) dslot2: nop
        memory[18] = 32'h08000008; // (48)         j    loop2
        memory[19] = 32'h00000000; // (4c) dslot3: nop
        memory[20] = 32'h2005ffff; // (50) shift:  addi $5, $0, -1
        memory[21] = 32'h000543c0; // (54)         sll  $8, $5, 15
        memory[22] = 32'h00084400; // (58)         sll  $8, $8, 16
        memory[23] = 32'h00084403; // (5c)         sra  $8, $8, 16
        memory[24] = 32'h000843c2; // (60)         srl  $8, $8, 15
        memory[25] = 32'h08000019; // (64) finish: j    finish
        memory[26] = 32'h00000000; // (68) dslot4: nop
        memory[27] = 32'h00004020; // (6c) sum:    add  $8, $0, $0
        memory[28] = 32'h8c890000; // (70) loop:   lw   $9, 0($4)
        memory[29] = 32'h01094020; // (74) stall:  add  $8, $8, $9
        memory[30] = 32'h20a5ffff; // (78)         addi $5, $5, -1
        memory[31] = 32'h14a0fffc; // (7c)         bne  $5, $0, loop
        memory[32] = 32'h20840004; // (80) dslot5: addi $4, $4, 4
        memory[33] = 32'h03e00008; // (84)         jr   $31
        memory[34] = 32'h00081000; // (88) dslot6: sll  $2, $8, 0
    end
    
    // Read Instruction (Combinational Logic)
    always @(*) begin
        do = memory[a >> 2];
    end
    
endmodule



//------------------------------------------------------------------------------
// IFID - IF/ID Pipeline Register
//------------------------------------------------------------------------------
// Stores the PC+4 value and fetched instruction from the IF stage.
// Holds its current values when wpcir = 0 during a pipeline stall.
//
// Inputs:
//   clk    - clock signal
//   wpcir  - write enable for IF/ID register (1=update, 0=stall/hold)
//   pc4    - IF-stage | PC + 4 value (32 bits)
//   ins    - IF-stage | instruction from instruction memory (32 bits)
//
// Outputs:
//   dpc4   - ID-stage | PC + 4 value passed to ID stage (32 bits)
//   inst   - ID-stage | instruction passed to ID stage (32 bits)
//------------------------------------------------------------------------------

module IFID(
    input clk,
    input wpcir,
    input [31:0] pc4,
    input [31:0] ins,
    output reg [31:0] dpc4,
    output reg [31:0] inst
);
    // Store IF/ID Signals (Positive Clock Edge)
    always @(posedge clk) begin
        if (wpcir) begin
            dpc4 <= pc4;
            inst <= ins;
        end
    end
    
endmodule



//==============================================================================
// STAGE 2: INSTRUCTION DECODE (ID) MODULES
//==============================================================================

//------------------------------------------------------------------------------
// CU - Control Unit
//------------------------------------------------------------------------------
// Generates control signals based on the opcode and function code.
// Also contains the forwarding unit logic and load-use stall detection.
//
// Inputs:
//   op        - opcode field from instruction (6 bits)
//   func      - function field from instruction (6 bits)
//   rs        - source register 1 address (5 bits)
//   rt        - source register 2 address (5 bits)
//   ewreg     - EXE-stage | register write enable
//   em2reg    - EXE-stage | memory-to-register control
//   ern       - EXE-stage | final destination register after jal override (5 bits)
//   mwreg     - MEM-stage | register write enable
//   mm2reg    - MEM-stage | memory-to-register control
//   mrn       - MEM-stage | destination register passed from EXE/MEM (5 bits)
//   rsrtequ   - ID-stage  | 1 if forwarded rs == forwarded rt (for beq/bne)
//
// Outputs:
//   wreg    - ID-stage | write enable for register file
//   m2reg   - ID-stage | memory to register (1=load, 0=ALU result)
//   wmem    - ID-stage | write enable for data memory
//   aluc    - ID-stage | ALU control (4 bits)
//   aluimm  - ID-stage | ALU operand B select (1=immediate, 0=register)
//   regrt   - destination register select (0=rd, 1=rt)
//   jal     - ID-stage | 1 if instruction is jal; later forces ern=31 and ealu=PC+8
//   sext    - immediate extension mode (1=sign extend, 0=zero extend)
//   shift   - ID-stage | 1 if this is a shift instruction (ALU uses shamt from eimm[10:6])
//   pcsrc   - PC source select (00=pc4, 01=bpc, 10=da, 11=jpc)
//   wpcir   - write enable for PC and IFID (0=stall, 1=normal)
//   fwda    - forwarding select for rs (00=reg, 01=EXE ALU, 10=MEM ALU, 11=MEM load)
//   fwdb    - forwarding select for rt (00=reg, 01=EXE ALU, 10=MEM ALU, 11=MEM load)
//------------------------------------------------------------------------------

module CU(
    input [5:0] op,
    input [5:0] func,
    input [4:0] rs,
    input [4:0] rt,
    input ewreg,
    input em2reg,
    input [4:0] ern,
    input mwreg,
    input mm2reg,
    input [4:0] mrn,
    input rsrtequ,
    output reg wreg,
    output reg m2reg,
    output reg wmem,
    output reg [3:0] aluc,
    output reg aluimm,
    output reg regrt,
    output reg jal,
    output reg sext,
    output reg shift,
    output reg [1:0] pcsrc,
    output reg wpcir,
    output reg [1:0] fwda,
    output reg [1:0] fwdb
);
    reg i_rs, i_rt, stall;
    
    // Generate Control Signals (Combinational Logic)
    always @(*) begin
        //--------------------------------------------------
        // Defaults (safe no-op state)
        //--------------------------------------------------
        wreg   = 1'b0;
        m2reg  = 1'b0;
        wmem   = 1'b0;
        aluc   = 4'b0000;
        aluimm = 1'b0;
        regrt  = 1'b0;
        jal    = 1'b0;
        sext   = 1'b1;      // sign extend by default
        shift  = 1'b0;
        pcsrc  = 2'b00;
        i_rs   = 1'b0;
        i_rt   = 1'b0;
        
        case(op)
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            // R-TYPE
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            //--------------------------------------------------
            6'b000000: begin
                case(func)
                    //▷▷▷ ADD
                    6'b100000: begin        
                        wreg = 1'b1;
                        aluc = 4'b0010;   // ADD
                        i_rs = 1'b1;
                        i_rt = 1'b1;
                    end
                    
                    //▷▷▷ SUB
                    6'b100010: begin
                        wreg = 1'b1;
                        aluc = 4'b0110;   // SUB
                        i_rs = 1'b1;
                        i_rt = 1'b1;
                    end
                    
                    //▷▷▷ AND
                    6'b100100: begin
                        wreg = 1'b1;
                        aluc = 4'b0000;   // AND
                        i_rs = 1'b1;
                        i_rt = 1'b1;
                    end
                    
                    //▷▷▷ OR
                    6'b100101: begin
                        wreg = 1'b1;
                        aluc = 4'b0001;   // OR
                        i_rs = 1'b1;
                        i_rt = 1'b1;
                    end
                    
                    //▷▷▷ XOR
                    6'b100110: begin
                        wreg = 1'b1;
                        aluc = 4'b0011;   // XOR
                        i_rs = 1'b1;
                        i_rt = 1'b1;
                    end
                    
                    //▷▷▷ SLL (also covers NOP when all fields = 0)
                    6'b000000: begin
                        wreg  = 1'b1;
                        aluc  = 4'b0100;  // SLL
                        shift = 1'b1;     // use shamt from eimm32[10:6]
                        i_rt  = 1'b1;     // source is rt (rs field unused for shifts)
                    end
                    
                    //▷▷▷ SRL
                    6'b000010: begin
                        wreg  = 1'b1;
                        aluc  = 4'b0101;  // SRL
                        shift = 1'b1;
                        i_rt  = 1'b1;
                    end
                    
                    //▷▷▷ SRA
                    6'b000011: begin
                        wreg  = 1'b1;
                        aluc  = 4'b0111;  // SRA
                        shift = 1'b1;
                        i_rt  = 1'b1;
                    end
                    
                    //▷▷▷ JR
                    6'b001000: begin
                        pcsrc = 2'b10;    // da: target is register rs
                        i_rs  = 1'b1;
                    end
                    
                    //▷▷▷ DEFAULT
                    default: begin end
                endcase
            end
            //--------------------------------------------------
            
            
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            // LW
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            //--------------------------------------------------
            6'b100011: begin
                wreg   = 1'b1;
                m2reg  = 1'b1;
                aluc   = 4'b0010;   // ADD (compute address)
                aluimm = 1'b1;
                regrt  = 1'b1;
                i_rs   = 1'b1;      // base address from rs
            end
            //--------------------------------------------------
            
            
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            // SW
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            //--------------------------------------------------
            6'b101011: begin
                wmem   = 1'b1;
                aluc   = 4'b0010;   // ADD (compute address)
                aluimm = 1'b1;
                i_rs   = 1'b1;      // base address from rs
                i_rt   = 1'b1;      // data to store from rt
            end
            //--------------------------------------------------
            
            
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            // ADDI
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            //--------------------------------------------------
            6'b001000: begin
                wreg   = 1'b1;
                aluc   = 4'b0010;   // ADD
                aluimm = 1'b1;
                regrt  = 1'b1;
                i_rs   = 1'b1;
            end
            //--------------------------------------------------
            
            
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            // ANDI
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            //--------------------------------------------------
            6'b001100: begin
                wreg   = 1'b1;
                aluc   = 4'b0000;   // AND
                aluimm = 1'b1;
                regrt  = 1'b1;
                sext   = 1'b0;      // zero extend
                i_rs   = 1'b1;
            end
            //--------------------------------------------------
            
            
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            // ORI
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            //--------------------------------------------------
            6'b001101: begin
                wreg   = 1'b1;
                aluc   = 4'b0001;   // OR
                aluimm = 1'b1;
                regrt  = 1'b1;
                sext   = 1'b0;      // zero extend
                i_rs   = 1'b1;
            end
            //--------------------------------------------------
            
            
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            // XORI
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            //--------------------------------------------------
            6'b001110: begin
                wreg   = 1'b1;
                aluc   = 4'b0011;   // XOR
                aluimm = 1'b1;
                regrt  = 1'b1;
                sext   = 1'b0;      // zero extend
                i_rs   = 1'b1;
            end
            //--------------------------------------------------
            
            
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            // LUI
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            //--------------------------------------------------
            6'b001111: begin
                wreg   = 1'b1;
                aluc   = 4'b1000;   // LUI: result = {imm, 16'b0}
                aluimm = 1'b1;
                regrt  = 1'b1;
                sext   = 1'b0;
            end
            //--------------------------------------------------
           
           
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            // BEQ
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            //--------------------------------------------------
            6'b000100: begin
                pcsrc = rsrtequ ? 2'b01 : 2'b00;   // bpc if equal
                i_rs  = 1'b1;
                i_rt  = 1'b1;
            end
            //--------------------------------------------------
            
            
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            // BNE
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            //--------------------------------------------------
            6'b000101: begin
                pcsrc = rsrtequ ? 2'b00 : 2'b01;   // bpc if not equal
                i_rs  = 1'b1;
                i_rt  = 1'b1;
            end
            //--------------------------------------------------
            
            
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            // J
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            //--------------------------------------------------
            6'b000010: begin
                pcsrc = 2'b11;      // jpc
            end
            //--------------------------------------------------
            
            
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            // JAL
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            //--------------------------------------------------
            6'b000011: begin
                wreg  = 1'b1;       // write PC+8 to $31
                jal   = 1'b1;       // EXE: override ern=31, result=epc8
                pcsrc = 2'b11;      // jpc
            end
            //--------------------------------------------------
            
            
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            // DEFAULT
            //▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷▷
            //--------------------------------------------------
            default: begin end
            //--------------------------------------------------
        endcase
        
        
        //--------------------------------------------------
        // Load-Use Stall Detection
        // stall when lw is in EXE and its destination matches
        // a source register of the instruction currently in ID
        //--------------------------------------------------
        stall = ewreg & em2reg & (ern != 5'b0) & ((i_rs & (ern == rs)) | (i_rt & (ern == rt)));
        wpcir = ~stall;
        
        // Bubble: zero out state-changing signals so the stalled
        // instruction does not corrupt registers or memory
        if (stall) begin
            wreg  = 1'b0;
            wmem  = 1'b0;
            m2reg = 1'b0;
            jal   = 1'b0;
        end
        
        //--------------------------------------------------
        // Forward Register rs (fwda)
        //--------------------------------------------------
        if      (ewreg && !em2reg && (ern != 5'b0) && (ern == rs)) fwda = 2'b01;
        else if (mwreg && !mm2reg && (mrn != 5'b0) && (mrn == rs)) fwda = 2'b10;
        else if (mwreg &&  mm2reg && (mrn != 5'b0) && (mrn == rs)) fwda = 2'b11;
        else fwda = 2'b00;
        
        //--------------------------------------------------
        // Forward Register rt (fwdb)
        //--------------------------------------------------
        if      (ewreg && !em2reg && (ern != 5'b0) && (ern == rt)) fwdb = 2'b01;
        else if (mwreg && !mm2reg && (mrn != 5'b0) && (mrn == rt)) fwdb = 2'b10;
        else if (mwreg &&  mm2reg && (mrn != 5'b0) && (mrn == rt)) fwdb = 2'b11;
        else fwdb = 2'b00;
        
    end
    
endmodule



//------------------------------------------------------------------------------
// JShift - Jump Address Shifter
//------------------------------------------------------------------------------
// Shifts the 26-bit jump address field left by 2
// to produce the jump target address jpc for j and jal instructions.
//
// Inputs:
//   addr  - ID-stage | 26-bit jump address field from instruction
//
// Outputs:
//   jpc   - jump target address (32 bits)
//------------------------------------------------------------------------------

module JShift(
    input [25:0] addr,
    output reg [31:0] jpc
);
    // Shift Left 2 (Combinational Logic)
    always @(*) begin
        jpc = addr << 2;
    end

endmodule



//------------------------------------------------------------------------------
// ImmShift - Immediate Shifter
//------------------------------------------------------------------------------
// Sign-extends the 16-bit immediate and shifts left by 2
// to produce the branch offset for bpc calculation.
//
// Inputs:
//   imm      - ID-stage | 16-bit immediate field from instruction
//
// Outputs:
//   ioffset  - sign-extended and left-shifted branch offset (32 bits)
//------------------------------------------------------------------------------

module ImmShift(
    input [15:0] imm,
    output reg [31:0] ioffset
);
    // Sign-Extend and Shift Left 2 (Combinational Logic)
    always @(*) begin
        ioffset = {{16{imm[15]}}, imm} << 2;
    end

endmodule



//------------------------------------------------------------------------------
// Regfile - Register File
//------------------------------------------------------------------------------
// Contains 32 general-purpose registers.
// Provides two read ports and one write port.
// All registers are initialized to 0.
// Register $0 is hardwired to 0 and cannot be overwritten.
//
// Inputs:
//   clk  - clock signal
//   rna  - ID-stage | source register 1 address (5 bits)
//   rnb  - ID-stage | source register 2 address (5 bits)
//   we   - WB-stage | register write enable
//   d    - WB-stage | writeback data (32 bits)
//   wn   - WB-stage | destination register address (5 bits)
//
// Outputs:
//   qa   - ID-stage | data from register rna (32 bits)
//   qb   - ID-stage | data from register rnb (32 bits)
//------------------------------------------------------------------------------

module Regfile(
    input clk,
    input [4:0] rna,
    input [4:0] rnb,
    input we,
    input [31:0] d,
    input [4:0] wn,
    output reg [31:0] qa,
    output reg [31:0] qb
);
    reg [31:0] regs [0:31];
    
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            regs[i] = 32'b0;
        end
    end
    
    // Read Registers (Combinational Logic)
    always @(*) begin
        qa = regs[rna];
        qb = regs[rnb];
    end
    
    // Write Register (Negative Clock Edge)
    always @(negedge clk) begin
        if (we && wn != 5'b0)
            regs[wn] <= d;
    end
    
endmodule



//------------------------------------------------------------------------------
// Ext - Immediate Extender
//------------------------------------------------------------------------------
// Extends the 16-bit immediate value to 32 bits.
// Uses sign extension or zero extension based on sext.
//
// Inputs:
//   imm    - 16-bit immediate value from instruction
//   sext   - extension mode (1 = sign extend, 0 = zero extend)
//
// Outputs:
//   dimm   - 32-bit extended immediate
//------------------------------------------------------------------------------

module Ext(
    input [15:0] imm,
    input sext,
    output reg [31:0] dimm
);
    // Extend Immediate (Combinational Logic)
    always @(*) begin
        if (sext)
            dimm = {{16{imm[15]}}, imm};   // sign extend
        else
            dimm = {16'b0, imm};            // zero extend (ori, andi, xori)
    end

endmodule



//------------------------------------------------------------------------------
// EqCheck - Equality Comparator
//------------------------------------------------------------------------------
// Compares two forwarded register values for branch resolution in the ID stage.
// Used by beq and bne to determine whether to take the branch.
//
// Inputs:
//   da       - forwarded rs operand (32 bits)
//   db       - forwarded rt operand (32 bits)
//
// Outputs:
//   rsrtequ  - 1 if da == db, 0 otherwise
//------------------------------------------------------------------------------

module EqCheck(
    input [31:0] da,
    input [31:0] db,
    output reg rsrtequ
);
    always @(*) begin
        rsrtequ = (da == db);
    end

endmodule



//------------------------------------------------------------------------------
// Mux2_5b - Destination Register Multiplexer
//------------------------------------------------------------------------------
// Selects the destination register number.
// For R-type instructions, destination is rd.
// For I-type instructions (like lw, addi, ori, etc.), destination is rt.
// Drawn "backward" in the diagram to signal it is NOT the same as Mux2_32b.
//
// Inputs:
//   rd     - destination register for R-type (5 bits)
//   rt     - destination register for I-type (5 bits)
//   regrt  - select signal (0 = rd, 1 = rt)
//
// Outputs:
//   drn    - selected destination register (5 bits)
//------------------------------------------------------------------------------

module Mux2_5b(
    input [4:0] rd,
    input [4:0] rt,
    input regrt,
    output reg [4:0] drn
);
    // Select Destination Register (Combinational Logic)
    always @(*) begin
        if (regrt == 1'b0)
            drn = rd;
        else
            drn = rt;
    end

endmodule



//------------------------------------------------------------------------------
// IDEXE - ID/EXE Pipeline Register
//------------------------------------------------------------------------------
// Stores all control signals and data from ID stage for use in EXE stage.
// Updates on the positive edge of the clock.
//
// Inputs:
//   clk      - clock signal
//   wreg     - ID-stage | write register enable
//   m2reg    - ID-stage | memory to register
//   wmem     - ID-stage | write memory enable
//   jal      - ID-stage | 1 if jal instruction
//   aluc     - ID-stage | ALU control (4 bits)
//   aluimm   - ID-stage | ALU operand B select (1=immediate, 0=register)
//   shift    - ID-stage | 1 if shift instruction (ALU uses shamt)
//   dpc4     - ID-stage | PC+4 value (32 bits, needed for jal PC+8)
//   da       - ID-stage | forwarded rs operand (32 bits)
//   db       - ID-stage | forwarded rt operand (32 bits)
//   dimm     - ID-stage | sign/zero extended immediate (32 bits)
//   drn      - ID-stage | destination register number (5 bits)
//
// Outputs:
//   ewreg    - EXE-stage | write register enable
//   em2reg   - EXE-stage | memory to register
//   ewmem    - EXE-stage | write memory enable
//   ejal     - EXE-stage | jal flag
//   ealuc    - EXE-stage | ALU control
//   ealuimm  - EXE-stage | ALU operand B select
//   eshift   - EXE-stage | shift flag
//   epc4     - EXE-stage | PC+4 value
//   ea       - EXE-stage | forwarded rs operand
//   eb       - EXE-stage | forwarded rt operand
//   eimm     - EXE-stage | extended immediate
//   ern0     - EXE-stage | destination register number (before f-component override)
//------------------------------------------------------------------------------

module IDEXE(
    input clk,
    input wreg,
    input m2reg,
    input wmem,
    input jal,
    input [3:0] aluc,
    input aluimm,
    input shift,
    input [31:0] dpc4,
    input [31:0] da,
    input [31:0] db,
    input [31:0] dimm,
    input [4:0] drn,
    output reg ewreg,
    output reg em2reg,
    output reg ewmem,
    output reg ejal,
    output reg [3:0] ealuc,
    output reg ealuimm,
    output reg eshift,
    output reg [31:0] epc4,
    output reg [31:0] ea,
    output reg [31:0] eb,
    output reg [31:0] eimm,
    output reg [4:0] ern0
);
    // Initialize to safe no-op state so wpcir is not X at t=0
    initial begin
        ewreg   = 1'b0;
        em2reg  = 1'b0;
        ewmem   = 1'b0;
        ejal    = 1'b0;
        ealuc   = 4'b0;
        ealuimm = 1'b0;
        eshift  = 1'b0;
        epc4    = 32'b0;
        ea      = 32'b0;
        eb      = 32'b0;
        eimm    = 32'b0;
        ern0    = 5'b0;
    end

    // Store ID/EXE Signals (Positive Clock Edge)
    always @(posedge clk) begin
        ewreg   <= wreg;
        em2reg  <= m2reg;
        ewmem   <= wmem;
        ejal    <= jal;
        ealuc   <= aluc;
        ealuimm <= aluimm;
        eshift  <= shift;
        epc4    <= dpc4;
        ea      <= da;
        eb      <= db;
        eimm    <= dimm;
        ern0    <= drn;
    end

endmodule



//==============================================================================
// STAGE 3: EXECUTION (EXE) MODULES
//==============================================================================

//------------------------------------------------------------------------------
// ALU - Arithmetic Logic Unit
//------------------------------------------------------------------------------
// Performs arithmetic, logic, and shift operations.
//
// Inputs:
//   a     - first operand (32 bits): rs value or zero-extended shamt
//   b     - second operand (32 bits): rt value or sign/zero extended immediate
//   aluc  - ALU control signal (4 bits)
//
// Outputs:
//   r     - ALU result (32 bits)
//------------------------------------------------------------------------------

module ALU (
    input [31:0] a,
    input [31:0] b,
    input [3:0] aluc,
    output reg [31:0] r
);
    // Execute ALU Operation (Combinational Logic)
    always @(*) begin
        case (aluc)
            4'b0010: r = a + b;                     // ADD
            4'b0110: r = a - b;                     // SUB
            4'b0000: r = a & b;                     // AND
            4'b0001: r = a | b;                     // OR
            4'b0011: r = a ^ b;                     // XOR
            4'b0100: r = b << a[4:0];               // SLL
            4'b0101: r = b >> a[4:0];               // SRL
            4'b0111: r = $signed(b) >>> a[4:0];     // SRA
            4'b1000: r = {b[15:0], 16'b0};          // LUI
            default: r = 32'b0;
        endcase
    end

endmodule



//------------------------------------------------------------------------------
// F - JAL Destination Override (f-component)
//------------------------------------------------------------------------------
// Overrides the destination register to $31 when the instruction is jal.
// For all other instructions, passes ern0 through unchanged.
//
// Inputs:
//   ern0  - EXE-stage | destination register before override (5 bits)
//   ejal  - EXE-stage | 1 if jal instruction
//
// Outputs:
//   ern   - EXE-stage | final destination register (5 bits)
//------------------------------------------------------------------------------

module F(
    input [4:0] ern0,
    input ejal,
    output reg [4:0] ern
);
    always @(*) begin
        if (ejal)
            ern = 5'd31;
        else
            ern = ern0;
    end

endmodule



//------------------------------------------------------------------------------
// EXEMEM - EXE/MEM Pipeline Register
//------------------------------------------------------------------------------
// Stores EXE stage results and control signals.
// Passes data to MEM stage on clock edge.
// Receives final ern (after F override) and ealu (after jal mux).
//
// Inputs:
//   clk    - clock signal
//   ewreg  - EXE-stage | register write enable
//   em2reg - EXE-stage | memory to register
//   ewmem  - EXE-stage | memory write enable
//   ealu   - EXE-stage | final result (ALU result or PC+8)
//   eb     - EXE-stage | forwarded rt value (store data for sw)
//   ern    - EXE-stage | final destination register (after f-component)
//
// Outputs:
//   mwreg  - MEM-stage | register write enable
//   mm2reg - MEM-stage | memory to register
//   mwmem  - MEM-stage | memory write enable
//   malu   - MEM-stage | ALU result / return address
//   mb     - MEM-stage | store data for sw
//   mrn    - MEM-stage | destination register
//------------------------------------------------------------------------------

module EXEMEM (
    input clk,
    input ewreg,
    input em2reg,
    input ewmem,
    input [31:0] ealu,
    input [31:0] eb,
    input [4:0] ern,
    output reg mwreg,
    output reg mm2reg,
    output reg mwmem,
    output reg [31:0] malu,
    output reg [31:0] mb,
    output reg [4:0] mrn
);
    initial begin
        mwreg  = 1'b0;
        mm2reg = 1'b0;
        mwmem  = 1'b0;
        malu   = 32'b0;
        mb     = 32'b0;
        mrn    = 5'b0;
    end

    // Store EXE/MEM Signals (Positive Clock Edge)
    always @(posedge clk) begin
        mwreg  <= ewreg;
        mm2reg <= em2reg;
        mwmem  <= ewmem;
        malu   <= ealu;
        mb     <= eb;
        mrn    <= ern;
    end

endmodule



//==============================================================================
// STAGE 4: MEMORY ACCESS (MEM) MODULES
//==============================================================================

//------------------------------------------------------------------------------
// DataMem - Data Memory Unit
//------------------------------------------------------------------------------
// Reads and writes data memory using the ALU-generated address.
//
// Inputs:
//   clk  - clock signal
//   a    - memory address from ALU result (32 bits)
//   di   - data to write into memory (32 bits)
//   we   - memory write enable (1 bit)
//
// Outputs:
//   do   - data read from memory (32 bits)
//------------------------------------------------------------------------------

module DataMem (
    input clk,
    input [31:0] a,
    input [31:0] di,
    input we,
    output reg [31:0] do
);
    // Data Memory Array
    reg [31:0] memory [0:63];
    
    // Initialize memory
    integer i;
    initial begin
        // Clear data memory
        for (i = 0; i < 64; i = i + 1) begin
            memory[i] = 32'h00000000;
        end
        
        // Project test data
        memory[20] = 32'h000000a3; // (50) data[0]   0 +  a3 =  a3 
        memory[21] = 32'h00000027; // (54) data[1]  a3 +  27 =  ca
        memory[22] = 32'h00000079; // (58) data[2]  ca +  79 = 143
        memory[23] = 32'h00000115; // (5c) data[3] 143 + 115 = 258 
        // memory[24] should become:  32'h00000258 after program execution
    end
    
    // Read Memory Data (Combinational Logic)
    always @(*) begin
        do = memory[a >> 2];
    end

    // Write Memory Data (Negative Clock Edge)
    always @(negedge clk) begin
        if (we == 1'b1)
            memory[a >> 2] <= di;
    end
    
endmodule



//------------------------------------------------------------------------------
// MEMWB - MEM/WB Pipeline Register
//------------------------------------------------------------------------------
// Stores MEM stage results and control signals.
// Passes data to WB stage on clock edge.
//
// Inputs:
//   clk    - clock signal
//   mwreg  - MEM-stage | register write enable
//   mm2reg - MEM-stage | memory to register
//   mmo    - MEM-stage | memory memory output (from DataMem)
//   malu   - MEM-stage | ALU result / return address
//   mrn    - MEM-stage | destination register
//
// Outputs:
//   wwreg  - WB-stage | register write enable
//   wm2reg - WB-stage | memory to register
//   wmo    - WB-stage | writeback memory output
//   walu   - WB-stage | ALU result / return address
//   wrn    - WB-stage | destination register
//------------------------------------------------------------------------------

module MEMWB (
    input clk,
    input mwreg,
    input mm2reg,
    input [31:0] mmo,
    input [31:0] malu,
    input [4:0] mrn,
    output reg wwreg,
    output reg wm2reg,
    output reg [31:0] wmo,
    output reg [31:0] walu,
    output reg [4:0] wrn
);
    initial begin
        wwreg  = 1'b0;
        wm2reg = 1'b0;
        wmo    = 32'b0;
        walu   = 32'b0;
        wrn    = 5'b0;
    end

    always @(posedge clk) begin
        wwreg  <= mwreg;
        wm2reg <= mm2reg;
        wmo    <= mmo;
        walu   <= malu;
        wrn    <= mrn;
    end

endmodule

