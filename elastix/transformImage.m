function Mreg = transformImage(save_path,fn_tf,M,voxsz,orient)

d = size(M);

% Write image to file
fn_temp = fullfile(save_path,'temp_image.nii');
saveNIFTI(fn_temp,M,{'temp'},voxsz.*d,orient);

% Transformix command
cmdstr = sprintf('transformix -in "%s" -out "%" -tp "%s"',fn_temp,save_path,fn_tf);
system(cmdstr);

% Return transformed image
[Mreg,~,fov,orient,info] = readNIFTI(fullfile());