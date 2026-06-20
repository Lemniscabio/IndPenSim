function Generate_Single_Batch_CSV(Batch_no, output_dir)
% Generate one batch and write exactly one batch CSV.

if nargin < 2
    output_dir = fullfile('output_800', 'batch_csv');
end

[Batch_run_flags, Num_of_Batches] = get_fault_batch_run_flags();
if Batch_no < 1 || Batch_no > Num_of_Batches
    error('Batch_no must be between 1 and %d', Num_of_Batches);
end

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

Batch_ref = sprintf('Batch_%02d', Batch_no);
Raw_Batch_data.(Batch_ref) = indpensim_run(Batch_no, Batch_run_flags);
Generate_Batch_records(Raw_Batch_data, fullfile(output_dir, 'IndPenSim_V2_export_V7'), Batch_run_flags);
end
