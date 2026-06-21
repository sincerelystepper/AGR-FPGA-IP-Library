VERILATOR = verilator
RTL       = ../rtl/agr_spi_bridge.sv
SIM_DIR   = obj_dir_sim
WAVE_DIR  = obj_dir_wave
WAVE_OUT  = ../waveforms/wave.vcd

.PHONY: sim wave view clean

sim:
	$(VERILATOR) -Wall -Wno-UNUSEDSIGNAL -Wno-CASEINCOMPLETE \
		--cc $(RTL) --exe tb.cpp --build -CFLAGS "-std=c++17" \
		--Mdir $(SIM_DIR)
	$(SIM_DIR)/Vagr_spi_bridge

wave:
	$(VERILATOR) -Wall --trace --trace-structs -Wno-UNUSEDSIGNAL -Wno-CASEINCOMPLETE \
		--cc $(RTL) --exe tb_wave.cpp --build -CFLAGS "-std=c++17" \
		--Mdir $(WAVE_DIR)
	cd $(WAVE_DIR) && ./Vagr_spi_bridge
	cp $(WAVE_DIR)/wave.vcd $(WAVE_OUT)

view: wave
	@echo "Would launch: gtkwave $(WAVE_OUT)"

clean:
	rm -rf $(SIM_DIR) $(WAVE_DIR)
