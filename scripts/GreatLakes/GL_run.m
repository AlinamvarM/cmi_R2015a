function GL_run(varargin)
% Prepares processes for running on Great Lakes
% Saves temporary files to: Turbo:\GreatLakes\temp
% Must execute sbatch manually using PuTTy
% Syntax:
%   GL_run( username , ...   % your uniquename (e.g. 'cgalban')
%           function_string , ... % name of recursive function (e.g. 'job_tPRM')
%           inputs , ...     % <1xM> cell array - inputs to recursive function
%           path_flag , ...  % <1xM> logical - (optional) flag to correct Turbo path (local to GL)
%           static_flag , ...% <1xM> logical - indicateds static input accross increments
%           Name/Value )
% Optional Name/Value inputs:
%   'Nodes' - number of nodes to run on
%   'ProcessTime' - estimated processing time (minutes) per iteration (overestimate)
%   'ProcessMemory' - estimated memory requirement (GB) per iteration
%   'Partition' - type of partition to use {'auto','standard','largemem'}
% Example:
%   GL_run('bahoff','job_tPRM',{fn_prm,fn_seg,sv_path},[true,true,true],[false,false,true],...
%          'Nodes',5,'ProcessTime',120,'ProcessMemory',12,'Partition','auto')

if nargin~=2
    
% ~~~~~~~~~~~~~~~~~~~~~
% ~~ LOCAL EXECUTION ~~
% ~~~~~~~~~~~~~~~~~~~~~
    
    opts = parseInputs(varargin{:});

    % Determine SBATCH inputs
    jobname = sprintf('%s_%s_%s',opts.username,opts.function_string,opts.TimeStamp);
    fname = [jobname,'.sh'];

    % Calculate number of nodes
    % Max cores are adjusted smalled than max to make sure jobs can find an available partition
    switch opts.Partition 
        case 'standard'
            core_max = 30;
        case 'largemem'
            core_max = 24;
        otherwise
            core_max = 20;
    end 
    cores = min(min(opts.Niter,floor(opts.MaxMem/opts.ProcessMemory))+1,core_max);
    walltime = opts.ProcessTime*ceil(opts.Niter/(cores-1));
    if isnan(opts.Nodes)
        opts.Nodes = ceil(walltime/(14*24*60)); % 14 days max walltime
    end

    % Recalculate taking into account #nodes
    Niter_sub = ceil(opts.Niter/opts.Nodes);
    cores = min(min(Niter_sub,floor(opts.MaxMem/opts.ProcessMemory))+1,core_max);
    mem = opts.ProcessMemory * (cores-1);
    walltime = opts.ProcessTime*ceil(Niter_sub/(cores-1));
    if walltime > (14*24*60) % 14 day max walltime
        warning('Processes may not complete.\nEstimated time = %s\n',...
            datestr(duration(0,walltime,0),'dd-HH:MM:SS'));
    end

    % Save batch job inputs to Turbo temp directory
    fname_inputs = fullfile(opts.TempDir,sprintf('%s_INPUTS.mat',jobname));
    save(fname_inputs,'-struct','opts');

    % Write SBATCH file
    SBopts = {'partition',opts.Partition, 'cores',cores, 'mem',mem, 'walltime',walltime,...
        'username',opts.username, 'inputs_fname',fname_inputs,'acctname',opts.Account      };
    if opts.Nodes > 1
        SBopts = [SBopts,{'array',opts.Nodes}];
    end
    if ~isempty(opts.mods)
        SBopts = [SBopts,{'mods',opts.mods}];
    end
    write_sbatch(fullfile(opts.TempDir,fname),jobname,'GL_run',SBopts{:});

    % Run SBATCH
    sb_str = sprintf('cd /nfs/turbo/umms-cgalban/GreatLakes/temp && sbatch %s',fname);
    clipboard('copy',sb_str);
    fprintf(['\n\n1) Use PuTTy to log onto Great Lakes:\n',...
             '   Host Name: greatlakes.arc-ts.umich.edu\n',...
             '   Login: Level 1\n',...
             '2) Start SBATCH using terminal commands:\n',...
             '   (ALREADY IN CLIPBOARD, just paste into PuTTy using middle mouse button)\n',...
             '   ',sb_str,'\n\n'],fname);

else
    
% ~~~~~~~~~~~~~~~~~~~~~~~~~~
% ~~ GREATLAKES EXECUTION ~~
% ~~~~~~~~~~~~~~~~~~~~~~~~~~
    
        % In GL, load file containing relevant inputs to the processing function
        %   and start processing jobs  
        
        if ischar(varargin{2}) && exist(varargin{2},'file') && strcmp(varargin{2}(end-3:end),'.mat')
            inputs_fname = varargin{2};
        else
            error('Invalid input: must be valid .mat file containing function inputs.');
        end
        
        fprintf('Available workers on this node: %s\n',getenv('SLURM_CPUS_PER_TASK'));
        
        p = load(inputs_fname);
        
        % Check for job array:
        jobname = getenv('SLURM_JOB_NAME');
        jobnum = str2double(getenv('SLURM_ARRAY_TASK_ID'));
        if isnan(jobnum)
            ind = 1:p.Niter;
        else
            fprintf('Running job number %u of %u\n',jobnum,p.Nodes);
            
            ind = round(p.Niter/p.Nodes * [jobnum-1 jobnum]) + [1,0];
            fprintf('ind: %u-%u\n',ind);
            
            ind = ind(1):ind(2);
        end
        p.Niter = numel(ind);
        
        % Set up cluster properties
        c = parcluster;
        jobdir = fullfile(c.JobStorageLocation,sprintf('%s_array%u',jobname,jobnum));
        mkdir(jobdir);
        c.JobStorageLocation = jobdir;
        
        % Start batch jobs
        Nin = numel(p.inputs);
        for i = 1:p.Niter
            % Find subsection index:
            ii = ind(i);
            
            % Extract inputs:
            temp_inputs = cell(1,Nin);
            for j = 1:Nin
                if p.static_flag(j)
                    temp_inputs{j} = p.inputs{j};
                elseif iscell(p.inputs{j})
                    temp_inputs{j} = p.inputs{j}{ii};
                else
                    temp_inputs{j} = p.inputs{j}(ii);
                end
            end
            
            fprintf('Starting batch job %u\n',ii);
            job(i) = batch(c,str2func(p.function_string),1,temp_inputs);
        end
        
        % Initialize table for statistics:
        T = table;
        
        % Wait for all jobs to complete
        errflag = true(p.Niter,1);
        dt = zeros(p.Niter,1);
        for i = 1:p.Niter
            wait(job(i));
            if ~isempty(job(i).Tasks(1).Error) || strcmp(job(i).State,'failed')
                errflag(i) = false;
                try
                    getReport(job(i).Tasks(1).Error)
                catch
                    job(i).Tasks(1).Error
                end
            else
                % Compile statistics:
                dt(i) = minutes(job(i).FinishDateTime - job(i).StartDateTime);
                val = job(i).fetchOutputs;
                val = val{1};
                if istable(val) && ~isempty(val) && (isempty(T) || (size(val,2) == size(T,2)))
                    val.Properties.RowNames = {};
                    T = [T;val];
                elseif ischar(val)
                    fprintf(val);
                end
            end
            fprintf('Job %u finished after %.1f minutes.\n',ind(i),dt(i));
            fprintf('  State: %s\n',job(i).State);
            job(i).diary
            
            % Delete job files:
            job(i).delete;
            
        end
        rmdir(jobdir,'s');
        
        % Write table with mean values to save path
        if ~isempty(p.save_path)
            svdir = checkTurboPath(p.save_path);
            jobnum_str = '';
            if ~isnan(jobnum)
                jobnum_str = [num2str(jobnum),'_'];
            end
            svname = fullfile(svdir,sprintf('%s_%sResults',jobname,jobnum_str));
            fprintf('Attempting to save results:\n');
            if istable(T)
                svname = [svname,'.csv'];
                writetable(T,svname,'WriteRowNames',true);
            else
                svname = [svname,'.mat'];
                save(svname,T);
            end
            fprintf('   ... %s\n',svname);
        end
        
        fprintf('Processing complete.\nAverage processing time = %.1f (%.1f) minutes.\n',...
            mean(dt(errflag)),std(dt(errflag)));
end


function opts = parseInputs(varargin)
p = inputParser;
addRequired(p,'username',@ischar);
addRequired(p,'function_string',@(x)ischar(x)&&(exist(x,'file')==2));
addRequired(p,'inputs',@iscell);
addRequired(p,'path_flag',@islogical);
addRequired(p,'static_flag',@islogical);
addParameter(p,'Nodes',1,@isscalar);
addParameter(p,'ProcessTime',60,@isscalar);
addParameter(p,'ProcessMemory',6,@isscalar);
addParameter(p,'Account','cgalban0',@(x)ismember(x,{'cgalban0','cgalban1','cgalban99'}))
addParameter(p,'Partition','auto',@(x)ismember(x,{'auto','standard','largemem'}));
addParameter(p,'mods',{},@iscellstr);
addParameter(p,'TimeStamp','',@ischar);
addParameter(p,'save_path','',@ischar);
parse(p,varargin{:});
opts = p.Results;

% Validate recursive inputs
opts.Niter = numel(opts.inputs{find(~opts.static_flag,1)});
for i = 1:numel(opts.inputs)
    % Check agreement in number of iterations
    if ~opts.static_flag(i) && numel(opts.inputs{i})~=opts.Niter
        error('Number of iterations must agree between inputs.');
    end
    
    % Validate directory inputs:
    if opts.path_flag(i)
        [opts.inputs{i},~,LOC_Turbo_Path] = checkTurboPath(opts.inputs{i});
    end
end

% Determine what type of partition to use
partition_stats = {'standard',180;...
                   'largemem',1500};
if strcmp(opts.Partition,'auto')
    if opts.ProcessMemory > 20
        opts.Partition = 'largemem';
    else
        opts.Partition = 'standard';
    end
end
opts.MaxMem = partition_stats{strcmp(opts.Partition,partition_stats(:,1)),2};

opts.TempDir = fullfile(LOC_Turbo_Path,'GreatLakes','temp');



