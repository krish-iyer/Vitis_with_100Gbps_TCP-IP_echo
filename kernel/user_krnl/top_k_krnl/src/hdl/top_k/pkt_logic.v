`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/28/2025 07:08:49 PM
// Design Name: 
// Module Name: pkt_logic
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module pkt_logic
#(MAX_META_COUNT = 32)
(
    input wire clk,
    input wire rst,
    input wire [512+88-1 + 1 : 0] pkt_rx_TDATA,
    input wire pkt_rx_TVALID,
    output wire pkt_rx_TREADY,
    output reg [512+32-1 + 1: 0] pkt_tx_TDATA,
    output reg pkt_tx_TVALID,
    input wire pkt_tx_TREADY
);
    
    // Storage for seen metadata values
    reg [15:0] metadata_values [0:MAX_META_COUNT-1];
    reg metadata_valid [0:MAX_META_COUNT-1];
    reg [5:0] next_meta_index;
    
    // State tracking
    reg first_line;  // Track if this is first line of a new metadata
    reg [15:0] current_packet_meta;  // Store metadata of current packet being processed
    reg processing_new_meta;  // Indicates if we're processing a new metadata
    
    // Metadata from current packet
    wire [15:0] current_metadata;
    assign current_metadata = pkt_rx_TDATA[513+16 - 1: 513];// Conn ID
    
    // Check if current metadata exists in our tracking
    reg metadata_exists;
    integer check_idx;
    always @(*) begin
        metadata_exists = 0;
        for (check_idx = 0; check_idx < MAX_META_COUNT; check_idx = check_idx + 1) begin
            if (metadata_valid[check_idx] && metadata_values[check_idx] == current_metadata) begin
                metadata_exists = 1;
            end
        end
    end
    
    // Ready to accept new data when tx is ready or we're going to drop the packet
    assign pkt_rx_TREADY = pkt_tx_TREADY || (pkt_rx_TVALID && !metadata_exists && first_line);
    
    // Reset logic and packet processing
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            // Reset all tracking memory and outputs
            pkt_tx_TVALID <= 0;
            next_meta_index <= 0;
            first_line <= 1;
            processing_new_meta <= 0;
            current_packet_meta <= 0;
            for (i = 0; i < MAX_META_COUNT; i = i + 1) begin
                metadata_valid[i] <= 0;
                metadata_values[i] <= 0;
            end
        end else begin
            if (pkt_rx_TVALID && pkt_rx_TREADY) begin
                if (first_line) begin
                    // Start of new packet
                    if (!metadata_exists) begin
                        // New metadata - store it temporarily and mark for processing
                        current_packet_meta <= current_metadata;
                        processing_new_meta <= 1;
                        first_line <= 0;
                        pkt_tx_TVALID <= 0;
                    end else begin
                        // Known metadata - forward as is
                        pkt_tx_TDATA <= {pkt_rx_TDATA[600:513], pkt_rx_TDATA[512:0]};
                        pkt_tx_TVALID <= 1;
                        first_line <= 0;
                    end
                end else begin
                    if (processing_new_meta) begin
                        // Processing new metadata - forward with modified upper metadata
                        pkt_tx_TDATA[512:0] <= pkt_rx_TDATA[512:0];
                        pkt_tx_TDATA[513+16-1:513] <= pkt_rx_TDATA[513+16-1:513];
                        pkt_tx_TDATA[513 + 32 - 1:513 + 16] <= pkt_rx_TDATA[513 + 32 - 1:513 + 16] - 16'd64;
                        pkt_tx_TVALID <= 1;
                        
                        // If this is the end of packet, store the metadata permanently
                        if (pkt_rx_TDATA[512]) begin
                            metadata_values[next_meta_index] <= current_packet_meta;
                            metadata_valid[next_meta_index] <= 1;
                            next_meta_index <= (next_meta_index + 1) % MAX_META_COUNT;
                            processing_new_meta <= 0;
                        end
                    end else begin
                        // Known metadata - forward as is
                        pkt_tx_TDATA <= {pkt_rx_TDATA[600:513], pkt_rx_TDATA[512:0]};
                        pkt_tx_TVALID <= 1;
                    end
                end
                
                // Reset first_line flag on end of packet
                if (pkt_rx_TDATA[512]) begin
                    first_line <= 1;
                end
            end else if (pkt_tx_TVALID && pkt_tx_TREADY) begin
                // Clear valid flag once packet is accepted
                pkt_tx_TVALID <= 0;
            end
        end
    end

endmodule
