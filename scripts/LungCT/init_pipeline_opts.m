function opts = init_pipeline_opts(varargin)

opts = struct( ...
              'dcm_path',       ''          ,... % Location of catalog file
              'save_path',      ''          ,... % Location to save pipeline results (for GL, must be on Turbo)
              'par_size',       5           ,... % parallel processes for local analysis
              'cluster',        'batch'     ,... % Where to process the data: 'GL', 'batch', or 'debug'
              'acct',           'cgalban0'  ,... % Account used for SBATCH
              'cluster_type',   'standard'  ,... % GL cluster type to use: 'largemem', 'standard'
              'mem',            24          ,... % GL memory needed per process
              'nnodes',         1           ,... % GL number of nodes (only for standard)
              'username',       ''          ,... % GL your uniquename for email notifications
              ...
              'unreg',          true    ,... % MODULE unregistered stats for Exp/Ins
              'totalseg',       false   ,... % MODULE TotalSegmentator
              'airway',         true    ,... % MODULE airways results from YACTA
              'airsim',         false   ,... % MODULE simulated airways (Alex Bell 2024)
              'scatnetAT',      true    ,... % MODULE scatternet air trapping
              'scatnetAT_PEDS', false   ,... % MODULE scatternet air trapping for pediatrics
              'vessel',         true    ,... % MODULE blood vessel analysis
              'reg',            true    ,... % MODULE register Ins to Exp
              'scatnetEmph',    true    ,... % MODULE scatternet Emph map
              'prm',            true    ,... % MODULE PRM analysis
              'eprm',           false   ,... % MODULE ePRM analysis
              'tprm',           false   ,... % MODULE tPRM analysis
              'dBlood',         true    ,... % MODULE generation of dBlood map
              'saa',            false   ,... % MODULE Stratified Axial Analysis
              ...
              'quickreg',       false   ,... % OPTION to skip last step in registration for speed
              'orient_check',   true    ,... % OPTION to auto-correct image orientation
              'peds',           false   ,... % OPTION for Pediatrics analysis (Scatnet AT)
              'jac',            true    ,... % OPTION to generate Jacobian from reg
              'jacmat',         false   ,... % OPTION to generate Jacobian matrix from reg
              'def',            false   ,... % OPTION to generate deformation fields from reg
              'Tvoi',           false   ,... % OPTION to transform Ins VOI
              ...
              'timestamp',      char(datetime('now','Format','yyyyMMddHHmmss')),...
              'report_path',    fullfile(fileparts(mfilename("fullpath")),'ReportTemplates\+Pipeline_Report\@Chapter\resources\templates\pdf\default.pdftx')...
             );

if nargin && (iscellstr(varargin) || isstring(varargin))
    fld = fieldnames(opts);
    for i = 8:numel(fld)
        if islogical(opts.(fld{i}))
            if ismember(fld{i},varargin)
                opts.(fld{i}) = true;
            else
                opts.(fld{i}) = false;
            end
        end
    end
end