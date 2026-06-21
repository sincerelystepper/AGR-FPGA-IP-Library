#include <verilated.h>
#include "Vagr_spi_bridge.h"
#include <cstdio>

vluint64_t sim_time = 0;
double sc_time_stamp() { return sim_time; }

Vagr_spi_bridge* dut;

void tick() {
    dut->clk = 0; dut->eval();
    if (dut->bus_req && !dut->bus_we) {
        printf("  READ_REQ: addr=0x%04x\n", dut->bus_addr);
        dut->bus_rdata = 0xA5;
        dut->bus_ready = 1;
    }
    dut->clk = 1; dut->eval();
    if (dut->bus_ready) dut->bus_ready = 0;
}

void wait_cycles(int n) { for(int i=0;i<n;i++) tick(); }

void spi_byte_tx(uint8_t d) {
    for(int b=7;b>=0;b--) {
        dut->spi_mosi=(d>>b)&1;
        dut->spi_sck=0;wait_cycles(20);
        dut->spi_sck=1;wait_cycles(20);
    }
    dut->spi_sck=0;
}

uint8_t spi_byte_rx(uint8_t d) {
    uint8_t r=0;
    for(int b=7;b>=0;b--) {
        dut->spi_mosi=(d>>b)&1;
        dut->spi_sck=0;wait_cycles(20);
        dut->spi_sck=1;wait_cycles(20);
        r=(r<<1)|(dut->spi_miso&1);
        dut->spi_sck=0;
    }
    return r;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vagr_spi_bridge;
    // NO VCD tracing - just run fast

    dut->rst_n=0;dut->spi_csn=1;dut->spi_sck=0;
    dut->spi_mosi=0;dut->bus_ready=0;dut->bus_rdata=0;
    for(int i=0;i<10;i++) tick();
    dut->rst_n=1;wait_cycles(20);

    // WRITE
    printf("=== WRITE ===\n");
    dut->spi_csn=0;wait_cycles(20);
    spi_byte_tx(0x80);spi_byte_tx(0x12);spi_byte_tx(0x34);spi_byte_tx(0xAB);
    dut->spi_csn=1;
    bool wp=false;
    for(int i=0;i<200;i++){tick();if(dut->bus_req&&dut->bus_we&&dut->bus_addr==0x1234&&dut->bus_wdata==0xAB)wp=true;}
    wait_cycles(20);
    printf("WRITE: %s\n",wp?"PASS":"FAIL");

    // READ Transaction 1
    printf("=== READ ===\n");
    dut->spi_csn=0;wait_cycles(20);
    spi_byte_tx(0x00);spi_byte_tx(0x12);spi_byte_tx(0x34);
    dut->spi_csn=1;
    wait_cycles(200);

    // READ Transaction 2
    dut->spi_csn=0;wait_cycles(20);
    uint8_t rx = spi_byte_rx(0x00);
    dut->spi_csn=1;wait_cycles(20);
    printf("READ: 0x%02x (expected 0xA5) -> %s\n", rx, rx==0xA5?"PASS":"FAIL");

    delete dut;
    return 0;
}
