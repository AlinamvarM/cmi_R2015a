function sadTier_v02(caseLC, img, voi, refInfo)
% next 4 lines are used to get inputs from demo case 10005Q
% caseLC = '11104X';
% img = niftiread('11104X_PRM.nii.gz');
% refInfo = niftiinfo('11104X_PRM.nii.gz');
% voi = niftiread('11104X_EXP_STD_JHU_COPD.njh.lobe_segmentation.nii.gz');
% initialize
% read in CTA files into structure with ID and Gold at baseline
strMod = {'PRM'; 'lobe_segmentation'};
pSize = [16 16 16]; % patch size.
imSizeNew = [512 512 512]; % resize
homepwd = pwd;
imgTag = 1;
if exist(fullfile(pwd,[caseLC,'_features']), 'dir') == 0
    mkdir(fullfile(pwd,[caseLC,'_features']));
end
% Resize data to 512^3
voi = single(permute(imresize3(logical(voi), imSizeNew, 'nearest'),[2 1 3]));
img = single(permute(imresize3(img, imSizeNew, 'nearest'),[2 1 3]));
% I do need to save A_mask in this function for each case to map back to 3D space.
% strMod([1 3:end]); grabs all labels in strMod except the 2nd position which
% is Segmentation.
finalCTAtable = cta_csv(img, voi, homepwd, caseLC, refInfo, strMod([1 3:end]), pSize);
% Save finalCTAtable as CSV file.
% csvFilename = fullfile(homepwd, [caseLC, '_finalCTAtable.csv']);
% writetable(finalCTAtable, csvFilename);
% disp(['finalCTAtable saved as CSV file: ', csvFilename]);
% Add these debugging lines
disp('Checking finalCTAtable:');
disp(class(finalCTAtable));  % Should be 'table'
disp(size(finalCTAtable));   % Check dimensions
if istable(finalCTAtable)
    disp(finalCTAtable.Properties.VariableNames); % See what variables are present
end
%% Project data in finalCTAtable onto Clintrajan model [Call Python Code]
clear X
% Load data used to make original Elastic Graph Model
python_path = update_python_paths();
origDataFile = dir(fullfile('**','*','caseSelection_ID_Final300_random.csv'));
origData = readtable(fullfile(origDataFile.folder, origDataFile.name), 'VariableNamingRule','preserve');
rootNode= 1
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
original_data_size = size(origData, 1);
% After computing PCA
[score, score_case, coeff, explained] = PCApython(Xs_combined, your_data_size, numComp);
% Load VOX PCA data
vox_pca = readmatrix(fullfile(pwd, 'data.txt'));
% Align PCA components
[score_aligned, score_case_aligned, coeff_aligned, flip_report] = ...
    align_pca_components(score, score_case, coeff, vox_pca);
% Use aligned scores for subsequent analysis
score = score_aligned;
score_case = score_case_aligned(1:your_data_size, :);
% Create visualization to compare with VOX model PCA after alignment
figure('Position', [100, 100, 1200, 400]);
% PC1 vs PC2 plot
subplot(1, 3, 1);
scatter(vox_pca(:, 1), vox_pca(:, 2), 10, 'blue', 'filled', 'MarkerFaceAlpha', 0.3);
hold on;
scatter(score_case(:, 1), score_case(:, 2), 80, 'red', 'filled');
xlabel('PC1');
ylabel('PC2');
title('PC1 vs PC2');
legend('VOX Model', 'Your Case (Aligned)', 'Location', 'best');
grid on;
% PC1 vs PC3 plot
subplot(1, 3, 2);
scatter(vox_pca(:, 1), vox_pca(:, 3), 10, 'blue', 'filled', 'MarkerFaceAlpha', 0.3);
hold on;
scatter(score_case(:, 1), score_case(:, 3), 80, 'red', 'filled');
xlabel('PC1');
ylabel('PC3');
title('PC1 vs PC3');
grid on;
% PC2 vs PC3 plot
subplot(1, 3, 3);
scatter(vox_pca(:, 2), vox_pca(:, 3), 10, 'blue', 'filled', 'MarkerFaceAlpha', 0.3);
hold on;
scatter(score_case(:, 2), score_case(:, 3), 80, 'red', 'filled');
xlabel('PC2');
ylabel('PC3');
title('PC2 vs PC3');
grid on;
sgtitle('Comparison of Case PCA with VOX Model PCA (After Alignment)');
saveas(gcf, fullfile(homepwd, 'pca_alignment_check.png'));
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Setup Enviroment
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Tell MATLAB which Python to use
python_path = update_python_paths();
pyenv('Version', python_path, 'ExecutionMode', 'OutOfProcess');
% Find the VOX file exactly
vox_file = dir(fullfile('**','caseSelection_ID_Final300_random_Vonly_n40__VOX1'));
if isempty(vox_file)
    error('VOX file not found');
end
vox_filepath = fullfile(vox_file(1).folder, vox_file(1).name);
% Set output path
output_path = fullfile(homepwd, 'results', [caseLC '_clintrajan_results.csv']);
% Make sure the directory exists
if ~exist(fullfile(homepwd, 'results'), 'dir')
    mkdir(fullfile(homepwd, 'results'));
end
% Keep track of your data size vs. original model data
your_data_size = size(finalCTAtable, 1);
original_data_size = size(origData, 1);
fprintf('Number of points in current case: %d\n', your_data_size);
fprintf('Total points after adding reference data: %d\n', size(score, 1));
% Load the VOX file to get the pre-trained tree structure 
tree_elpi = load_and_process_tree(score_case, vox_filepath);
% Data Partition - use full score but track only your points
[vec_labels_by_branches, partition_by_node] = partition_data_from_python(score_case, tree_elpi);
% Extract Trajectories
[all_trajectories, all_trajectories_edges] = extract_trajectories_from_python(tree_elpi, rootNode);
% Project data onto tree
ProjStruct = project_on_tree_from_python(score_case, tree_elpi);
% Calculate pseudotime for all points
PseudoTimeTraj = quantify_pseudotime_from_python(all_trajectories, all_trajectories_edges, ProjStruct);
% Save only your points using the modified function
CTA = save_point_projections_in_table_yours(vec_labels_by_branches, PseudoTimeTraj, output_path, your_data_size, finalCTAtable);
% After calculating pseudotime
feature_name = 'fsad.v';
output_path = fullfile(homepwd, 'results', [caseLC '_' feature_name '_tree.png']);
% Call visualization function
visualize_eltree_from_python(tree_elpi, score_case, finalCTAtable, feature_name, output_path);
% Extract str_cases from the filename
[~, str_cases, ~] = fileparts(fullfile(homepwd, 'results', [caseLC '_clintrajan_results.csv']));
str_cases = extractBefore(str_cases, '_clintrajan_results');
%% Determine Tier assignment and position and generate 3D map
idx = CTA{:,2};
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
segmentRange = [3 1	3;
    1	1	9;
    2	1	16;
    0	9	13;
    4	9	20]; % Hard coded based on consensus tree (Attempt Final N=300 (nodes = 40) 20240505)
idx_unique = [3 1 0 4 2]; % specify which segments and in which order [Norm Transition fSAD Emph HAA].
%------------------------------------
idx_scale = [100 200 300 400 500]; % specify scaleing factor for ech segment.
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
writetable([CTA(:,"idx") table(idxSeg)],fullfile(pwd,[str_cases,'_features'],[caseLC,'_idxSeg.csv']))
%-------------------
segTnum = [];
segTmean = [];
segTmed = [];
segTmeanFeature = [];
segT = [];
for segN = 1 : length(idx_unique)
    segTnum = cat(2, segTnum, sum(scaleSeg == segN*100)/numel(scaleSeg));
    segTmean = cat(2, segTmean, mean(frcSeg(scaleSeg == segN*100)));
    segTmed = cat(2, segTmed, median(frcSeg(scaleSeg == segN*100)));
    % segTmeanFeature = cat(2, segTmeanFeature, mean(CTA{scaleSeg == segN*100, featureNames},1)); % saves mean of features over segment
end
segT = cat(1, segT, [segTnum segTmean segTmed segTmeanFeature]);
%% Generate 3D map
% Map Relabeled Segments to 3D volume
if imgTag == 1
    CTA_class = num2cell(idx_Segment);
    M=zeros([32^3 1]);
    M_idx=zeros([32^3 1]);
    M(CTA{:,"idx"}) = idxSeg; % this is to make the Tier map
    M_idx(CTA{:,"idx"}) = CTA{:,"idx"}; % this is just QC to confirm that idx is in right place when in 3D
    M1 = reshape(M,[32 32 32]);
    M1_idx = reshape(M_idx,[32 32 32]);
    % I put the rescaled data back to the original dimensions.
    finalCTAmap = imresize3(M1, refInfo.ImageSize, 'nearest');
    finalIDXmap = imresize3(M1_idx, refInfo.ImageSize, 'nearest');
    % cmiObj0.imgAppend(cat(4, finalCTAmap, finalIDXmap),{'tPRMClass', 'IDX'});
    % cmiObj0.setImg(cat(4, finalCTAmap, finalIDXmap),{},[1 1 1],eye(4),{'tPRMClass', 'IDX'}); % this is for QC to see scaled img on cmi gui
    %%--------------Save final table as csv
    if exist(fullfile(pwd,[str_cases,'_features'],'CTA_Maps'), 'dir') == 0
        mkdir(fullfile(pwd,[str_cases,'_features'],'CTA_Maps'));
    end
    if exist(fullfile(pwd,[str_cases,'_features'],'CTA_Maps',caseLC), 'dir') == 0
        mkdir(fullfile(pwd,[str_cases,'_features'],'CTA_Maps',caseLC));
    end
    refInfo.Datatype = 'int16';
    refInfo.Filename = fullfile(pwd,'CTA_Maps',caseLC,[caseLC,'_CTAMaps.nii']);
    niftiwrite(int16(permute(finalCTAmap, [2 1 3])),fullfile(pwd,[str_cases,'_features'],'CTA_Maps',caseLC,[caseLC,'_CTAMaps.nii']),refInfo,'Compressed',true);
    refInfo.Filename = fullfile(pwd,'CTA_Maps',caseLC,[caseLC,'_IDXMaps.nii']);
    niftiwrite(int16(permute(finalIDXmap, [2 1 3])),fullfile(pwd,[str_cases,'_features'],'CTA_Maps',caseLC,[caseLC,'_IDXMaps.nii']),refInfo,'Compressed',true);
end
%%
function finalCTAtable = cta_csv(img_rs, mask_rs, homePwd, IDfolder, info, strMod, pSizeNew)
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
pat_mask2=reshape(patches_mask,[],1); % reshape to vector with 16^3 cells
A_mask=cellfun(@(x) {mean(x, 'All','omitnan')}, pat_mask2); % this will determine which 16^3 patches have a 1 and convert to scalar value of 1 or NaN
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
sprintf('total number of indices is %d', length(idx))
% This is for the imaging data
for j = 1:size(img_rs,4)
    sprintf('Working on imaging modality %s interation %d',strMod{j}, j)
    [~, patches_img] = image_patches(img_rs(:,:,:,j), pSizeNew); % get patches for img as pSizeNew
    pat2=reshape(patches_img,[],1); % reshape to vector with product of pSizeNew
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
                sprintf('Error occurred in Radiomics for Case %s, modality %s',IDfolder, strMod{j})
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
