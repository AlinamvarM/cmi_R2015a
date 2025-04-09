function [T,p] = dipg_case(ID,TP,C,p)
% Processing for each case
% Inputs:
%   ID = Subject ID (e.g. DMG013)
%   TP = Datestamp (e.g. 20230421)
%   C = Catalog entries for this case (cell array)
%   p = processing options (struct)
%
%   


T = table();

bl_chk = isempty(p.fn_ref);

caseID = [ID,'_',TP];
casedir = fullfile(p.procdir,ID,TP);
if ~isfolder(casedir)
    mkdir(casedir);
end

%% Find relevant image files
fprintf('\n\n%s : Beginning analysis ...\n',caseID)
% ADC    
info_adc = [];
fn_ADC = fullfile(casedir,[caseID,'.ADC.nii.gz']);
if ~isfile(fn_ADC)
    ind = find(strcmp(C.Tag,'ADC'),1);
    if isempty(ind)
        fprintf('%s : Image not found: ADC\n',caseID); return;
% ----------------- Maybe calculate from DWI or DTI?
                            % % Assumes b-values of 0 and 1000
                            % img = img(:,:,:,2)./img(:,:,:,1);
                            % img(isnan(img) | isinf(img)) = 0;
                            % if mean(img,"all")>1
                            %     img = 1./img;
                            %     img(isnan(img) | isinf(img)) = 0;
                            % end
                            % img = -log(img);
    else
        % Load DICOM and save as Nifti
        [img,~,fov,orient,~] = readDICOM(C.DataPath{ind},'noprompt');
        % Account for undocumented image scaling (found in a handful of Philips cases)
        v = mode(img,'all');
        if abs(v) > 0.1 % Background should be around 0
            img = img - v;
        end
        % Make sure ADC scale is correct
        img = img(:,:,:,1)./10.^round(log10(squeeze(prctile(img(:,:,:,1),95,'all'))'));
    end
    % Save ADC map to Nifti (units of x10^-3 mm^2/s)
    saveNIFTI(fn_ADC,img,[caseID,'_ADC'],fov,orient);
    info_adc = struct('fov',fov,'orient',orient,'dim',size(img,[1,2,3]));
end

% DWI
fn_b0 = fullfile(casedir,[caseID,'.DWI.b0.nii.gz']);
if ~isfile(fn_b0)
    ind = find(strcmp(C.Tag,'DWI'),1);
    if isempty(ind)
        ind = find(strcmp(C.Tag,'DTI'),1);
    end
    if isempty(ind)
        fprintf('%s : Image not found: DWI\n',caseID); return;
    else
        % Load DICOM and save as Nifti
        img = readDICOM(C.DataPath{ind},'noprompt');
        if all(size(img,[1,2,3])==info_adc.dim)
            saveNIFTI(fn_b0,img(:,:,:,1),[caseID,'_b0'],info_adc.fov,info_adc.orient);
        end
    end
end

% tumorVOI
tagFLAIR = {'FLAIR','FLAIR_post'};
fn_tVOI = strcat(caseID,'.',tagFLAIR,'.tumorVOI.nii.gz');
ind = find(isfile(fullfile(casedir,fn_tVOI)),1);
if isempty(ind)
    % Try to copy from VOI folder
    fn = fullfile(p.voidir,fn_tVOI);
    ind = find(isfile(fn),1);
    if isempty(ind)
        fprintf('%s : Tumor VOI not found.\n',caseID); return;
    else
        tagFLAIR = tagFLAIR{ind};
        fn_tVOI = fullfile(casedir,fn_tVOI{ind});
        copyfile(fn_tVOI,casedir);
    end
else
    tagFLAIR = tagFLAIR{ind};
end

% FLAIR
fn_FLAIR = fullfile(casedir,strcat(caseID,'.',tagFLAIR,'.nii.gz'));
if ~isfile(fn_FLAIR)
    ind = find(strcmp(C.Tag,tagFLAIR),1);
    if isempty(ind)
        fprintf('%s : Image not found: %s',caseID,tagFLAIR); return;
    else
        % Load DICOM and save as Nifti
        [img,~,fov,orient,~] = readDICOM(C.DataPath{ind},'noprompt');
        saveNIFTI(fn_FLAIR,img(:,:,:,1),[caseID,'_',tagFLAIR],fov,orient);
    end
end

% T2w - high-res image for cross-timepoint registration and base geometry
fn_T2w = fullfile(casedir,[caseID,'.T2w.nii.gz']);
if ~isfile(fn_T2w)
    ind = find(strcmp(C.Tag,'T2w'),1);
    if isempty(ind)
        fprintf('%s : Image not found: T2w\n',caseID); return;
    else
        % Load DICOM and save as Nifti
        [img,~,fov,orient,~] = readDICOM(C.DataPath{ind},'noprompt');
        saveNIFTI(fn_T2w,img(:,:,:,1),[caseID,'_T2w'],fov,orient);
    end
end


%% Perform within-timepoint registrations to T2w (affine)

% DWI for ADC
fn_reg = fullfile(p.regdir,[caseID,'.reg.ADC.nii.gz']);
if ~isfile(fn_reg)
    fprintf('%s : Elastix : Affine : DWI to T2w ...\n',caseID);
    fn_reg = brainReg(casedir,fn_T2w,fn_b0,false);
    rename_reg(fn_reg,fn_b0,caseID);
end

% FLAIR for tumorVOI
fn_reg = fullfile(p.regdir,[caseID,'.reg.',tagFLAIR,'.tumorVOI.nii.gz']);
if ~isfile(fn_reg)
    fprintf('%s : Elastix : Affine : FLAIR to T2w ...\n',caseID);
    fn_reg = brainReg(casedir,fn_T2w,fn_FLAIR,false);
    rename_reg(fn_reg,fn_FLAIR,caseID);
end


%% Perform longitudinal registration to baseline T2w (warp)
fn_reg = fullfile(p.regdir,[caseID,'.reg.T2w.nii.gz']);
if bl_chk
    % If this is the first data set, set baseline T2w image to register to
    p.fn_ref = fn_reg;
elseif ~isfile(fn_reg)
    fprintf('%s : Elastix : Warp : T2w to baseline T2w ...\n',caseID);
    fn_reg = brainReg(casedir,p.fn_ref,fn_T2w,true);
    rename_reg(fn_reg,fn_T2w,caseID);
end
dipg_mtform(caseID,casedir,p,bl_chk);


%% Perform fDM analysis
fprintf('%s : Starting fDM analysis ...\n',caseID);
% Determine baseline ID:
[~,baseID] = fileparts(p.fn_ref);
baseID = extractBefore(baseID,'.');

% Find T2w for baseline background
if ~isfile(p.fn_ref)
    fprintf('%s : Baseline T2w not found: %s\n',caseID,baseID); return;
end

% Find baseline tumorVOI
fn_voi0 = fullfile(p.regdir,strcat(baseID,'.reg.',{'FLAIR','FLAIR_post','T2w'},'.tumorVOI.nii.gz'));
fn_voi0 = fn_voi0{isfile(fn_voi0)};
if isempty(fn_voi0)
    fprintf('%s : Baseline tumorVOI not found: %s\n',caseID,baseID); return;
end

% Find follow-up tumorVOI
fn_voi1 = fullfile(p.regdir,strcat(caseID,'.reg.',{'FLAIR','FLAIR_post'},'.tumorVOI.nii.gz'));
fn_voi1 = fn_voi1{isfile(fn_voi1)};
if isempty(fn_voi1)
    fprintf('%s : Registered tumorVOI not found\n',caseID); return;
end

% Baseline ADC
fn_adc0 = fullfile(p.regdir,[baseID,'.reg.ADC.nii.gz']);
if ~isfile(fn_adc0)
    fprintf('%s : Baseline ADC not found: %s\n',caseID,baseID); return;
end

% Registered ADC map for fDM
fn_adc1 = fullfile(p.regdir,[caseID,'.reg.ADC.nii.gz']);
if ~isfile(fn_adc1)
    fprintf('%s : Registered ADC not found\n',caseID); return;
end
    
% Initialize ImageClass object for analysis
if ~isfield(p,'cmi') || ~isa(p.cmi,'CMIclass')
    p.cmi = CMIclass;
    p.cmi.img.prm.setOpts('thresh',[2,3,1,-.55; 2,3,1,.55],...
                          'prmmap',{[false false], 'ADC_-';...
                                    [true  false], 'ADC_0';...
                                    [true  true], 'ADC_+'},...
                          'cutoff',[2,0.0001,3 ; 3,0.0001,3],...
                          'cmap',flip(eye(3)),...
                          'statchk',false);
end
p.cmi.img.prm.setOpts('labels',{['ADC (',baseID,')'],['ADC (',caseID,')']});

% Load images and VOI(s)
p.cmi.loadImg(0,{p.fn_ref,fn_adc0,fn_adc1});
p.cmi.loadMask(fn_voi0);
if ~bl_chk
    % p.cmi.loadMask(fn_voi1,'intersect'); % <---- comment this line for baseline VOI only
end

% Calculate and save difference map
dADC = diff(p.cmi.img.mat(:,:,:,[2,3]),4);
saveNIFTI(fullfile(casedir,[caseID,'.dADC.nii.gz']),dADC,{'dADC'},p.cmi.img.voxsz.*p.cmi.img.dims(1:3),p.cmi.img.orient);

% Run fDM
p.cmi.setVec(3);
[~,~,vals] = p.cmi.activatePRM(true);
% Convert to percent of cutoff-thresholded VOI
vals = vals/sum(vals)*100;

% Calculate actual volume used for fDM
prmvol = nnz(~isnan(p.cmi.img.prm.mat))*prod(p.cmi.img.voxsz)/1000;

if ~bl_chk
    % Save scatterplot for QC
    pipeline_save_fig(p.cmi.img.prm.hfscatter,fullfile(casedir,[caseID,'.PRMscatter.blVOI.tif']));
    
    % Save PRM map
    fov = p.cmi.img.voxsz .* p.cmi.img.dims(1:3);
    saveNIFTI(fullfile(p.regdir,[caseID,'.prm.blVOI.nii.gz']),p.cmi.img.prm.mat,[caseID,'_PRM'],fov,p.cmi.img.orient);
    
    % Save PRM overlays
    % Full tumor volume
    monti = struct('vdim',{3},'mdim',3,'mind',{find(any(p.cmi.img.mask.mat,[1,2]))'});
    hf = p.cmi.genMontage(monti,round(sqrt(numel(monti.mind))));
    saveas(hf,fullfile(casedir,[caseID,'.PRMmontage.blVOI.tif']));
    hf.delete;
    % Grab central slice
    monti.mind = monti.mind(round(numel(monti.mind)/2));
    hf = p.cmi.genMontage(monti,1);
    saveas(hf,fullfile(p.regdir,sprintf('%s.PRMoverlay.blVOI.Slice%d.tif',caseID,monti.mind)));
    hf.delete;
end

% Set fDM results
if ~isempty(vals)
    T.SubjectID = {ID};
    T.StudyDate = {TP};
    T.ROI = {'tumorVOI'};
    T.Volume_cc = prmvol;
    T.("fDM-") = vals(1);
    T.fDM0     = vals(2);
    T.("fDM+") = vals(3);
end


function rename_reg(fn_reg,fn_hom,caseID)
    if isfile(fn_reg)
        % Rename resulting file and move to caseid/reg directory
        fn_new = insertAfter(fn_hom,caseID,'.reg');
        tfn = fn_new(1:end-3);
        movefile(fn_reg,tfn);
        gzip(tfn);
        delete(tfn);
    else
        fprintf('Registration failed: \n');
    end

function dipg_mtform(caseID,casedir,p,bl_chk)

    % MultiTform between tp
    nn_tag = {'ADC','SynthSeg','VOI'};
    ext = '.nii';
    go = true;

    % Initialize transform parameters for multiTform
    tpdef = struct('chain', {1}, ...
                'fname', {''}, ...
                'im', {cell(0,4)}, ...
                'jac', {false},...
                'defOrig', {0});
    tp = tpdef;
    ii = 1;
    if bl_chk
        % Copy over the baseline T2w image
        copyfile(fullfile(casedir,[caseID,'.T2w.nii.gz']),fullfile(p.regdir,[caseID,'.reg.T2w.nii.gz']));
    else
        ii = 2;
        % First transform is T2w to baseline T2w
        fn_tp = dir(fullfile(casedir,['elxreg_',caseID,'.T2w\TransformParameters.?.txt']));
        if isempty(fn_tp)
            % Can't go ahead without the T2w registration to baseline
            go = false;
        else
            tp(1).fname = fullfile(fn_tp(end).folder,fn_tp(end).name);
        end
    end

    if go
        % Loop over within-tp registrations
        for iq = 1:numel(p.img_tree)
            % Reset transform
            tp(ii) = tpdef;

            % Add transform parameters for within-tp registration
            fn_tp = dir(fullfile(casedir,['**\elxreg_',caseID,'.',p.img_tree{iq}{1},'*\TransformParameters.?.txt']));
            if ~isempty(fn_tp)
                tp(ii).fname = fullfile(fn_tp(end).folder,fn_tp(end).name);
                % Loop over relevant images to register
                regname = {};
                imtag = p.img_tree{iq}(~strcmp(p.img_tree{iq},'T2w'));
                for iim = 1:numel(imtag)
                    fn_im = dir(fullfile(casedir,['*.',p.img_tree{iq}{iim},'.*nii.gz']));
                    if ~isempty(fn_im)
                        fn_im(contains({fn_im.name},'.reg.')) = [];
                        N = numel(fn_im);
                        fname = {fn_im.name}';
                        nn_flag = num2cell(contains(fname,nn_tag));
                        svname = strcat(caseID,'_reg',cellfun(@(x)regexprep(x,'\.','_'),...
                                        extractBetween(fname,caseID,'.nii'),'UniformOutput',false));
                        finalname = fullfile(p.regdir,regexprep(fname,'\.','.reg.',1));
                        im = [nn_flag,fullfile(casedir,fname),svname,repmat({0},N,1)];
                        ind = ~isfile(finalname);
                        if any(ind)
                            ind = ind & ~ismember(fullfile(casedir,fname),tp(ii).im(:,2));
                            regname = [regname;[fname(ind),svname(ind),finalname(ind)]];
                            tp(ii).im = [tp(ii).im; im(ind,:)];
                        end
                    end
                end
                if ~isempty(tp(ii).im)
                    % Perform multiTform
                    multiTform(tp,p.regdir,ext);
                    % Fix registered files
                    for iim = 1:size(regname,1)
                        oldname = fullfile(p.regdir,[regname{iim,2},'.nii']);
                        if isfile(oldname)
                            newname = extractBefore(regname{iim,3},'.gz');
                            movefile(oldname,newname);
                            gzip(newname);
                            delete(newname);
                        end
                    end
                end
            end
        end
    end

function calc_fDM()