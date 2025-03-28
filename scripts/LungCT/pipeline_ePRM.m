function x = pipeline_ePRM(caseID,procdir,prm,voi,info,imgTag,fn_log)
% Inputs:
%   caseID = label for case being processed
%   procdir = case directory for processing
%   prm = 3D map of PRM
%   voi = Exp segmentation
%   info = 
%   imgTag = flag to map results to 3D image space

% Check for Matlab version R2024b
mver = version('-release');
v_year = str2double(mver(1:4));
if v_year<2024 || mver(5)<'b'
    writeLog(fn_log,'ePRM requires Matlab version 2024b or later. Current version: %s',mver);
    return;
end

pSize = [16 16 16]; % patch size.
imSizeNew = [512 512 512]; % resize

% Make sure python is set up to run ClinTrajAn
if ispref('Clintrajan','PythonPath')
    pypath = getpref('Clintrajan','PythonPath');
else
    pypath = update_python_paths;
end
% [stat,pypath] = CTApython_setup;

% Create folder for ePRM
savepath = fullfile(procdir,[caseID,'_ePRM']);
if ~isfolder(savepath)
    mkdir(savepath);
end

% Resize data
voi = single(imresize3(logical(voi), imSizeNew, 'nearest'));
img = single(imresize3(prm, imSizeNew, 'nearest'));

% Save 
finalCTAtable = cta_csv(img, voi, caseID, info, {'PRM'}, pSize, fn_log);

% Load data used to make original Elastic Graph Model
path_ePRM = fullfile(fileparts(which('cmi')),'scripts/LungCT/ePRM');
origDataFile = fullfile(path_ePRM,'caseSelection_ID_Final300_random.csv');
if isfile(origDataFile)
    origData = readtable(origDataFile,'VariableNamingRule','preserve');
else
    warning('ePRM model file not found.')
    return
end

rootNode = 1;
numComp = 3; % based on original Elastic Graph Model
% Extract the same features
m = contains(finalCTAtable.Properties.VariableNames, ["norm.v" "fsad.v" "emph.v" "pd.v"]);
X_case = finalCTAtable{:,m};
m_ref = contains(origData.Properties.VariableNames, ["norm.v" "fsad.v" "emph.v" "pd.v"]);
X_ref = origData{:,m_ref};


% Calculate normalization statistics from reference data only
mean_val_original = mean(X_ref, 1);
std_original = std(X_ref, [], 1);
std_original(std_original == 0) = 1;
Xs_combined = [X_case; X_ref];

 % Normalize reference data
Xs_combined = (Xs_combined - mean_val_original) ./ std_original;

% Keep track of your data size vs. original model data
your_data_size = size(finalCTAtable, 1);

% After computing PCA
[score, score_case, coeff, ~] = PCApython(savepath, Xs_combined, your_data_size, numComp);

% Load VOX PCA data
vox_pca = readmatrix(fullfile(path_ePRM, 'model_pca_data.txt'));

% Align PCA components
[score_aligned, score_case_aligned, ~, ~] = align_pca_components(score, score_case, coeff, vox_pca);

% Use aligned scores for subsequent analysis
score = score_aligned;
score_case = score_case_aligned(1:your_data_size, :);

% Create visualization to compare with VOX model PCA after alignment
hf = figure('Position', [100, 100, 1200, 400]);
% PC1 vs PC2 plot
    ha = subplot(1, 3, 1);
    scatter(ha,vox_pca(:, 1), vox_pca(:, 2), 10, 'blue', 'filled', 'MarkerFaceAlpha', 0.3);
    hold(ha,'on');
    scatter(ha,score_case(:, 1), score_case(:, 2), 80, 'red', 'filled');
    xlabel(ha,'PC1');
    ylabel(ha,'PC2');
    title(ha,'PC1 vs PC2');
    legend(ha,'VOX Model', 'Your Case (Aligned)', 'Location', 'best');
    grid(ha,'on');
% PC1 vs PC3 plot
    ha = subplot(1, 3, 2);
    scatter(ha,vox_pca(:, 1), vox_pca(:, 3), 10, 'blue', 'filled', 'MarkerFaceAlpha', 0.3);
    hold(ha,'on');
    scatter(ha,score_case(:, 1), score_case(:, 3), 80, 'red', 'filled');
    xlabel(ha,'PC1');
    ylabel(ha,'PC3');
    title(ha,'PC1 vs PC3');
    grid(ha,'on');
% PC2 vs PC3 plot
    ha = subplot(1, 3, 3);
    scatter(ha,vox_pca(:, 2), vox_pca(:, 3), 10, 'blue', 'filled', 'MarkerFaceAlpha', 0.3);
    hold(ha,'on');
    scatter(ha,score_case(:, 2), score_case(:, 3), 80, 'red', 'filled');
    xlabel(ha,'PC2');
    ylabel(ha,'PC3');
    title(ha,'PC2 vs PC3');
    grid(ha,'on');
sgtitle(hf,'Comparison of Case PCA with VOX Model PCA (After Alignment)');
saveas(hf, fullfile(savepath, 'pca_alignment_check.png'));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Setup Enviroment
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Tell MATLAB which Python to use
pyenv('Version', pypath, 'ExecutionMode', 'OutOfProcess');
% Find the VOX file exactly
fn_vox = fullfile(path_ePRM,'caseSelection_ID_Final300_random_Vonly_n40__VOX1');
if ~isfile(fn_vox)
    writeLog(fn_log,'ePRM - error: VOX file not found\n');
end
% Set output path
fn_results = fullfile(savepath, [caseID '_clintrajan_results.csv']);
writeLog(fn_log,'Number of points in current case: %d\n', your_data_size);
writeLog(fn_log,'Total points after adding reference data: %d\n', size(score, 1));
% Load the VOX file to get the pre-trained tree structure 
tree_elpi = load_and_process_tree(score_case, fn_vox);
% Data Partition - use full score but track only your points
[vec_labels_by_branches, ~] = partition_data_from_python(score_case, tree_elpi);
% Extract Trajectories
[all_trajectories, all_trajectories_edges] = extract_trajectories_from_python(tree_elpi, rootNode);
% Project data onto tree
ProjStruct = project_on_tree_from_python(score_case, tree_elpi);
% Calculate pseudotime for all points
PseudoTimeTraj = quantify_pseudotime_from_python(all_trajectories, all_trajectories_edges, ProjStruct);
% Save only your points using the modified function
CTA = save_point_projections_in_table_yours(vec_labels_by_branches, PseudoTimeTraj, fn_results, your_data_size, finalCTAtable);
% After calculating pseudotime
feature_name = 'fsad.v';
fn_results = fullfile(savepath, [caseID '_' feature_name '_tree.png']);
% Call visualization function
visualize_eltree_from_python(tree_elpi, score_case, finalCTAtable, feature_name, fn_results);
%% Determine Tier assignment and position and generate 3D map
idx_Segment = zeros(size(CTA{:,3}));
numSeg = zeros(size(CTA{:,3}));
denSeg = zeros(size(CTA{:,3}));
frcSeg = zeros(size(CTA{:,3}));
scaleSeg = zeros(size(CTA{:,3}));
% [IMPORTANT] 20240314 Tree:
% segmentRange is [segment# startStep[relative to root] endStep[relative to root]] all relevent to root node.
% Root node is 1
% Segments are tree dependent and may change for different fits
% Need to look over Volume density of each PRM:
% 4 = Emphysema
% 0 = fSAD
% 1 = Transition
% 3 = Norm
% 2 = HAA
% Hard coded based on consensus tree (Attempt Final N=300 (nodes = 40) 20240505)
segmentRange = [3 1	3;
                1	1	9;
                2	1	16;
                0	9	13;
                4	9	20]; 
idx_unique = [3 1 0 4 2]; % specify which segments and in which order [Norm Transition fSAD Emph HAA].
%------------------------------------
idx_scale = [100 200 300 400 500]; % specify scaling factor for ech segment.
% [Norm Transition fSAD Emph HAA]
for i = 1:length(idx_unique)
    idx_Class = find(CTA{:,3} == idx_unique(i));
    scaleSeg(idx_Class) = idx_scale(i);
    numSeg(idx_Class) = (CTA{idx_Class,4}-segmentRange(segmentRange(:,1) == idx_unique(i),2)); % pseudoTime (CTA(:,4)) - min(pseudoTime for seg)
    denSeg(idx_Class) = diff(segmentRange(segmentRange(:,1) == idx_unique(i),2:3)); % range of pseudoTime for seg (segmentRange)
    numSeg(numSeg < 0) = 0; % if the pseudoTime form point is less than starting node value
    numSeg(numSeg > denSeg) = denSeg(numSeg > denSeg); % if the pseudoTime form point is greater than number of steps in segment
    frcSeg(idx_Class) = 99.*numSeg(idx_Class)./denSeg(idx_Class);
    idx_Segment(idx_Class) = scaleSeg(idx_Class) + frcSeg(idx_Class); % Classes get renamed 100, 200, 300, 400, 500, ...etc.
end
idx_Segment(idx_Segment == 0) = NaN;
%%--------------Save final table as csv
idxSeg = round(idx_Segment,0);
writetable([CTA(:,"idx") table(idxSeg)],fullfile(savepath,[caseID,'_idxSeg.csv']))
%-------------------
segTnum = [];
segTmean = [];
segTmed = [];
% segTmeanFeature = [];
% segT = [];
for segN = 1 : length(idx_unique)
    segTnum = cat(2, segTnum, sum(scaleSeg == segN*100)/numel(scaleSeg));
    segTmean = cat(2, segTmean, mean(frcSeg(scaleSeg == segN*100)));
    segTmed = cat(2, segTmed, median(frcSeg(scaleSeg == segN*100)));
    % segTmeanFeature = cat(2, segTmeanFeature, mean(CTA{scaleSeg == segN*100, featureNames},1)); % saves mean of features over segment
end
% segT = cat(1, segT, [segTnum segTmean segTmed segTmeanFeature]);

%% Generate 3D map
% Map Relabeled Segments to 3D volume
if imgTag
    % CTA_class = num2cell(idx_Segment);
    M = zeros([32^3 1]);
    M_idx = zeros([32^3 1]);
    M(CTA{:,"idx"}) = idxSeg; % this is to make the Tier map
    M_idx(CTA{:,"idx"}) = CTA{:,"idx"}; % this is just QC to confirm that idx is in right place when in 3D
    M1 = reshape(M,[32 32 32]);
    M1_idx = reshape(M_idx,[32 32 32]);
    % I put the rescaled data back to the original dimensions.
    finalCTAmap = imresize3(M1, info.ImageSize, 'nearest');
    finalIDXmap = imresize3(M1_idx, info.ImageSize, 'nearest');

    fov = info.PixelDimensions .* info.ImageSize;
    orient = diag([-1 -1 1 1]) * info.Transform.T';
    saveNIFTI(fullfile(savepath,[caseID,'.CTAMap.nii.gz']),finalCTAmap,{'CTAmap'},fov,orient);
    saveNIFTI(fullfile(savepath,[caseID,'.IDXMap.nii.gz']),finalIDXmap,{'IDXmap'},fov,orient);
end







function finalCTAtable = cta_csv(img_rs, mask_rs, caseID, info, strMod, pSizeNew, fn_log)
mask_rs(mask_rs>0) = 1; mask_rs(mask_rs == 0) = nan; % label outside mask as nan.
% img_rs = img_rs_orig;
% img_rs = mask_rs.*img_rs; % segment lungs
% Determine 16^3 patch volume using 512^3 matrix size
if pSizeNew(3)>1
    sx = 1; sy = 1; sz = 1;
    tx = 0; ty = 0; tz = 0;
    A = [0 sx 0 tx;
        sy 0 0 ty;
        0 0 sz tz;
        0 0 0 1];
    tform = affinetform3d(A);
    volGeo = medicalref3d(pSizeNew,tform);
end
%%----------------------------------
% Generate patches of 16^3 as cells in 32^3 batches and use cellfun to generate mean (and other variables) values for feeding into ClinTrajAn
% this is for the Mask
[~, patches_mask] = image_patches(mask_rs, pSizeNew); % get patches for mask from pSizeNew
pat_mask2 = reshape(patches_mask,[],1); % reshape to vector with 16^3 cells
A_mask = cellfun(@(x) {mean(x, 'All','omitnan')}, pat_mask2); % this will determine which 16^3 patches have a 1 and convert to scalar value of 1 or NaN
info.A_mask = A_mask;
info.PatchSize = pSizeNew;
info.ImageResize = size(mask_rs);
%--Save info for 3D mapping back to Imaging space
% if exist(fullfile(homePwd,'CTA_info'), 'dir') == 0
%     mkdir(fullfile(homePwd,'CTA_info'));
% end
% save(fullfile(homePwd,'CTA_info', [IDfolder,'_info.mat']), "info")
% generate percent volume and indices------------------------
percVol2 = cellfun(@(x) round(100.*sum(x, 'All','omitnan')./(prod(pSizeNew)),2), pat_mask2); % percent volume not Nan
idx = find(~isnan(cell2mat(A_mask))&percVol2>=75); % this determines which indices don't have nan (within mask) and percVol>75%
writeLog(fn_log,'total number of indices is %d\n', length(idx))
% This is for the imaging data
for j = 1:size(img_rs,4)
    writeLog(fn_log,'Working on imaging modality %s interation %d\n',strMod{j}, j)
    [~, patches_img] = image_patches(img_rs(:,:,:,j), pSizeNew); % get patches for img as pSizeNew
    pat2 = reshape(patches_img,[],1); % reshape to vector with product of pSizeNew
    pat = pat2(idx); % only use idx patches
    pat_mask = pat_mask2(idx); % only use idx mask patches
    percVol = percVol2(idx);
    %------------------------
    rad = [];
    for ii = 1:length(idx)
        if strcmp(strMod{j},"prm") || strcmp(strMod{j},"PRM")
            prm_class = {"norm" "fsad" "emph" "pd"};
            prm_top = {"v" "s" "b" "x"};
            prmLabel = [];
            count_PRM = 1;
            for prm_i = 1:length(prm_class)
                switch prm_class{prm_i}
                    case "norm"
                        prm_Inc = 1:2;
                    case "fsad"
                        prm_Inc = 3;
                    case "emph"
                        prm_Inc = 4:5;
                    case "pd"
                        prm_Inc = 8:10;
                end
                BW = ismember(pat{ii,1},prm_Inc);
                mask = pat_mask{ii,1}; mask(isnan(mask)) = 0;
                for mf_i = 1:1 % set to only generate volume density
                    p(1,count_PRM) = calcMF3D(BW,info.PixelDimensions,mf_i-1,logical(mask)); % topology of PRM
                    prmStr = "Y.Z";
                    prmStr = strrep(prmStr,"Y",prm_class{prm_i});
                    prmStr = strrep(prmStr,"Z",prm_top{mf_i});
                    prmLabel = [prmLabel prmStr];
                    count_PRM = count_PRM + 1;
                end
            end
            prm(ii).mf = splitvars([table([idx(ii) percVol(ii) p])]);
        else
            medVOI = medicalVolume(pat_mask{ii,1}, volGeo);
            medImg = medicalVolume(pat{ii,1}, volGeo);
            %-Info on Subtype and Features
            % https://www.mathworks.com/help/medical-imaging/ug/ibsi-standard-and-radiomics-function-feature-correspondences.html
            try
                R = radiomics(medImg, medVOI);
                % rad(ii).sf =[table([idx(ii) percVol(idx(ii))]) shapeFeatures(R,"SubType","3D")];
                rad(ii).if = [table([idx(ii) percVol(idx(ii))]) intensityFeatures(R,"Type", "all","SubType","2D")];
                % rad(ii).tf = [table([idx(ii) percVol(idx(ii))]) textureFeatures(R,"Type","GLCM", "SubType","3D")];
            catch
                sprintf('Error occurred in Radiomics for Case %s, modality %s',caseID, strMod{j})
            end
        end
    end
    %%-----------------------------------------------
    if strcmp(strMod{j},"prm") || strcmp(strMod{j},"PRM")
        prmMF = cat(1, prm(:).mf);
        prmMF.Properties.VariableNames(1:end) =  ["idx" "percVol" prmLabel];
    else
        % Surface Features
        % sF = cat(1, rad(:).sf);
        % sF = removevars(sF, 'LabelID'); sF{:,:} = single(sF{:,:});
        % sF.Properties.VariableNames(2:end) =  sF.Properties.VariableNames(2:end) + "_sf_" + strMod{j};
        % Intensity Features
        iF = cat(1, rad(:).if);
        iF = removevars(iF, {'LabelID'}); iF{:,:} = single(iF{:,:});
        iF.Properties.VariableNames(2:end) =  iF.Properties.VariableNames(2:end) + "_if_" + strMod{j};
        % Texture Features
        % tF = cat(1, rad(:).tf);
        % tF = removevars(tF, {'LabelID'}); tF{:,:} = single(tF{:,:});
        % tF.Properties.VariableNames(2:end) =  tF.Properties.VariableNames(2:end) + "_tf_" + strMod{j};
    end
    %--------------------------
    % CTA_table(j).tableNew = innerjoin(innerjoin(sF, iF), tF);
    CTA_table(j).tableNew = prmMF;
end
%%------------------------------------------
for kk = 1: length(CTA_table)
    if kk == 1
        finalCTAtable = CTA_table(kk).tableNew;
    else
        finalCTAtable = innerjoin(finalCTAtable, CTA_table(kk).tableNew);
    end
end
if ismember('Var1', finalCTAtable.Properties.VariableNames)
    finalCTAtable = splitvars(finalCTAtable,'Var1','NewVariableNames',{'index' 'percVol'});
end
% uncomment below when you are ready to save patch csv file
% writetable(finalCTAtable,fullfile(homePwd,'CTA_tables',[IDfolder,'_4CTA.csv']));
%%


function [P, patches] = image_patches(data, patchDim)
xsize = patchDim(1); ysize = patchDim(2); zsize = patchDim(3);
[nrows, ncols, npanes] = size(data);
if mod(nrows,ysize) ~= 0 || mod(ncols,xsize) ~= 0 || mod(npanes, zsize) ~= 0
    error('Image size [%d, %d, %d] is not evenly divisible into blocks of size [%d, %d, %d]', nrows, ncols, npanes, ysize, xsize, zsize );
end
patches = mat2cell( data, ysize * ones(1, nrows/ysize), xsize * ones(1, ncols/xsize), zsize * ones(1, npanes / zsize) );
P=cat(4,patches{:});
