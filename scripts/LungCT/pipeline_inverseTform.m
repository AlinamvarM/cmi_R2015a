function Mreg = pipeline_inverseTform(procdir,M,voxsz,orient)
% Transform images from Ref space (Exp) to Homologous space (Ins)
% Inputs:
%   procdir = case processing directory
%   M       = image matrix to transform
%   voxsz   = voxel dimensions
%   orient  = affine matrix defining Ref space

[~,ID] = fileparts(procdir);
fn_ref = fullfile(procdir,[ID,'.exp.nii.gz']);
fn_seg = fullfile(procdir,[ID,'.exp.label.nii.gz']);
fn_hom = fullfile(procdir,[ID,'.ins.nii.gz']);
path_elx = fullfile(procdir,['elastix_',ID]);

if isfile(fn_ref) && isfile(fn_seg) && isfile(fn_hom) && isfolder(path_elx)

    % Inverse transform
    fn_tfi = dir(fullfile(path_elx,'InverseTransformParameters.*.txt'));
    if isempty(fn_tfi)
        fn_tf = dir(fullfile(path_elx,'TransformParameters.*.txt'));
        if isempty(fn_tf)
            fprintf('No transform found in: %s\n',path_elx);
            fn_tfi = '';
        else
            fprintf('Generating inverse transform.\n');
            fn_tfi = inverseTransform(fullfile(path_elx,fn_tf(end).name),fn_ref,fn_seg);
        end
    else
        fprintf('InverseTransformParameters.*.txt files found.\n');
        fn_tfi = fullfile(path_elx,fn_tfi(end).name);
    end
    
    if ~isempty(fn_tfi)
        fprintf('Transforming Ref->Hom ... ');
        Mreg = transformImage(path_elx,fn_tfi,M,voxsz,orient);
        fprintf('done\n');
    end

end