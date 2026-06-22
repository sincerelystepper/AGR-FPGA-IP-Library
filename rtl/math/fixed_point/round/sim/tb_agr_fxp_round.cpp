#include "Vtb_agr_fxp_round.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
vluint64_t sim_time = 0;
double sc_time_stamp() { return sim_time; }
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    Vtb_agr_fxp_round* top = new Vtb_agr_fxp_round;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("wave.vcd");
    while (!Verilated::gotFinish()) {
        top->eval();
        tfp->dump(sim_time);
        sim_time++;
        if (sim_time > 10000000) break;
    }
    tfp->close(); top->final(); delete top;
    return 0;
}
