%Generate Batch records from Output data
function Batch_Records = Generate_Batch_records(Raw_Batch_data, Batches_File_Name, Batch_run_flags)

[output_dir, ~, ~] = fileparts(Batches_File_Name);
if isempty(output_dir)
    output_dir = '.';
end
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

All_batches = fieldnames(Raw_Batch_data);
Num_of_Batches = size(All_batches, 1);

for Batch_index = 1:Num_of_Batches
    Batch_ref = All_batches{Batch_index};
    Batch_no = batch_number_from_ref(Batch_ref);
    Batch_data = Raw_Batch_data.(Batch_ref);
    Excluded_fields = fields_excluded_from_export(Batch_data);
    Excluded_fields = Excluded_fields(isfield(Batch_data, Excluded_fields));
    Export_batch = rmfield(Batch_data, Excluded_fields);
    Batch_Records.(Batch_ref) = Export_batch;

    [DF_Batch_data, df_headers] = build_batch_csv_data(Export_batch, Batch_no, Batch_run_flags);
    CSV_file_temp = fullfile(output_dir, sprintf('%s_fault_%d.csv', Batch_ref, Batch_run_flags.Batch_fault_order_reference(Batch_no)));
    csvwrite_with_headers(CSV_file_temp, DF_Batch_data, df_headers);
end

end

function Batch_no = batch_number_from_ref(Batch_ref)
Batch_no = str2double(strrep(Batch_ref, 'Batch_', ''));
if isnan(Batch_no)
    error('Batch reference must use the Batch_NN format');
end
end

function Excluded_fields = fields_excluded_from_export(Batch_data)
Excluded_fields = {'sc', 'abc', 'a0', 'a1', 'a3', 'a4', 'n0', 'n1', ...
    'n2', 'n3', 'n4', 'n5', 'n6', 'n7', 'n8', 'n9', 'nm', 'phi0', ...
    'Culture_age', 'mup', 'mux', 'X_CER', 'mu_X_calc', 'mu_P_calc', ...
    'F_discharge_cal', 'CO2_d', 'NH3', 'PAA', 'Viscosity', 'X', ...
    'PRBS_noise_addition'};

Optional_fields = {'Raman_Spec', 'PAA_pred', 'Stats'};
for field_no = 1:size(Optional_fields, 2)
    if isfield(Batch_data, Optional_fields{field_no})
        Excluded_fields = [Excluded_fields, Optional_fields(field_no)];
    end
end
end

function [DF_Batch_data, df_headers] = build_batch_csv_data(Batch_data, Batch_no, Batch_run_flags)
All_variables_to_import = fieldnames(Batch_data);
Reference_time = Batch_data.(All_variables_to_import{1}).t;
DF_Batch_data = Reference_time;
df_headers = {'Time (h)'};

for variable_no = 1:size(All_variables_to_import, 1)
    Variable_name = All_variables_to_import{variable_no};
    Channel = Batch_data.(Variable_name);

    if ~isfield(Channel, 'y') || ~isfield(Channel, 't')
        continue;
    end

    if size(Channel.y, 1) ~= size(Reference_time, 1)
        continue;
    end

    DF_Batch_data = [DF_Batch_data, Channel.y];
    df_headers = [df_headers, {channel_header(Channel, Variable_name)}];
end

Fault_code = Batch_run_flags.Batch_fault_order_reference(Batch_no);
DF_Batch_data = [DF_Batch_data, ...
    ones(size(Reference_time, 1), 1) * Batch_no, ...
    ones(size(Reference_time, 1), 1) * Fault_code];
df_headers = [df_headers, {'Batch_ref', 'Fault_code'}];
end

function Header = channel_header(Channel, Variable_name)
if isfield(Channel, 'name') && isfield(Channel, 'yUnit')
    Header = strcat(Channel.name, '(', Variable_name, ':', Channel.yUnit, ')');
else
    Header = Variable_name;
end
end
