#include "Vtb_agr_complex_mult.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

vluint64_t sim_time = 0;
double sc_time_stamp() { return (double)sim_time; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    Vtb_agr_complex_mult* top = new Vtb_agr_complex_mult;

    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("wave.vcd");

    while (!Verilated::gotFinish()) {
        top->eval();
        tfp->dump(sim_time++);
    }

    tfp->close();
    top->final();
    delete top;
    return 0;
}
