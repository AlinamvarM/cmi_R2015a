function Main_Pipeline_2

% Input: catalog = cell array of dicom information in a directory generated
%                   by the "dcmCatalog()" script

% Pipeline consists of:
% 1. Select data for processing based on catalogDICOM script .csv file
% 2. Identify image key information and read images
% 3. Generate lung segmentations
% 4. Identify Exp/Ins images and save as .nii.gz
% 5. Quantify unregistered lung statistics
% 2. Enqueue elastix registration

%% Determine data for processing:
% cases is structure array:
%   cases(i).PatientID
%           .StudyDate
%           .Scans - Structure containing scan info for selected data
if nargin==0
    catalog = [];
end
[cases, home_pwd] = catalog_select_2(catalog);

%% prepare Data Table with Dummy values
dataTable = table;

%% Initialize processing structure:
data = struct('img',{[ImageClass;ImageClass]},...
    'dcmnames',{dcmnames},...
    'procdir',fullfile(procdir,ID),...
    'elxdir',fullfile(procdir,ID,sprintf('elxreg_%s',fname_Ins)),...
    'fname',struct('exp',sprintf('%s_Exp',ID),...
                   'ins',sprintf('%s_Ins',ID),...
                   'exp_label',sprintf('%s_Exp_Label',ID),...
                   'ins_label',sprintf('%s_Ins_Label',ID),...
                   'scatnet',sprintf('%s_SNmap',ID)),...
    'ext','.nii.gz',...
    'table',table);

if ~isfolder(data.elxdir)
    mkdir(data.elxdir);
end

%% Loop over cases
N = length(cases);
fn_ext = '.nii.gz';
h1 = waitbar(0, 'Analyze Exp and Ins data');
for i = 1:N
    ID = sprintf('%s_%s',cases(i).PatientName,cases(i).StudyDate);
    waitbar(i/N,h1,[num2str(round(100*(i-1)/N,1)),'% Complete: Load Data and Masks for ',ID])
        
        %% Establish relevant filenmes:
        data.
        data.procdir = fullfile(home_pwd,'ProcessedData',ID);
        fname_Exp = sprintf('%s_Exp',ID);
        fname_Ins = sprintf('%s_Ins',ID);
        fname_Exp_Label = sprintf('%s_Exp_Label',ID);
        fname_Ins_Label = sprintf('%s_Ins_Label',ID);
        fname_ScatNet = sprintf('%s_SNmap',ID);
        elxdir = fullfile(procdir,sprintf('elxreg_%s',fname_Ins));
        if ~isfolder(elxdir)
            mkdir(elxdir);
        end
        
        %% Read selected DICOM data:
        fprintf('\nReading image data from file ... ID = %s\n',ID)
        if ~(exist(fullfile(procdir,[fname_Exp,fn_ext]),'file') && exist(fullfile(procdir,[fname_Ins,fn_ext]),'file'))
            fprintf('   ... from DICOM\n');
            regObj.cmiObj(1).loadImg(0,cases(i).Scans(strcmp({cases(i).Scans(:).Tag},'Exp')).Directory,procdir,fname_Exp);
            regObj.cmiObj(2).loadImg(0,cases(i).Scans(strcmp({cases(i).Scans(:).Tag},'Ins')).Directory,procdir,fname_Ins);
            check_EI = true;
        else
            fprintf('   ... from NiFTi\n');
            fprintf('   ... Reading Exp\n');
            regObj.cmiObj(1).loadImg(0,fullfile(procdir,[fname_Exp,fn_ext]),procdir,fname_Exp);
            fprintf('   ... Reading Ins\n');
            regObj.cmiObj(2).loadImg(0,fullfile(procdir,[fname_Ins,fn_ext]),procdir,fname_Ins);
            check_EI = false;
        end
        
        %% Generate Lung Segmentation [This is when VOI don't exist]
        if ~(exist(fullfile(procdir,[fname_Exp_Label,fn_ext]),'file') && exist(fullfile(procdir,[fname_Ins_Label,fn_ext]),'file'))
            fprintf('   Generating VOIs\n')
            tmask = Step02_segLungHuman_cjg(1,regObj.cmiObj(1).img.mat,fname_Exp_Label, procdir);
            regObj.cmiObj(1).img.mask.merge('replace',tmask);
            tmask = Step02_segLungHuman_cjg(1,regObj.cmiObj(2).img.mat,fname_Ins_Label, procdir);
            regObj.cmiObj(2).img.mask.merge('replace',tmask);
        else
            fprintf('   Reading VOIs from file\n')
            regObj.cmiObj(1).loadMask(fullfile(procdir,[fname_Exp_Label,fn_ext]));
            regObj.cmiObj(2).loadMask(fullfile(procdir,[fname_Ins_Label,fn_ext]));
        end

        %% Identify Exp and Ins using lung volume; used for determining file name
        if check_EI
            %   ** Need to double-check in case of mislabel
            if nnz(regObj.cmiObj(1).img.mask.mat) > nnz(regObj.cmiObj(2).img.mask.mat)
                regObj.swapCMIdata;
            end
            %% Save nii.gz files using ID and Tag
            regObj.cmiObj(1).img.saveImg(1,fullfile(procdir,[fname_Exp,fn_ext]),1);
            regObj.cmiObj(2).img.saveImg(1,fullfile(procdir,[fname_Ins,fn_ext]),1);
            regObj.cmiObj(1).img.saveMask(fullfile(procdir,[fname_Exp_Label,fn_ext]));
            regObj.cmiObj(2).img.saveMask(fullfile(procdir,[fname_Ins_Label,fn_ext]));
        end
        
        
        %% Quantify unregiste44444red CT scans
        fprintf('\n   Quantifying unregistered statistics\n');
        [expData,insData] = Step05_UnRegLungAnalysis(procdir, fname_ScatNet, regObj);

        %% Save data to Table
        dataTable.ID(i,:) = ID;

        dataTable.Exp_dFile(i,:) = {fname_Exp};
        dataTable.Ins_dFile(i,:) = {fname_Ins};

        dataTable.Exp_mFile(i,:) = {fname_Exp_Label};
        dataTable.Ins_mFile(i,:) = {fname_Ins_Label};

        dataTable.ExpVol(i,1) = expData(1); dataTable.ExpHU(i,1) = expData(2); dataTable.Exp856(i,1) = expData(3);
        dataTable.SNperc(i,1) = expData(4); dataTable.SNmean(i,1) = expData(5);

        dataTable.InsVol(i,1) = insData(1); dataTable.InsHU(i,1) = insData(2); dataTable.Ins950(i,1) = insData(3);
        dataTable.Ins810(i,1) = insData(4);

        %% Register I2E
        lungreg_BH(ID,elxdir,regObj);
end
delete(h1);

%% Assign data to base workspace
assignin('base', 'dataTable', dataTable)