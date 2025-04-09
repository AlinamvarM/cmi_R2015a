function T = catalog_dmg(basedir)

v = struct('CaseNumber',{},...
           'Tag',{},...
           'UMlabel',{},...
           'StudyDate',{},...
           'SliceThickness',{},...
           'Slices',{},...
           'DataPath',{},...
           'DataType',{},...
           'SeriesDescription',{},...
           'ScanOptions',{},...
           'Rows',{},...
           'Columns',{},...
           'dy',{},...
           'dx',{});
cnt = 0;
casenum = 0;

if nargin==0
    basedir = pwd;
end

% Search for folders named by subject ID
sdir = dir(fullfile(basedir,'DMG*'));
sdir = {sdir.name}';

subjID = sdir;
for i = 1:numel(sdir)
    sdir_full = fullfile(basedir,sdir{i});

    % Validate subject ID
    tok = regexp(sdir{i},'(DMG\d*)','tokens');
    subjID{i} = tok{1}{1};
    
    % Search subject folder for timepoints
    tdir = dir(fullfile(sdir_full));
    tdir = {tdir(3:end).name}';

    tpID = tdir;
    for j = 1:numel(tdir)
        tdir_full = fullfile(sdir_full,tdir{j});

        % Validate timepoint datestamp
        tok = regexp(tdir{j},'_(\d{8})_');
        if ~isempty(tok)
            tpID{j} = tok{1}{1};
            casenum = casenum+1;

            % Search for images
            fn = dir(fullfile(tdir_full));
            fn = {fn(3:end).name}';
            for k = 1:numel(fn)
                if endsWith(fn{k},'.nii.gz')
                    cnt = cnt+1;
                    fn_full = fullfile(tdir,fn{k});
                    info = niftiinfo(fn_full);
                    v(cnt).CaseNumber = casenum;
                    v(cnt).UMlabel = subjID{i};
                    v(cnt).StudyDate = tpID{j};
                    v(cnt).SliceThickness = info.PixelDimensions(3);
                    v(cnt).Slices = info.ImageSize(3);
                    v(cnt).DataPath = fn_full;
                    v(cnt).SeriesDescription = extractBefore();
                    v(cnt).Rows = ;
                    v(cnt).Columns = ;
                    v(cnt).dy = ;
                    v(cnt).dx = ;
                    v(cnt).Tag = ;
                else
                end
            end




            % Search for Nifti images
            fn_nii = dir(fullfile(tdir_full,'*.nii.gz'));
            
            % Search for DICOMs
            fn_dcm = dir(fullfile(tdir_full));
            fn_dcm(1:2) = [];
            fn_dcm = {fn_dcm.name}';
            fn_valid = false(numel(fn_dcm),1);
            for k = 1:numel(fn_dcm)
                fn = dir(fullfile(tdir_full,fn_dcm{k}));
                try
                    fn_valid(k) = isdicom(fullfile(fn(3).folder,fn(3).name));
                end
            end




        end

    end

end