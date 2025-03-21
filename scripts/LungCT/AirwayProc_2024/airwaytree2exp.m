function N_exp = airwaytree2exp(procdir)
% Transforms airway nodes (real and simulated) to EXP space
% ** Note: Node coordinates are in non-oriented units
% *!*    This will replace previous results stored in AirwayTreeSim.mat
% Inputs:
%   procdir = path of processing case

[~,ID] = fileparts(procdir);
fn_tree = fullfile(procdir,[ID,'.AirwayProc'],[ID,'_AirwayTreeSim.mat']);
if isfile(fn_tree)
    % Filenames relevant to registration
    fn_ref = fullfile(procdir,[ID,'.exp.nii.gz']);
    fn_seg = fullfile(procdir,[ID,'.exp.label.nii.gz']);
    fn_hom = fullfile(procdir,[ID,'.ins.nii.gz']);
    path_elx = fullfile(procdir,['elastix_',ID]);

    if isfolder(path_elx)
        % Find inverse transform
        fn_tfi = dir(fullfile(path_elx,'InverseTransformParameters.*.txt'));
        if isempty(fn_tfi)
            fn_tf = dir(fullfile(path_elx,'TransformParameters.*.txt'));
            if isempty(fn_tf)
                fn_tfi = '';
            else
                fn_tfi = inverseTransform(fullfile(path_elx,fn_tf(end).name),fn_ref,fn_seg);
            end
        else
            fn_tfi = fullfile(path_elx,fn_tfi(end).name);
        end
    
        % Transform points with transformix
        if ~isempty(fn_tfi)

            % Load relevant data
            p = load(fn_tree);
            np = size(p.N,1);
            info_h = niftiinfo(fn_hom);
            info_r = niftiinfo(fn_ref);

            % Find transformed node locations in INS space
            N_ins = p.N(:,[3,2,4]) ./ info_h.PixelDimensions;
            N_ins = (info_h.Transform.T' * [ N_ins , ones(np,1) ]')';
            N_ins = N_ins(:,1:3);

            % Transform points using elastix results
            N_exp = transformPoints(fn_tfi,N_ins(:,1:3)); % results in xyz coordinates

            % Convert points back to scaled index format in EXP space
            N_exp = (info_r.Transform.T' \ [ N_exp , ones(np,1) ]')';
            N_exp = N_exp(:,1:3) .* info_r.PixelDimensions;
            N_exp = [p.N(:,1),N_exp(:,[2,1,3])];

            % Save points to airway tree MAT file
            save(fn_tree,'N_exp','-append');
        end
    end
end
