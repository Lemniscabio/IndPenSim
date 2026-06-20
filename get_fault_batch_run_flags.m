function [Batch_run_flags, Num_of_Batches] = get_fault_batch_run_flags()
% ============================================================================
% SINGLE SOURCE OF TRUTH for the campaign: number of batches AND fault types.
% Both run paths (Generate_Production_Batch_data_V4.m and the parallel runner
% run_parallel_batches.sh / Generate_Single_Batch_CSV.m) read from here, so
% edit ONLY this file to change a campaign. Do not hardcode counts elsewhere.
%
% Batch_fault_order_reference is a 1-by-N row vector. Its LENGTH is the number
% of batches; each ENTRY is the fault code applied to that batch:
%   0 = no fault (fault-free)   1 = Aeration       2 = Pressure
%   3 = Substrate               4 = Base           5 = Coolant
%   6 = All process faults      7 = Temp sensor    8 = pH sensor
%
% Examples (replace the line below):
%   10 fault-free batches ........ zeros(1, 10)
%   50 batches, all aeration fault .. ones(1, 50)
%   24 batches cycling faults 1-8 ... repmat(1:8, 1, 3)
%   current: 800 faulty batches ..... [repmat(1:8,1,96), repmat(1:4,1,8)]
% ============================================================================

Batch_run_flags.Batch_fault_order_reference = [repmat(1:8,1,96), repmat(1:4,1,8)];
Num_of_Batches = size(Batch_run_flags.Batch_fault_order_reference, 2);

Batch_run_flags.Control_strategy = zeros(1, Num_of_Batches);
Batch_run_flags.Batch_length = ones(1, Num_of_Batches);
Batch_run_flags.Raman_spec = zeros(1, Num_of_Batches);
end
