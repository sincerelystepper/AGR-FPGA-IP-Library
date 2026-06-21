`default_nettype none

module agr_spi_bridge #(
    parameter int ADDR_W = 16,
    parameter int DATA_W = 8
)(
    input  wire               clk,
    input  wire               rst_n,

    input  wire               spi_csn,
    input  wire               spi_sck,
    input  wire               spi_mosi,
    output logic              spi_miso,

    output logic              bus_req,
    output logic              bus_we,
    output logic [ADDR_W-1:0] bus_addr,
    output logic [DATA_W-1:0] bus_wdata,

    input  wire [DATA_W-1:0]  bus_rdata,
    input  wire               bus_ready
);

    // ============================================================
    // 1. CDC Synchronizers
    // ============================================================
    logic [2:0] cs_ff, sck_ff, mosi_ff;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs_ff   <= 3'b111;
            sck_ff  <= 3'b000;
            mosi_ff <= 3'b000;
        end else begin
            cs_ff   <= {cs_ff[1:0], spi_csn};
            sck_ff  <= {sck_ff[1:0], spi_sck};
            mosi_ff <= {mosi_ff[1:0], spi_mosi};
        end
    end

    wire sck_rise =  sck_ff[2] & ~sck_ff[1];
    wire sck_fall = ~sck_ff[2] &  sck_ff[1];
    wire cs_fall  = ~cs_ff[2]  &  cs_ff[1];
    wire cs_rise  =  cs_ff[2]  & ~cs_ff[1];
    wire mosi_d   =  mosi_ff[2];

    // ============================================================
    // 2. Bit engine
    // ============================================================
    logic [2:0] bit_cnt;
    logic [7:0] rx_shift;

    wire byte_done = sck_rise && (bit_cnt == 3'd7);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt  <= 3'd0;
            rx_shift <= 8'd0;
        end else begin
            if (cs_fall) begin
                bit_cnt <= 3'd0;
            end else if (sck_rise) begin
                rx_shift <= {rx_shift[6:0], mosi_d};
                bit_cnt  <= bit_cnt + 1;
            end
        end
    end

    // ============================================================
    // 3. Byte latch
    // ============================================================
    logic [7:0] rx_byte;
    logic       rx_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_valid <= 1'b0;
            rx_byte  <= 8'd0;
        end else begin
            rx_valid <= byte_done;
            if (byte_done)
                rx_byte <= {rx_shift[6:0], mosi_d};
        end
    end

    // ============================================================
    // 4. FSM
    // ============================================================
    typedef enum logic [2:0] {
        S_IDLE,
        S_CMD,
        S_ADDR_H,
        S_ADDR_L,
        S_DATA
    } state_t;

    state_t state;

    logic [7:0]  cmd_commit;
    logic [15:0] addr_reg;
    logic [7:0]  wdata_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end else begin
            if (cs_rise)
                state <= S_IDLE;
            else if (rx_valid) begin
                case (state)
                    S_IDLE:   state <= S_CMD;
                    S_CMD:    state <= S_ADDR_H;
                    S_ADDR_H: state <= S_ADDR_L;
                    S_ADDR_L: state <= S_DATA;
                    S_DATA:   state <= S_IDLE;
                endcase
            end
        end
    end

    // Command capture - capture on first rx_valid of transaction
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cmd_commit <= 8'd0;
        else if (cs_rise)
            cmd_commit <= 8'd0;
        else if (rx_valid && state == S_IDLE)
            cmd_commit <= rx_byte;
    end

    // Address + data latching
    always_ff @(posedge clk) begin
        if (rx_valid) begin
            case (state)
                S_CMD:    addr_reg[15:8] <= rx_byte;
                S_ADDR_H: addr_reg[7:0]  <= rx_byte;
                S_ADDR_L: wdata_reg      <= rx_byte;
            endcase
        end
    end

    // ============================================================
    // 5. Commit (pipelined, handles both 3-byte and 4-byte)
    // ============================================================
    logic commit_raw;
    logic commit_strobe;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            commit_raw <= 1'b0;
        else
            commit_raw <= ((state == S_ADDR_H && !cmd_commit[7]) || (state == S_ADDR_L && cmd_commit[7])) && rx_valid;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            commit_strobe <= 1'b0;
        else
            commit_strobe <= commit_raw;
    end

    // ============================================================
    // 6. Transaction engine
    // ============================================================
    logic [7:0] read_buffer;
    logic       read_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bus_req      <= 1'b0;
            bus_we       <= 1'b0;
            read_pending <= 1'b0;
            read_buffer  <= 8'd0;
        end else begin
            bus_req <= 1'b0;

            if (commit_strobe) begin
                if (cmd_commit[7]) begin
                    // WRITE
                    bus_req   <= 1'b1;
                    bus_we    <= 1'b1;
                    bus_addr  <= addr_reg;
                    bus_wdata <= wdata_reg;
                end else begin
                    // READ
                    if (!read_pending) begin
                        bus_req      <= 1'b1;
                        bus_we       <= 1'b0;
                        bus_addr     <= addr_reg;
                        read_pending <= 1'b1;
                    end
                end
            end

            if (bus_ready) begin
                read_buffer  <= bus_rdata;
                read_pending <= 1'b0;
            end

            if (cs_rise)
                read_pending <= 1'b0;
        end
    end

    // ============================================================
    // 7. TX data staging
    // ============================================================
    logic [7:0] tx_data_reg;
    logic       tx_data_valid;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_data_reg   <= 8'd0;
            tx_data_valid <= 1'b0;
        end else begin
            if (bus_ready) begin
                tx_data_reg   <= bus_rdata;
                tx_data_valid <= 1'b1;
            end
            if (cs_rise && tx_data_valid)
                tx_data_valid <= 1'b0;
        end
    end
    // ============================================================
    // 8. TX shift engine
    // ============================================================
    logic [7:0] tx_shift;
    logic       tx_loaded;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_shift  <= 8'd0;
            spi_miso  <= 1'b0;
            tx_loaded <= 1'b0;
        end else begin
            if (cs_rise) begin
                if (tx_data_valid) begin
                    tx_shift  <= tx_data_reg;
                    tx_loaded <= 1'b1;
                end else begin
                    tx_loaded <= 1'b0;
                end
            end else if (sck_fall && tx_loaded) begin
                spi_miso <= tx_shift[7];
                tx_shift <= {tx_shift[6:0], 1'b0};
            end
        end
    end

endmodule

`default_nettype wire
