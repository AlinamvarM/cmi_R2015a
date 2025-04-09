function [opts,cases,results] = CTlung_Pipeline_run(cases,opts)
% Script for looping over selected Pipeline cases
%   AND optionally setting up inputs for running on Great Lakes

results = [];

try
    
% Start CT lung pipeline script (Main_Pipeline_sub) with GUI selection for
% cases based on DCMcatalog.csv

if nargin<2
    % use default options
    opts = init_pipeline_opts;
end

% Find files
if nargin<2
    [cases,opts] = catalog_select_4('opts',opts);
    if isempty(cases)
        return;
    end
end
ncases = numel(cases);

% Make sure the save directory is on Turbo, for access from GL
if ismember(opts.cluster,{'GL','tier2'})
    [~,flag_turbo] = checkTurboPath(opts.save_path);
    if flag_turbo
        error('Save path must be on Turbo for access from Great Lakes.');
    end
end

% Determine pipeline inputs
for i = 1:ncases
    ind = find(strcmp(cases(i).Scans.Tag,'Exp'));
    if isempty(ind)
        cases(i).fname_exp = '';
    else
        cases(i).fname_exp = cases(i).Scans.DataPath{ind};
    end
    ind = find(strcmp(cases(i).Scans.Tag,'Ins'));
    if isempty(ind)
        cases(i).fname_ins = '';
    else
        cases(i).fname_ins = cases(i).Scans.DataPath{ind};
    end
    cases(i).basename = sprintf('%s_%s',cases(i).UMlabel,cases(i).StudyDate);
    cases(i).procdir = fullfile(opts.save_path,cases(i).basename);
end

% Delete existing GIF montages to start from scratch
fn = fullfile(opts.save_path,["Montage_exp","Montage_ins","Montage_reg","Montage_PRM","Montage_PRM_Scatter"]+".gif");
for i = 1:numel(fn)
    if exist(fn(i),'file')
        delete(fn(i));
    end
end

% Determine how to run the pipeline, based on opts.cluster:
%  - 'GL'    = run DICOM loading and YACTA locally, then the rest on GL
%  - 'batch' = run full pipeline locally in batch job
%  - 'debug' = run full pipeline locally in command window
if strcmp(opts.cluster,'debug')
    
%~~~~~~~~~ debug ~~~~~~~~~
    results = [];
    for i = 1:ncases
        res = pipeline_full(cases(i),opts);
        if ~isempty(res) && istable(res)
            results = addResultsToTable(results,res);%[results;res];
        end
    end
else
    % Set up cluster properties
    c = parcluster('local');
    nworkers_orig = c.NumWorkers;
    jobdir = fullfile(c.JobStorageLocation,sprintf('pipeline_local_%s',opts.timestamp));
    if ~isfolder(jobdir)
        mkdir(jobdir);
    end
    c.JobStorageLocation = jobdir;
    np = min([c.NumWorkers-1,ncases,opts.par_size]);
    if strcmp(opts.cluster,'GL') % Run DICOM load and YACTA locally, then the rest on GL
%~~~~~~~~~ GL ~~~~~~~~~
        fprintf(['Running local processes as batch with pool size of %d\n',...
                 'Please wait at least an hour before starting GL process\n'],np);
        save_path = checkTurboPath(opts.save_path);
        batch(@pipeline_loop,1,{cases,opts},'Pool',nworkers_orig,'Pool',np);
        GL_run(opts.username, 'CTlung_Pipeline_sub', {{cases.procdir}',opts}, [true,false], [false,true],...
            'Partition',opts.cluster_type,'ProcessMemory',opts.mem,'ProcessTime',720,'Nodes',opts.nnodes,...
            'TimeStamp',opts.timestamp,'Account',opts.acct,'save_path',save_path);
    elseif strcmp(opts.cluster,'tier2')
%~~~~~~~~~ Tier2 ~~~~~~~~~
        fprintf(['Running local processes as batch with pool size of %d\n,...' ...
                 'Please wait at least an hour before starting server processing\n'],np)
        save_path = checkTurboPath(opts.save_path);
        batch(@pipeline_loop,1,{cases,opts},'Pool',nworkers_orig,'Pool',np);
        Tier2_run(opts.username,'CTlung_Pipeline_sub',{{cases.procdir}',opts}, [true,false], [false,true],...
            'TimeStamp',opts.timestamp,'save_path',save_path);
    else
%~~~~~~~~~ batch ~~~~~~~~~
        fprintf('Running FULL PIPELINE in batch with pool size of %d\n',np);
        batch(@pipeline_loop,1,{cases,opts},'Pool',np);
    end
end

    
catch err
    getReport(err)
end


function results = pipeline_loop(cases,opts)
results = [];

% Loop function for inside batch process
ncases = numel(cases);

f(1:ncases) = parallel.FevalFuture;
switch opts.cluster
    case {'GL','tier2'} 
        % Start queue for local processes:
        for i = 1:ncases
            fprintf('Starting processing for case #%d of %d: %s\n',i,ncases,cases(i).basename);
            f(i) = parfeval(@(x,y,z,k,l)CTlung_Pipeline_local(x,y,z,k,l),0,...
                cases(i).basename,cases(i).fname_exp,cases(i).fname_ins,cases(i).procdir,opts);
        end
        % Flag processes as they complete
        for i = 1:ncases
            idx = fetchNext(f);
            fprintf('Finished process #%d of %d: %s\n', idx, ncases, cases(idx).basename);
        end
    otherwise % 'batch' or 'debug' - Run full process locally
        % Start queue for parallel processes:
        for i = 1:ncases
            fprintf('Starting processing for case #%d of %d: %s\n',i,ncases,cases(i).basename);
            f(i) = parfeval(@(x,y)pipeline_full(x,y),1,cases(i),opts);
        end
        % Flag processes as they complete
        for i = 1:ncases
            [idx,res] = fetchNext(f);
            fprintf('Finished process #%d of %d: %s\n', idx, ncases, cases(idx).basename);
            % Gather results
            if ~isempty(res) && istable(res)
                results = addResultsToTable(results,res);%[results;res];
            end
        end
        % Write compiled results to CSV
        if ~isempty(results) && istable(results)
            writetable(results,fullfile(opts.save_path,'Pipeline_Results.csv'));
        end
end

function res = pipeline_full(case_i,opts)
CTlung_Pipeline_local(case_i.basename,case_i.fname_exp,case_i.fname_ins,case_i.procdir,opts);
res = CTlung_Pipeline_sub(case_i.procdir,opts);