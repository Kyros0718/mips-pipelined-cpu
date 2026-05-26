# mips-pipelined-cpu

[![Verilog](https://img.shields.io/badge/Verilog-b22222?style=flat&logo=v&logoColor=white)](https://en.wikipedia.org/wiki/Verilog)
[![Vivado](https://img.shields.io/badge/Xilinx%20Vivado-E01F27?style=flat)](https://www.xilinx.com/products/design-tools/vivado.html)

---

A fully functional 5-stage pipelined MIPS CPU implemented in Verilog HDL and synthesized to FPGA. Supports the complete MIPS instruction set with data forwarding, load-use stall detection, delayed branch, and subroutine call/return.

## TABLE OF CONTENTS

- [Architecture](#architecture)
- [Features](#features)
- [Instruction Set](#instruction-set)
- [File Structure](#file-structure)
- [Simulation](#simulation)
- [FPGA Target](#fpga-target)
- [Verification](#verification)

---

## ARCHITECTURE

The CPU is organized as a classic 5-stage pipeline. Each stage is separated by a pipeline register that carries the instruction's data and control signals forward.

```
[ Instruction Fetch ] → [ Instruction Decode ] → [ Execute ] → [ Memory Access ] → [ Write Back ]
         ↑                        |                                                       |
         |                        └───────────────── forwarding ──────────────────────────┘
         └──────────────────────── branch resolution (ID stage) ───────────────────────────
```

**Instruction Fetch** — fetches the next instruction from instruction memory using the program counter. The next-PC logic is a 4-to-1 mux selecting between sequential, branch target, jump register, and jump address, controlled by the branch/jump decision made in Instruction Decode.

**Instruction Decode** — decodes the instruction, reads the register file, generates all control signals, resolves branches and jumps using an equality check on the two source register values, and handles forwarding into the ID/EX pipeline register. Load-use stall detection also lives here.

**Execute** — performs the ALU operation. The ALU supports ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, and LUI. A shift amount mux selects between the `shamt` field and a register value. JAL computes PC+8 here to save as the return address.

**Memory Access** — reads or writes data memory for load and store instructions.

**Write Back** — selects between ALU result and memory load data, then writes back to the register file on the negative clock edge.

---

## FEATURES

**Data Forwarding** — the forwarding unit detects read-after-write hazards and routes the most recent version of a register value directly to the instruction that needs it, selecting from the Execute-stage ALU result, the Memory-stage ALU result, or the Memory-stage load data. This eliminates stalls for all hazards except load-use.

**Load-Use Stall** — when a load instruction is immediately followed by an instruction that needs the loaded value, the pipeline freezes the program counter and the IF/ID register for one cycle and injects a bubble, giving the load time to complete before the dependent instruction reaches Execute.

**Delayed Branch** — branches and jumps are resolved in the Instruction Decode stage. The instruction in the delay slot (immediately after the branch) always executes before the transfer takes effect. This keeps the branch penalty to exactly one slot with no flushing required.

**JAL and JR** — jump-and-link saves PC+8 into register $31 (accounting for the delay slot at PC+4 which is already committed). Jump-register reads the return address from $31 and drives it into the next-PC mux.

**Full FPGA Synthesis** — the design passes RTL analysis, synthesis, implementation, and bitstream generation in Xilinx Vivado with no errors. All output pins are assigned, clock is routed to a dedicated input, and all DRC checks are satisfied.

---

## INSTRUCTION SET

| Type | Instructions |
|------|-------------|
| R-type | add, sub, and, or, xor, sll, srl, sra |
| Immediate | addi, ori, andi, xori, lui |
| Memory | lw, sw |
| Branch | beq, bne |
| Jump | j, jal, jr |

Sign extension is controlled per instruction — `andi`, `ori`, `xori`, and `lui` zero-extend their immediate fields. All others sign-extend.

---

## FILE STRUCTURE

```
mips-pipelined-cpu/
├── datapath.v              # full CPU design — all modules in one file
├── testbench.v             # simulation testbench
├── constraints.xdc         # Xilinx pin assignments and clock constraints
└── README.md
```

`datapath.v` contains all modules: PC, instruction memory, IF/ID register, register file, control unit, forwarding logic, stall detection, ALU, data memory, pipeline registers (ID/EX, EX/MEM, MEM/WB), and the top-level datapath.

---

## SIMULATION

Open Vivado and create a new project targeting the Zynq XC7Z010-CLG400-1. Add `datapath.v` and `testbench.v` as sources, with `testbench.v` set as the simulation top. Run behavioral simulation.

The testbench runs a 35-instruction program that calls a subroutine to accumulate four values from data memory using load-then-add pairs. Every load is immediately followed by a dependent add, so every iteration triggers a load-use stall. The expected final state is:

```
register $2  = 0x00000258
memory[24]   = 0x00000258
```

The input values are pre-loaded in data memory:
```
memory[20] = 0x000000A3
memory[21] = 0x00000027
memory[22] = 0x00000079
memory[23] = 0x00000115
sum        = 0x00000258
```

---

## FPGA TARGET

| Field | Value |
|-------|-------|
| Board | Zybo (Digilent) |
| Device | Xilinx Zynq XC7Z010-CLG400-1 |
| Tool | Xilinx Vivado |
| Clock pin | H16 (dedicated clock input) |
| I/O standard | LVCMOS18 |
| Top-level output | `wdi[31:0]` |

Add `constraints.xdc` to the project before running synthesis. The constraint file assigns `wdi[31:0]` to physical output pins and sets the clock period and I/O standard.

---

## VERIFICATION

Simulation confirmed:

- All three forwarding cases fire correctly in the waveform
- Load-use stall freezes the pipeline for exactly one cycle and injects a clean bubble
- Delayed branch executes the delay slot instruction before redirecting
- JAL saves the correct return address and JR returns to it
- Final accumulation result matches hand-computed expected value

Bitstream generated successfully with no DRC errors.

---

> This was an academic project. Please do not submit it as your own work.

<div align="center">

[Back to Top](#mips-pipelined-cpu)

</div>
