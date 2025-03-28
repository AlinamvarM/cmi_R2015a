function T = save_point_projections_in_table_yours(vec_labels_by_branches, PseudoTimeTraj, outFile, your_data_size, finalCTAtable)
% Function that saves ClinTrajan results in CSV format with 1-based indexing
%
% Inputs:
%   vec_labels_by_branches - Branch labels for your points only
%   PseudoTimeTraj - Cell array containing trajectory information (for all points)
%   outFile - Path for saving the output file
%   your_data_size - Number of your data points
%   finalCTAtable - The original table with idx column (optional)
%
% Output:
%   T - Table containing the processed data for your points only

% Print information about input data size for debugging
fprintf('Size of vec_labels_by_branches: %d\n', length(vec_labels_by_branches));
fprintf('Number of trajectories: %d\n', length(PseudoTimeTraj));
fprintf('Filtering to keep only your %d points\n', your_data_size);

% Default full path if not provided
if nargin < 3 || isempty(outFile)
    outFile = fullfile(pwd, 'Results.csv');
end

% Ensure file has .csv extension
[filepath, name, ext] = fileparts(outFile);
if ~strcmpi(ext, '.csv')
    outFile = fullfile(filepath, [name '.csv']);
end

% Make sure the directory exists
if ~isempty(filepath) && ~exist(filepath, 'dir')
    mkdir(filepath);
end

% Check if idx values are available
has_idx = false;
if nargin >= 5 && istable(finalCTAtable) && ismember('idx', finalCTAtable.Properties.VariableNames)
    original_idx = finalCTAtable.idx;
    has_idx = true;
    fprintf('Using idx values from finalCTAtable: First 10 values - %s\n', mat2str(original_idx(1:min(10,length(original_idx)))));
else
    % If idx isn't available, use sequential numbers
    original_idx = (1:your_data_size)';
    fprintf('Original idx column not found in finalCTAtable. Using sequential numbers instead.\n');
end

% Initialize data structures
N = length(vec_labels_by_branches);
point2trajmap = cell(N, 1);
point2trajnamemap = cell(N, 1);
point2pst = nan(N, 1);
alltrajnames = {};

% Initialize cells
for p = 1:N
    point2trajmap{p} = [];
    point2trajnamemap{p} = {};
end

traj_binary = struct();

% Process each trajectory, but only include points that are yours
for i = 1:length(PseudoTimeTraj)
    pstt = PseudoTimeTraj{i};
    trajName = sprintf('Trajectory:%d--%d', pstt.Trajectory(1), pstt.Trajectory(end));
    alltrajnames{end+1} = trajName;

    points = pstt.Points;     % 0-based indices from Python
    pseudotime = pstt.Pseudotime; % same length as points

    % Process only points that are in your dataset (first your_data_size points)
    for k = 1:length(points)
        p = points(k);

        % Skip points that aren't in your dataset
        if p >= your_data_size
            continue;
        end

        % Ensure point index is valid for your dataset
        if p+1 > N
            warning('Point index %d exceeds array size %d. Skipping this point.', p, N);
            continue;
        end

        point2trajmap{p+1} = [point2trajmap{p+1}, pstt.Trajectory(end)];
        point2trajnamemap{p+1}{end+1} = trajName;
        point2pst(p+1) = pseudotime(k);
    end

    % Create binary trajectory indicator
    fld = matlab.lang.makeValidName(trajName);
    traj_binary.(fld) = zeros(N, 1, 'int32');
end

% Build binary membership
for p = 1:N
    for nm = 1:length(point2trajnamemap{p})
        colName = matlab.lang.makeValidName(point2trajnamemap{p}{nm});
        if isfield(traj_binary, colName)
            traj_binary.(colName)(p) = 1;
        end
    end
end

% Create table columns - Use 1-based points to match Python
Point = (1:N)';          % 1-based indexing for points
Segment = vec_labels_by_branches(:);
Pseudotime = point2pst(:);
Trajectories = cell(N, 1);

for p = 1:N
    Trajectories{p} = point2trajmap{p};
end

% Create initial table with both idx and Point columns if idx is available
if has_idx
    idx = original_idx(1:N); % Include original idx values
    T = table(idx, Point, Segment, Pseudotime, Trajectories);
else
    T = table(Point, Segment, Pseudotime, Trajectories);
end

% Add trajectory binary indicators
uniqueTrajNames = unique(alltrajnames, 'stable');
for i = 1:length(uniqueTrajNames)
    colName = matlab.lang.makeValidName(uniqueTrajNames{i});
    if isfield(traj_binary, colName)
        T.(colName) = traj_binary.(colName);
    end
end

% Display first few rows of the table for verification
disp('First few rows of the output table:');
disp(T(1:min(5,height(T)), :));

% Write to CSV
fprintf('Saving file to: %s\n', outFile);
writetable(T, outFile, 'Delimiter', ',');
fprintf('File saved successfully with %d points.\n', size(T, 1));
end
