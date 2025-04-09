function stat = write_sbatch(fname,jobname,fcn,varargin)
% Syntax: stat = write_sbatch(fname,jobname,fcn,'Name',Value,...)
% Inputs:
%   - Required:
%       fname = name of SBATCH file to write
%       jobname = name of job to run
%       fcn = name of Matlab function to run
%   - Optional Name/Value pairs
%     inputs_fname = [char] file name (in Great Lakes) to input into fcn
%     partition = partition type: standard, gpu, or largemem
%     cores = number of cores to use
%     mem = GB of RAM
%     walltime = time limit in minutes
%     username = your UniqueName for email notifications
%     mailtype = comma-separated list of events for email (BEGIN,END,FAIL)

    r = parseInputs(fname,jobname,fcn,varargin);

    stat = false;

    GL_turbo_path = '/nfs/turbo/umms-cgalban';
    GL_Matlab_path = [GL_turbo_path,'/GreatLakes/cmi_R2015a'];

    % Check that inputs_fname is on Turbo and fix path if necessary
    if ~startsWith(r.inputs_fname,GL_turbo_path)
        errstr = '';
        tokens = regexp(r.inputs_fname,'([A-Z]+:)(.*)','tokens');
        if ~(isempty(tokens) || isempty(tokens{1}))
            driveLetter = tokens{1}{1};
            fpath = tokens{1}{2};
            netdrives = findNetDrives;
            ind = strcmp(driveLetter,{netdrives.Drive});
            if contains(netdrives(ind).Remote,'umms-cgalban')
                r.inputs_fname = [GL_turbo_path,regexprep(fpath,'\\','/')];
            else
                errstr = 'inputs_fname must be located in Turbo storage.';
            end
        else
            errstr = 'Invalid path for inputs_fname';
        end
        if ~isempty(errstr)
            error(errstr);
        end
    end
    
    % Fix defaults for partition
    switch r.partition
        case 'standard'
            cores_mx = 36;
            mem_mx = 180;
        case 'gpu'
            cores_mx = 40;
            mem_mx = 180;
        case 'largemem'
            cores_mx = 36;
            mem_mx = 1538;
    end

    % Determine modules needed:
    modstr = 'module load matlab\n\n';
    for i = 1:numel(r.mods)
        modstr = [modstr,'module load ',r.mods{i},'\n\n'];
    end
    
    fprintf('Writing SBATCH file: %s\n',r.fname);
   
    str = sprintf('#!/bin/bash\n\n'); % The interpreter used to execute the script
    str = [str,sprintf('#“#SBATCH” directives that convey submission options:\n\n')];
    str = [str,sprintf('#SBATCH --job-name=%s\n',r.jobname)];
    str = [str,sprintf('#SBATCH --account=%s\n',r.acctname)];
    str = [str,sprintf('#SBATCH --partition=%s\n',r.partition)];
    str = [str,sprintf('#SBATCH --nodes=1\n')];
    str = [str,sprintf('#SBATCH --ntasks-per-node=1\n')];
    str = [str,sprintf('#SBATCH --cpus-per-task=%u\n',min(r.cores,cores_mx))];
    str = [str,sprintf('#SBATCH --mem=%ug\n',min(r.mem,mem_mx))];
    str = [str,sprintf('#SBATCH --time=%s\n',r.walltime)];
    if ~isempty(r.username)
        str = [str,sprintf('#SBATCH --mail-user=%s@med.umich.edu\n',r.username)];
        str = [str,sprintf('#SBATCH --mail-type=%s\n',r.mailtype)];
    end
    if ~isempty(r.array)
        str = [str,sprintf('#SBATCH --array=1-%u\n',r.array)];
    end
    str = [str,sprintf(['#SBATCH --output=./%%x-%%j.log\n\n',...
                        'if [[ $SLURM_JOB_NODELIST ]] ; then\n',...
                        '   echo "Running on"\n',...
                        '   scontrol show hostnames $SLURM_JOB_NODELIST\n',...
                        'fi\n\n',...
                        modstr,...
                        'my_job_header\n\n',... % Script for printing info about job environment
                        'echo -n "My job array ID is:  "\n',...
                        'env | grep ARRAY_TASK_ID\n\n',...
                        '#  Put your job commands after this line\n'])];
    str = [str,sprintf(['matlab -nodisplay -r "cd(''%s'');','cmi_setPath;%s(1,''%s''); exit"\n\n'],GL_Matlab_path,r.fcn,r.inputs_fname)];
    str = [str,sprintf('my_job_statistics $SLURM_JOB_ID\n')]; % Script for printing performance statistics 
                   
    fid = fopen(r.fname,'w');
    if fid 
        fwrite(fid,str,'char');
        fclose(fid);
        stat = true;
    end
    
end

function r = parseInputs(fname,jobname,fcn,in)
    p = inputParser;
    p.addRequired('fname',@ischar);
    p.addRequired('jobname',@(x)ischar(x)&&isempty(regexp(x,'[/\*:?"<>|]','once')));
    p.addRequired('fcn',@(x)ischar(x)&&~isempty(which(x)));
    p.addParameter('inputs_fname','',@(x)ischar(x)&&exist(x,'file'));
    p.addParameter('acctname','cgalban0',@(x)ismember(x,{'cgalban0','cgalban1','cgalban99'}));
        % cgalban0 - UMRCP free alotment
        % cgalban1 - Paid account
        % cgalban99 - Med School free alotment
    p.addParameter('partition','standard',@(x)ischar(x)&&ismember(x,{'standard','largemem','gpu'}))
    p.addParameter('cores',1,@(x)isnumeric(x)&&(x>0)&&~isinf(x)&&floor(x)==x);
    p.addParameter('mem',8,@(x)isnumeric(x)&&(x>0)&&~isinf(x)&&floor(x)==x);
    p.addParameter('walltime',60,@(x)isnumeric(x)&&(x>0)&&~isinf(x)&&floor(x)==x);
    p.addParameter('array',[],@isnumeric);
    p.addParameter('username','',@(x)ischar(x)&&isempty(regexp(x,'[^a-z]','once')));
    p.addParameter('mailtype','END',@(x)ischar(x)&&all(ismember(strsplit(x,','),{'BEGIN','END','FAIL'})));
    p.addParameter('mods',{},@iscellstr);
    p.parse(fname,jobname,fcn,in{:});
    
    r = p.Results;
    
    % fname
    [fpath,fn,~] = fileparts(r.fname);
    if ~(isfolder(fpath) && isempty(regexp(fn, '[/\*:?"<>|]', 'once')))
        error('Invalid SBATCH file name.');
    end
    
    r.walltime = datestr(duration(0,p.Results.walltime,0),'dd-HH:MM:SS');
    r.array = round(p.Results.array);
end